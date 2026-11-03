import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  baseBuildings, buildingWorkerAssignments, combatPartySlots, heroes, masterItems, masterParties, masters,
} from '../../database/drizzle-schema.js';
import {
  FEED_HUNGER_RELIEF, applyActivity, applyDrift, baseFoodConsumption, clampScore, fatigueState, hungerState,
  isImmobilised, rationsFor, starvationMultiplier, type FatigueState, type HungerState, type RationContext,
} from './survival-rules.js';
import { heroSurvivalStates } from '../../database/drizzle-schema.js';

export class SurvivalError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'SurvivalError';
  }
}

const FOOD_ITEM = 'FOOD';
const RAW_FOOD_ITEM = 'FOOD_RAW';
const RAW_FOOD_PER_MEAL = 2;

export interface SurvivalRow {
  heroId: string;
  name: string;
  level: number;
  heroState: string;
  hungerScore: number;
  fatigueScore: number;
  hungerState: HungerState;
  fatigueState: FatigueState;
  isResting: boolean;
  assignedBuildingId: string | null;
  attackMultiplier: number;
}

export class SurvivalService {
  private async foodStock(masterId: string): Promise<number> {
    const [row] = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM))).limit(1);
    return row?.quantity ?? 0;
  }

  private async foodCapacity(masterId: string): Promise<number> {
    const [kitchen] = await db.select({ level: baseBuildings.level }).from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, 'KITCHEN'))).limit(1);
    return Math.max(100, (kitchen?.level ?? 0) * 200);
  }

  private async ensureStates(masterId: string, now: Date) {
    const roster = await db.select({ id: heroes.id }).from(heroes).where(eq(heroes.masterId, masterId));
    if (roster.length === 0) return [];
    const existing = await db.select().from(heroSurvivalStates)
      .where(inArray(heroSurvivalStates.heroId, roster.map(row => row.id)));
    const known = new Set(existing.map(row => row.heroId));
    const missing = roster.filter(row => !known.has(row.id));
    if (missing.length > 0) {
      await db.insert(heroSurvivalStates).values(missing.map(row => ({
        heroId: row.id, hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: now,
      }))).onConflictDoNothing();
    }
    return db.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, roster.map(row => row.id)));
  }

  /** Advance hunger/fatigue for every Hero of a Master and persist the result. */
  async settle(masterId: string, now = new Date()) {
    const states = await this.ensureStates(masterId, now);
    if (states.length === 0) return;
    const hasFood = (await this.foodStock(masterId)) > 0;
    for (const state of states) {
      const drift = applyDrift({
        hungerScore: state.hungerScore,
        fatigueScore: state.fatigueScore,
        isResting: state.isResting,
        lastTickAt: state.lastTickAt,
      }, now, hasFood);
      await db.update(heroSurvivalStates).set({
        hungerScore: drift.hungerScore,
        fatigueScore: drift.fatigueScore,
        isResting: drift.isResting,
        lastTickAt: now,
      }).where(eq(heroSurvivalStates.heroId, state.heroId));
    }
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const roster = await db.select({
      id: heroes.id, name: heroes.name, level: heroes.level, state: heroes.state, maxHp: heroes.maxHp, hp: heroes.hp,
    }).from(heroes).where(eq(heroes.masterId, masterId)).orderBy(asc(heroes.name));
    const states = roster.length === 0 ? [] : await db.select().from(heroSurvivalStates)
      .where(inArray(heroSurvivalStates.heroId, roster.map(row => row.id)));
    const assignments = roster.length === 0 ? [] : await db.select().from(buildingWorkerAssignments)
      .where(inArray(buildingWorkerAssignments.heroInstanceId, roster.map(row => row.id)));
    const stateByHero = new Map(states.map(row => [row.heroId, row]));
    const buildingByHero = new Map(assignments.map(row => [row.heroInstanceId, row.buildingId]));

    const rows: SurvivalRow[] = roster.map(hero => {
      const state = stateByHero.get(hero.id);
      const hungerScore = state?.hungerScore ?? 0;
      const fatigueScore = state?.fatigueScore ?? 0;
      return {
        heroId: hero.id,
        name: hero.name,
        level: hero.level,
        heroState: hero.state,
        hungerScore,
        fatigueScore,
        hungerState: hungerState(hungerScore),
        fatigueState: fatigueState(fatigueScore),
        isResting: state?.isResting ?? false,
        assignedBuildingId: buildingByHero.get(hero.id) ?? null,
        attackMultiplier: starvationMultiplier(hungerScore),
      };
    });

    const food = await this.foodStock(masterId);
    return {
      heroes: rows,
      food: { stock: food, capacity: await this.foodCapacity(masterId), itemId: FOOD_ITEM },
      summary: {
        starving: rows.filter(row => row.hungerState === 'STARVING' || row.hungerState === 'CRITICAL').length,
        exhausted: rows.filter(row => row.fatigueState === 'CRITICAL' || row.fatigueState === 'OVEREXHAUSTED').length,
        resting: rows.filter(row => row.isResting).length,
      },
    };
  }

  async feed(masterId: string, heroId: string, quantityInput: unknown) {
    await this.settle(masterId);
    const quantity = Math.max(1, Math.min(10, Math.floor(Number(quantityInput) || 1)));
    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);

    const stock = await this.foodStock(masterId);
    if (stock < quantity) throw new SurvivalError('Kho thức ăn không đủ.', 409);
    const [state] = await db.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).limit(1);

    const now = new Date();
    const nextHunger = clampScore((state?.hungerScore ?? 0) - FEED_HUNGER_RELIEF * quantity);
    await db.transaction(async tx => {
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${quantity}`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM)));
      await tx.update(heroSurvivalStates).set({ hungerScore: nextHunger, lastTickAt: now })
        .where(eq(heroSurvivalStates.heroId, heroId));
    });
    return { heroId, foodUsed: quantity, hungerScore: nextHunger, hungerState: hungerState(nextHunger) };
  }

  async setResting(masterId: string, heroId: string, resting: boolean) {
    await this.settle(masterId);
    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);
    if (hero.state === 'DEAD' || hero.state === 'DISABLED') throw new SurvivalError('Hero không thể nghỉ ngơi.', 409);
    if (resting) {
      const [assigned] = await db.select().from(buildingWorkerAssignments)
        .where(eq(buildingWorkerAssignments.heroInstanceId, heroId)).limit(1);
      if (assigned) throw new SurvivalError('Hero đang làm việc, hãy thu hồi trước khi nghỉ.', 409);
    }
    const now = new Date();
    const [updated] = await db.update(heroSurvivalStates).set({ isResting: resting, lastTickAt: now })
      .where(eq(heroSurvivalStates.heroId, heroId)).returning();
    return { heroId, isResting: updated.isResting, fatigueScore: updated.fatigueScore };
  }

  /**
   * Charge one labour shift to the Heroes working a building. Returns the Heroes
   * auto-ejected because they reached Overexhausted (FUN-09-02-006).
   */
  async applyShift(masterId: string, heroIds: string[]) {
    if (heroIds.length === 0) return { ejected: [] as string[] };
    const now = new Date();
    const states = await db.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, heroIds));
    const byHero = new Map(states.map(row => [row.heroId, row]));
    const ejected: string[] = [];

    for (const heroId of heroIds) {
      const state = byHero.get(heroId);
      const activity = applyActivity(state?.hungerScore ?? 0, state?.fatigueScore ?? 0, 'SHIFT');
      await db.update(heroSurvivalStates).set({ ...activity, lastTickAt: now }).where(eq(heroSurvivalStates.heroId, heroId));
      if (activity.fatigueScore >= 100) {
        await db.delete(buildingWorkerAssignments).where(eq(buildingWorkerAssignments.heroInstanceId, heroId));
        ejected.push(heroId);
      }
    }
    return { ejected };
  }

  /**
   * Validate the party before a dungeon run: settle survival, block overexhausted
   * Heroes, charge travel rations and return the starvation multipliers.
   */
  async battleReadiness(masterId: string, partyId?: string) {
    await this.settle(masterId);
    let party = partyId
      ? await db.select({ id: masterParties.id }).from(masterParties).where(and(eq(masterParties.id, partyId), eq(masterParties.masterId, masterId))).limit(1)
      : await db.select({ id: masterParties.id }).from(masterParties).where(and(eq(masterParties.masterId, masterId), eq(masterParties.isDefault, true))).limit(1);
    if (!party[0]) return { ok: true as const, multipliers: {} as Record<string, number>, rations: 0 };

    const members = await db.select({ heroId: combatPartySlots.heroId }).from(combatPartySlots).where(eq(combatPartySlots.partyId, party[0].id));
    if (members.length === 0) return { ok: true as const, multipliers: {} as Record<string, number>, rations: 0 };

    const states = await db.select().from(heroSurvivalStates)
      .where(inArray(heroSurvivalStates.heroId, members.map(row => row.heroId)));
    const byHero = new Map(states.map(row => [row.heroId, row]));

    for (const member of members) {
      const state = byHero.get(member.heroId);
      if (!state) continue;
      if (isImmobilised(state.hungerScore, state.fatigueScore)) {
        return {
          ok: false as const,
          statusCode: 409,
          message: state.fatigueScore >= 100
            ? 'ERR_HERO_OVEREXHAUSTED_MUST_REST'
            : 'ERR_HERO_STARVING_MUST_FEED',
        };
      }
    }

    const rations = rationsFor('DUNGEON', members.length);
    const stock = await this.foodStock(masterId);
    if (stock < rations) {
      return { ok: false as const, statusCode: 409, message: `ERR_INSUFFICIENT_RATIONS: cần ${rations} lương khô.` };
    }
    await db.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${rations}`, updatedAt: new Date() })
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM)));

    const multipliers: Record<string, number> = {};
    for (const member of members) {
      multipliers[member.heroId] = starvationMultiplier(byHero.get(member.heroId)?.hungerScore ?? 0);
    }
    return { ok: true as const, multipliers, rations };
  }

  /** Kitchen conversion: 2 raw food become 1 meal, capped by storage. */
  async cook(masterId: string, quantityInput: unknown) {
    await this.settle(masterId);
    const requested = Math.max(1, Math.min(50, Math.floor(Number(quantityInput) || 1)));
    const capacity = await this.foodCapacity(masterId);
    const stock = await this.foodStock(masterId);
    const room = Math.max(0, capacity - stock);
    if (room <= 0) throw new SurvivalError('Kho thức ăn đã đầy.', 409);

    const meals = Math.min(requested, room);
    const needed = meals * RAW_FOOD_PER_MEAL;
    const [raw] = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, RAW_FOOD_ITEM))).limit(1);
    if ((raw?.quantity ?? 0) < needed) throw new SurvivalError(`Cần ${needed} ${RAW_FOOD_ITEM}.`, 409);

    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${needed}`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, RAW_FOOD_ITEM)));
      await tx.insert(masterItems).values({ id: uuidv4(), masterId, itemId: FOOD_ITEM, quantity: meals, updatedAt: now })
        .onConflictDoUpdate({ target: [masterItems.masterId, masterItems.itemId], set: { quantity: sql`${masterItems.quantity} + ${meals}`, updatedAt: now } });
    });
    return { meals, rawUsed: needed, stock: stock + meals, capacity };
  }

  /** Quote (and for dungeons charge) rations for a dispatch (FUN-09-03-004/005). */
  async rationQuote(masterId: string, context: RationContext, heroCountInput: unknown, charge = false) {
    const heroCount = Math.max(1, Math.min(5, Math.floor(Number(heroCountInput) || 1)));
    const required = rationsFor(context, heroCount);
    const stock = await this.foodStock(masterId);
    if (!charge) return { context, heroCount, required, stock, affordable: stock >= required };
    if (stock < required) throw new SurvivalError(`ERR_INSUFFICIENT_RATIONS: cần ${required} lương khô.`, 409);
    await db.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${required}`, updatedAt: new Date() })
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM)));
    return { context, heroCount, required, charged: true, stock: stock - required };
  }

  /** Baseline daily upkeep for Heroes idling in the base (FUN-09-03-003). */
  async baseUpkeep(masterId: string, hoursInput: unknown) {
    const hours = Math.max(1, Math.min(24, Number(hoursInput) || 1));
    const roster = await db.select({ id: heroes.id }).from(heroes)
      .where(and(eq(heroes.masterId, masterId), eq(heroes.state, 'HEALTHY')));
    const required = Math.ceil(baseFoodConsumption(roster.length, hours));
    const stock = await this.foodStock(masterId);
    await this.settle(masterId);
    return { heroCount: roster.length, hours, required, stock, shortfall: Math.max(0, required - stock) };
  }
}

export const survivalService = new SurvivalService();
