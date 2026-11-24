import { and, asc, between, desc, eq, inArray, ne, or, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  expeditionMembers, heroExpeditions, heroes, masterAirships, masterAirshipTechs, masters,
  masterTileVision, masterWorldStatus, pvpBattles, territories, territoryEvents,
  tileClearances, tileDiscoveries, worldDungeons, worldTiles, worlds,
} from '../../database/drizzle-schema.js';
import {
  clampChunkRadius, clampGridY, DEFAULT_CHUNK_RADIUS, PLANET_GRID_HEIGHT, PLANET_GRID_WIDTH, wrapGridX,
} from './planet-grid-rules.js';
import { mulberry32 } from '@infiniti-gacha/shared';
import { resolveBattleV2 } from '../combat/combat-v2.engine.js';
import { combatV2Service } from '../combat/combat-v2.service.js';
import { assertHeroesActivityReadiness } from '../combat/combat-readiness.js';
import {
  fetchMasterHeroesWithPower, fetchMasterTopCombatPower, fetchPartyCombatPower,
} from '../hero/hero-combat-power.js';
import {
  AIRSHIP_BLUEPRINTS, AIRSHIP_UNLOCK_FLOOR, BASE_HOME_VISION_RADIUS,
  airshipStatsForLevel, traceFlightPath, visionDurationSeconds,
  type AirshipBlueprintCode,
} from './airship-rules.js';
import { airshipService } from './airship.service.js';
import { conquestService } from './conquest.service.js';
import { worldDungeonService } from './world-dungeon.service.js';
import { tileDistance } from './world-rules.js';
import {
  MAX_EXPEDITION_HEROES, expeditionProgress, resolveGuardianBattle, travelSeconds, validateParty,
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

const ACTIVE_STATUSES = ['TRAVELING', 'RETURNING', 'GARRISONED', 'STRANDED'];

export interface DispatchOptions {
  airshipId?: string | null;
  dungeonId?: string | null;
  rescueTargetExpeditionId?: string | null;
}

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

  private async visionSecondsForMaster(masterId: string): Promise<number> {
    const techs = await db.select({ code: masterAirshipTechs.techCode })
      .from(masterAirshipTechs).where(eq(masterAirshipTechs.masterId, masterId));
    return visionDurationSeconds(techs.map(row => row.code));
  }

  /**
   * Dynamic Fog of War (1 hour default):
   * Reveals tiles along a Scout airship's flight corridor up to `now` (plus radarRadius).
   * Each tile gets visible_until = max(existing, passTime + visionSeconds).
   */
  private async applyPathVision(
    masterId: string,
    path: Array<{ x: number; y: number }>,
    departAt: Date,
    arriveAt: Date,
    radarRadius: number,
    now: Date,
  ) {
    if (path.length === 0) return;
    const durationMs = Math.max(1, arriveAt.getTime() - departAt.getTime());
    const elapsedRatio = Math.max(0, Math.min(1, (now.getTime() - departAt.getTime()) / durationMs));
    const maxIndex = Math.min(path.length - 1, Math.floor(elapsedRatio * (path.length - 1)));
    if (maxIndex < 0) return;

    const visionSec = await this.visionSecondsForMaster(masterId);
    // Query ONLY the tight bounding box around the active flight path (avoids scanning 180,000 planet tiles!)
    let minX = Infinity; let maxX = -Infinity; let minY = Infinity; let maxY = -Infinity;
    for (let i = 0; i <= maxIndex; i++) {
      const pt = path[i];
      if (pt.x < minX) minX = pt.x;
      if (pt.x > maxX) maxX = pt.x;
      if (pt.y < minY) minY = pt.y;
      if (pt.y > maxY) maxY = pt.y;
    }
    const qMinX = Math.max(0, minX - radarRadius);
    const qMaxX = Math.min(PLANET_GRID_WIDTH - 1, maxX + radarRadius);
    const qMinY = clampGridY(minY - radarRadius);
    const qMaxY = clampGridY(maxY + radarRadius);
    const pathBoxTiles = await db.select({ id: worldTiles.id, x: worldTiles.x, y: worldTiles.y })
      .from(worldTiles)
      .where(and(between(worldTiles.x, qMinX, qMaxX), between(worldTiles.y, qMinY, qMaxY)));
    const tileByCoord = new Map(pathBoxTiles.map(t => [`${t.x},${t.y}`, t.id]));

    const revealExpiryByTileId = new Map<string, Date>();
    for (let i = 0; i <= maxIndex; i++) {
      const pt = path[i];
      const stepRatio = path.length <= 1 ? 1 : i / (path.length - 1);
      const passTime = new Date(departAt.getTime() + Math.round(durationMs * stepRatio));
      const expiresAt = new Date(passTime.getTime() + visionSec * 1000);
      if (expiresAt <= now) continue;

      for (let dx = -radarRadius; dx <= radarRadius; dx++) {
        for (let dy = -radarRadius; dy <= radarRadius; dy++) {
          const tid = tileByCoord.get(`${pt.x + dx},${pt.y + dy}`);
          if (!tid) continue;
          const prev = revealExpiryByTileId.get(tid);
          if (!prev || expiresAt > prev) revealExpiryByTileId.set(tid, expiresAt);
        }
      }
    }

    for (const [tileId, visibleUntil] of revealExpiryByTileId.entries()) {
      await db.insert(masterTileVision).values({
        id: uuidv4(),
        masterId,
        tileId,
        visibleUntil,
        lastScoutedAt: now,
      }).onConflictDoUpdate({
        target: [masterTileVision.masterId, masterTileVision.tileId],
        set: {
          visibleUntil: sql`GREATEST(${masterTileVision.visibleUntil}, ${visibleUntil})`,
          lastScoutedAt: now,
        },
      });
    }
  }

  /** Dispatch 1..N idle Heroes (with optional Airship) for SCOUT, DUNGEON, RESCUE, or ATTACK. */
  async dispatch(
    masterId: string,
    tileId: string,
    missionInput: unknown,
    heroIdsInput: unknown,
    options: DispatchOptions = {},
    now = new Date(),
  ) {
    await Promise.all([airshipService.settle(masterId, now), this.settle(masterId, now)]);
    const status = await this.statusRow(masterId);
    if (!status) throw new ExpeditionError('ERR_WORLD_LOCKED', 409);

    const mission = String(missionInput ?? '').toUpperCase() as ExpeditionMission;
    if (!['SCOUT', 'ATTACK', 'DUNGEON', 'RESCUE', 'GARRISON'].includes(mission)) {
      throw new ExpeditionError('mission phải là SCOUT, GARRISON, DUNGEON, RESCUE hoặc ATTACK.', 400);
    }

    let airship: typeof masterAirships.$inferSelect | null = null;
    let speedMult = 1;
    let maxHeroes = MAX_EXPEDITION_HEROES;
    if (options.airshipId) {
      const [found] = await db.select().from(masterAirships)
        .where(and(eq(masterAirships.id, options.airshipId), eq(masterAirships.masterId, masterId))).limit(1);
      if (!found) throw new ExpeditionError('Không tìm thấy tàu bay đã chọn.', 404);
      if (found.status !== 'DOCKED') throw new ExpeditionError('Tàu bay đang bận hoặc chưa hoàn tất đóng/sửa.', 409);
      if (found.hp < Math.ceil(found.maxHp * 0.2)) {
        throw new ExpeditionError('Độ bền tàu bay dưới 20%, hãy sửa chữa tại Cảng trước khi xuất kích.', 409);
      }
      airship = found;
      const stats = airshipStatsForLevel(found.blueprintCode as AirshipBlueprintCode, found.level);
      speedMult = stats.speedMult;
      maxHeroes = stats.maxHeroes;

      if (mission === 'RESCUE' && found.blueprintCode !== 'RESCUE_CUTTER') {
        throw new ExpeditionError('Nhiệm vụ cứu hộ yêu cầu sử dụng Tàu Cứu Hộ (RESCUE_CUTTER).', 409);
      }
    } else if (mission === 'RESCUE') {
      throw new ExpeditionError('Nhiệm vụ cứu hộ yêu cầu chọn Tàu Cứu Hộ.', 400);
    }

    const heroIds = Array.isArray(heroIdsInput) ? heroIdsInput.map(String) : [];
    const partyCheck = validateParty(heroIds, maxHeroes);
    if (!partyCheck.ok) throw new ExpeditionError(partyCheck.reason ?? 'ERR_EXPEDITION_INVALID', 400);

    let targetTileId = tileId;
    let rescueTargetId: string | null = null;
    if (mission === 'RESCUE') {
      const targetId = String(options.rescueTargetExpeditionId ?? '').trim();
      if (!targetId) throw new ExpeditionError('Cần chỉ định chuyến thám hiểm mắc kẹt cần cứu hộ.', 400);
      const [stranded] = await db.select().from(heroExpeditions)
        .where(and(eq(heroExpeditions.id, targetId), eq(heroExpeditions.masterId, masterId), eq(heroExpeditions.status, 'STRANDED')))
        .limit(1);
      if (!stranded) throw new ExpeditionError('Không tìm thấy tổ đội đang mắc kẹt (STRANDED).', 404);
      targetTileId = stranded.tileId;
      rescueTargetId = stranded.id;
    }

    const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, targetTileId)).limit(1);
    if (!tile) throw new ExpeditionError('Ô đất không tồn tại.', 404);

    let dungeonId: string | null = null;
    if (mission === 'DUNGEON') {
      await worldDungeonService.ensureActiveDungeons(now);
      const [dungeon] = options.dungeonId
        ? await db.select().from(worldDungeons).where(and(eq(worldDungeons.id, options.dungeonId), eq(worldDungeons.status, 'ACTIVE'))).limit(1)
        : await db.select().from(worldDungeons).where(and(eq(worldDungeons.tileId, tile.id), eq(worldDungeons.status, 'ACTIVE'))).limit(1);
      if (!dungeon) throw new ExpeditionError('Không có Hầm Ngục Nổi đang hoạt động tại ô này.', 404);
      if (heroIds.length > dungeon.maxPartySize) {
        throw new ExpeditionError(`Hầm ngục này chỉ cho phép tối đa ${dungeon.maxPartySize} Hero.`, 400);
      }
      dungeonId = dungeon.id;
    }

    // Legacy ATTACK still requires discovery when no airship is used; SCOUT/DUNGEON/RESCUE work with dynamic fog.
    if (mission === 'ATTACK' && !airship) {
      const [discovery] = await db.select().from(tileDiscoveries)
        .where(and(eq(tileDiscoveries.masterId, masterId), eq(tileDiscoveries.tileId, tile.id))).limit(1);
      if (!discovery) throw new ExpeditionError('ERR_EXPEDITION_TILE_NOT_DISCOVERED', 409);
    }

    const owned = await db.select({ id: heroes.id, state: heroes.state }).from(heroes)
      .where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)));
    if (owned.length !== heroIds.length) throw new ExpeditionError('Có Hero không thuộc về bạn.', 404);
    if (owned.some(hero => hero.state === 'DEAD' || hero.state === 'DISABLED')) {
      throw new ExpeditionError('Hero đã chết hoặc bị vô hiệu hoá.', 409);
    }
    const busy = new Set(await this.busyHeroIds(masterId));
    if (heroIds.some(id => busy.has(id))) throw new ExpeditionError('ERR_EXPEDITION_HERO_BUSY', 409);
    await assertHeroesActivityReadiness(db, masterId, heroIds, now, 'ANY');

    if (mission === 'ATTACK') {
      const [targetTerritory] = await db.select().from(territories).where(eq(territories.tileId, tile.id)).limit(1);
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

    const origin = { x: status.baseX, y: status.baseY };
    const distance = tileDistance(origin, { x: tile.x, y: tile.y });
    const travel = travelSeconds(distance, speedMult);
    const arriveAt = new Date(now.getTime() + travel * 1000);
    const pathTiles = traceFlightPath(origin, { x: tile.x, y: tile.y });
    const id = uuidv4();

    await db.transaction(async tx => {
      if (airship) {
        await tx.update(masterAirships).set({ status: 'DEPLOYED', updatedAt: now })
          .where(eq(masterAirships.id, airship.id));
      }
      await tx.insert(heroExpeditions).values({
        id,
        masterId,
        tileId: tile.id,
        airshipId: airship?.id ?? null,
        dungeonId,
        originX: origin.x,
        originY: origin.y,
        pathTiles,
        rescueTargetExpeditionId: rescueTargetId,
        mission,
        status: 'TRAVELING',
        departAt: now,
        arriveAt,
        createdAt: now,
      });
      await tx.insert(expeditionMembers).values(heroIds.map((heroId, index) => ({
        id: uuidv4(), expeditionId: id, heroId, slotIndex: index,
      })));
    });

    // Immediately reveal starting tiles for SCOUT missions
    if (mission === 'SCOUT') {
      const radar = airship ? AIRSHIP_BLUEPRINTS[airship.blueprintCode as AirshipBlueprintCode].radarRadius : 1;
      await this.applyPathVision(masterId, pathTiles, now, arriveAt, radar, now);
    }

    return {
      expeditionId: id,
      mission,
      tileId: tile.id,
      airshipId: airship?.id ?? null,
      dungeonId,
      rescueTargetExpeditionId: rescueTargetId,
      distance,
      travelSeconds: travel,
      arriveAt,
      heroes: heroIds,
    };
  }

  /** RTS live redirect: reroute a TRAVELING airship/expedition to a new tile from its interpolated position. */
  async redirect(masterId: string, expeditionId: string, newTileId: string, now = new Date()) {
    await this.settle(masterId, now);
    const [row] = await db.select().from(heroExpeditions)
      .where(and(eq(heroExpeditions.id, expeditionId), eq(heroExpeditions.masterId, masterId))).limit(1);
    if (!row) throw new ExpeditionError('Không tìm thấy chuyến thám hiểm.', 404);
    if (row.status !== 'TRAVELING' && row.status !== 'GARRISONED') {
      throw new ExpeditionError('Chỉ có thể đổi hướng khi hạm đội đang bay hoặc đang tập kết đồn trú.', 409);
    }

    const [oldTile] = await db.select().from(worldTiles).where(eq(worldTiles.id, row.tileId)).limit(1);
    const [newTile] = await db.select().from(worldTiles).where(eq(worldTiles.id, newTileId)).limit(1);
    if (!newTile) throw new ExpeditionError('Ô đích mới không tồn tại.', 404);

    const status = await this.statusRow(masterId);
    const startX = row.originX ?? status?.baseX ?? newTile.x;
    const startY = row.originY ?? status?.baseY ?? newTile.y;
    const oldX = oldTile?.x ?? startX;
    const oldY = oldTile?.y ?? startY;

    let curX = oldX;
    let curY = oldY;
    if (row.status === 'TRAVELING') {
      const totalMs = Math.max(1, row.arriveAt.getTime() - row.departAt.getTime());
      const ratio = Math.max(0, Math.min(1, (now.getTime() - row.departAt.getTime()) / totalMs));
      curX = Math.round(startX + (oldX - startX) * ratio);
      curY = Math.round(startY + (oldY - startY) * ratio);
    }

    let speedMult = 1;
    let radar = 1;
    if (row.airshipId) {
      const [ship] = await db.select().from(masterAirships).where(eq(masterAirships.id, row.airshipId)).limit(1);
      if (ship) {
        const stats = airshipStatsForLevel(ship.blueprintCode as AirshipBlueprintCode, ship.level);
        speedMult = stats.speedMult;
        radar = stats.radarRadius;
      }
    }

    const distance = tileDistance({ x: curX, y: curY }, { x: newTile.x, y: newTile.y });
    const travel = travelSeconds(distance, speedMult);
    const arriveAt = new Date(now.getTime() + travel * 1000);
    const pathTiles = traceFlightPath({ x: curX, y: curY }, { x: newTile.x, y: newTile.y });

    const [updated] = await db.update(heroExpeditions).set({
      tileId: newTile.id,
      status: 'TRAVELING',
      originX: curX,
      originY: curY,
      pathTiles,
      departAt: now,
      arriveAt,
      redirectedAt: now,
    }).where(eq(heroExpeditions.id, row.id)).returning();

    if (row.mission === 'SCOUT') {
      await this.applyPathVision(masterId, pathTiles, now, arriveAt, radar, now);
    }

    return { expedition: updated, from: { x: curX, y: curY }, to: { x: newTile.x, y: newTile.y }, travelSeconds: travel, arriveAt };
  }

  /** Resolve in-flight vision trails, arrivals, dungeon raids, rescues and returns. */
  async settle(masterId?: string, now = new Date()) {
    // 1. Update live vision trails for all currently traveling SCOUT expeditions
    const liveScouts = await db.select().from(heroExpeditions).where(and(
      eq(heroExpeditions.status, 'TRAVELING'),
      eq(heroExpeditions.mission, 'SCOUT'),
      ...(masterId ? [eq(heroExpeditions.masterId, masterId)] : []),
    ));
    for (const scout of liveScouts) {
      const path = Array.isArray(scout.pathTiles) ? scout.pathTiles : [];
      if (path.length === 0) continue;
      let radar = 1;
      if (scout.airshipId) {
        const [ship] = await db.select().from(masterAirships).where(eq(masterAirships.id, scout.airshipId)).limit(1);
        if (ship) radar = AIRSHIP_BLUEPRINTS[ship.blueprintCode as AirshipBlueprintCode]?.radarRadius ?? 1;
      }
      await this.applyPathVision(scout.masterId, path, scout.departAt, scout.arriveAt, radar, now);
    }

    // 2. Settle arrived TRAVELING expeditions
    const travelling = await db.select().from(heroExpeditions).where(and(
      eq(heroExpeditions.status, 'TRAVELING'),
      sql`${heroExpeditions.arriveAt} <= ${now}`,
      ...(masterId ? [eq(heroExpeditions.masterId, masterId)] : []),
    ));

    for (const expedition of travelling) {
      const members = await db.select({ heroId: expeditionMembers.heroId }).from(expeditionMembers)
        .where(eq(expeditionMembers.expeditionId, expedition.id));
      const heroIds = members.map(row => row.heroId);
      const basePower = await this.partyPower(heroIds);
      const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, expedition.tileId)).limit(1);
      const [ship] = expedition.airshipId
        ? await db.select().from(masterAirships).where(eq(masterAirships.id, expedition.airshipId)).limit(1)
        : [];
      const shipStats = ship ? airshipStatsForLevel(ship.blueprintCode as AirshipBlueprintCode, ship.level) : null;
      const power = shipStats ? Math.round(basePower * (1 + shipStats.powerBonusPct / 100)) : basePower;

      let result: Record<string, unknown> = {};
      let becameStranded = false;
      let hpLoss = 0;

      if (expedition.mission === 'SCOUT') {
        const path = Array.isArray(expedition.pathTiles) ? expedition.pathTiles : [];
        const radar = shipStats?.radarRadius ?? 1;
        await this.applyPathVision(expedition.masterId, path, expedition.departAt, expedition.arriveAt, radar, now);
        hpLoss = ship ? Math.max(2, Math.round(ship.maxHp * 0.05)) : 0;

        const [dungeon] = tile
          ? await db.select().from(worldDungeons).where(and(eq(worldDungeons.tileId, tile.id), eq(worldDungeons.status, 'ACTIVE'))).limit(1)
          : [];
        const [territoryRow] = await db.select().from(territories).where(eq(territories.tileId, expedition.tileId)).limit(1);
        const [owner] = territoryRow?.masterId
          ? await db.select({ id: masters.id, name: masters.masterName }).from(masters).where(eq(masters.id, territoryRow.masterId)).limit(1)
          : [];
        const defenderHeroesWithPower = territoryRow?.masterId
          ? await fetchMasterHeroesWithPower(territoryRow.masterId)
          : [];
        const topDefenders = defenderHeroesWithPower.sort((a, b) => b.combatPower - a.combatPower).slice(0, 5);
        const defenderPowerBase = topDefenders.reduce((sum, d) => sum + d.combatPower, 0);

        result = {
          kind: 'SCOUT_REPORT',
          tile: { x: tile?.x ?? 0, y: tile?.y ?? 0, terrain: tile?.terrain ?? 'UNKNOWN' },
          visionDurationSeconds: await this.visionSecondsForMaster(expedition.masterId),
          dungeonFound: dungeon ? {
            id: dungeon.id, name: dungeon.name, rank: dungeon.rank,
            recommendedPower: dungeon.recommendedPower, maxPartySize: dungeon.maxPartySize, bossName: dungeon.bossName,
          } : null,
          guardianPower: tile?.requiredPower ?? 0,
          owner: owner ? { masterId: owner.id, name: owner.name, level: territoryRow?.level ?? 1 } : null,
          defenderHeroes: defenderHeroesWithPower.length,
          defenderPower: defenderPower(defenderPowerBase, territoryRow?.level ?? 1),
          partyPower: power,
          scoutedAt: now.toISOString(),
        };
      } else if (expedition.mission === 'RESCUE') {
        const targetId = expedition.rescueTargetExpeditionId;
        const [stranded] = targetId
          ? await db.select().from(heroExpeditions).where(and(eq(heroExpeditions.id, targetId), eq(heroExpeditions.status, 'STRANDED'))).limit(1)
          : [];
        hpLoss = ship ? Math.max(4, Math.round(ship.maxHp * 0.08)) : 0;

        const status = await this.statusRow(expedition.masterId);
        const distance = status && tile ? tileDistance({ x: status.baseX, y: status.baseY }, { x: tile.x, y: tile.y }) : 1;
        const returnSec = travelSeconds(distance, shipStats?.speedMult ?? 1.5);
        const returnAt = new Date(now.getTime() + returnSec * 1000);

        if (stranded) {
          await db.update(heroExpeditions).set({
            status: 'RETURNING',
            returnAt,
            result: { ...(stranded.result ?? {}), rescuedAt: now.toISOString(), rescuedByExpeditionId: expedition.id },
          }).where(eq(heroExpeditions.id, stranded.id));
          if (stranded.airshipId) {
            await db.update(masterAirships).set({
              status: 'DEPLOYED',
              hp: sql`GREATEST(1, ${masterAirships.hp})`,
              updatedAt: now,
            }).where(eq(masterAirships.id, stranded.airshipId));
          }
        }

        result = {
          kind: 'RESCUE_REPORT',
          rescued: Boolean(stranded),
          rescuedExpeditionId: stranded?.id ?? null,
          rescuedAt: now.toISOString(),
        };
      } else if (expedition.mission === 'DUNGEON') {
        const [dungeon] = expedition.dungeonId
          ? await db.select().from(worldDungeons).where(eq(worldDungeons.id, expedition.dungeonId)).limit(1)
          : await db.select().from(worldDungeons).where(and(eq(worldDungeons.tileId, expedition.tileId), eq(worldDungeons.status, 'ACTIVE'))).limit(1);

        if (!dungeon || dungeon.status !== 'ACTIVE') {
          result = { kind: 'DUNGEON_EXPIRED', won: false, message: 'Hầm ngục đã biến mất hoặc đã bị chinh phục trước đó.' };
          hpLoss = ship ? Math.max(3, Math.round(ship.maxHp * 0.05)) : 0;
        } else {
          const battle = resolveGuardianBattle(power, dungeon.recommendedPower);
          if (battle.won) {
            const rewardSilver = Number((dungeon.rewards as Record<string, unknown>)?.silverCoins ?? 1500);
            await db.update(worldDungeons).set({
              status: 'CLEARED', clearedByMasterId: expedition.masterId,
            }).where(eq(worldDungeons.id, dungeon.id));
            await db.update(masters).set({
              silverCoins: sql`${masters.silverCoins} + ${rewardSilver}`, updatedAt: now,
            }).where(eq(masters.id, expedition.masterId));
            hpLoss = ship ? Math.max(5, Math.round(ship.maxHp * 0.14)) : 0;
            result = {
              kind: 'DUNGEON_REPORT',
              won: true,
              dungeonName: dungeon.name,
              rank: dungeon.rank,
              bossName: dungeon.bossName,
              partyPower: power,
              recommendedPower: dungeon.recommendedPower,
              silverReward: rewardSilver,
              heroCount: heroIds.length,
              resolvedAt: now.toISOString(),
            };
          } else {
            // Heavy loss or ship hull failure causes STRANDED -> requires RESCUE_CUTTER!
            const severeLoss = battle.ratio < 0.7;
            hpLoss = ship ? Math.round(ship.maxHp * (severeLoss ? 0.45 : 0.28)) : 0;
            const remainingHp = ship ? Math.max(0, ship.hp - hpLoss) : 100;
            becameStranded = severeLoss || remainingHp <= 0;
            result = {
              kind: 'DUNGEON_REPORT',
              won: false,
              stranded: becameStranded,
              dungeonName: dungeon.name,
              rank: dungeon.rank,
              bossName: dungeon.bossName,
              partyPower: power,
              recommendedPower: dungeon.recommendedPower,
              ratio: battle.ratio,
              resolvedAt: now.toISOString(),
            };
          }
        }
      } else if (expedition.mission === 'GARRISON') {
        hpLoss = ship ? Math.max(1, Math.round(ship.maxHp * 0.03)) : 0;
        result = {
          kind: 'GARRISON_REPORT',
          stationedAt: now.toISOString(),
          tile: { x: tile?.x ?? 0, y: tile?.y ?? 0, terrain: tile?.terrain ?? 'UNKNOWN' },
          heroCount: heroIds.length,
        };
      } else {
        // ATTACK (PvP territory or Guardian)
        const [territoryRow] = await db.select().from(territories).where(eq(territories.tileId, expedition.tileId)).limit(1);
        const [owner] = territoryRow?.masterId
          ? await db.select({ id: masters.id, name: masters.masterName }).from(masters).where(eq(masters.id, territoryRow.masterId)).limit(1)
          : [];
        const defenderHeroesWithPower = territoryRow?.masterId
          ? await fetchMasterHeroesWithPower(territoryRow.masterId)
          : [];
        const topDefenders = defenderHeroesWithPower.sort((a, b) => b.combatPower - a.combatPower).slice(0, 5);
        const defenderPowerBase = topDefenders.reduce((sum, d) => sum + d.combatPower, 0);

        if (territoryRow?.masterId && territoryRow.masterId !== expedition.masterId) {
          const strength = defenderPower(defenderPowerBase, territoryRow.level);
          const defenderHeroIds = topDefenders.map(d => d.hero.id);
          const attackerUnits = await combatV2Service.buildHeroUnits(heroIds, expedition.masterId, 'HERO');
          const defenderUnits = await combatV2Service.buildHeroUnits(defenderHeroIds, territoryRow.masterId, 'ENEMY');
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
          hpLoss = ship ? Math.round(ship.maxHp * (won ? 0.15 : 0.35)) : 0;

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
              masterId: expedition.masterId, protectedUntil: protectionAfterCapture(now), updatedAt: now,
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
          await conquestService.recordPvp({
            attackerMasterId: expedition.masterId, defenderMasterId: territoryRow.masterId,
            tileId: expedition.tileId, attackerWon: won, now,
          }).catch(error => console.error('[expedition] war scoring failed', error));
        } else {
          const battle = resolveGuardianBattle(power, Math.max(tile?.requiredPower ?? 0, defenderPowerBase * 0.5));
          hpLoss = ship ? Math.round(ship.maxHp * (battle.won ? 0.12 : 0.28)) : 0;
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
      }

      if (ship) {
        const nextHp = Math.max(0, ship.hp - hpLoss);
        if (nextHp <= 0) becameStranded = true;
        await db.update(masterAirships).set({
          hp: nextHp,
          status: becameStranded ? 'STRANDED' : 'DEPLOYED',
          updatedAt: now,
        }).where(eq(masterAirships.id, ship.id));
      }

      if (becameStranded) {
        await db.update(heroExpeditions).set({
          status: 'STRANDED',
          strandedAt: now,
          result,
        }).where(eq(heroExpeditions.id, expedition.id));
      } else if (expedition.mission === 'GARRISON') {
        await db.update(heroExpeditions).set({
          status: 'GARRISONED',
          result,
        }).where(eq(heroExpeditions.id, expedition.id));
      } else {
        const status = await this.statusRow(expedition.masterId);
        const distance = status && tile
          ? tileDistance({ x: status.baseX, y: status.baseY }, { x: tile.x, y: tile.y })
          : 1;
        const returnSeconds = travelSeconds(distance, shipStats?.speedMult ?? 1);
        await db.update(heroExpeditions).set({
          status: 'RETURNING',
          result,
          returnAt: new Date(now.getTime() + returnSeconds * 1000),
        }).where(eq(heroExpeditions.id, expedition.id));
      }
    }

    // 3. Complete returned expeditions and dock their airships
    const returning = await db.select().from(heroExpeditions).where(and(
      eq(heroExpeditions.status, 'RETURNING'),
      sql`${heroExpeditions.returnAt} <= ${now}`,
      ...(masterId ? [eq(heroExpeditions.masterId, masterId)] : []),
    ));
    for (const expedition of returning) {
      await db.update(heroExpeditions).set({ status: 'COMPLETED' }).where(eq(heroExpeditions.id, expedition.id));
      if (expedition.airshipId) {
        await db.update(masterAirships).set({ status: 'DOCKED', updatedAt: now })
          .where(eq(masterAirships.id, expedition.airshipId));
      }
    }
  }

  /** Unified RTS map snapshot for Godot WorldRtsMap (Viewport Chunk Streaming + Fog of War + Dungeons + Nearby Players). */
  async rtsSnapshot(
    masterId: string,
    optionsOrNow: { cx?: unknown; cy?: unknown; radius?: unknown } | Date = {},
    maybeNow?: Date,
  ) {
    const now = optionsOrNow instanceof Date ? optionsOrNow : (maybeNow ?? new Date());
    const opts = optionsOrNow instanceof Date ? {} : (optionsOrNow ?? {});

    await Promise.all([
      airshipService.settle(masterId, now),
      this.settle(masterId, now),
    ]);

    const [[world], status, portState] = await Promise.all([
      db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1),
      this.statusRow(masterId),
      airshipService.getPortState(masterId, now),
    ]);

    const clearedFloor = world?.currentFloor ?? 1;
    if (!status) {
      return {
        unlocked: false,
        clearedFloor,
        requiredFloor: AIRSHIP_UNLOCK_FLOOR,
        worldGrid: { width: PLANET_GRID_WIDTH, height: PLANET_GRID_HEIGHT },
        portState,
        base: null,
        chunkCenter: null,
        nearbyPlayers: [],
        tiles: [],
        activeFleets: [],
      };
    }

    const cx = opts.cx !== undefined && opts.cx !== '' ? wrapGridX(Number(opts.cx)) : status.baseX;
    const cy = opts.cy !== undefined && opts.cy !== '' ? clampGridY(Number(opts.cy)) : status.baseY;
    const radius = clampChunkRadius(opts.radius ?? DEFAULT_CHUNK_RADIUS);
    const minY = clampGridY(cy - radius);
    const maxY = clampGridY(cy + radius);

    // Handle horizontal wrap cleanly across x=0 / x=599 meridian
    const rawMinX = cx - radius;
    const rawMaxX = cx + radius;
    const xFilter = rawMinX < 0
      ? or(between(worldTiles.x, 0, rawMaxX), between(worldTiles.x, PLANET_GRID_WIDTH + rawMinX, PLANET_GRID_WIDTH - 1))
      : (rawMaxX >= PLANET_GRID_WIDTH
        ? or(between(worldTiles.x, rawMinX, PLANET_GRID_WIDTH - 1), between(worldTiles.x, 0, rawMaxX - PLANET_GRID_WIDTH))
        : between(worldTiles.x, rawMinX, rawMaxX));

    await worldDungeonService.ensureDungeonsNear(cx, cy, radius, 5, now);

    const [activeExpeditions, chunkTiles] = await Promise.all([
      db.select({ expedition: heroExpeditions, tile: worldTiles })
        .from(heroExpeditions)
        .innerJoin(worldTiles, eq(worldTiles.id, heroExpeditions.tileId))
        .where(and(eq(heroExpeditions.masterId, masterId), inArray(heroExpeditions.status, ACTIVE_STATUSES)))
        .orderBy(desc(heroExpeditions.createdAt)),
      db.select().from(worldTiles)
        .where(and(xFilter, between(worldTiles.y, minY, maxY)))
        .orderBy(asc(worldTiles.y), asc(worldTiles.x)),
    ]);

    // Merge expedition target tiles even if outside current viewport chunk so flight vectors stay complete
    const tileMap = new Map(chunkTiles.map(t => [t.id, t]));
    for (const row of activeExpeditions) {
      if (!tileMap.has(row.tile.id)) tileMap.set(row.tile.id, row.tile);
    }
    const tiles = Array.from(tileMap.values());
    const tileIds = tiles.map(t => t.id);

    const playerXFilter = rawMinX < 0
      ? or(between(masterWorldStatus.baseX, 0, rawMaxX), between(masterWorldStatus.baseX, PLANET_GRID_WIDTH + rawMinX, PLANET_GRID_WIDTH - 1))
      : (rawMaxX >= PLANET_GRID_WIDTH
        ? or(between(masterWorldStatus.baseX, rawMinX, PLANET_GRID_WIDTH - 1), between(masterWorldStatus.baseX, 0, rawMaxX - PLANET_GRID_WIDTH))
        : between(masterWorldStatus.baseX, rawMinX, rawMaxX));

    const [visionRows, activeDungeons, nearbyPlayerRows] = await Promise.all([
      tileIds.length > 0
        ? db.select().from(masterTileVision).where(and(
            eq(masterTileVision.masterId, masterId),
            inArray(masterTileVision.tileId, tileIds),
            sql`${masterTileVision.visibleUntil} > ${now}`,
          ))
        : Promise.resolve([]),
      tileIds.length > 0
        ? db.select().from(worldDungeons).where(and(
            eq(worldDungeons.status, 'ACTIVE'),
            inArray(worldDungeons.tileId, tileIds),
          ))
        : Promise.resolve([]),
      db.select({
        masterId: masterWorldStatus.masterId,
        masterName: masters.masterName,
        x: masterWorldStatus.baseX,
        y: masterWorldStatus.baseY,
        continentId: masterWorldStatus.continentId,
        shieldUntil: masterWorldStatus.shieldUntil,
      })
        .from(masterWorldStatus)
        .innerJoin(masters, eq(masters.id, masterWorldStatus.masterId))
        .where(and(
          ne(masterWorldStatus.masterId, masterId),
          playerXFilter,
          between(masterWorldStatus.baseY, minY, maxY),
        ))
        .limit(40),
    ]);

    const visionByTile = new Map(visionRows.map(row => [row.tileId, row.visibleUntil]));
    const dungeonByTile = new Map(activeDungeons.map(row => [row.tileId, row]));
    const shipById = new Map(portState.airships.map(ship => [ship.id, ship]));

    const expIds = activeExpeditions.map(r => r.expedition.id);
    const members = expIds.length > 0
      ? await db.select({ expeditionId: expeditionMembers.expeditionId, heroId: heroes.id, name: heroes.name })
          .from(expeditionMembers)
          .innerJoin(heroes, eq(heroes.id, expeditionMembers.heroId))
          .where(inArray(expeditionMembers.expeditionId, expIds))
      : [];

    const garrisonCoords = activeExpeditions
      .filter(row => row.expedition.status === 'GARRISONED')
      .map(row => ({ x: row.tile.x, y: row.tile.y }));

    const mappedTiles = tiles.map(tile => {
      const distFromBase = tileDistance({ x: tile.x, y: tile.y }, { x: status.baseX, y: status.baseY });
      const homeLit = distFromBase <= BASE_HOME_VISION_RADIUS;
      const garrisonLit = garrisonCoords.some(g => tileDistance({ x: tile.x, y: tile.y }, g) <= 1);
      const visionExpiry = visionByTile.get(tile.id) ?? null;
      const visible = homeLit || garrisonLit || Boolean(visionExpiry && visionExpiry > now);
      const visionSecondsRemaining = (homeLit || garrisonLit)
        ? -1
        : (visionExpiry ? Math.max(0, Math.ceil((visionExpiry.getTime() - now.getTime()) / 1000)) : 0);
      const dungeon = visible ? dungeonByTile.get(tile.id) ?? null : null;

      return {
        id: tile.id,
        x: tile.x,
        y: tile.y,
        terrain: tile.terrain,
        continentId: tile.continentId,
        regionId: tile.regionId,
        zoneTier: tile.zoneTier,
        isBase: tile.x === status.baseX && tile.y === status.baseY,
        visible,
        homeLit,
        garrisonLit,
        visionSecondsRemaining,
        dungeon: dungeon ? {
          id: dungeon.id,
          name: dungeon.name,
          rank: dungeon.rank,
          recommendedPower: dungeon.recommendedPower,
          maxPartySize: dungeon.maxPartySize,
          bossName: dungeon.bossName,
          rewards: dungeon.rewards,
          expiresInSeconds: Math.max(0, Math.ceil((dungeon.expiresAt.getTime() - now.getTime()) / 1000)),
        } : null,
      };
    });

    const visibleCoordKeys = new Set(mappedTiles.filter(t => t.visible).map(t => `${t.x},${t.y}`));
    const nearbyPlayers = nearbyPlayerRows.map(p => ({
      masterId: p.masterId,
      masterName: p.masterName,
      x: p.x,
      y: p.y,
      continentId: p.continentId,
      shieldActive: p.shieldUntil > now,
      visible: visibleCoordKeys.has(`${p.x},${p.y}`),
    }));

    const activeFleets = activeExpeditions.map(row => {
      const exp = row.expedition;
      const prog = expeditionProgress(exp.status as ExpeditionStatus, exp.arriveAt, exp.returnAt, now);
      const ship = exp.airshipId ? shipById.get(exp.airshipId) ?? null : null;
      const fromX = exp.status === 'RETURNING' ? row.tile.x : (exp.originX ?? status.baseX);
      const fromY = exp.status === 'RETURNING' ? row.tile.y : (exp.originY ?? status.baseY);
      const toX = exp.status === 'RETURNING' ? status.baseX : row.tile.x;
      const toY = exp.status === 'RETURNING' ? status.baseY : row.tile.y;

      let progressRatio = 0;
      let totalDurationSeconds = 0;
      if (exp.status === 'TRAVELING') {
        const total = Math.max(1, exp.arriveAt.getTime() - exp.departAt.getTime());
        totalDurationSeconds = Math.max(1, Math.round(total / 1000));
        progressRatio = Math.max(0, Math.min(1, (now.getTime() - exp.departAt.getTime()) / total));
      } else if (exp.status === 'RETURNING' && exp.returnAt) {
        const start = exp.arriveAt.getTime();
        const total = Math.max(1, exp.returnAt.getTime() - start);
        totalDurationSeconds = Math.max(1, Math.round(total / 1000));
        progressRatio = Math.max(0, Math.min(1, (now.getTime() - start) / total));
      } else if (exp.status === 'STRANDED' || exp.status === 'GARRISONED') {
        progressRatio = 1;
      }

      return {
        id: exp.id,
        mission: exp.mission,
        status: exp.status,
        phase: prog.phase,
        secondsRemaining: prog.secondsRemaining,
        totalDurationSeconds,
        progressRatio,
        fromX,
        fromY,
        toX,
        toY,
        tileId: row.tile.id,
        dungeonId: exp.dungeonId,
        airship: ship ? {
          id: ship.id, name: ship.name, blueprintCode: ship.blueprintCode,
          sizeClass: ship.sizeClass, hp: ship.hp, maxHp: ship.maxHp, status: ship.status,
        } : null,
        heroes: members.filter(m => m.expeditionId === exp.id).map(m => ({ id: m.heroId, name: m.name })),
      };
    });

    return {
      unlocked: true,
      serverNow: now.toISOString(),
      clearedFloor,
      requiredFloor: AIRSHIP_UNLOCK_FLOOR,
      worldGrid: { width: PLANET_GRID_WIDTH, height: PLANET_GRID_HEIGHT },
      chunkCenter: { x: cx, y: cy, radius },
      base: { x: status.baseX, y: status.baseY, continentId: status.continentId },
      nearbyPlayers,
      portState,
      tiles: mappedTiles,
      activeFleets,
    };
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
    if (row.status === 'STRANDED') {
      throw new ExpeditionError('Tổ đội đang mắc kẹt (STRANDED), không thể tự triệu hồi — hãy cử Tàu Cứu Hộ!', 409);
    }
    if (!ACTIVE_STATUSES.includes(row.status)) throw new ExpeditionError('Chuyến thám hiểm đã kết thúc.', 409);
    const [updated] = await db.update(heroExpeditions).set({ status: 'RECALLED', returnAt: now })
      .where(eq(heroExpeditions.id, expeditionId)).returning();
    if (row.airshipId) {
      await db.update(masterAirships).set({ status: 'DOCKED', updatedAt: now })
        .where(eq(masterAirships.id, row.airshipId));
    }
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
