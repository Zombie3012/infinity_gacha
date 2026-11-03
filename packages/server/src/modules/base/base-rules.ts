/**
 * Domain 08 (P1) base rules. Kept free of I/O so the numbers are unit-testable
 * and the prototype tuning is visible in one place.
 *
 * Sample tuning (documented as prototype data, not approved balance):
 * - one zone holds 3 building plots, a base starts with zone 1, maximum 6 zones
 * - expanding to zone 2 costs 2,000 Silver; every later zone costs 5,000 Silver
 * - a zone can be bought only once the world level reaches `zone - 1`
 * - production rate grows 60% per building level, capacity grows linearly
 * - a building upgrade costs 75% of the build price per target level plus materials
 */

export const PLOTS_PER_ZONE = 3;
export const MAX_BASE_ZONES = 6;
export const CONSTRUCTION_SECONDS = 20;
export const UPGRADE_SECONDS_PER_LEVEL = 15;
export const DEMOLISH_REFUND_RATIO = 0.5;

/** World level follows PvE progress: every 3 cleared floors raise it by one. */
export function worldLevelForFloor(currentFloor: number): number {
  const floor = Number.isFinite(currentFloor) ? Math.max(1, Math.floor(currentFloor)) : 1;
  return Math.min(10, 1 + Math.floor((floor - 1) / 3));
}

export function plotsForZones(zones: number): number {
  return Math.max(1, Math.min(MAX_BASE_ZONES, Math.floor(zones))) * PLOTS_PER_ZONE;
}

export function expansionCostSilver(currentZones: number): number {
  return currentZones <= 1 ? 2000 : 5000;
}

export function expansionRequiredWorldLevel(nextZone: number): number {
  return Math.max(1, nextZone - 1);
}

/** Level 1 keeps the configured rate; every extra level adds 60% of the base. */
export function levelRateMultiplier(level: number): number {
  return 1 + 0.6 * (Math.max(1, Math.floor(level)) - 1);
}

export function capacityForLevel(baseCapacity: number, level: number): number {
  return Math.round(baseCapacity * Math.max(1, Math.floor(level)));
}

/** Worker boosts are additive on top of 1.0, e.g. [1.2] -> +20%. */
export function productionRatePerHour(baseRate: number, level: number, boosts: readonly number[] = []): number {
  const workerShare = boosts.reduce((sum, boost) => sum + (Math.max(0, boost) - 1), 0);
  return Math.max(0, baseRate * levelRateMultiplier(level) * (1 + workerShare));
}

export function accruedStored(
  stored: number,
  ratePerHour: number,
  lastHarvestAt: Date,
  capacity: number,
  now: Date,
): { stored: number; atCapacity: boolean; hoursElapsed: number } {
  const hoursElapsed = Math.max(0, (now.getTime() - lastHarvestAt.getTime()) / 3_600_000);
  const projected = Math.max(0, stored) + Math.max(0, ratePerHour) * hoursElapsed;
  const capped = Math.min(Math.max(0, capacity), projected);
  return {
    stored: Math.round(capped * 100) / 100,
    atCapacity: projected >= capacity,
    hoursElapsed: Math.round(hoursElapsed * 100) / 100,
  };
}

export function upgradeCostSilver(buildCostSilver: number, targetLevel: number): number {
  return Math.round(buildCostSilver * Math.max(2, Math.floor(targetLevel)) * 0.75);
}

export function upgradeMaterials(targetLevel: number): { itemId: string; quantity: number }[] {
  const level = Math.max(2, Math.floor(targetLevel));
  return [
    { itemId: 'WOOD', quantity: 10 * level },
    { itemId: 'STONE', quantity: 5 * level },
  ];
}

/** Demolishing returns half of the invested Silver, rounded down. */
export function demolishRefundSilver(buildCostSilver: number, currentLevel: number): number {
  const invested = buildCostSilver + (currentLevel > 1 ? upgradeCostSilver(buildCostSilver, currentLevel) : 0);
  return Math.floor(invested * DEMOLISH_REFUND_RATIO);
}

export function constructionSeconds(level = 1): number {
  return CONSTRUCTION_SECONDS + Math.max(0, level - 1) * 10;
}

export function upgradeSeconds(targetLevel: number): number {
  return Math.max(2, Math.floor(targetLevel)) * UPGRADE_SECONDS_PER_LEVEL;
}
