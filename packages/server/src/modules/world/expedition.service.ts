import { and, desc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  expeditionMembers, heroExpeditions, heroes, masters, masterWorldStatus, pvpBattles, territories,
  tileDiscoveries, tileClearances, territoryEvents, worldTiles,
} from '../../database/drizzle-schema.js';
import { mulberry32 } from '@infiniti-gacha/shared';
import { resolveBattleV2 } from '../combat/combat-v2.engine.js';
import { combatV2Service } from '../combat/combat-v2.service.js';
import {
  fetchMasterHeroesWithPower, fetchMasterTopCombatPower, fetchPartyCombatPower,
} from '../hero/hero-combat-power.js';
import { conquestService } from './conquest.service.js';
import { tileDistance } from './world-rules.js';
import {
  expeditionProgress, resolveGuardianBattle, travelSeconds, validateParty,
  type ExpeditionMission, type ExpeditionStatus,
} from './expedition-rules.js';
import {
  DEFENDER_BONUS, LEVEL_BONUS_PER_LEVEL, canAttack, canHoldMoreTerritories,
  defenderPower, protectionAfterCapture,
} from './pvp-rules.js';

function hashSeed(seed: string): number {
  let hash = 2166136261;
  for (const char of seed) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export class ExpeditionError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ExpeditionError';
  }
}

const ACTIVE_STATUSES = ['TRAVELING', 'RETURNING'];

export class ExpeditionService {
  private async statusRow(masterId: string) {
    const [row] = await db.select().from(masterWorldStatus).where(eq(masterWorldStatus.masterId, masterId)).limit(1);
    return row;
  }

  private async busyHeroIds(masterId: string): Promise<string[]> {
    const rows = await db.select({ heroId: expeditionMembers.heroId })
      .from(expeditionMembers)
      .innerJoin(heroExpeditions, eq(heroExpeditions.id, expeditionMembers.expeditionId))
      .where(and(eq(heroExpeditions.masterId, masterId), inArray(heroExpeditions.status, ACTIVE_STATUSES)));
    return rows.map(row => row.heroId);
  }

  private async partyPower(heroIds: string[]): Promise<number> {
    return fetchPartyCombatPower(heroIds);
  }

