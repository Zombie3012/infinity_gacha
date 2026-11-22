import { and, eq, inArray, sql } from 'drizzle-orm';
import { db } from '../../database/db.js';
import type { GameTransaction } from '../../database/transaction.js';
import { heroes, heroSurvivalStates, masterItems, pveMaps } from '../../database/drizzle-schema.js';
import { applyDrift, isImmobilised, rationsFor, starvationMultiplier } from '../survival/survival-rules.js';

export class CombatReadinessError extends Error {
  readonly statusCode = 409;
}

/** Early read-only gate; the authoritative gate runs again under the caller's Master lock. */
export async function assertNoPrivatePve(masterId: string, transaction?: GameTransaction) {
  const database = transaction ?? db;
  const [active] = await database.select({ id: pveMaps.id }).from(pveMaps)
    .where(and(eq(pveMaps.masterId, masterId), eq(pveMaps.status, 'ACTIVE'))).limit(1);
  if (active) throw new CombatReadinessError('ERR_PVE_MAP_ACTIVE');
}

/** Charge rations with the same transaction that creates the session/reserves the squad. */
export async function chargeCombatDispatch(tx: GameTransaction, masterId: string, heroIds: string[], now: Date) {
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
    if (drift.isResting || isImmobilised(drift.hungerScore, drift.fatigueScore)) throw new CombatReadinessError('ERR_PVE_HERO_EXHAUSTED');
    await tx.insert(heroSurvivalStates).values({ heroId: hero.id, hungerScore: drift.hungerScore, fatigueScore: drift.fatigueScore, lastTickAt: now })
      .onConflictDoUpdate({ target: heroSurvivalStates.heroId, set: { hungerScore: drift.hungerScore, fatigueScore: drift.fatigueScore, isResting: false,
        lastTickAt: state && state.lastTickAt > now ? state.lastTickAt : now } });
    multipliers[hero.id] = starvationMultiplier(drift.hungerScore);
  }
  await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${required}`, updatedAt: now }).where(eq(masterItems.id, food.id));
  return { rations: required, multipliers };
}
