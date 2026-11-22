import { alchemyService, addItem, reserveConsumables, returnConsumables } from '../base/alchemy.service.js';
import { createHash } from 'node:crypto';
import { and, asc, desc, eq, gt, inArray, isNull, lt, or, sql } from 'drizzle-orm';
import { v4 as uuid } from 'uuid';
import {
  GAME_CONSTANTS, defaultPvePlan, findPvePath, mulberry32, pveSeed, pveTileId,
  revealPveTiles, validatePvePlan, type DerivedStats, type PvePlan, type PvePoint, type PveTile,
  createPveExploration, materializePveArea, pveAreaPath, pveAutoAction, pveObserve, pveEnemyStep,
  pveVisibleEnemies, pveReveal, pveWitnessPortal, completePveObjective, pveLineOfSight,
  type PveEnemy,
  defaultPveRecallPolicy, PVE_TELEPORT_STONE,
} from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import type { GameTransaction } from '../../database/transaction.js';
import {
  buildingWorkerAssignments, combatPartySlots, combatSessions, dungeonInstances, enemyTemplates, expeditionMembers, heroExpeditions,
  heroInjuries, heroPersonalityTraits, heroRelationships, heroSkillInstances, heroSurvivalStates, heroTreatments,
  heroes, masterItems, masterParties, masters, pveBattles, pveCommands, pveEvents, pveHeroReservations,
  pveMaps, pvePartyPlans, pveSquads, pveFloorRules, worlds, heroConsumables, pveConsumableDrops,
} from '../../database/drizzle-schema.js';
import { combatV2Service } from '../combat/combat-v2.service.js';
import { resolveBattleV2, type CombatV2UnitInput, type CombatV2Report, type CombatChoice } from '../combat/combat-v2.engine.js';
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
type LiveBattle = {
  mapId: string; squadId: string; tile: PveTile;
  encounter?: { enemy: PveEnemy; ambush: boolean; areaId: string };
  heroes: CombatV2UnitInput[]; foes: { units: CombatV2UnitInput[]; silver: number; exp: number };
  seed: number; choices: Record<string, CombatChoice>; watching?: boolean; deadline: number; report: CombatV2Report;
};
const ACTIVE = ['IDLE', 'MOVING', 'FIGHTING'];
const STEP_MS = GAME_CONSTANTS.PVE.SECONDS_PER_TILE * 1000;
export function pveDevToolsEnabled() {
  return ['development', 'test'].includes(process.env.NODE_ENV ?? 'development') && process.env.PVE_DEV_TOOLS !== '0';
}

