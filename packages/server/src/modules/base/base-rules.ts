/**
 * Domain 08 (P1) base rules — Multi-Floor Waiting Room (Pick Me Up style).
 * Kept free of I/O so the numbers are unit-testable and prototype tuning is visible in one place.
 *
 * Multi-floor & building rules:
 * - Each floor (zone) holds 3 building plots; base starts with Floor 1, up to 6 Floors (18 plots).
 * - Every 15 Master levels unlocks a higher floor (Lv.1 -> Floor 1, Lv.15 -> Floor 2, Lv.30 -> Floor 3, etc.),
 *   or a floor can be unlocked once World Level reaches `floor - 1`.
 * - Dormitory (`HOUSE`) can be promoted to `PARTY_MANSION` once Master reaches Level 30.
 * - `FORGE` is an active equipment crafting facility (not passive iron mining).
 */

export const PLOTS_PER_ZONE = 3;
export const MAX_BASE_ZONES = 6;
export const MASTER_LEVELS_PER_FLOOR = 15;
export const PARTY_MANSION_REQUIRED_MASTER_LEVEL = 30;
export const PARTY_MANSION_UPGRADE_COST_SILVER = 5000;
export const CONSTRUCTION_SECONDS = 20;
export const UPGRADE_SECONDS_PER_LEVEL = 15;
export const DEMOLISH_REFUND_RATIO = 0.5;

/** World level follows PvE progress: every 3 cleared floors raise it by one. */
export function worldLevelForFloor(currentFloor: number): number {
  const floor = Number.isFinite(currentFloor) ? Math.max(1, Math.floor(currentFloor)) : 1;
  return Math.min(10, 1 + Math.floor((floor - 1) / 3));
}

/**
 * Multi-floor lobby rule:
 * Floor 1 is available at Master Level 1; every 15 Master levels unlocks 1 higher floor
 * (Lv.1 -> 1, Lv.15 -> 2, Lv.30 -> 3, Lv.45 -> 4, Lv.60 -> 5, Lv.75 -> 6).
 */
export function unlockedLobbyFloorsForMasterLevel(masterLevel: number): number {
  const lvl = Number.isFinite(masterLevel) ? Math.max(1, Math.floor(masterLevel)) : 1;
  return Math.min(MAX_BASE_ZONES, 1 + Math.floor(lvl / MASTER_LEVELS_PER_FLOOR));
}

export function requiredMasterLevelForFloor(floorNumber: number): number {
  const f = Math.max(1, Math.floor(floorNumber));
  return f <= 1 ? 1 : (f - 1) * MASTER_LEVELS_PER_FLOOR;
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
