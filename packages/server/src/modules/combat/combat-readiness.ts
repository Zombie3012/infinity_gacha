import { and, eq, inArray, sql } from 'drizzle-orm';
import { db } from '../../database/db.js';
import type { GameDatabase, GameTransaction } from '../../database/transaction.js';
import { heroes, heroSurvivalStates, masterItems, pveMaps } from '../../database/drizzle-schema.js';
import {
  applyDrift, checkActivityRefusal, rationsFor, starvationMultiplier, type ActivityGate,
} from '../survival/survival-rules.js';

export class CombatReadinessError extends Error {
  readonly statusCode = 409;
}

export function refusalErrorCodeFor(gate: ActivityGate, reason: 'HUNGER' | 'FATIGUE'): string {
  if (gate === 'TOWER') {
    return reason === 'FATIGUE' ? 'ERR_HERO_TOO_TIRED_FOR_TOWER' : 'ERR_HERO_TOO_HUNGRY_FOR_TOWER';
  }
  if (gate === 'DUNGEON') {
    return reason === 'FATIGUE' ? 'ERR_HERO_TOO_TIRED_FOR_DUNGEON' : 'ERR_HERO_TOO_HUNGRY_FOR_DUNGEON';
  }
  return 'ERR_HERO_REFUSES_ALL_WORK';
}

/**
 * Evaluate live hunger/fatigue at dispatch/assignment time and throw if any Hero
 * meets or exceeds the activity's threshold (TOWER >= 60, DUNGEON >= 80, ANY >= 90).
 */
export async function assertHeroesActivityReadiness(
  database: GameDatabase,
  masterId: string,
  heroIds: string[],
  now: Date,
  gate: ActivityGate,
): Promise<void> {
  if (!heroIds.length) return;
  const roster = await database.select({ id: heroes.id, hunger: heroes.hunger, fatigue: heroes.fatigue })
    .from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)));
  const states = await database.select().from(heroSurvivalStates).where(inArray(heroSurvivalStates.heroId, heroIds));
  const stateByHero = new Map(states.map(s => [s.heroId, s]));
  const [food] = await database.select({ quantity: masterItems.quantity }).from(masterItems)
    .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, 'FOOD'))).limit(1);
  const hasFood = (food?.quantity ?? 0) > 0;
  for (const hero of roster) {
    const state = stateByHero.get(hero.id);
    const drift = applyDrift(
      state ?? { hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: now },
      now,
      hasFood,
    );
    const refusal = checkActivityRefusal(drift.hungerScore, drift.fatigueScore, gate);
    if (refusal.refused && refusal.reason) {
      throw new CombatReadinessError(refusalErrorCodeFor(gate, refusal.reason));
    }
  }
}

/** Early read-only gate; the authoritative gate runs again under the caller's Master lock. */
export async function assertNoPrivatePve(masterId: string, transaction?: GameTransaction) {
  const database = transaction ?? db;
  const [active] = await database.select({ id: pveMaps.id }).from(pveMaps)
    .where(and(eq(pveMaps.masterId, masterId), eq(pveMaps.status, 'ACTIVE'))).limit(1);
  if (active) throw new CombatReadinessError('ERR_PVE_MAP_ACTIVE');
}

/** Charge rations with the same transaction that creates the session/reserves the squad. */
export async function chargeCombatDispatch(
  tx: GameTransaction,
  masterId: string,
  heroIds: string[],
  now: Date,
  gate: ActivityGate = 'TOWER',
  allowResting = false,
) {
  const roster = await tx.select().from(heroes).where(and(eq(heroes.masterId, masterId), inArray(heroes.id, heroIds)))
    .orderBy(heroes.id).for('update');
  if (!heroIds.length || roster.length !== heroIds.length) throw new CombatReadinessError('ERR_PVE_INVALID_PARTY');
  const [food] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, 'FOOD'))).for('update');
  const required = rationsFor('DUNGEON', heroIds.length);
  if (!food || food.quantity < required) throw new CombatReadinessError('ERR_INSUFFICIENT_RATIONS');
  const multipliers: Record<string, number> = {};
  for (const hero of roster) {
    const [state] = await tx.select().from(heroSurvivalStates).where(eq(heroSurvivalStates.heroId, hero.id));
    const drift = applyDrift(state ?? { hungerScore: hero.hunger, fatigueScore: hero.fatigue, isResting: false, lastTickAt: now }, now, true);
    if (drift.isResting && !allowResting) throw new CombatReadinessError('ERR_PVE_HERO_RESTING');
    const refusal = checkActivityRefusal(drift.hungerScore, drift.fatigueScore, gate);
    if (refusal.refused && refusal.reason) {
      throw new CombatReadinessError(refusalErrorCodeFor(gate, refusal.reason));
    }
    await tx.insert(heroSurvivalStates).values({ heroId: hero.id, hungerScore: drift.hungerScore, fatigueScore: drift.fatigueScore, lastTickAt: now })
      .onConflictDoUpdate({ target: heroSurvivalStates.heroId, set: { hungerScore: drift.hungerScore, fatigueScore: drift.fatigueScore, isResting: false,
        lastTickAt: state && state.lastTickAt > now ? state.lastTickAt : now } });
    multipliers[hero.id] = starvationMultiplier(drift.hungerScore);
  }
  await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${required}`, updatedAt: now }).where(eq(masterItems.id, food.id));
  return { rations: required, multipliers };
}
