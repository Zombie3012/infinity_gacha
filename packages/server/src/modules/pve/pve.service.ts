import { createHash } from 'node:crypto';
import { and, asc, desc, eq, gt, inArray, isNull, lt, or, sql } from 'drizzle-orm';
import { v4 as uuid } from 'uuid';
import {
  GAME_CONSTANTS, defaultPvePlan, findPvePath, generatePveLayout, mulberry32, pveSeed, pveTileId,
  revealPveTiles, validatePvePlan, type DerivedStats, type PvePlan, type PvePoint, type PveTile,
} from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import type { GameTransaction } from '../../database/transaction.js';
import {
  buildingWorkerAssignments, combatPartySlots, combatSessions, dungeonInstances, enemyTemplates, expeditionMembers, heroExpeditions,
  heroInjuries, heroPersonalityTraits, heroRelationships, heroSkillInstances, heroSurvivalStates, heroTreatments,
  heroes, masterItems, masterParties, masters, pveBattles, pveCommands, pveEvents, pveHeroReservations,
  pveMaps, pvePartyPlans, pveSquads, worlds,
} from '../../database/drizzle-schema.js';
import { combatV2Service } from '../combat/combat-v2.service.js';
import { resolveBattleV2, type CombatV2UnitInput } from '../combat/combat-v2.engine.js';
import { settleCombat } from '../combat/combat-settlement.js';
import { chargeCombatDispatch } from '../combat/combat-readiness.js';
import { isV2Origin } from '../hero/hero-progression.js';
import { applyActivity, applyDrift, isImmobilised, starvationMultiplier } from '../survival/survival-rules.js';
import { injuryMultiplier } from '../medical/medical-rules.js';
import { loyaltyCombatMultiplier, relationshipTier, resonanceMultiplier } from '../personality/personality-rules.js';
import { questService } from '../quest/quest.service.js';
import { eventService } from '../liveops/event.service.js';
import { leaderboardService } from '../liveops/leaderboard.service.js';

type MapRow = typeof pveMaps.$inferSelect;
type SquadRow = typeof pveSquads.$inferSelect;
type CommandResult = Record<string, unknown>;
const ACTIVE = ['IDLE', 'MOVING', 'FIGHTING'];
const STEP_MS = GAME_CONSTANTS.PVE.SECONDS_PER_TILE * 1000;

export class PveError extends Error {
  constructor(message: string, readonly statusCode = 409) { super(message); this.name = 'PveError'; }
}