function recallAtPoint(map: MapRow, squad: SquadRow) {
  return map.recallPoints.some(p => p.areaId === squad.areaId && p.x === squad.x && p.y === squad.y);
}

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
    const result = await db.transaction(async tx => {
      const { now } = await lockMaster(tx, masterId);
      const [previous] = await tx.select().from(pveCommands).where(and(eq(pveCommands.masterId, masterId), eq(pveCommands.key, key)));
      if (previous) {
        if (previous.operation !== operation || previous.requestHash !== requestHash) throw new PveError('ERR_PVE_IDEMPOTENCY_CONFLICT');
        return previous.result;
      }
      if (await this.settle(tx, masterId, now)) return { catchupPending: true };
      const result = await action(tx, now);
      await tx.insert(pveCommands).values({ id: uuid(), masterId, key, operation, requestHash, result, createdAt: now });
      return result;
    });
    // Commit catch-up progress, but never execute a new order ahead of older due events.
    if (result.catchupPending) throw new PveError('ERR_PVE_CATCHUP_PENDING', 503);
    return result;
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
      const [existing] = await tx.select().from(pveMaps).where(and(eq(pveMaps.worldId, world.id), eq(pveMaps.floor, world.currentFloor), eq(pveMaps.run, world.pveRun)));
      if (existing) throw new PveError('ERR_PVE_FLOOR_ALREADY_CLEARED');
      const foes = await tx.select().from(enemyTemplates).where(eq(enemyTemplates.isActive, true)).orderBy(asc(enemyTemplates.code));
      if (!foes.some(row => row.isBoss) || !foes.some(row => !row.isBoss)) throw new PveError('ERR_PVE_ENCOUNTERS_NOT_CONFIGURED', 503);
      const exploration = createPveExploration(world.worldSeed, world.currentFloor);
      const [rule] = await tx.select().from(pveFloorRules).where(eq(pveFloorRules.floor, world.currentFloor));
      const root = exploration.areas.floor;
      const layout = { algorithmVersion: exploration.version, width: root.width, height: root.height, tiles: root.tiles };
      const scale = world.difficultyMultiplier * (1 + (world.currentFloor - 1) * 0.08);
      const [map] = await tx.insert(pveMaps).values({
        id: uuid(), masterId, worldId: world.id, floor: world.currentFloor, run: world.pveRun,
        recallPolicy: rule?.recallPolicy ?? defaultPveRecallPolicy(world.currentFloor), layout, exploration,
        discovered: root.discovered, createdAt: now,
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
      const value = input as { name?: unknown; heroIds?: unknown; plan?: unknown; loadouts?: Record<string, unknown> } | null;
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
      if (value?.loadouts) {
        if (typeof value.loadouts !== 'object' || Array.isArray(value.loadouts) || Object.keys(value.loadouts).some(id => !ids.includes(id))) throw new PveError('ERR_CONSUMABLE_CONFIG',400);
        for (const heroId of ids) if (value.loadouts[heroId]) await alchemyService.configure(tx,masterId,heroId,value.loadouts[heroId]);
      }
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
      await reserveConsumables(tx, masterId, squad.id, ids);
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
      if (map.exploration) {
        const value = destination as (PvePoint & { areaId?: string }) | null;
        if (!value || value.areaId !== squad.areaId) throw new PveError('ERR_PVE_AREA_MISMATCH', 400);
        const area = map.exploration.areas[squad.areaId];
        const route = pveAreaPath(area, squad, value, area.discovered);
        if (!route?.length) throw new PveError('ERR_PVE_INVALID_DESTINATION', 400);
        const keepEta = !squad.pendingPortalId && squad.nextStepAt && squad.route[0]?.x === route[0].x && squad.route[0]?.y === route[0].y;
        const nextStepAt = keepEta ? squad.nextStepAt! : new Date(now.getTime() + STEP_MS);
        await tx.update(pveSquads).set({ route, pendingPortalId: null, nextStepAt, status: 'MOVING', autoExplore: false }).where(eq(pveSquads.id, squad.id));
        await this.emit(tx, map, 'MOVE_ORDERED', { squadId, areaId: squad.areaId, destination: value }, now);
        return { squadId, areaId: squad.areaId, route, nextStepAt: nextStepAt.toISOString(), secondsPerTile: 1 };
      }
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
      if (!enabled && squad.status === 'MOVING') { squad.status = 'IDLE'; squad.route = []; squad.nextStepAt = null; squad.pendingPortalId = null; }
      await tx.update(pveSquads).set({ autoExplore: squad.autoExplore, status: squad.status, route: squad.route, nextStepAt: squad.nextStepAt, pendingPortalId: squad.pendingPortalId }).where(eq(pveSquads.id, squad.id));
      if (map.exploration) await this.saveExploration(tx, map);
      await this.emit(tx, map, 'AUTO_CHANGED', { squadId, enabled: squad.autoExplore }, now);
      return { squadId, enabled: squad.autoExplore, status: squad.status, nextStepAt: squad.nextStepAt?.toISOString() ?? null };
    });
  }

  private async scheduleAuto(tx: GameTransaction, map: MapRow, squad: SquadRow, now: Date) {
    if (map.exploration) {
      const action = pveAutoAction(map.exploration, squad);
      squad.pendingPortalId = null;
      if (action.type === 'STOP') {
        squad.autoExplore = false; squad.status = 'IDLE'; squad.route = []; squad.nextStepAt = null;
        await this.emit(tx, map, 'AUTO_STOPPED', { squadId: squad.id, reason: action.reason }, now);
      } else {
        squad.route = action.type === 'MOVE' ? action.path : [];
        squad.pendingPortalId = action.type === 'PORTAL' ? action.portalId : null;
        squad.status = 'MOVING'; squad.nextStepAt = new Date(now.getTime() + STEP_MS);
      }
      return;
    }
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
      if (map.recallPolicy === 'UNTIL_COMPLETE') throw new PveError('ERR_PVE_RECALL_LOCKED');
      if (!recallAtPoint(map, squad) && map.exploration?.enemies.some(e => e.targetSquadId === squad.id && ['CHASE', 'INVESTIGATE'].includes(e.state))) {
        throw new PveError('ERR_PVE_SQUAD_PURSUED');
      }
      if (map.exploration) {
        for (const enemy of map.exploration.enemies) if (enemy.state !== 'DEAD' && enemy.targetSquadId === squad.id) {
          enemy.targetSquadId = null; enemy.lastSeen = null; enemy.state = 'RETURN'; enemy.nextStepAt ??= now.getTime() + 1500;
        }
        await this.saveExploration(tx, map);
      }
      await tx.update(pveSquads).set({ status: 'WITHDRAWN', autoExplore: false, route: [], pendingPortalId: null, nextStepAt: null, withdrawnAt: now }).where(eq(pveSquads.id, squadId));
      await returnConsumables(tx, masterId, [squadId]);
      await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.squadId, squadId));
      await this.emit(tx, map, 'SQUAD_RECALLED', { squadId }, now);
      return { squadId, status: 'WITHDRAWN' };
    });
  }

  async placeRecallPoint(masterId: string, squadId: string, input: unknown, key: string) {
    return this.command(masterId, `RECALL_POINT:${squadId}`, key, input, async (tx, now) => {
      const { squad, map } = await this.squad(tx, masterId, squadId);
      const value = input as { areaId?: unknown; x?: unknown; y?: unknown } | null;
      if (map.recallPolicy === 'UNTIL_COMPLETE') throw new PveError('ERR_PVE_RECALL_LOCKED');
      if (!value || value.areaId !== squad.areaId || value.x !== squad.x || value.y !== squad.y) throw new PveError('ERR_PVE_AREA_MISMATCH', 400);
      if (squad.status !== 'IDLE') throw new PveError('ERR_PVE_SQUAD_MUST_STOP');
      if (recallAtPoint(map, squad)) throw new PveError('ERR_PVE_RECALL_POINT_EXISTS');
      const [spent] = await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - 1`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, PVE_TELEPORT_STONE), gt(masterItems.quantity, 0))).returning({ quantity: masterItems.quantity });
      if (!spent) throw new PveError('ERR_PVE_TELEPORT_STONE_REQUIRED');
      const point = { areaId: squad.areaId, x: squad.x, y: squad.y, createdBy: squad.id };
      map.recallPoints.push(point);
      await tx.update(pveMaps).set({ recallPoints: map.recallPoints }).where(eq(pveMaps.id, map.id));
      await this.emit(tx, map, 'RECALL_POINT_CREATED', { squadId, ...point }, now);
      return { squadId, mapId: map.id, point, teleportStones: spent.quantity };
    });
  }

  async resetTower(masterId: string, input: unknown, key: string) {
    if (!pveDevToolsEnabled()) throw new PveError('ERR_PVE_DEV_ONLY', 404);
    if (!input || (input as { confirm?: unknown }).confirm !== true) throw new PveError('ERR_PVE_RESET_CONFIRM_REQUIRED', 400);
    // Dev recovery intentionally bypasses offline catch-up and floor/pursuit restrictions.
    if (!/^[\x21-\x7e]{1,80}$/.test(key)) throw new PveError('ERR_PVE_IDEMPOTENCY_KEY_REQUIRED', 400);
    return db.transaction(async tx => {
      const { now } = await lockMaster(tx, masterId);
      const requestHash = createHash('sha256').update(canonical(input)).digest('hex');
      const [previous] = await tx.select().from(pveCommands).where(and(eq(pveCommands.masterId, masterId), eq(pveCommands.key, key)));
      if (previous) {
        if (previous.operation !== 'DEV_RESET_TOWER' || previous.requestHash !== requestHash) throw new PveError('ERR_PVE_IDEMPOTENCY_CONFLICT');
        return previous.result;
      }
      const [world] = await tx.select().from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt), asc(worlds.id)).limit(1).for('update');
      if (!world) throw new PveError('ERR_PVE_NO_WORLD');
      const legacy = await tx.select({ id: combatSessions.id }).from(combatSessions)
        .where(and(eq(combatSessions.masterId, masterId), inArray(combatSessions.status, ['ACTIVE', 'RESOLVING']))).limit(1);
      const dungeon = await tx.select({ id: dungeonInstances.id }).from(dungeonInstances)
        .where(and(eq(dungeonInstances.masterId, masterId), eq(dungeonInstances.status, 'ACTIVE'))).limit(1);
      if (legacy.length || dungeon.length) throw new PveError('ERR_PVE_LEGACY_COMBAT_ACTIVE');
      const map = await this.activeMap(tx, masterId);
      if (map) {
        await this.cancelOtherBattles(tx, map, now);
        const deployed = await tx.select({id:pveSquads.id}).from(pveSquads).where(eq(pveSquads.mapId,map.id));
        await returnConsumables(tx,masterId,deployed.map(s=>s.id));
        if (map.exploration) for (const enemy of map.exploration.enemies) {
          enemy.targetSquadId = null; enemy.nextStepAt = null;
          if (enemy.state !== 'DEAD') enemy.state = 'IDLE';
        }
        await tx.update(pveMaps).set({ status: 'ABANDONED', exploration: map.exploration }).where(eq(pveMaps.id, map.id));
        await this.emit(tx, map, 'TOWER_RESET', { floor: 1, previousFloor: world.currentFloor, run: world.pveRun + 1 }, now);
      }
      await tx.update(pveSquads).set({ status: 'WITHDRAWN', autoExplore: false, route: [], pendingPortalId: null, nextStepAt: null, withdrawnAt: now })
        .where(and(eq(pveSquads.masterId, masterId), inArray(pveSquads.status, ACTIVE)));
      await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.masterId, masterId));
      await tx.update(worlds).set({ currentFloor: 1, pveRun: world.pveRun + 1 }).where(eq(worlds.id, world.id));
      const result = { floor: 1, run: world.pveRun + 1 };
      await tx.insert(pveCommands).values({ id: uuid(), masterId, key, operation: 'DEV_RESET_TOWER', requestHash, result, createdAt: now });
      return result;
    });
  }

  private async settle(tx: GameTransaction, masterId: string, now: Date) {
    const map = await this.activeMap(tx, masterId);
    if (!map) return;
    if (map.exploration) return this.settleExploration(tx, map, now);
    // Chronological, stable tie-break ordering keeps collisions and offline catch-up deterministic.
    for (let step = 0; step < map.layout.tiles.length * GAME_CONSTANTS.PVE.MAX_DEPLOYED_SQUADS; step++) {
      if (map.status !== 'ACTIVE') break;
      const [squad] = await tx.select().from(pveSquads).where(and(eq(pveSquads.mapId, map.id), eq(pveSquads.status, 'MOVING'),
        sql`${pveSquads.nextStepAt} <= ${now}`)).orderBy(asc(pveSquads.nextStepAt), asc(pveSquads.id)).limit(1).for('update');
      await this.advanceExpiredBattles(tx,map,new Date(Math.min(now.getTime(),squad?.nextStepAt?.getTime() ?? now.getTime())));
      if (!squad || map.status !== 'ACTIVE') break;
      if (!squad.route.length || !squad.nextStepAt) throw new Error('Invalid persisted PvE route.');
      const arrivedAt = squad.nextStepAt;
      const [point, ...remaining] = squad.route;
      squad.x = point.x; squad.y = point.y;
      await this.pickupConsumables(tx, map, squad, arrivedAt);
      squad.route = remaining;
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

  async portal(masterId: string, squadId: string, input: unknown, key: string) {
    return this.command(masterId, `PORTAL:${squadId}`, key, input, async (tx, now) => {
      const { squad, map } = await this.squad(tx, masterId, squadId);
      const value = input as { areaId?: string; portalId?: string } | null;
      if (!map.exploration || value?.areaId !== squad.areaId) throw new PveError('ERR_PVE_AREA_MISMATCH', 400);
      const portal = map.exploration.areas[squad.areaId].portals.find(p => p.id === value.portalId);
      if (!portal || portal.x !== squad.x || portal.y !== squad.y) throw new PveError('ERR_PVE_INVALID_PORTAL', 400);
      if (squad.status === 'FIGHTING') throw new PveError('ERR_PVE_SQUAD_FIGHTING');
      const nextStepAt = squad.pendingPortalId === portal.id && squad.nextStepAt ? squad.nextStepAt : new Date(now.getTime() + STEP_MS);
      await tx.update(pveSquads).set({ route: [], pendingPortalId: portal.id, status: 'MOVING', autoExplore: false, nextStepAt }).where(eq(pveSquads.id, squad.id));
      await this.emit(tx, map, 'PORTAL_ORDERED', { squadId, areaId: squad.areaId, portalId: portal.id }, now);
      return { squadId, areaId: squad.areaId, portalId: portal.id, nextStepAt: nextStepAt.toISOString() };
    });
  }

  private async saveExploration(tx: GameTransaction, map: MapRow) {
    await tx.update(pveMaps).set({ exploration: map.exploration }).where(eq(pveMaps.id, map.id));
  }

  private async persistExplorer(tx: GameTransaction, s: SquadRow) {
    await tx.update(pveSquads).set({ x: s.x, y: s.y, areaId: s.areaId, status: s.status, route: s.route,
      pendingPortalId: s.pendingPortalId, nextStepAt: s.nextStepAt, autoExplore: s.autoExplore, lastBattleId: s.lastBattleId }).where(eq(pveSquads.id, s.id));
  }

  private async settleExploration(tx: GameTransaction, map: MapRow, now: Date) {
    const world = map.exploration!;
    const squads = await tx.select().from(pveSquads).where(and(eq(pveSquads.mapId, map.id), inArray(pveSquads.status, ACTIVE)))
      .orderBy(asc(pveSquads.id)).for('update');
    // No wall-clock polling ticks: idle enemies wake only when a squad movement reveals a target.
    // Every due movement is processed before a command; elapsed client time is never trusted.
    let processed = 0;
    while (map.status === 'ACTIVE' && processed++ < 512) {
      const liveSessions = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId,map.masterId),eq(combatSessions.status,'PVE_LIVE')));
      const due = [
        ...squads.filter(s => s.status === 'MOVING' && s.nextStepAt).map(s => ({ at: s.nextStepAt!.getTime(), id: `s:${s.id}`, squad: s, enemy: null as PveEnemy | null, battle: null as typeof liveSessions[number] | null })),
        ...world.enemies.filter(e => e.nextStepAt !== null && e.state !== 'DEAD').map(e => ({ at: e.nextStepAt!, id: `e:${e.id}`, squad: null as SquadRow | null, enemy: e, battle: null as typeof liveSessions[number] | null })),
        ...liveSessions.filter(b=>(b.combatState as unknown as LiveBattle).mapId===map.id).map(b=>({at:(b.combatState as unknown as LiveBattle).deadline,id:`b:${b.id}`,squad:null as SquadRow | null,enemy:null as PveEnemy | null,battle:b})),
      ].filter(v => v.at <= now.getTime()).sort((a, b) => a.at - b.at || a.id.localeCompare(b.id));
      if (!due.length) break;
      const step = due[0], at = new Date(step.at);
      if (step.battle) {
        await this.resolveLive(tx,map,step.battle.id,step.battle.combatState as unknown as LiveBattle,at,true);
        const refreshed = await tx.select().from(pveSquads).where(and(eq(pveSquads.mapId,map.id),inArray(pveSquads.status,ACTIVE))).orderBy(asc(pveSquads.id));
        squads.splice(0,squads.length,...refreshed);
        continue;
      }
      const before = new Map(squads.map(s => [s.id, new Set(pveVisibleEnemies(world, s).map(e => e.id))]));
      if (step.squad) {
        const s = step.squad;
        if (s.pendingPortalId) {
          const p = world.areas[s.areaId].portals.find(p => p.id === s.pendingPortalId);
          if (!p || s.x !== p.x || s.y !== p.y) throw new Error('Invalid persisted PvE portal.');
          pveWitnessPortal(world, s, p, step.at);
          materializePveArea(world, p.toAreaId);
          s.areaId = p.toAreaId; s.x = p.arrival.x; s.y = p.arrival.y;
          s.pendingPortalId = null; s.route = []; s.status = 'IDLE'; s.nextStepAt = null;
          await this.emit(tx, map, 'AREA_ENTERED', { squadId: s.id, areaId: s.areaId, portalId: p.id }, at);
        } else {
          const [p, ...remaining] = s.route;
          if (!p) throw new Error('Invalid persisted PvE route.');
          s.x = p.x; s.y = p.y; s.route = remaining; s.status = remaining.length ? 'MOVING' : 'IDLE';
          s.nextStepAt = remaining.length ? new Date(step.at + STEP_MS) : null;
        }
        await this.pickupConsumables(tx, map, s, at);
        const area = world.areas[s.areaId];
        pveReveal(area, s);
        await this.emit(tx, map, 'SQUAD_ARRIVED', { squadId: s.id, areaId: s.areaId, x: s.x, y: s.y }, at);
        const tile = area.tiles[pveTileId(s, area.width)];
        if (tile.resource && !area.collected.includes(tile.id)) {
          const { itemId, quantity } = tile.resource;
          await tx.insert(masterItems).values({ id: uuid(), masterId: map.masterId, itemId, quantity, updatedAt: now })
            .onConflictDoUpdate({ target: [masterItems.masterId, masterItems.itemId], set: { quantity: sql`${masterItems.quantity} + ${quantity}`, updatedAt: now } });
          area.collected.push(tile.id);
          await this.emit(tx, map, 'RESOURCE_COLLECTED', { squadId: s.id, areaId: area.id, tileId: tile.id, itemId, quantity }, at);
          await questService.recordEvent(map.masterId, 'COLLECT_RESOURCE', quantity, at, tx);
          await eventService.recordEvent(map.masterId, 'COLLECT_RESOURCE', quantity, at, tx);
        }
      } else if (step.enemy) pveEnemyStep(world, step.enemy, step.at);

      for (const e of world.enemies.filter(e => e.state !== 'DEAD' && !e.battleId)) {
        const s = squads.find(s => ['IDLE', 'MOVING'].includes(s.status) && s.areaId === e.areaId && s.x === e.x && s.y === e.y
          && !(e.disengaged?.squadId === s.id && e.disengaged.areaId === s.areaId && e.disengaged.x === s.x && e.disengaged.y === s.y));
        if (!s) continue;
        const ambush = !before.get(s.id)?.has(e.id);
        const tile: PveTile = { id: e.encounterId, x: e.x, y: e.y, kind: e.boss ? 'BOSS' : 'ENEMY', seed: e.seed };
        s.pendingPortalId = null;
        await this.fight(tx, map, s, tile, at, { enemy: e, ambush, areaId: e.areaId });
        if (s.status === 'FIGHTING') { e.battleId = s.lastBattleId!; e.nextStepAt = null; e.targetSquadId = null; continue; }
        if (map.cleared.includes(e.encounterId)) { e.state = 'DEAD'; e.nextStepAt = null; e.targetSquadId = null; }
        else {
          s.autoExplore = false;
          e.disengaged = { squadId: s.id, areaId: s.areaId, x: s.x, y: s.y };
          e.state = 'RETURN'; e.targetSquadId = null; e.nextStepAt = step.at + 1500;
        }
        if (map.status !== 'ACTIVE') break;
      }
      if (map.status !== 'ACTIVE') break;
      const previous = new Map(world.enemies.map(e => [e.id, e.state]));
      pveObserve(world, squads, step.at);
      for (const e of world.enemies) if (e.state !== previous.get(e.id)) await this.emit(tx, map,
        e.state === 'CHASE' ? 'SQUAD_DETECTED' : e.state === 'INVESTIGATE' ? 'SQUAD_LOST' : 'ENEMY_STATE_CHANGED',
        { enemyId: e.id, squadId: e.targetSquadId, state: e.state }, at);
      for (const s of squads) {
        // Re-plan auto after every world step, without resetting an already running step's ETA.
        if (s.autoExplore && ['IDLE', 'MOVING'].includes(s.status)) {
          const eta = s.nextStepAt;
          await this.scheduleAuto(tx, map, s, at);
          if (eta && s.status === 'MOVING') s.nextStepAt = eta;
        }
        await this.persistExplorer(tx, s);
      }
    }
    await this.saveExploration(tx, map);
    const waiting = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId,map.masterId),eq(combatSessions.status,'PVE_LIVE')));
    return map.status === 'ACTIVE' && (squads.some(s => s.status === 'MOVING' && s.nextStepAt && s.nextStepAt <= now)
      || world.enemies.some(e => e.state !== 'DEAD' && e.nextStepAt !== null && e.nextStepAt <= now.getTime())
      || waiting.some(s=>(s.combatState as unknown as LiveBattle).mapId===map.id && (s.combatState as unknown as LiveBattle).deadline<=now.getTime()));
  }

  private async autoHeal(tx: GameTransaction, masterId: string, squadId: string) {
    const bags = await tx.select().from(heroConsumables).where(eq(heroConsumables.squadId,squadId));
    for (const bag of bags) {
      const [hero] = await tx.select().from(heroes).where(eq(heroes.id,bag.heroId));
      if (!hero || hero.hp <= 0 || hero.state === 'DEAD') continue;
      const threshold = bag.config.autoHpBelow ?? 30;
      if (hero.hp / Math.max(1,hero.maxHp) * 100 >= threshold) continue;
      const index = bag.config.slots.findIndex(s=>s?.itemId==='MEDICINE' && s.quantity>0);
      if (index >= 0) await alchemyService.use(tx,masterId,hero.id,'MEDICINE',index);
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
    const bags = await tx.select().from(heroConsumables).where(eq(heroConsumables.squadId, squad.id));
    return units.map(unit => {
      const hero = roster.find(row => row.id === unit.id)!;
      const member = squad.plan.members.find(row => row.heroId === unit.id)!;
      const hpPct = isV2Origin(hero.originStats) ? hero.currentHpPct : hero.hp / Math.max(1, hero.maxHp);
      const mpPct = isV2Origin(hero.originStats) ? hero.currentMpPct : hero.maxMp > 0 ? hero.mp / hero.maxMp : 0;
      const bag = bags.find(b => b.heroId === unit.id);
      return { ...unit, consumables: bag?.config, strengthReady: bag?.strengthReady, formationSlot: member.slotIndex, targetPriority: squad.plan.targetPriority, skillOrder: member.skillOrder,
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

  private async fight(tx: GameTransaction, map: MapRow, squad: SquadRow, tile: PveTile, now: Date,
    encounter?: { enemy: PveEnemy; ambush: boolean; areaId: string }) {
    await tx.execute(sql`select set_config('app.pve_map_id', ${map.id}, true)`);
    await this.autoHeal(tx,map.masterId,squad.id);
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
    const otherLive = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId,map.masterId),eq(combatSessions.status,'PVE_LIVE')));
    const anotherWatched = otherLive.some(row => {
      const live = row.combatState as unknown as LiveBattle;
      return live.watching && live.deadline > now.getTime();
    });
    const report = resolveBattleV2(heroUnits, foes.units, { random: mulberry32(combatSeed), maxRounds: 30, timeoutIsDraw: true, ambush: encounter?.ambush, pauseManual: squad.plan.battleMode === 'MANUAL' && !anotherWatched });
    const battleId = uuid();
    const live = { engine: 'PVE_MAP', combatAlgorithmVersion: squad.plan.battleMode === 'MANUAL' ? 2 : 1,
      enemies: foes.units, maxRounds: 30, timeoutIsDraw: true,
      mapId: map.id, squadId: squad.id, tile, encounter, heroes: heroUnits, foes, seed: combatSeed,
      choices: {} as Record<string, CombatChoice>, deadline: now.getTime() + 10000, report };
    await tx.insert(combatSessions).values({ id: battleId, masterId: map.masterId, worldId: map.worldId, partyId: squad.partyId,
      status: report.pending ? 'PVE_LIVE' : 'COMPLETED', createdAt: now, finishedAt: report.pending ? null : now,
      combatState: live as unknown as CommandResult, battleReport: report as unknown as CommandResult });
    if (report.pending) {
      squad.route = []; squad.nextStepAt = null; squad.lastBattleId = battleId;
      await this.persistExplorer(tx, squad);
      await this.emit(tx, map, 'BATTLE_STARTED', { squadId: squad.id, battleId, pending: report.pending, deadline: live.deadline, ambush: !!encounter?.ambush }, now);
      return;
    }
    await this.finishBattle(tx, map, squad, tile, now, heroUnits, foes, report, battleId, encounter);
  }

  private async finishBattle(tx: GameTransaction, map: MapRow, squad: SquadRow, tile: PveTile, now: Date,
    heroUnits: CombatV2UnitInput[], foes: { units: CombatV2UnitInput[]; silver: number; exp: number }, report: CombatV2Report,
    battleId: string, encounter?: { enemy: PveEnemy; ambush: boolean; areaId: string }) {
    await tx.execute(sql`select set_config('app.pve_map_id', ${map.id}, true)`);
    for (const [heroId, config] of Object.entries(report.consumables ?? {})) {
      await tx.update(heroConsumables).set({ config, strengthReady: false }).where(and(eq(heroConsumables.heroId, heroId), eq(heroConsumables.squadId, squad.id)));
    }
    const settlement = await settleCombat(tx, { masterId: map.masterId, sessionId: battleId, worldId: map.worldId, floor: map.floor,
      report, silverReward: foes.silver, heroExpReward: foes.exp, masterExpReward: foes.exp, transactionType: 'PVE_MAP_REWARD', now });
    for (const hero of heroUnits) {
      const [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, hero.id));
      if (state) await tx.update(heroSurvivalStates).set({ ...applyActivity(state.hungerScore, state.fatigueScore, 'BATTLE'),
        lastTickAt: state.lastTickAt > now ? state.lastTickAt : now }).where(eq(heroSurvivalStates.heroId, hero.id));
    }
    const fallen = settlement.deaths.map(hero => hero.heroId);
    if (fallen.length) {
      const bags = await tx.select().from(heroConsumables).where(inArray(heroConsumables.heroId, fallen));
      for (const bag of bags) {
        const items = bag.config.slots.filter((s): s is NonNullable<typeof s> => !!s && s.quantity > 0);
        if (items.length) await tx.insert(pveConsumableDrops).values({ id:uuid(),masterId:map.masterId,mapId:map.id,areaId:squad.areaId,x:squad.x,y:squad.y,items });
        await tx.update(heroConsumables).set({ squadId:null,strengthReady:false,config:{...bag.config,slots:[null,null,null,null,null]} }).where(eq(heroConsumables.heroId,bag.heroId));
      }
      await tx.delete(pveHeroReservations).where(inArray(pveHeroReservations.heroId, fallen));
    }
    const survived = report.units.some(unit => unit.side === 'HERO' && unit.alive);
    squad.status = survived ? 'IDLE' : 'DEFEATED'; squad.route = []; squad.nextStepAt = null; squad.lastBattleId = battleId;
    if (!survived) await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.squadId, squad.id));
    const won = report.winner === 'HERO';
    const bossCleared = won && (map.exploration
      ? !!encounter && completePveObjective(map.exploration, encounter.enemy.id)
      : tile.kind === 'BOSS');
    const result = { ...settlement, floor: map.floor, nextFloor: bossCleared ? map.floor + 1 : map.floor, bossCleared,
      ...(encounter ? { enemyId: encounter.enemy.id, areaId: encounter.areaId, ambush: encounter.ambush, objectiveCompleted: bossCleared } : {}) };
    await tx.insert(pveBattles).values({ id: battleId, masterId: map.masterId, mapId: map.id, squadId: squad.id,
      tileId: tile.id, combatSessionId: battleId, report, settlement: result, createdAt: now });
    await tx.update(pveSquads).set({ status: squad.status, x: squad.x, y: squad.y, route: [], nextStepAt: null, lastBattleId: battleId }).where(eq(pveSquads.id, squad.id));
    if (survived) await this.autoHeal(tx,map.masterId,squad.id);
    if (won) {
      map.cleared.push(tile.id);
      await tx.update(pveMaps).set({ cleared: map.cleared }).where(eq(pveMaps.id, map.id));
      await questService.recordEvent(map.masterId, 'WIN_BATTLE', 1, now, tx);
      await eventService.recordEvent(map.masterId, 'WIN_BATTLE', 1, now, tx);
    }
    await this.emit(tx, map, 'BATTLE_COMPLETED', { squadId: squad.id, battleId, tileId: tile.id, winner: report.winner, ...result }, now);
    if (bossCleared) {
      await this.cancelOtherBattles(tx, map, now, battleId);
      map.status = 'CLEARED'; map.clearedAt = now;
      await tx.update(pveMaps).set({ status: 'CLEARED', clearedAt: now, cleared: map.cleared }).where(eq(pveMaps.id, map.id));
      await tx.update(worlds).set({ currentFloor: sql`greatest(${worlds.currentFloor}, ${map.floor + 1})` }).where(eq(worlds.id, map.worldId));
      await tx.update(pveSquads).set({ status: 'WITHDRAWN', autoExplore: false, route: [], pendingPortalId: null, nextStepAt: null, withdrawnAt: now })
        .where(and(eq(pveSquads.mapId, map.id), inArray(pveSquads.status, ACTIVE)));
      const withdrawn = await tx.select({id:pveSquads.id}).from(pveSquads).where(eq(pveSquads.mapId, map.id));
      await returnConsumables(tx, map.masterId, withdrawn.map(s => s.id));
      await tx.delete(pveHeroReservations).where(eq(pveHeroReservations.mapId, map.id));
      await questService.recordEvent(map.masterId, 'CLEAR_FLOOR', 1, now, tx);
      await eventService.recordEvent(map.masterId, 'CLEAR_FLOOR', 1, now, tx);
      await leaderboardService.recordFloor(map.masterId, map.floor + 1, report.rounds, now, tx);
      await this.emit(tx, map, 'MAP_CLEARED', { floor: map.floor, nextFloor: map.floor + 1, battleId }, now);
    }
  }

  private async pickupConsumables(tx: GameTransaction, map: MapRow, squad: SquadRow, now: Date) {
    const drops = await tx.select().from(pveConsumableDrops).where(and(eq(pveConsumableDrops.mapId,map.id),eq(pveConsumableDrops.areaId,squad.areaId),eq(pveConsumableDrops.x,squad.x),eq(pveConsumableDrops.y,squad.y))).for('update');
    for (const drop of drops) {
      for (const item of drop.items) await addItem(tx,map.masterId,item.itemId,item.quantity);
      await tx.delete(pveConsumableDrops).where(eq(pveConsumableDrops.id,drop.id));
      await this.emit(tx,map,'CONSUMABLES_RECOVERED',{squadId:squad.id,dropId:drop.id,items:drop.items},now);
    }
  }

  private async cancelOtherBattles(tx: GameTransaction, map: MapRow, now: Date, except?: string) {
    const sessions = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId,map.masterId),eq(combatSessions.status,'PVE_LIVE')));
    for (const session of sessions) {
      if (session.id === except) continue;
      const live = session.combatState as unknown as LiveBattle;
      if (live.mapId !== map.id) continue;
      const [squad] = await tx.select().from(pveSquads).where(eq(pveSquads.id,live.squadId));
      const report = { ...live.report, pending:undefined, winner:'DRAW' as const };
      await tx.update(combatSessions).set({status:'COMPLETED',finishedAt:now,battleReport:report as unknown as CommandResult}).where(eq(combatSessions.id,session.id));
      await this.finishBattle(tx,map,squad,live.tile,now,live.heroes,live.foes,report,session.id,live.encounter);
      const enemy = map.exploration?.enemies.find(e=>e.id===live.encounter?.enemy.id);
      if (enemy) { delete enemy.battleId; enemy.nextStepAt=null; enemy.state='IDLE'; enemy.targetSquadId=null; }
    }
  }

  private async resolveLive(tx: GameTransaction, map: MapRow, sessionId: string, live: LiveBattle, now: Date, auto: boolean) {
    const [squad] = await tx.select().from(pveSquads).where(eq(pveSquads.id, live.squadId)).for('update');
    if (!squad || squad.status !== 'FIGHTING') throw new PveError('ERR_PVE_BATTLE_FINISHED');
    try {
      live.report = resolveBattleV2(live.heroes, live.foes.units, { random: mulberry32(live.seed), maxRounds: 30,
        timeoutIsDraw: true, ambush: live.encounter?.ambush, choices: live.choices, pauseManual: !auto });
    } catch (error) { throw new PveError(error instanceof Error ? error.message : 'ERR_COMBAT_ACTION', 400); }
    await tx.update(combatSessions).set({ combatState: live as unknown as CommandResult,
      battleReport: live.report as unknown as CommandResult, status: live.report.pending ? 'PVE_LIVE' : 'COMPLETED',
      finishedAt: live.report.pending ? null : now }).where(eq(combatSessions.id, sessionId));
    if (!live.report.pending) {
      const enemy = map.exploration?.enemies.find(e => e.id === live.encounter?.enemy.id);
      const encounter = enemy && live.encounter ? { ...live.encounter, enemy } : live.encounter;
      await this.finishBattle(tx, map, squad, live.tile, now, live.heroes, live.foes, live.report, sessionId, encounter);
      if (enemy) {
        delete enemy.battleId; enemy.targetSquadId = null;
        enemy.state = live.report.winner === 'HERO' ? 'DEAD' : 'RETURN';
        enemy.nextStepAt = enemy.state === 'DEAD' ? null : now.getTime() + 1500;
        enemy.disengaged = { squadId: squad.id, areaId: squad.areaId, x: squad.x, y: squad.y };
      }
      if (map.exploration) await this.saveExploration(tx, map);
    }
    return { id: sessionId, squadId: squad.id, report: live.report, deadline: live.deadline, live: !!live.report.pending };
  }

  private async advanceExpiredBattles(tx: GameTransaction, map: MapRow, now: Date) {
    const sessions = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId, map.masterId), eq(combatSessions.status, 'PVE_LIVE'))).orderBy(asc(combatSessions.createdAt));
    sessions.sort((a,b)=>(a.combatState as unknown as LiveBattle).deadline-(b.combatState as unknown as LiveBattle).deadline || a.id.localeCompare(b.id));
    for (const session of sessions) {
      const live = session.combatState as unknown as LiveBattle;
      if (live.mapId === map.id && live.deadline <= now.getTime() && map.status === 'ACTIVE') await this.resolveLive(tx, map, session.id, live, new Date(live.deadline), true);
    }
  }

  async liveBattle(masterId: string, battleId: string, body: unknown, key: string) {
    return this.command(masterId, `BATTLE_ACTION:${battleId}`, key, body, async (tx, now) => {
      const [session] = await tx.select().from(combatSessions).where(and(eq(combatSessions.id, battleId), eq(combatSessions.masterId, masterId))).for('update');
      if (!session || session.status !== 'PVE_LIVE') throw new PveError('ERR_PVE_BATTLE_FINISHED');
      const live = session.combatState as unknown as LiveBattle;
      const map = await this.activeMap(tx, masterId);
      if (!map || map.id !== live.mapId) throw new PveError('ERR_PVE_MAP_CLEARED');
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new PveError('ERR_COMBAT_ACTION',400);
      const input = body as { turnKey?: string; action?: 'BASIC' | 'SKILL'; skillCode?: string; targetId?: string; itemId?: string; watching?: boolean };
      if (input.watching === false) return this.resolveLive(tx, map, session.id, live, now, true);
      if (input.watching === true) {
        live.watching = true;
        await tx.update(combatSessions).set({combatState:live as unknown as CommandResult}).where(eq(combatSessions.id,session.id));
        // Watching one battle releases every other manual battle to its configured AI.
        const others = await tx.select().from(combatSessions).where(and(eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'PVE_LIVE')));
        for (const other of others) if (other.id !== session.id) await this.resolveLive(tx, map, other.id, other.combatState as unknown as LiveBattle, now, true);
        if (map.status !== 'ACTIVE') return { id:battleId,live:false };
        return { id: battleId, report: live.report, deadline: live.deadline, live: true };
      }
      if (!live.report.pending || input.turnKey !== live.report.pending.key) throw new PveError('ERR_COMBAT_STALE_TURN');
      if (input.action !== undefined && !['BASIC','SKILL'].includes(input.action)) throw new PveError('ERR_COMBAT_ACTION', 400);
      if (!input.action && !input.itemId) throw new PveError('ERR_COMBAT_ACTION', 400);
      const choice = live.choices[input.turnKey] ?? {};
      if (input.itemId) choice.items = [...(choice.items ?? []), input.itemId];
      if (input.action) { choice.action = input.action; choice.skillCode = input.skillCode; choice.targetId = input.targetId; }
      live.choices[input.turnKey] = choice;
      const previousTurn = live.report.pending.key;
      // Item-only actions must not reset the ten-second action deadline.
      const result = await this.resolveLive(tx, map, session.id, live, now, false);
      if (live.report.pending && live.report.pending.key !== previousTurn) {
        live.deadline = now.getTime() + 10000;
        await tx.update(combatSessions).set({ combatState: live as unknown as CommandResult }).where(eq(combatSessions.id, session.id));
        result.deadline = live.deadline;
      }
      return result;
    });
  }

  async state(masterId: string, cursor = 0, cursorMapId?: string) {
    return db.transaction(async tx => {
      const { now } = await lockMaster(tx, masterId);
      const catchupPending = !!await this.settle(tx, masterId, now);
      const [map] = await tx.select().from(pveMaps).where(and(eq(pveMaps.masterId, masterId),
        sql`${pveMaps.run} = (select pve_run from worlds where id = ${pveMaps.worldId})`)).orderBy(desc(pveMaps.createdAt), desc(pveMaps.id)).limit(1);
      const [world] = await tx.select({ floor: worlds.currentFloor, run: worlds.pveRun }).from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt), asc(worlds.id)).limit(1);
      const [stones] = await tx.select({ quantity: masterItems.quantity }).from(masterItems).where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, PVE_TELEPORT_STONE)));
      const loadouts = await tx.select().from(heroConsumables).where(eq(heroConsumables.masterId,masterId));
      const metadata = { loadouts, devToolsEnabled: pveDevToolsEnabled(), currentFloor: world?.floor ?? 1, run: world?.run ?? 0, teleportStones: stones?.quantity ?? 0 };
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
      if (!map) return { ...metadata, serverNow: now.toISOString(), map: null, squads: [], parties: partyViews, events: [], cursor: 0 };
      const squads = await tx.select().from(pveSquads).where(eq(pveSquads.mapId, map.id)).orderBy(asc(pveSquads.deployedAt), asc(pveSquads.id));
      const reservations = await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.mapId, map.id));
      const squadViews = squads.map(squad => {
        const reserved = new Set(reservations.filter(row => row.squadId === squad.id).map(row => row.heroId));
        const ordered = partyViews.find(party => party.id === squad.partyId)?.members.map(member => member.heroId) ?? [];
        const leaderHeroId = [...ordered, ...squad.plan.members.map(member => member.heroId)].find(id => reserved.has(id)) ?? null;
        const pursued = map.exploration?.enemies.some(e => e.targetSquadId === squad.id && ['CHASE', 'INVESTIGATE'].includes(e.state)) ?? false;
        const atRecallPoint = recallAtPoint(map, squad);
        const recallBlockReason = !ACTIVE.includes(squad.status) ? 'ERR_PVE_SQUAD_WITHDRAWN'
          : squad.status === 'FIGHTING' ? 'ERR_PVE_SQUAD_FIGHTING' : map.recallPolicy === 'UNTIL_COMPLETE' ? 'ERR_PVE_RECALL_LOCKED'
          : pursued && !atRecallPoint ? 'ERR_PVE_SQUAD_PURSUED' : null;
        return { ...squad, leaderHeroId, pursued, atRecallPoint, canRecall: recallBlockReason === null, recallBlockReason };
      });
      const known = new Set(map.discovered);
      const tiles = map.layout.tiles.map(tile => known.has(tile.id) ? { id: tile.id, x: tile.x, y: tile.y, kind: tile.kind,
        cleared: map.cleared.includes(tile.id), collected: map.collected.includes(tile.id), resource: tile.resource }
        : { id: tile.id, x: tile.x, y: tile.y, kind: 'UNKNOWN' });
      const after = cursorMapId === map.id ? cursor : 0;
      const events = await tx.select().from(pveEvents).where(and(eq(pveEvents.mapId, map.id), gt(pveEvents.revision, after)))
        .orderBy(asc(pveEvents.revision)).limit(100);
      const [food] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, 'FOOD')));
      const exploration = map.exploration;
      const drops = await tx.select().from(pveConsumableDrops).where(eq(pveConsumableDrops.mapId,map.id));
      const areas = exploration ? Object.values(exploration.areas).map(area => {
        const known = new Set(area.discovered);
        const present = squadViews.filter(s => s.areaId === area.id && ACTIVE.includes(s.status));
        const visible = new Set(present.flatMap(s => pveVisibleEnemies(exploration, s).map(e => e.id)));
        return { id: area.id, name: area.name, level: area.level, parentAreaId: area.parentAreaId,
          width: area.width, height: area.height, metersPerTile: area.metersPerTile, explored: area.explored,
          tiles: area.tiles.map(t => known.has(t.id) ? { id: t.id, x: t.x, y: t.y, kind: t.kind,
            collected: area.collected.includes(t.id), resource: t.resource } : { id: t.id, x: t.x, y: t.y, kind: 'UNKNOWN' }),
          drops: drops.filter(d=>d.areaId===area.id && known.has(pveTileId(d,area.width))),
          portals: area.portals.filter(p => known.has(pveTileId(p, area.width))),
          buildings: exploration.buildings.filter(b => area.level === 'FLOOR'
            ? known.has(b.parentTileId) : area.id === `region:${b.parentTileId}` && known.has(pveTileId(b.door, area.width))),
          enemies: exploration.enemies.filter(e => visible.has(e.id)).map(e => ({ id: e.id, x: e.x, y: e.y,
            boss: e.boss, state: e.state, targetSquadId: e.targetSquadId, radarRadius: 4,
            radarTileIds: area.tiles.filter(t => known.has(t.id) && pveLineOfSight(area, e, t)).map(t => t.id) })),
        };
      }) : undefined;
      return { ...metadata, serverNow: now.toISOString(), catchupPending, map: { id: map.id, floor: map.floor, status: map.status,
        run: map.run, recallPolicy: map.recallPolicy, recallPoints: map.recallPoints,
        width: map.layout.width, height: map.layout.height, algorithmVersion: map.layout.algorithmVersion,
        drops: drops.filter(d=>d.areaId==='floor' && known.has(pveTileId(d,map.layout.width))),
        tiles: areas?.find(a => a.id === 'floor')?.tiles ?? tiles, revision: map.revision },
        ...(exploration ? { areas, objective: exploration.objective, enemySecondsPerTile: 1.5 } : {}),
        squads: squadViews, parties: partyViews, events, cursor: events.at(-1)?.revision ?? after, food: food?.quantity ?? 0,
        secondsPerTile: GAME_CONSTANTS.PVE.SECONDS_PER_TILE, maxSquads: GAME_CONSTANTS.PVE.MAX_DEPLOYED_SQUADS };
    });
  }

  async battle(masterId: string, battleId: string) {
    await this.state(masterId);
    const [live] = await db.select().from(combatSessions).where(and(eq(combatSessions.id, battleId), eq(combatSessions.masterId, masterId), eq(combatSessions.status, 'PVE_LIVE')));
    if (live) {
      const state = live.combatState as unknown as LiveBattle;
      return { id: battleId, squadId: state.squadId, live: true, report: state.report, deadline: state.deadline };
    }
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
