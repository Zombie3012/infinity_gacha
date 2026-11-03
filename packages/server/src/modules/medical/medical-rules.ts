/**
 * Domain 04 (P1) medical rules: injury classification, treatment and
 * resurrection pricing. Pure functions for testability.
 *
 * Sample tuning (prototype data):
 * - HP below 15% after a battle => SEVERE (-25% ATK/DEF, 2h natural heal)
 * - HP below 30% => MODERATE (-15%, 1h), below 50% => MINOR (-10%, 30m)
 * - each Medical Facility level adds one bed (level 1 = 2 beds) and speeds
 *   treatment by 20% of the base duration per level
 * - emergency treatment consumes one MEDICINE and heals instantly
 * - resurrection costs (n) tears and 10,000 × n Silver, where n is the number
 *   of resurrections already performed in the current 30-day cycle
 */

export type InjurySeverity = 'MINOR' | 'MODERATE' | 'SEVERE';
export type TreatmentType = 'INJURY' | 'RESURRECTION';
export type TreatmentStatus = 'ACTIVE' | 'COMPLETED' | 'CANCELLED';

export const RESURRECTION_CYCLE_DAYS = 30;
export const RESURRECTION_BASE_SILVER = 10_000;
export const DIVINE_TEAR_ITEM = 'DIVINE_TEAR';
export const MEDICINE_ITEM = 'MEDICINE';

export interface InjuryProfile {
  severity: InjurySeverity;
  penaltyPercent: number;
  naturalHealSeconds: number;
}

/** Scenario 4.1: surviving under 15% HP yields SEVERE with a 25% penalty and 2h timer. */
export function classifyInjury(hpPercent: number): InjuryProfile | null {
  const percent = Number.isFinite(hpPercent) ? Math.max(0, Math.min(100, hpPercent)) : 100;
  if (percent < 15) return { severity: 'SEVERE', penaltyPercent: 25, naturalHealSeconds: 7200 };
  if (percent < 30) return { severity: 'MODERATE', penaltyPercent: 15, naturalHealSeconds: 3600 };
  if (percent < 50) return { severity: 'MINOR', penaltyPercent: 10, naturalHealSeconds: 1800 };
  return null;
}

export function bedCapacityForLevel(level: number): number {
  return Math.max(1, Math.floor(level)) + 1;
}

/** Facility care shortens the natural timer, but never below 20% of it. */
export function treatmentSeconds(naturalHealSeconds: number, facilityLevel: number): number {
  const factor = Math.max(0.2, 1 - 0.2 * Math.max(0, Math.floor(facilityLevel) - 1));
  return Math.max(60, Math.round(naturalHealSeconds * factor));
}

export function injuryMultiplier(penaltyPercent: number): number {
  return Math.max(0, 1 - Math.max(0, Math.min(100, penaltyPercent)) / 100);
}

export interface ResurrectionQuote {
  cycleCount: number;
  tears: number;
  silver: number;
  cycleReset: boolean;
}

/** Cost grows linearly inside a 30-day cycle and resets when the cycle expires. */
export function resurrectionQuote(cycleCount: number, cycleStartAt: Date, now: Date): ResurrectionQuote {
  const cycleAgeDays = (now.getTime() - cycleStartAt.getTime()) / 86_400_000;
  const cycleReset = cycleAgeDays >= RESURRECTION_CYCLE_DAYS;
  const count = cycleReset ? 0 : Math.max(0, Math.floor(cycleCount));
  return {
    cycleCount: count,
    tears: count + 1,
    silver: RESURRECTION_BASE_SILVER * (count + 1),
    cycleReset,
  };
}

export function revivedHpPercent(): number {
  return 0.5;
}

export function revivedFatigueGain(): number {
  return 25;
}
