/**
 * Domain 09 (P1) survival rules: hunger, fatigue and food logistics.
 * Pure functions so the thresholds and drift maths stay testable.
 *
 * Sample tuning (prototype data, not approved balance):
 * - hunger +1/hour while food is in storage, +2/hour when the warehouse is empty
 * - fatigue +2/hour awake, -15/hour while resting in the Dormitory
 * - a labour shift adds +5 hunger and +8 fatigue, a battle +8 hunger and +12 fatigue
 * - feeding one FOOD item relieves 20 hunger points
 * - at 60+ hunger the Hero fights at 60% ATK/DEF; at 100 the Hero cannot be dispatched
 * - at 100 fatigue the Hero is Overexhausted and must rest before joining a party
 */

export const HUNGER_PER_HOUR = 1;
export const HUNGER_PER_HOUR_WITHOUT_FOOD = 2;
export const HUNGER_PER_SHIFT = 5;
export const HUNGER_PER_BATTLE = 8;
export const FATIGUE_PER_HOUR = 2;
export const FATIGUE_PER_SHIFT = 8;
export const FATIGUE_PER_BATTLE = 12;
export const REST_RECOVERY_PER_HOUR = 15;
export const FEED_HUNGER_RELIEF = 20;
export const STARVATION_PENALTY_MULTIPLIER = 0.6;
export const FOOD_PER_HERO_PER_DAY = 2;

export type HungerState = 'FULL' | 'SATISFIED' | 'HUNGRY' | 'STARVING' | 'CRITICAL';
export type FatigueState = 'RESTED' | 'NORMAL' | 'TIRED' | 'EXHAUSTED' | 'CRITICAL' | 'OVEREXHAUSTED';
export type RationContext = 'DUNGEON' | 'WAR';

export const clampScore = (value: number): number => Math.min(100, Math.max(0, Math.round(value * 100) / 100));

export function hungerState(score: number): HungerState {
  const value = clampScore(score);
  if (value >= 100) return 'CRITICAL';
  if (value >= 60) return 'STARVING';
  if (value >= 40) return 'HUNGRY';
  if (value >= 10) return 'SATISFIED';
  return 'FULL';
}

export function fatigueState(score: number): FatigueState {
  const value = clampScore(score);
  if (value >= 100) return 'OVEREXHAUSTED';
  if (value >= 80) return 'CRITICAL';
  if (value >= 60) return 'EXHAUSTED';
  if (value >= 40) return 'TIRED';
  if (value >= 20) return 'NORMAL';
  return 'RESTED';
}

/** Starving Heroes fight at 60% ATK/DEF; critical hunger immobilises them. */
export function starvationMultiplier(score: number): number {
  return clampScore(score) >= 60 ? STARVATION_PENALTY_MULTIPLIER : 1;
}

export function isImmobilised(hungerScore: number, fatigueScore: number): boolean {
  return clampScore(hungerScore) >= 100 || clampScore(fatigueScore) >= 100;
}

/** Arena rounds: rations are charged per Hero dispatched. */
export function rationsFor(context: RationContext, heroCount: number): number {
  const heroes = Math.max(0, Math.floor(heroCount));
  if (context === 'DUNGEON') return heroes * 10;
  return heroes * 15;
}

/** Passive food consumption of Heroes idling in the base. */
export function baseFoodConsumption(heroCount: number, hours: number): number {
  return Math.max(0, heroCount) * FOOD_PER_HERO_PER_DAY * (Math.max(0, hours) / 24);
}

export interface SurvivalSnapshot {
  hungerScore: number;
  fatigueScore: number;
  isResting: boolean;
  lastTickAt: Date;
}

export interface DriftResult {
  hungerScore: number;
  fatigueScore: number;
  isResting: boolean;
  hungerState: HungerState;
  fatigueState: FatigueState;
  hoursElapsed: number;
}

/**
 * Apply the pass of time to one Hero. Food availability doubles hunger gain,
 * resting drains fatigue instead of adding it, and resting stops at 0.
 */
export function applyDrift(state: SurvivalSnapshot, now: Date, foodAvailable: boolean): DriftResult {
  const hoursElapsed = Math.max(0, (now.getTime() - state.lastTickAt.getTime()) / 3_600_000);
  const hungerGain = (foodAvailable ? HUNGER_PER_HOUR : HUNGER_PER_HOUR_WITHOUT_FOOD) * hoursElapsed;
  const fatigueDelta = state.isResting
    ? -REST_RECOVERY_PER_HOUR * hoursElapsed
    : FATIGUE_PER_HOUR * hoursElapsed;

  const hungerScore = clampScore(state.hungerScore + hungerGain);
  const fatigueScore = clampScore(state.fatigueScore + fatigueDelta);
  const isResting = state.isResting && fatigueScore > 0;

  return {
    hungerScore,
    fatigueScore,
    isResting,
    hungerState: hungerState(hungerScore),
    fatigueState: fatigueState(fatigueScore),
    hoursElapsed: Math.round(hoursElapsed * 100) / 100,
  };
}

export function applyActivity(hunger: number, fatigue: number, activity: 'SHIFT' | 'BATTLE'): { hungerScore: number; fatigueScore: number } {
  if (activity === 'BATTLE') {
    return { hungerScore: clampScore(hunger + HUNGER_PER_BATTLE), fatigueScore: clampScore(fatigue + FATIGUE_PER_BATTLE) };
  }
  return { hungerScore: clampScore(hunger + HUNGER_PER_SHIFT), fatigueScore: clampScore(fatigue + FATIGUE_PER_SHIFT) };
}