function canonical(value: unknown): string {
  if (value === undefined) return 'null';
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(key =>
    `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`).join(',')}}`;
  return JSON.stringify(value);
}

/** Per-Master row lock is shared by every map command/read: arrivals and user actions have one order. */
async function lockMaster(tx: GameTransaction, masterId: string) {
  const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
  if (!master) throw new PveError('ERR_PVE_MASTER_NOT_FOUND', 404);
  const clock = await tx.execute<{ now: Date }>(sql`select clock_timestamp() as now`);
  return { master, now: new Date(clock.rows[0].now) };
}

export class PveService {
  private async activeMap(tx: GameTransaction, masterId: string) {
    const [map] = await tx.select().from(pveMaps).where(and(eq(pveMaps.masterId, masterId), eq(pveMaps.status, 'ACTIVE'))).for('update');
    return map;
  }

  private async emit(tx: GameTransaction, map: MapRow, kind: string, data: CommandResult, now: Date) {
    map.revision += 1;
    await tx.update(pveMaps).set({ revision: map.revision }).where(eq(pveMaps.id, map.id));
    await tx.insert(pveEvents).values({ id: uuid(), masterId: map.masterId, mapId: map.id,
      revision: map.revision, kind, data, occurredAt: now });
  }

  /** Failed actions roll back their command record and side effects; committed keys replay exactly. */
  async command(masterId: string, operation: string, key: string, body: unknown,
    action: (tx: GameTransaction, now: Date) => Promise<CommandResult>) {
    if (!/^[\x21-\x7e]{1,80}$/.test(key)) throw new PveError('ERR_PVE_IDEMPOTENCY_KEY_REQUIRED', 400);
    const requestHash = createHash('sha256').update(canonical(body)).digest('hex');
    return db.transaction(async tx => {
      const { now } = await lockMaster(tx, masterId);
      const [previous] = await tx.select().from(pveCommands).where(and(eq(pveCommands.masterId, masterId), eq(pveCommands.key, key)));
      if (previous) {
        if (previous.operation !== operation || previous.requestHash !== requestHash) throw new PveError('ERR_PVE_IDEMPOTENCY_CONFLICT');
        return previous.result;
      }
      await this.settle(tx, masterId, now);
      const result = await action(tx, now);
      await tx.insert(pveCommands).values({ id: uuid(), masterId, key, operation, requestHash, result, createdAt: now });
      return result;
    });
  }

  async enter(masterId: string, key: string) {
    return this.command(masterId, 'ENTER', key, {}, async (tx, now) => {
      const current = await this.activeMap(tx, masterId);
      if (current) return { mapId: current.id, floor: current.floor, status: current.status };
      const legacy = await tx.select({ id: combatSessions.id }).from(combatSessions)
        .where(and(eq(combatSessions.masterId, masterId), inArray(combatSessions.status, ['ACTIVE', 'RESOLVING']))).limit(1);
      if (legacy.length) throw new PveError('ERR_PVE_LEGACY_COMBAT_ACTIVE');
      const dungeon = await tx.select({ id: dungeonInstances.id }).from(dungeonInstances)
        .where(and(eq(dungeonInstances.masterId, masterId), eq(dungeonInstances.status, 'ACTIVE'))).limit(1);
      if (dungeon.length) throw new PveError('ERR_PVE_LEGACY_DUNGEON_ACTIVE');
      const [world] = await tx.select().from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt), asc(worlds.id)).limit(1).for('update');
      if (!world) throw new PveError('ERR_PVE_NO_WORLD');
      const [existing] = await tx.select().from(pveMaps).where(and(eq(pveMaps.worldId, world.id), eq(pveMaps.floor, world.currentFloor)));
      if (existing) throw new PveError('ERR_PVE_FLOOR_ALREADY_CLEARED');
      const foes = await tx.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code));
      if (!foes.some(row => row.isBoss) || !foes.some(row => !row.isBoss)) throw new PveError('ERR_PVE_ENCOUNTERS_NOT_CONFIGURED', 503);
      const layout = generatePveLayout(world.worldSeed, world.currentFloor);
      const scale = world.difficultyMultiplier * (1 + (world.currentFloor - 1) * 0.08);
      const [map] = await tx.insert(pveMaps).values({
        id: uuid(), masterId, worldId: world.id, floor: world.currentFloor, layout,
        discovered: revealPveTiles(layout, [], { x: 0, y: 0 }), createdAt: now,
        encounterCatalog: foes.map(foe => ({ code: foe.code, name: foe.name,
          hp: Math.max(1, Math.round(foe.baseHp * scale)), attack: Math.max(1, Math.round(foe.baseAttack * scale)),
          defense: Math.max(0, Math.round(foe.baseDefense * scale)), agi: Math.max(1, foe.baseSpeed),
          silver: Math.floor(foe.baseSilverReward * scale), exp: Math.floor(foe.baseExpReward * scale), boss: foe.isBoss,
        })),
      }).returning();
      await this.emit(tx, map, 'MAP_ENTERED', { floor: map.floor }, now);
      return { mapId: map.id, floor: map.floor, status: map.status };
    });
  }

  private async party(tx: GameTransaction, masterId: string, partyId: string) {
    const [party] = await tx.select().from(masterParties).where(and(eq(masterParties.id, partyId), eq(masterParties.masterId, masterId)));
    if (!party) throw new PveError('ERR_PVE_PARTY_NOT_FOUND', 404);
    const members = await tx.select({ heroId: combatPartySlots.heroId }).from(combatPartySlots)
      .where(eq(combatPartySlots.partyId, partyId)).orderBy(asc(combatPartySlots.slotIndex));
    const ids = members.map(member => member.heroId);
    if (ids.length < 1 || ids.length > 5) throw new PveError('ERR_PVE_INVALID_PARTY', 400);
    return { party, ids };
  }

  private async validateSkills(tx: GameTransaction, plan: PvePlan) {
    const skills = await tx.select().from(heroSkillInstances).where(and(
      inArray(heroSkillInstances.heroId, plan.members.map(member => member.heroId)), eq(heroSkillInstances.isUnlocked, true)));
    for (const member of plan.members) if (member.skillOrder.some(code => !skills.some(skill => skill.heroId === member.heroId && skill.skillCode === code))) {
      throw new PveError('ERR_PVE_SKILL_UNAVAILABLE', 400);
    }
  }

  async saveParty(masterId: string, input: unknown, key: string, partyId?: string) {
    return this.command(masterId, partyId ? `PARTY_UPDATE:${partyId}` : 'PARTY_CREATE', key, input, async (tx, now) => {
      const value = input as { name?: unknown; heroIds?: unknown; plan?: unknown } | null;
      const name = typeof value?.name === 'string' ? value.name.trim() : '';
      const ids = Array.isArray(value?.heroIds) ? value.heroIds : [];
      if (!/^[\p{L}\p{N} _-]{1,60}$/u.test(name) || ids.some(id => typeof id !== 'string')) throw new PveError('ERR_PVE_INVALID_PARTY', 400);
      const plan = validatePvePlan(value?.plan ?? defaultPvePlan(ids), ids);
      if (partyId) {
        const [existing] = await tx.select({ id: masterParties.id }).from(masterParties)
          .where(and(eq(masterParties.id, partyId), eq(masterParties.masterId, masterId)));
        if (!existing) throw new PveError('ERR_PVE_PARTY_NOT_FOUND', 404);
        const busy = await tx.select({ id: pveSquads.id }).from(pveSquads).where(and(eq(pveSquads.partyId, partyId), inArray(pveSquads.status, ACTIVE)));
        if (busy.length) throw new PveError('ERR_PVE_PARTY_DEPLOYED');
      }
      const roster = await tx.select().from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, ids))).orderBy(asc(heroes.id)).for('update');
      if (roster.length !== ids.length || roster.some(hero => ['DEAD', 'DISABLED'].includes(hero.state))) throw new PveError('ERR_PVE_HERO_UNAVAILABLE');
      if ((await tx.select().from(pveHeroReservations).where(inArray(pveHeroReservations.heroId, ids))).length) throw new PveError('ERR_PVE_HERO_DEPLOYED');
      await this.validateSkills(tx, plan);
      const duplicates = await tx.select({ id: masterParties.id }).from(masterParties).where(and(eq(masterParties.masterId, masterId), eq(masterParties.name, name)));
      if (duplicates.some(row => row.id !== partyId)) throw new PveError('ERR_PVE_DUPLICATE_PARTY_NAME');
      const id = partyId ?? uuid();
      if (partyId) {
        await tx.update(masterParties).set({ name, updatedAt: now }).where(eq(masterParties.id, id));
        await tx.delete(combatPartySlots).where(eq(combatPartySlots.partyId, id));
      } else {
        const previous = await tx.select({ id: masterParties.id }).from(masterParties).where(eq(masterParties.masterId, masterId));
        await tx.insert(masterParties).values({ id, masterId, name, isDefault: previous.length === 0, createdAt: now, updatedAt: now });
      }
      await tx.insert(combatPartySlots).values(ids.map((heroId, index) => ({ id: uuid(), masterId, partyId: id, heroId, slotIndex: index })));
      await tx.insert(pvePartyPlans).values({ partyId: id, masterId, plan, updatedAt: now })
        .onConflictDoUpdate({ target: pvePartyPlans.partyId, set: { plan, updatedAt: now } });
      return { partyId: id, plan };
    });
  }

  async savePlan(masterId: string, partyId: string, input: unknown, key: string) {
    return this.command(masterId, `PLAN:${partyId}`, key, input, async (tx, now) => {
      const { ids } = await this.party(tx, masterId, partyId);
      const deployed = await tx.select({ id: pveSquads.id }).from(pveSquads).where(and(eq(pveSquads.partyId, partyId), inArray(pveSquads.status, ACTIVE)));
      if (deployed.length) throw new PveError('ERR_PVE_PARTY_DEPLOYED');
      const plan = validatePvePlan(input, ids);
      await this.validateSkills(tx, plan);
      await tx.insert(pvePartyPlans).values({ masterId, partyId, plan, updatedAt: now })
        .onConflictDoUpdate({ target: pvePartyPlans.partyId, set: { plan, updatedAt: now } });
      return { partyId, plan };
    });
  }

  async deploy(masterId: string, partyId: string, key: string) {
    return this.command(masterId, `DEPLOY:${partyId}`, key, {}, async (tx, now) => {
      const map = await this.activeMap(tx, masterId);
      if (!map) throw new PveError('ERR_PVE_NO_ACTIVE_MAP');
      const squads = await tx.select().from(pveSquads).where(and(eq(pveSquads.masterId, masterId), inArray(pveSquads.status, ACTIVE)));
      if (squads.some(squad => squad.partyId === partyId)) throw new PveError('ERR_PVE_PARTY_DEPLOYED');
      if (squads.length >= GAME_CONSTANTS.PVE.MAX_DEPLOYED_SQUADS) throw new PveError('ERR_PVE_SQUAD_LIMIT');
      const { party, ids } = await this.party(tx, masterId, partyId);
      const roster = await tx.select().from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, ids))).orderBy(asc(heroes.id)).for('update');
      if (roster.length !== ids.length || roster.some(hero => ['DEAD', 'DISABLED'].includes(hero.state) || hero.hp <= 0)) throw new PveError('ERR_PVE_HERO_UNAVAILABLE');
      if ((await tx.select().from(pveHeroReservations).where(inArray(pveHeroReservations.heroId, ids))).length) throw new PveError('ERR_PVE_HERO_DEPLOYED');
      await this.checkOtherActivities(tx, masterId, ids);
      const [stored] = await tx.select().from(pvePartyPlans).where(eq(pvePartyPlans.partyId, partyId));
      const plan = stored ? validatePvePlan(stored.plan, ids) : defaultPvePlan(ids);
      await this.validateSkills(tx, plan);
      const { rations: needed } = await chargeCombatDispatch(tx, masterId, ids, now);
      const [squad] = await tx.insert(pveSquads).values({ id: uuid(), masterId, mapId: map.id, partyId, name: party.name, plan, deployedAt: now }).returning();
      await tx.insert(pveHeroReservations).values(ids.map(heroId => ({ heroId, masterId, mapId: map.id, squadId: squad.id, reservedAt: now })));
      await this.emit(tx, map, 'SQUAD_DEPLOYED', { squadId: squad.id, name: party.name, rationsConsumed: needed }, now);
      return { squadId: squad.id, mapId: map.id, rationsConsumed: needed };
    });
  }

  private async checkOtherActivities(tx: GameTransaction, masterId: string, ids: string[]) {
    // One transaction owns one PostgreSQL connection: queries must be sequential.
    const workers = await tx.select().from(buildingWorkerAssignments).where(inArray(buildingWorkerAssignments.heroInstanceId, ids));
    const treatment = await tx.select().from(heroTreatments).where(and(inArray(heroTreatments.heroId, ids), inArray(heroTreatments.status, ['ACTIVE', 'QUEUED'])));
    const expeditions = await tx.select({ id: expeditionMembers.heroId }).from(expeditionMembers)
      .innerJoin(heroExpeditions, eq(heroExpeditions.id, expeditionMembers.expeditionId))
      .where(and(inArray(expeditionMembers.heroId, ids), inArray(heroExpeditions.status, ['TRAVELING', 'RETURNING'])));
    const legacy = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId, masterId), inArray(combatSessions.status, ['ACTIVE', 'RESOLVING'])));
    if (workers.length || treatment.length || expeditions.length || legacy.length) throw new PveError('ERR_PVE_HERO_BUSY');
  }

  private async squad(tx: GameTransaction, masterId: string, squadId: string) {
    const [squad] = await tx.select().from(pveSquads).where(and(eq(pveSquads.id, squadId), eq(pveSquads.masterId, masterId))).for('update');
    if (!squad) throw new PveError('ERR_PVE_SQUAD_NOT_FOUND', 404);
    if (!ACTIVE.includes(squad.status)) throw new PveError('ERR_PVE_SQUAD_WITHDRAWN');
    const map = await this.activeMap(tx, masterId);
    if (!map || map.id !== squad.mapId) throw new PveError('ERR_PVE_MAP_CLEARED');
    return { squad, map };
  }

  async move(masterId: string, squadId: string, destination: unknown, key: string) {
    return this.command(masterId, `MOVE:${squadId}`, key, destination, async (tx, now) => {
      const { squad, map } = await this.squad(tx, masterId, squadId);
      if (squad.status === 'FIGHTING') throw new PveError('ERR_PVE_SQUAD_FIGHTING');
      const to = destination as PvePoint | null;
      if (!to || typeof to !== 'object') throw new PveError('ERR_PVE_INVALID_DESTINATION', 400);
      const route = findPvePath(map.layout, map.discovered, squad, to);
      if (route.length === 0) {
        const tile = map.layout.tiles[pveTileId(squad, map.layout.width)];
        if (['ENEMY', 'BOSS'].includes(tile.kind) && !map.cleared.includes(tile.id)) {
          squad.autoExplore = false;
          await tx.update(pveSquads).set({ autoExplore: false }).where(eq(pveSquads.id, squad.id));
          await this.fight(tx, map, squad, tile, now);
          return { squadId, mapId: map.id, battleId: squad.lastBattleId };
        }
        throw new PveError('ERR_PVE_ALREADY_AT_DESTINATION', 400);
      }
      const keepEta = squad.nextStepAt && squad.route[0]?.x === route[0].x && squad.route[0]?.y === route[0].y;
      const nextStepAt = keepEta ? squad.nextStepAt! : new Date(now.getTime() + STEP_MS);
      await tx.update(pveSquads).set({ route, nextStepAt, status: 'MOVING', autoExplore: false }).where(eq(pveSquads.id, squadId));
      await this.emit(tx, map, 'MOVE_ORDERED', { squadId, destination: { x: to.x, y: to.y }, steps: route.length }, now);
      return { squadId, mapId: map.id, route, nextStepAt: nextStepAt.toISOString(), secondsPerTile: GAME_CONSTANTS.PVE.SECONDS_PER_TILE };
    });
  }

  async setAuto(masterId: string, squadId: string, input: unknown, key: string) {
    return this.command(masterId, `AUTO:${squadId}`, key, input, async (tx, now) => {
      const { squad, map } = await this.squad(tx, masterId, squadId);
      if (!input || typeof input !== 'object' || typeof (input as { enabled?: unknown }).enabled !== 'boolean') {
        throw new PveError('ERR_PVE_INVALID_AUTO', 400);
      }
      if (squad.status === 'FIGHTING') throw new PveError('ERR_PVE_SQUAD_FIGHTING');
      const enabled = (input as { enabled: boolean }).enabled;
      squad.autoExplore = enabled;
      if (enabled && squad.status === 'IDLE') await this.scheduleAuto(tx, map, squad, now);
      if (!enabled && squad.status === 'MOVING') { squad.status = 'IDLE'; squad.route = []; squad.nextStepAt = null; }
      await tx.update(pveSquads).set({ autoExplore: squad.autoExplore, status: squad.status, route: squad.route, nextStepAt: squad.nextStepAt }).where(eq(pveSquads.id, squad.id));
      await this.emit(tx, map, 'AUTO_CHANGED', { squadId, enabled: squad.autoExplore }, now);
      return { squadId, enabled: squad.autoExplore, status: squad.status, nextStepAt: squad.nextStepAt?.toISOString() ?? null };
    });
  }

  private async scheduleAuto(tx: GameTransaction, map: MapRow, squad: SquadRow, now: Date) {
    const visits = await tx.select({ data: pveEvents.data }).from(pveEvents)
      .where(and(eq(pveEvents.mapId, map.id), eq(pveEvents.kind, 'SQUAD_ARRIVED')));
    const visited = new Set([0, ...visits.map(event => pveTileId({ x: Number(event.data.x), y: Number(event.data.y) }, map.layout.width))]);
    const otherSquads = await tx.select().from(pveSquads).where(and(eq(pveSquads.mapId, map.id), inArray(pveSquads.status, ACTIVE)));
    const claimed = new Set(otherSquads.filter(row => row.id !== squad.id && row.route.length).map(row => pveTileId(row.route.at(-1)!, map.layout.width)));
    const candidates = map.discovered.filter(id => {
      const tile = map.layout.tiles[id];
      const remainingEnemy = ['ENEMY', 'BOSS'].includes(tile.kind) && !map.cleared.includes(id);
      return (!visited.has(id) || remainingEnemy) && id !== pveTileId(squad, map.layout.width);
    });
    const paths = candidates.map(id => ({ id, route: findPvePath(map.layout, map.discovered, squad, map.layout.tiles[id]) }))
      .sort((a, b) => Number(claimed.has(a.id)) - Number(claimed.has(b.id)) || a.route.length - b.route.length || a.id - b.id);
    if (!paths.length) {
      squad.autoExplore = false; squad.status = 'IDLE'; squad.route = []; squad.nextStepAt = null;
      await this.emit(tx, map, 'AUTO_STOPPED', { squadId: squad.id, reason: 'EXPLORED' }, now);
      return;
    }
    squad.route = paths[0].route; squad.status = 'MOVING'; squad.nextStepAt = new Date(now.getTime() + STEP_MS);
  }

  async recall(masterId: string, squadId: string, key: string) {
    return this.command(masterId, `RECALL:${squadId}`, key, {}, async (tx, now) => {
      const { squad, map } = await this.squad(tx, masterId, squadId);
      if (squad.status === 'FIGHTING') throw new PveError('ERR_PVE_SQUAD_FIGHTING');
      await tx.update(pveSquads).set({ status: 'WITHDRAWN', autoExplore: false, route: [], nextStepAt: null, withdrawnAt: now }).where(eq(pveSquads.id, squadId));
      await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.squadId, squadId));
      await this.emit(tx, map, 'SQUAD_RECALLED', { squadId }, now);
      return { squadId, status: 'WITHDRAWN' };
    });
  }

  private async settle(tx: GameTransaction, masterId: string, now: Date) {
    const map = await this.activeMap(tx, masterId);
    if (!map) return;
    // Chronological, stable tie-break ordering keeps collisions and offline catch-up deterministic.
    for (let step = 0; step < map.layout.tiles.length * GAME_CONSTANTS.PVE.MAX_DEPLOYED_SQUADS; step++) {
      if (map.status !== 'ACTIVE') break;
      const [squad] = await tx.select().from(pveSquads).where(and(eq(pveSquads.mapId, map.id), eq(pveSquads.status, 'MOVING'),
        sql`${pveSquads.nextStepAt} <= ${now}`)).orderBy(asc(pveSquads.nextStepAt), asc(pveSquads.id)).limit(1).for('update');
      if (!squad) break;
      if (!squad.route.length || !squad.nextStepAt) throw new Error('Invalid persisted PvE route.');
      const arrivedAt = squad.nextStepAt;
      const [point, ...remaining] = squad.route;
      squad.x = point.x; squad.y = point.y; squad.route = remaining;
      squad.status = remaining.length ? 'MOVING' : 'IDLE';
      squad.nextStepAt = remaining.length ? new Date(arrivedAt.getTime() + STEP_MS) : null;
      map.discovered = revealPveTiles(map.layout, map.discovered, point);
      const tile = map.layout.tiles[pveTileId(point, map.layout.width)];
      await this.emit(tx, map, 'SQUAD_ARRIVED', { squadId: squad.id, x: point.x, y: point.y }, arrivedAt);
      if (tile.kind === 'RESOURCE' && !map.collected.includes(tile.id)) {
        if (!tile.resource) throw new Error('Resource node has no reward.');
        const { itemId, quantity } = tile.resource;
        await tx.insert(masterItems).values({ id: uuid(), masterId, itemId, quantity, updatedAt: now })
          .onConflictDoUpdate({ target: [masterItems.masterId, masterItems.itemId], set: { quantity: sql`${masterItems.quantity} + ${quantity}`, updatedAt: now } });
        map.collected.push(tile.id);
        await this.emit(tx, map, 'RESOURCE_COLLECTED', { squadId: squad.id, tileId: tile.id, itemId, quantity }, arrivedAt);
        await questService.recordEvent(masterId, 'COLLECT_RESOURCE', quantity, arrivedAt, tx);
        await eventService.recordEvent(masterId, 'COLLECT_RESOURCE', quantity, arrivedAt, tx);
      }
      if (['ENEMY', 'BOSS'].includes(tile.kind) && !map.cleared.includes(tile.id)) {
        squad.route = []; squad.nextStepAt = null;
        await this.fight(tx, map, squad, tile, arrivedAt);
        if (!map.cleared.includes(tile.id)) squad.autoExplore = false;
      }
      if (map.status === 'ACTIVE' && squad.autoExplore && squad.status === 'IDLE') await this.scheduleAuto(tx, map, squad, arrivedAt);
      if (map.status === 'ACTIVE') await tx.update(pveSquads).set({
        x: squad.x, y: squad.y, route: squad.route, status: squad.status, nextStepAt: squad.nextStepAt, lastBattleId: squad.lastBattleId, autoExplore: squad.autoExplore,
      }).where(eq(pveSquads.id, squad.id));
      await tx.update(pveMaps).set({ discovered: map.discovered, cleared: map.cleared, collected: map.collected }).where(eq(pveMaps.id, map.id));
    }
  }

  private async heroUnits(tx: GameTransaction, map: MapRow, squad: SquadRow, now: Date) {
    const reserved = await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.squadId, squad.id));
    const ids = reserved.map(row => row.heroId);
    if (!ids.length) throw new PveError('ERR_PVE_SQUAD_EMPTY');
    const roster = await tx.select().from(heroes).where(inArray(heroes.id, ids)).orderBy(asc(heroes.id)).for('update');
    const states = await tx.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, ids));
    const injuries = await tx.select().from(heroInjuries).where(and(inArray(heroInjuries.heroId, ids), isNull(heroInjuries.healedAt), gt(heroInjuries.naturalHealAt, now)));
    const traits = await tx.select().from(heroPersonalityTraits).where(inArray(heroPersonalityTraits.heroId, ids));
    const relations = await tx.select().from(heroRelationships).where(and(inArray(heroRelationships.heroAId, ids), inArray(heroRelationships.heroBId, ids)));
    const [food] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, map.masterId), eq(masterItems.itemId, 'FOOD')));
    const readiness: Record<string, number> = {};
    const penalty: Record<string, number> = {};
    const personality: Record<string, { loyalty: number; resonance: number }> = {};
    for (const hero of roster) {
      if (['DEAD', 'DISABLED'].includes(hero.state) || hero.hp <= 0) throw new PveError('ERR_PVE_HERO_UNAVAILABLE');
      const state = states.find(row => row.heroId === hero.id);
      const drift = applyDrift(state ?? { hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: now }, now, (food?.quantity ?? 0) > 0);
      if (isImmobilised(drift.hungerScore, drift.fatigueScore)) throw new PveError('ERR_PVE_HERO_EXHAUSTED');
      readiness[hero.id] = starvationMultiplier(drift.hungerScore);
      penalty[hero.id] = Math.min(1, ...injuries.filter(row => row.heroId === hero.id).map(row => injuryMultiplier(row.penaltyPercent)));
      personality[hero.id] = { loyalty: loyaltyCombatMultiplier(traits.find(row => row.heroId === hero.id)?.loyaltyScore ?? 50),
        resonance: Math.max(1, ...relations.filter(row => row.heroAId === hero.id || row.heroBId === hero.id).map(row => resonanceMultiplier(relationshipTier(row.affinityPoints)))) };
      await tx.update(heroSurvivalStates).set({ hungerScore: drift.hungerScore, fatigueScore: drift.fatigueScore,
        lastTickAt: state && state.lastTickAt > now ? state.lastTickAt : now }).where(eq(heroSurvivalStates.heroId, hero.id));
    }
    const units = await combatV2Service.buildHeroUnits(ids, map.masterId, 'HERO', { database: tx, readiness, injuries: penalty, personality });
    return units.map(unit => {
      const hero = roster.find(row => row.id === unit.id)!;
      const member = squad.plan.members.find(row => row.heroId === unit.id)!;
      const hpPct = isV2Origin(hero.originStats) ? hero.currentHpPct : hero.hp / Math.max(1, hero.maxHp);
      const mpPct = isV2Origin(hero.originStats) ? hero.currentMpPct : hero.maxMp > 0 ? hero.mp / hero.maxMp : 0;
      return { ...unit, formationSlot: member.slotIndex, targetPriority: squad.plan.targetPriority, skillOrder: member.skillOrder,
        initialHp: Math.max(1, Math.round(unit.stats.maxHp * hpPct)),
        initialMp: Math.round(unit.stats.maxMp * mpPct),
      };
    });
  }

  private enemyUnits(map: MapRow, tile: PveTile) {
    const normal = map.encounterCatalog.filter(foe => !foe.boss);
    const bosses = map.encounterCatalog.filter(foe => foe.boss);
    const random = mulberry32(tile.seed);
    const pick = (pool: MapRow['encounterCatalog']) => pool[Math.floor(random() * pool.length)];
    const foes = tile.kind === 'BOSS' ? [pick(bosses), pick(normal), pick(normal)]
      : Array.from({ length: 1 + Math.floor(random() * 3) }, () => pick(normal));
    const units: CombatV2UnitInput[] = foes.map((foe, index) => {
      const stats: DerivedStats = { maxHp: foe.hp, maxMp: 0, atk: foe.attack, matk: foe.attack, def: foe.defense, mdef: foe.defense,
        hpRegen: 0, mpRegen: 0, critRate: 5, critDamage: 150, accuracy: 0, evasion: 0, blockRate: 0, blockEffect: 0,
        critResistance: 0, critDamageReduction: 0, damageReduction: 0, tenacity: 0, armorPen: 0, magicPen: 0, damageBonus: 0, lifesteal: 0 };
      return { id: `${tile.id}:${index}:${foe.code}`, name: foe.name, side: 'ENEMY', slotIndex: index,
        formationSlot: tile.kind === 'BOSS' ? [4, 0, 2][index] : [0, 2, 4][index], agi: foe.agi, stats, damageType: 'PHYSICAL', targetPriority: 'FRONTLINE' };
    });
    return { units, silver: foes.reduce((sum, foe) => sum + foe.silver, 0), exp: foes.reduce((sum, foe) => sum + foe.exp, 0) };
  }

  private async fight(tx: GameTransaction, map: MapRow, squad: SquadRow, tile: PveTile, now: Date) {
    await tx.execute(sql`select set_config('app.pve_map_id', ${map.id}, true)`);
    let heroUnits: CombatV2UnitInput[];
    try { heroUnits = await this.heroUnits(tx, map, squad, now); }
    catch (error) {
      if (!(error instanceof PveError) || error.message !== 'ERR_PVE_HERO_EXHAUSTED') throw error;
      squad.status = 'IDLE'; squad.route = []; squad.nextStepAt = null;
      await this.emit(tx, map, 'SQUAD_EXHAUSTED', { squadId: squad.id }, now);
      return;
    }
    squad.status = 'FIGHTING';
    const foes = this.enemyUnits(map, tile);
    const combatSeed = pveSeed(`pve:combat:v1:${map.floor}:${tile.seed}`);
    const report = resolveBattleV2(heroUnits, foes.units, { random: mulberry32(combatSeed), maxRounds: 30, timeoutIsDraw: true });
    const battleId = uuid();
    await tx.insert(combatSessions).values({ id: battleId, masterId: map.masterId, worldId: map.worldId, partyId: squad.partyId,
      status: 'COMPLETED', createdAt: now, finishedAt: now, combatState: {
        engine: 'PVE_MAP', combatAlgorithmVersion: 1, mapId: map.id, floor: map.floor, tileId: tile.id,
        heroes: heroUnits, enemies: foes.units, seed: combatSeed, maxRounds: 30, timeoutIsDraw: true,
      }, battleReport: report as unknown as CommandResult });
    const settlement = await settleCombat(tx, { masterId: map.masterId, sessionId: battleId, worldId: map.worldId, floor: map.floor,
      report, silverReward: foes.silver, heroExpReward: foes.exp, masterExpReward: foes.exp, transactionType: 'PVE_MAP_REWARD', now });
    for (const hero of heroUnits) {
      const [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, hero.id));
      if (state) await tx.update(heroSurvivalStates).set({ ...applyActivity(state.hungerScore, state.fatigueScore, 'BATTLE'),
        lastTickAt: state.lastTickAt > now ? state.lastTickAt : now }).where(eq(heroSurvivalStates.heroId, hero.id));
    }
    const fallen = settlement.deaths.map(hero => hero.heroId);
    if (fallen.length) await tx.delete(pveHeroReservations).where(inArray(pveHeroReservations.heroId, fallen));
    const survived = report.units.some(unit => unit.side === 'HERO' && unit.alive);
    squad.status = survived ? 'IDLE' : 'DEFEATED'; squad.route = []; squad.nextStepAt = null; squad.lastBattleId = battleId;
    if (!survived) await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.squadId, squad.id));
    const won = report.winner === 'HERO';
    const bossCleared = won && tile.kind === 'BOSS';
    const result = { ...settlement, floor: map.floor, nextFloor: bossCleared ? map.floor + 1 : map.floor, bossCleared };
    await tx.insert(pveBattles).values({ id: battleId, masterId: map.masterId, mapId: map.id, squadId: squad.id,
      tileId: tile.id, combatSessionId: battleId, report, settlement: result, createdAt: now });
    await tx.update(pveSquads).set({ status: squad.status, x: squad.x, y: squad.y, route: [], nextStepAt: null, lastBattleId: battleId }).where(eq(pveSquads.id, squad.id));
    if (won) {
      map.cleared.push(tile.id);
      await tx.update(pveMaps).set({ cleared: map.cleared }).where(eq(pveMaps.id, map.id));
      await questService.recordEvent(map.masterId, 'WIN_BATTLE', 1, now, tx);
      await eventService.recordEvent(map.masterId, 'WIN_BATTLE', 1, now, tx);
    }
    await this.emit(tx, map, 'BATTLE_COMPLETED', { squadId: squad.id, battleId, tileId: tile.id, winner: report.winner, ...result }, now);
    if (bossCleared) {
      map.status = 'CLEARED'; map.clearedAt = now;
      await tx.update(pveMaps).set({ status: 'CLEARED', clearedAt: now, cleared: map.cleared }).where(eq(pveMaps.id, map.id));
      await tx.update(worlds).set({ currentFloor: sql`greatest(${worlds.currentFloor}, ${map.floor + 1})` }).where(eq(worlds.id, map.worldId));
      await tx.update(pveSquads).set({ status: 'WITHDRAWN', autoExplore: false, route: [], nextStepAt: null, withdrawnAt: now })
        .where(and(eq(pveSquads.mapId, map.id), inArray(pveSquads.status, ACTIVE)));
      await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.mapId, map.id));
      await questService.recordEvent(map.masterId, 'CLEAR_FLOOR', 1, now, tx);
      await eventService.recordEvent(map.masterId, 'CLEAR_FLOOR', 1, now, tx);
      await leaderboardService.recordFloor(map.masterId, map.floor + 1, report.rounds, now, tx);
      await this.emit(tx, map, 'MAP_CLEARED', { floor: map.floor, nextFloor: map.floor + 1, battleId }, now);
    }
  }

  async state(masterId: string, cursor = 0, cursorMapId?: string) {
    return db.transaction(async tx => {
      const { now } = await lockMaster(tx, masterId);
      await this.settle(tx, masterId, now);
      const [map] = await tx.select().from(pveMaps).where(eq(pveMaps.masterId, masterId)).orderBy(desc(pveMaps.createdAt), desc(pveMaps.id)).limit(1);
      const parties = await tx.select().from(masterParties).where(eq(masterParties.masterId, masterId)).orderBy(asc(masterParties.createdAt));
      const partyIds = parties.map(party => party.id);
      const members = partyIds.length ? await tx.select({ partyId: combatPartySlots.partyId, heroId: heroes.id, name: heroes.name,
        state: heroes.state, hp: heroes.hp, rarity: heroes.rarity }).from(combatPartySlots).innerJoin(heroes, eq(heroes.id, combatPartySlots.heroId))
        .where(inArray(combatPartySlots.partyId, partyIds)).orderBy(asc(combatPartySlots.slotIndex)) : [];
      const plans = partyIds.length ? await tx.select().from(pvePartyPlans).where(inArray(pvePartyPlans.partyId, partyIds)) : [];
      const skills = members.length ? await tx.select({ heroId: heroSkillInstances.heroId, code: heroSkillInstances.skillCode }).from(heroSkillInstances)
        .where(and(inArray(heroSkillInstances.heroId, members.map(m => m.heroId)), eq(heroSkillInstances.isUnlocked, true))) : [];
      const partyViews = parties.map(party => {
        const rows = members.filter(member => member.partyId === party.id);
        const ids = rows.map(row => row.heroId);
        let plan: PvePlan | null = null;
        try { plan = validatePvePlan(plans.find(row => row.partyId === party.id)?.plan ?? defaultPvePlan(ids), ids); } catch { /* stale party membership requires a new plan */ }
        return { id: party.id, name: party.name, isDefault: party.isDefault, plan,
          members: rows.map(member => ({ ...member, skills: skills.filter(skill => skill.heroId === member.heroId).map(skill => skill.code) })) };
      });
      if (!map) return { serverNow: now.toISOString(), map: null, squads: [], parties: partyViews, events: [], cursor: 0 };
      const squads = await tx.select().from(pveSquads).where(eq(pveSquads.mapId, map.id)).orderBy(asc(pveSquads.deployedAt), asc(pveSquads.id));
      const reservations = await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.mapId, map.id));
      const squadViews = squads.map(squad => {
        const reserved = new Set(reservations.filter(row => row.squadId === squad.id).map(row => row.heroId));
        const ordered = partyViews.find(party => party.id === squad.partyId)?.members.map(member => member.heroId) ?? [];
        const leaderHeroId = [...ordered, ...squad.plan.members.map(member => member.heroId)].find(id => reserved.has(id)) ?? null;
        return { ...squad, leaderHeroId };
      });
      const known = new Set(map.discovered);
      const tiles = map.layout.tiles.map(tile => known.has(tile.id) ? { id: tile.id, x: tile.x, y: tile.y, kind: tile.kind,
        cleared: map.cleared.includes(tile.id), collected: map.collected.includes(tile.id), resource: tile.resource }
        : { id: tile.id, x: tile.x, y: tile.y, kind: 'UNKNOWN' });
      const after = cursorMapId === map.id ? cursor : 0;
      const events = await tx.select().from(pveEvents).where(and(eq(pveEvents.mapId, map.id), gt(pveEvents.revision, after)))
        .orderBy(asc(pveEvents.revision)).limit(100);
      const [food] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, 'FOOD')));
      return { serverNow: now.toISOString(), map: { id: map.id, floor: map.floor, status: map.status,
        width: map.layout.width, height: map.layout.height, algorithmVersion: map.layout.algorithmVersion, tiles, revision: map.revision },
        squads: squadViews, parties: partyViews, events, cursor: events.at(-1)?.revision ?? after, food: food?.quantity ?? 0,
        secondsPerTile: GAME_CONSTANTS.PVE.SECONDS_PER_TILE, maxSquads: GAME_CONSTANTS.PVE.MAX_DEPLOYED_SQUADS };
    });
  }

  async battle(masterId: string, battleId: string) {
    const [battle] = await db.select().from(pveBattles).where(and(eq(pveBattles.id, battleId), eq(pveBattles.masterId, masterId)));
    if (!battle) throw new PveError('ERR_PVE_BATTLE_NOT_FOUND', 404);
    return battle;
  }

  async battles(masterId: string, before?: string, mapId?: string, limit = 30) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 50) throw new PveError('ERR_PVE_INVALID_LIMIT', 400);
    const [cursor] = before ? await db.select({ id: pveBattles.id, createdAt: pveBattles.createdAt }).from(pveBattles)
      .where(and(eq(pveBattles.masterId, masterId), eq(pveBattles.id, before))) : [];
    if (before && !cursor) throw new PveError('ERR_PVE_BATTLE_NOT_FOUND', 404);
    const rows = await db.select({ id: pveBattles.id, mapId: pveBattles.mapId, squadId: pveBattles.squadId,
      name: pveSquads.name, tileId: pveBattles.tileId, settlement: pveBattles.settlement, createdAt: pveBattles.createdAt,
      winner: sql<string>`${pveBattles.report}->>'winner'`,
    }).from(pveBattles).innerJoin(pveSquads, eq(pveSquads.id, pveBattles.squadId))
      .where(and(eq(pveBattles.masterId, masterId), ...(mapId ? [eq(pveBattles.mapId, mapId)] : []),
        ...(cursor ? [or(lt(pveBattles.createdAt, cursor.createdAt), and(eq(pveBattles.createdAt, cursor.createdAt), lt(pveBattles.id, cursor.id)))] : [])))
      .orderBy(desc(pveBattles.createdAt), desc(pveBattles.id)).limit(limit);
    return { battles: rows, nextCursor: rows.length === limit ? rows.at(-1)!.id : null };
  }
}

export const pveService = new PveService();
