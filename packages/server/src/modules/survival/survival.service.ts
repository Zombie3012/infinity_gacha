import { and, asc, eq, gt, inArray, sql } from 'drizzle-orm';
import { isLivingHero } from '@infiniti-gacha/shared';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import type { GameDatabase, GameTransaction } from '../../database/transaction.js';
import {
  baseBuildings, buildingWorkerAssignments, combatPartySlots, heroes, masterItems, masterParties, masters, pveHeroReservations,
} from '../../database/drizzle-schema.js';
import {
  FEED_HUNGER_RELIEF, applyActivity, applyDrift, baseFoodConsumption, clampScore, fatigueState, hungerState,
  housingCapacityFor, housingRecoveryMultiplierFor, isImmobilised, rationsFor, starvationMultiplier,
  type FatigueState, type HungerState, type RationContext,
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
  private async foodStock(masterId: string, database: GameDatabase = db): Promise<number> {
    const [row] = await database.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM))).limit(1);
    return row?.quantity ?? 0;
  }

  private async foodCapacity(masterId: string): Promise<number> {
    const [kitchen] = await db.select({ level: baseBuildings.level }).from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, 'KITCHEN'))).limit(1);
    return Math.max(100, (kitchen?.level ?? 0) * 200);
  }

  private async ensureStates(masterId: string, now: Date, database: GameDatabase = db) {
    const roster = await database.select({ id: heroes.id, hunger: heroes.hunger, fatigue: heroes.fatigue }).from(heroes)
      .where(and(eq(heroes.masterId, masterId), gt(heroes.hp, 0), sql`${heroes.state} NOT IN ('DEAD','DISABLED')`));
    if (roster.length === 0) return [];
    const existing = await database.select().from(heroSurvivalStates)
      .where(inArray(heroSurvivalStates.heroId, roster.map(row => row.id)));
    const known = new Set(existing.map(row => row.heroId));
    const missing = roster.filter(row => !known.has(row.id));
    if (missing.length > 0) {
      await database.insert(heroSurvivalStates).values(missing.map(row => ({
        heroId: row.id, hungerScore: row.hunger, fatigueScore: row.fatigue, isResting: false, lastTickAt: now,
      }))).onConflictDoNothing();
    }
    return database.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, roster.map(row => row.id)));
  }

  /** Advance hunger/fatigue for every Hero of a Master and persist the result. */
  async settle(masterId: string, now = new Date()) {
    return db.transaction(async tx => {
      // PvE settlement takes the same Master lock before charging battle fatigue.
      // Reading before this lock could overwrite a battle with stale passive scores.
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const states = await this.ensureStates(masterId, now, tx);
      if (states.length === 0) return;
      const hasFood = (await this.foodStock(masterId, tx)) > 0;
      const restFacilities = await tx.select({
        id: baseBuildings.id,
        buildingType: baseBuildings.buildingType,
        level: baseBuildings.level,
        status: baseBuildings.status,
      }).from(baseBuildings).where(and(
        eq(baseBuildings.masterId, masterId),
        inArray(baseBuildings.buildingType, ['HOUSE', 'PARTY_MANSION']),
      ));
      const facilityById = new Map(restFacilities.map(f => [f.id, f]));
      for (const state of states) {
        const fac = state.housingBuildingId ? facilityById.get(state.housingBuildingId) : undefined;
        const recoveryMult = fac && fac.status === 'READY'
          ? housingRecoveryMultiplierFor(fac.buildingType, fac.level)
          : 1.0;
        const drift = applyDrift({
          hungerScore: state.hungerScore,
          fatigueScore: state.fatigueScore,
          isResting: state.isResting && Boolean(fac && fac.status === 'READY'),
          lastTickAt: state.lastTickAt,
        }, now, hasFood, recoveryMult);
        const keepRestingAtZero = state.isResting && Boolean(fac && fac.status === 'READY') && state.fatigueScore <= 0;
        await tx.update(heroSurvivalStates).set({
          hungerScore: drift.hungerScore,
          fatigueScore: drift.fatigueScore,
          isResting: keepRestingAtZero ? true : drift.isResting,
          lastTickAt: state.lastTickAt > now ? state.lastTickAt : now,
        }).where(eq(heroSurvivalStates.heroId, state.heroId));
      }
    });
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const roster = await db.select({
      id: heroes.id, name: heroes.name, level: heroes.level, state: heroes.state, maxHp: heroes.maxHp, hp: heroes.hp,
    }).from(heroes).where(and(eq(heroes.masterId, masterId), gt(heroes.hp, 0), sql`${heroes.state} NOT IN ('DEAD','DISABLED')`)).orderBy(asc(heroes.name));
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
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
      if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);
      if (!isLivingHero(hero)) throw new SurvivalError('Hero không còn sống hoặc đang chờ hồi sinh.', 409);
      if ((await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.heroId, heroId))).length) {
        throw new SurvivalError('ERR_PVE_HERO_DEPLOYED', 409);
      }

      const [food] = await tx.select().from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM))).for('update');
      if (!food || food.quantity < quantity) throw new SurvivalError('Kho thức ăn không đủ.', 409);
      const [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).for('update');

      const now = new Date();
      const nextHunger = clampScore((state?.hungerScore ?? 0) - FEED_HUNGER_RELIEF * quantity);
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${quantity}`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, FOOD_ITEM)));
      await tx.update(heroSurvivalStates).set({ hungerScore: nextHunger, lastTickAt: now })
        .where(eq(heroSurvivalStates.heroId, heroId));
      return { heroId, foodUsed: quantity, hungerScore: nextHunger, hungerState: hungerState(nextHunger) };
    });
  }

  async setResting(masterId: string, heroId: string, resting: boolean, buildingId?: string | null) {
    await this.settle(masterId);
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
      if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);
      if (!isLivingHero(hero)) throw new SurvivalError('Hero không thể nghỉ ngơi.', 409);
      if ((await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.heroId, heroId))).length) {
        throw new SurvivalError('ERR_PVE_HERO_DEPLOYED', 409);
      }
      if (resting) {
        const [assigned] = await tx.select().from(buildingWorkerAssignments)
          .where(eq(buildingWorkerAssignments.heroInstanceId, heroId)).limit(1);
        if (assigned) throw new SurvivalError('Hero đang làm việc, hãy thu hồi trước khi nghỉ.', 409);
      }
      const now = new Date();
      let [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).for('update');
      if (!state) {
        await tx.insert(heroSurvivalStates).values({
          heroId, hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: now,
        }).onConflictDoNothing();
        [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).for('update');
      }
      if (resting) {
        let targetHousingId = state?.housingBuildingId ?? null;
        if (buildingId && targetHousingId !== buildingId) {
          const [targetFac] = await tx.select().from(baseBuildings)
            .where(and(
              eq(baseBuildings.id, buildingId),
              eq(baseBuildings.masterId, masterId),
              eq(baseBuildings.status, 'READY'),
              inArray(baseBuildings.buildingType, ['HOUSE', 'PARTY_MANSION']),
            )).limit(1);
          if (!targetFac) throw new SurvivalError('Không tìm thấy công trình cư trú sẵn sàng.', 404);
          const occupants = await tx.select({ heroId: heroSurvivalStates.heroId })
            .from(heroSurvivalStates)
            .innerJoin(heroes, eq(heroes.id, heroSurvivalStates.heroId))
            .where(and(eq(heroes.masterId, masterId), eq(heroSurvivalStates.housingBuildingId, targetFac.id)));
          const cap = housingCapacityFor(targetFac.buildingType, targetFac.level);
          if (occupants.length >= cap) {
            throw new SurvivalError(`Nhà đã đầy chỗ (${occupants.length}/${cap}). Hãy đổi chỗ với Hero khác.`, 409);
          }
          await tx.update(heroSurvivalStates).set({ housingBuildingId: targetFac.id }).where(eq(heroSurvivalStates.heroId, heroId));
          targetHousingId = targetFac.id;
        } else if (!targetHousingId) {
          targetHousingId = await this.autoAssignDormitory(tx, masterId, heroId, now);
          if (!targetHousingId) {
            throw new SurvivalError('Tất cả Dormitory đã đầy hoặc chưa xây. Hãy đổi chỗ với Hero khác hoặc xếp vào Biệt Thự.', 409);
          }
        }
      }
      const [updated] = await tx.update(heroSurvivalStates).set({ isResting: resting, lastTickAt: now })
        .where(eq(heroSurvivalStates.heroId, heroId)).returning();
      return { heroId, isResting: updated.isResting, fatigueScore: updated.fatigueScore, housingBuildingId: updated.housingBuildingId };
    });
  }

  /**
   * Auto-assign a newly summoned or homeless Hero into the first Dormitory (HOUSE)
   * with available capacity. Never auto-assigns into PARTY_MANSION.
   */
  async autoAssignDormitory(tx: GameTransaction, masterId: string, heroId: string, now = new Date()): Promise<string | null> {
    const dorms = await tx.select({
      id: baseBuildings.id,
      level: baseBuildings.level,
    }).from(baseBuildings).where(and(
      eq(baseBuildings.masterId, masterId),
      eq(baseBuildings.buildingType, 'HOUSE'),
      eq(baseBuildings.status, 'READY'),
    )).orderBy(asc(baseBuildings.createdAt), asc(baseBuildings.id));
    if (dorms.length === 0) {
      await tx.insert(heroSurvivalStates).values({
        heroId, housingBuildingId: null, hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: now,
      }).onConflictDoNothing();
      return null;
    }

    const dormIds = dorms.map(d => d.id);
    const occupantRows = await tx.select({ housingBuildingId: heroSurvivalStates.housingBuildingId })
      .from(heroSurvivalStates)
      .innerJoin(heroes, eq(heroes.id, heroSurvivalStates.heroId))
      .where(and(
        eq(heroes.masterId, masterId),
        inArray(heroSurvivalStates.housingBuildingId, dormIds),
      ));
    const counts = new Map<string, number>();
    for (const row of occupantRows) {
      if (row.housingBuildingId) counts.set(row.housingBuildingId, (counts.get(row.housingBuildingId) ?? 0) + 1);
    }

    const targetDorm = dorms.find(d => (counts.get(d.id) ?? 0) < housingCapacityFor('HOUSE', d.level));
    const assignedId = targetDorm?.id ?? null;
    await tx.insert(heroSurvivalStates).values({
      heroId, housingBuildingId: assignedId, hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: now,
    }).onConflictDoUpdate({
      target: heroSurvivalStates.heroId,
      set: { housingBuildingId: assignedId },
    });
    return assignedId;
  }

  async assignHousing(masterId: string, buildingId: string, heroId: string, swapWithHeroId?: string | null) {
    if (!heroId) throw new SurvivalError('heroId là bắt buộc.');
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [building] = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
      if (!building) throw new SurvivalError('Không tìm thấy công trình cư trú.', 404);
      if (building.status !== 'READY') throw new SurvivalError('Công trình chưa sẵn sàng.', 409);
      if (building.buildingType !== 'HOUSE' && building.buildingType !== 'PARTY_MANSION') {
        throw new SurvivalError('Công trình này không hỗ trợ cư trú.', 409);
      }

      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
      if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);
      if (!isLivingHero(hero)) throw new SurvivalError('Hero không thể vào nhà ở.', 409);

      const now = new Date();
      let [heroState] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).for('update');
      if (!heroState) {
        await tx.insert(heroSurvivalStates).values({
          heroId, housingBuildingId: null, hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: now,
        }).onConflictDoNothing();
        [heroState] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, heroId)).for('update');
      }

      if (heroState.housingBuildingId === buildingId) {
        return { heroId, housingBuildingId: buildingId, swappedWithHeroId: null };
      }

      const occupants = await tx.select({ heroId: heroSurvivalStates.heroId })
        .from(heroSurvivalStates)
        .innerJoin(heroes, eq(heroes.id, heroSurvivalStates.heroId))
        .where(and(eq(heroes.masterId, masterId), eq(heroSurvivalStates.housingBuildingId, buildingId)));
      const cap = housingCapacityFor(building.buildingType, building.level);

      if (occupants.length < cap) {
        await tx.update(heroSurvivalStates).set({ housingBuildingId: buildingId }).where(eq(heroSurvivalStates.heroId, heroId));
        return { heroId, housingBuildingId: buildingId, swappedWithHeroId: null };
      }

      if (!swapWithHeroId) {
        throw new SurvivalError('Nhà đã đầy chỗ. Hãy chọn một Hero đang ở bên trong để đổi chỗ.', 409);
      }
      if (!occupants.some(o => o.heroId === swapWithHeroId)) {
        throw new SurvivalError('Hero được chọn để đổi chỗ không ở trong công trình này.', 409);
      }

      const previousBuildingId = heroState.housingBuildingId ?? null;
      await tx.update(heroSurvivalStates).set({
        housingBuildingId: previousBuildingId,
        isResting: previousBuildingId ? undefined : false,
      }).where(eq(heroSurvivalStates.heroId, swapWithHeroId));
      await tx.update(heroSurvivalStates).set({ housingBuildingId: buildingId })
        .where(eq(heroSurvivalStates.heroId, heroId));

      return { heroId, housingBuildingId: buildingId, swappedWithHeroId: swapWithHeroId };
    });
  }

  async removeHousing(masterId: string, heroId: string) {
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [hero] = await tx.select({ id: heroes.id }).from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
      if (!hero) throw new SurvivalError('Không tìm thấy Hero.', 404);
      await tx.update(heroSurvivalStates).set({ housingBuildingId: null, isResting: false })
        .where(eq(heroSurvivalStates.heroId, heroId));
      return { heroId, housingBuildingId: null, isResting: false };
    });
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
  async battleReadiness(masterId: string, partyId?: string, charge = true) {
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
    if (charge) await db.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${rations}`, updatedAt: new Date() })
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