  /** Scenario P3-03/04: dispatch 1–5 idle Heroes to scout or attack a known tile. */
  async dispatch(masterId: string, tileId: string, missionInput: unknown, heroIdsInput: unknown, now = new Date()) {
    const status = await this.statusRow(masterId);
    if (!status) throw new ExpeditionError('ERR_WORLD_LOCKED', 409);
    const mission = String(missionInput ?? '').toUpperCase() as ExpeditionMission;
    if (!['SCOUT', 'ATTACK'].includes(mission)) throw new ExpeditionError('mission phải là SCOUT hoặc ATTACK.', 400);
    const heroIds = Array.isArray(heroIdsInput) ? heroIdsInput.map(String) : [];
    const partyCheck = validateParty(heroIds);
    if (!partyCheck.ok) throw new ExpeditionError(partyCheck.reason ?? 'ERR_EXPEDITION_INVALID', 400);

    const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, tileId)).limit(1);
    if (!tile) throw new ExpeditionError('Ô đất không tồn tại.', 404);
    const [discovery] = await db.select().from(tileDiscoveries)
      .where(and(eq(tileDiscoveries.masterId, masterId), eq(tileDiscoveries.tileId, tileId))).limit(1);
    if (!discovery) throw new ExpeditionError('ERR_EXPEDITION_TILE_NOT_DISCOVERED', 409);

    const owned = await db.select({ id: heroes.id, state: heroes.state }).from(heroes)
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)));
    if (owned.length !== heroIds.length) throw new ExpeditionError('Có Hero không thuộc về bạn.', 404);
    if (owned.some(hero => hero.state === 'DEAD' || hero.state === 'DISABLED')) {
      throw new ExpeditionError('Hero đã chết hoặc bị vô hiệu hoá.', 409);
    }
    const busy = new Set(await this.busyHeroIds(masterId));
    if (heroIds.some(id => busy.has(id))) throw new ExpeditionError('ERR_EXPEDITION_HERO_BUSY', 409);

    // Attacking another Master's territory is a hero-vs-hero fight (no army).
    if (mission === 'ATTACK') {
      const [targetTerritory] = await db.select().from(territories).where(eq(territories.tileId, tileId)).limit(1);
      if (targetTerritory?.masterId && targetTerritory.masterId !== masterId) {
        const [ownerStatus] = await db.select().from(masterWorldStatus)
          .where(eq(masterWorldStatus.masterId, targetTerritory.masterId)).limit(1);
        const check = canAttack({
          tileOwned: true,
          ownedBySelf: false,
          territoryProtectedUntil: targetTerritory.protectedUntil,
          ownerShieldUntil: ownerStatus?.shieldUntil ?? null,
          now,
        });
        if (!check.ok) throw new ExpeditionError(check.reason ?? 'ERR_TARGET_UNATTACKABLE', 409);

        const [row] = await db.select({ total: sql<number>`count(*)::int` }).from(territories)
          .where(and(eq(territories.masterId, masterId), inArray(territories.status, ['OWNED', 'ABANDONING'])));
        if (!canHoldMoreTerritories(row?.total ?? 0)) throw new ExpeditionError('ERR_TERRITORY_LIMIT_REACHED', 409);
      }
    }

    const distance = tileDistance({ x: status.baseX, y: status.baseY }, { x: tile.x, y: tile.y });
    const travel = travelSeconds(distance);
    const id = uuidv4();
    await db.transaction(async tx => {
      await tx.insert(heroExpeditions).values({
        id, masterId, tileId, mission, status: 'TRAVELING',
        departAt: now, arriveAt: new Date(now.getTime() + travel * 1000), createdAt: now,
      });
      await tx.insert(expeditionMembers).values(heroIds.map((heroId, index) => ({
        id: uuidv4(), expeditionId: id, heroId, slotIndex: index,
      })));
    });

    return {
      expeditionId: id,
      mission,
      tileId,
      distance,
      travelSeconds: travel,
      arriveAt: new Date(now.getTime() + travel * 1000),
      heroes: heroIds,
    };
  }

  /** Resolve arrivals, battles and returns. Called lazily before reads and claims. */
  async settle(masterId?: string, now = new Date()) {
    const travelling = await db.select().from(heroExpeditions).where(and(
      eq(heroExpeditions.status, 'TRAVELING'),
      sql`${heroExpeditions.arriveAt} <= ${now}`,
      ...(masterId ? [eq(heroExpeditions.masterId, masterId)] : []),
    ));

    for (const expedition of travelling) {
      const members = await db.select({ heroId: expeditionMembers.heroId }).from(expeditionMembers)
        .where(eq(expeditionMembers.expeditionId, expedition.id));
      const heroIds = members.map(row => row.heroId);
      const power = await this.partyPower(heroIds);
      const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, expedition.tileId)).limit(1);
      const [territoryRow] = await db.select().from(territories).where(eq(territories.tileId, expedition.tileId)).limit(1);
      const [owner] = territoryRow?.masterId
        ? await db.select({ id: masters.id, name: masters.masterName }).from(masters).where(eq(masters.id, territoryRow.masterId)).limit(1)
        : [];
      const defenderHeroesWithPower = territoryRow?.masterId
        ? await fetchMasterHeroesWithPower(territoryRow.masterId)
        : [];
      const topDefenders = defenderHeroesWithPower
        .sort((a, b) => b.combatPower - a.combatPower)
        .slice(0, 5);
      const defenderPowerBase = topDefenders.reduce((sum, d) => sum + d.combatPower, 0);

      let result: Record<string, unknown>;
      if (expedition.mission === 'SCOUT') {
        result = {
          kind: 'SCOUT_REPORT',
          tile: { x: tile?.x ?? 0, y: tile?.y ?? 0, terrain: tile?.terrain ?? 'UNKNOWN', resourceType: tile?.resourceType ?? 'UNKNOWN' },
          guardianPower: tile?.requiredPower ?? 0,
          owner: owner ? { masterId: owner.id, name: owner.name, level: territoryRow?.level ?? 1 } : null,
          defenderHeroes: defenderHeroesWithPower.length,
          defenderPower: defenderPower(defenderPowerBase, territoryRow?.level ?? 1),
          partyPower: power,
          scoutedAt: now.toISOString(),
        };
      } else if (territoryRow?.masterId && territoryRow.masterId !== expedition.masterId) {
        // Hero-vs-Hero: the defender fights with their strongest five Heroes via Combat v2 Engine.
        const strength = defenderPower(defenderPowerBase, territoryRow.level);
        const defenderHeroIds = topDefenders.map(d => d.hero.id);
        const attackerUnits = await combatV2Service.buildHeroUnits(heroIds, expedition.masterId, 'HERO');
        const defenderUnits = await combatV2Service.buildHeroUnits(defenderHeroIds, territoryRow.masterId, 'ENEMY');

        // Defender territory bonus applies to combat stats
        const mult = DEFENDER_BONUS * (1 + LEVEL_BONUS_PER_LEVEL * Math.max(0, Math.floor(territoryRow.level) - 1));
        for (const unit of defenderUnits) {
          unit.stats.maxHp = Math.round(unit.stats.maxHp * mult);
          unit.stats.atk = Math.round(unit.stats.atk * mult);
          unit.stats.matk = Math.round(unit.stats.matk * mult);
          unit.stats.def = Math.round(unit.stats.def * mult);
          unit.stats.mdef = Math.round(unit.stats.mdef * mult);
        }

        const seedNum = hashSeed(expedition.id);
        const report = (defenderUnits.length > 0 && attackerUnits.length > 0)
          ? resolveBattleV2(attackerUnits, defenderUnits, { maxRounds: 30, random: mulberry32(seedNum) })
          : null;
        const won = report ? report.winner === 'HERO' : attackerUnits.length > 0;
        const winner: 'ATTACKER' | 'DEFENDER' = won ? 'ATTACKER' : 'DEFENDER';
        const rounds = Math.max(3, report?.rounds ?? 3);

        result = {
          kind: 'PVP_REPORT',
          won,
          winner,
          partyPower: power,
          defenderPower: strength,
          rounds,
          owner: owner ? { masterId: owner.id, name: owner.name } : null,
          resolvedAt: now.toISOString(),
          battleLog: report?.log ?? [],
          battleSummary: report ? {
            totalDamage: report.totalDamage,
            rounds: report.rounds,
            survivingUnits: report.units.filter(u => u.alive).length,
          } : null,
        };
        await db.insert(pvpBattles).values({
          id: uuidv4(), tileId: expedition.tileId, attackerMasterId: expedition.masterId,
          defenderMasterId: territoryRow.masterId, expeditionId: expedition.id,
          winner, attackerPower: power, defenderPower: strength, rounds,
          report: { ...result, ownerName: owner?.name ?? null }, createdAt: now,
        });
        if (won && tile) {
          await db.update(territories).set({
            masterId: expedition.masterId,
            protectedUntil: protectionAfterCapture(now),
            updatedAt: now,
          }).where(eq(territories.id, territoryRow.id));
          await db.insert(tileClearances).values({
            id: uuidv4(), masterId: expedition.masterId, tileId: tile.id, clearedAt: now,
          }).onConflictDoUpdate({ target: [tileClearances.masterId, tileClearances.tileId], set: { clearedAt: now } });
        }
        await db.insert(territoryEvents).values({
          id: uuidv4(), tileId: expedition.tileId, masterId: expedition.masterId,
          action: won ? 'PVP_CAPTURED' : 'PVP_REPELLED',
          detail: { defenderMasterId: territoryRow.masterId, attackerPower: power, defenderPower: strength, rounds },
          createdAt: now,
        });
        // MOD-13-07: won raids and repelled defences score alliance-war points.
        await conquestService.recordPvp({
          attackerMasterId: expedition.masterId, defenderMasterId: territoryRow.masterId,
          tileId: expedition.tileId, attackerWon: won, now,
        }).catch(error => console.error('[expedition] war scoring failed', error));
      } else {
        const battle = resolveGuardianBattle(power, Math.max(tile?.requiredPower ?? 0, defenderPowerBase * 0.5));
        result = {
          kind: 'BATTLE_REPORT',
          won: battle.won,
          partyPower: power,
          guardianPower: tile?.requiredPower ?? 0,
          defenderPower: defenderPowerBase,
          owner: owner ? { masterId: owner.id, name: owner.name } : null,
          resolvedAt: now.toISOString(),
        };
        if (battle.won && tile) {
          await db.insert(tileClearances).values({
            id: uuidv4(), masterId: expedition.masterId, tileId: tile.id, clearedAt: now,
          }).onConflictDoUpdate({ target: [tileClearances.masterId, tileClearances.tileId], set: { clearedAt: now } });
        }
      }

      const status = await this.statusRow(expedition.masterId);
      const distance = status && tile
        ? tileDistance({ x: status.baseX, y: status.baseY }, { x: tile.x, y: tile.y })
        : 1;
      const returnSeconds = travelSeconds(distance);
      await db.update(heroExpeditions).set({
        status: 'RETURNING', result, returnAt: new Date(now.getTime() + returnSeconds * 1000),
      }).where(eq(heroExpeditions.id, expedition.id));
    }

    const returning = await db.select().from(heroExpeditions).where(and(
      eq(heroExpeditions.status, 'RETURNING'),
      sql`${heroExpeditions.returnAt} <= ${now}`,
      ...(masterId ? [eq(heroExpeditions.masterId, masterId)] : []),
    ));
    for (const expedition of returning) {
      await db.update(heroExpeditions).set({ status: 'COMPLETED' }).where(eq(heroExpeditions.id, expedition.id));
    }
  }

  async list(masterId: string, now = new Date()) {
    await this.settle(masterId, now);
    const rows = await db.select({ expedition: heroExpeditions, tile: worldTiles })
      .from(heroExpeditions).innerJoin(worldTiles, eq(worldTiles.id, heroExpeditions.tileId))
      .where(eq(heroExpeditions.masterId, masterId))
      .orderBy(desc(heroExpeditions.createdAt)).limit(20);
    if (rows.length === 0) return [];

    const members = await db.select({ expeditionId: expeditionMembers.expeditionId, heroId: heroes.id, name: heroes.name })
      .from(expeditionMembers).innerJoin(heroes, eq(heroes.id, expeditionMembers.heroId))
      .where(inArray(expeditionMembers.expeditionId, rows.map(row => row.expedition.id)));
    const active = await this.busyHeroIds(masterId);

    return rows.map(row => {
      const progress = expeditionProgress(row.expedition.status as ExpeditionStatus, row.expedition.arriveAt, row.expedition.returnAt, now);
      return {
        ...row.expedition,
        tile: row.tile,
        heroes: members.filter(member => member.expeditionId === row.expedition.id)
          .map(member => ({ id: member.heroId, name: member.name })),
        phase: progress.phase,
        secondsRemaining: progress.secondsRemaining,
        active: active.includes(members.find(member => member.expeditionId === row.expedition.id)?.heroId ?? ''),
      };
    });
  }

  async recall(masterId: string, expeditionId: string, now = new Date()) {
    const [row] = await db.select().from(heroExpeditions)
      .where(and(eq(heroExpeditions.id, expeditionId), eq(heroExpeditions.masterId, masterId))).limit(1);
    if (!row) throw new ExpeditionError('Không tìm thấy chuyến thám hiểm.', 404);
    if (!ACTIVE_STATUSES.includes(row.status)) throw new ExpeditionError('Chuyến thám hiểm đã kết thúc.', 409);
    const [updated] = await db.update(heroExpeditions).set({ status: 'RECALLED', returnAt: now })
      .where(eq(heroExpeditions.id, expeditionId)).returning();
    return { expedition: updated, recalledAt: now };
  }

  async battles(masterId: string) {
    const rows = await db.select().from(pvpBattles)
      .where(sql`${pvpBattles.attackerMasterId} = ${masterId} or ${pvpBattles.defenderMasterId} = ${masterId}`)
      .orderBy(desc(pvpBattles.createdAt)).limit(30);
    return rows;
  }

  async defenseEstimate(tileId: string, now = new Date()) {
    const [row] = await db.select({ territory: territories, tile: worldTiles })
      .from(territories).innerJoin(worldTiles, eq(worldTiles.id, territories.tileId))
      .where(eq(territories.tileId, tileId)).limit(1);
    if (!row?.territory.masterId) return { owned: false, defensePower: 0, protected: false, protectedUntil: null };
    const base = await fetchMasterTopCombatPower(row.territory.masterId, 5);
    return {
      owned: true,
      ownerMasterId: row.territory.masterId,
      level: row.territory.level,
      defensePower: defenderPower(base, row.territory.level),
      protected: Boolean(row.territory.protectedUntil && row.territory.protectedUntil > now),
      protectedUntil: row.territory.protectedUntil,
    };
  }

  /** Heroes currently away from the base (used by the client roster). */
  async awayHeroes(masterId: string) {
    await this.settle(masterId);
    const rows = await db.select({ heroId: expeditionMembers.heroId })
      .from(expeditionMembers)
      .innerJoin(heroExpeditions, eq(heroExpeditions.id, expeditionMembers.expeditionId))
      .where(and(eq(heroExpeditions.masterId, masterId), inArray(heroExpeditions.status, ACTIVE_STATUSES)));
    return [...new Set(rows.map(row => row.heroId))];
  }
}

export const expeditionService = new ExpeditionService();
