/**
 * Domain 03 (P1) personality, loyalty and relationship rules.
 * Pure helpers; deterministic trait assignment keeps tests and replays stable.
 *
 * Sample tuning (prototype data):
 * - every Hero receives 4 traits (core / social / behavioural / special) plus a
 *   favourite food, derived deterministically from its instance id
 * - loyalty starts at 50, rises with victories (+1) and favourite meals (+5)
 * - loyalty state: DEVOTED >= 80, NORMAL 20–79, DANGER < 20
 * - DANGER Heroes fight at 50–80% stats and have a 30% chance to refuse dispatch
 * - shared victories add +2 affinity per Hero pair; 50 affinity unlocks COMRADE
 *   and a +5% ATK resonance when both fight together
 */

export const CORE_TRAITS = ['BRAVE', 'CAUTIOUS', 'KIND', 'STOIC'] as const;
export const SOCIAL_TRAITS = ['FRIENDLY', 'ALOOF', 'PLAYFUL'] as const;
export const BEHAVIORAL_TRAITS = ['AGGRESSIVE', 'DEFENSIVE', 'SUPPORTIVE'] as const;
export const SPECIAL_TRAITS = ['BONDED', 'LONE_WOLF', 'RESILIENT'] as const;
export const FAVORITE_FOODS = ['ROAST_CHICKEN', 'HONEY_BREAD', 'SPICED_STEW', 'MOON_CAKE'] as const;

export const LOYALTY_START = 50;
export const LOYALTY_DEVOTED_THRESHOLD = 80;
export const LOYALTY_DANGER_THRESHOLD = 20;
export const DISOBEDIENCE_CHANCE = 0.3;
export const COMRADE_THRESHOLD = 50;
export const TRUSTED_THRESHOLD = 80;
export const RESONANCE_BONUS = 1.05;

export type LoyaltyState = 'DEVOTED' | 'NORMAL' | 'DANGER';
export type RelationshipTier = 'RIVAL' | 'STRANGER' | 'ACQUAINTANCE' | 'COMRADE' | 'TRUSTED_ALLY';

export const clampLoyalty = (value: number): number => Math.min(100, Math.max(0, Math.round(value)));

/** Stable hash so the same Hero always keeps the same personality. */
export function hashSeed(value: string): number {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return Math.abs(hash);
}

export function pickTrait<T>(pool: readonly T[], heroId: string, slot: string): T {
  return pool[hashSeed(`${heroId}:${slot}`) % pool.length];
}

export function assignTraits(heroId: string) {
  return {
    coreTrait: pickTrait(CORE_TRAITS, heroId, 'core'),
    socialTrait: pickTrait(SOCIAL_TRAITS, heroId, 'social'),
    behavioralTrait: pickTrait(BEHAVIORAL_TRAITS, heroId, 'behavioral'),
    specialTrait: pickTrait(SPECIAL_TRAITS, heroId, 'special'),
    favoriteFood: pickTrait(FAVORITE_FOODS, heroId, 'food'),
  };
}

export function loyaltyState(score: number): LoyaltyState {
  const value = clampLoyalty(score);
  if (value >= LOYALTY_DEVOTED_THRESHOLD) return 'DEVOTED';
  if (value < LOYALTY_DANGER_THRESHOLD) return 'DANGER';
  return 'NORMAL';
}

/** Scenario 2.2: loyalty 0 => 50% stats, loyalty 19 => about 78.5%. */
export function loyaltyCombatMultiplier(score: number): number {
  const value = clampLoyalty(score);
  if (value >= LOYALTY_DEVOTED_THRESHOLD) return 1.05;
  if (value >= LOYALTY_DANGER_THRESHOLD) return 1;
  return Math.round((0.5 + (value / LOYALTY_DANGER_THRESHOLD) * 0.3) * 1000) / 1000;
}

export function disobedienceChance(score: number): number {
  return loyaltyState(score) === 'DANGER' ? DISOBEDIENCE_CHANCE : 0;
}

export function relationshipTier(affinity: number): RelationshipTier {
  if (affinity < 0) return 'RIVAL';
  if (affinity >= TRUSTED_THRESHOLD) return 'TRUSTED_ALLY';
  if (affinity >= COMRADE_THRESHOLD) return 'COMRADE';
  if (affinity >= 20) return 'ACQUAINTANCE';
  return 'STRANGER';
}

/** Scenario 3.1: five shared victories move affinity from 0 to 10. */
export function affinityGainForVictory(pairs = 1): number {
  return 2 * Math.max(1, Math.floor(pairs));
}

export function resonanceMultiplier(tier: RelationshipTier): number {
  return tier === 'COMRADE' || tier === 'TRUSTED_ALLY' ? RESONANCE_BONUS : 1;
}

export function loyaltyAfterVictory(score: number): number {
  return clampLoyalty(score + 1);
}

export function loyaltyAfterFavoriteMeal(score: number): number {
  return clampLoyalty(score + 5);
}
