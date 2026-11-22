/**
 * Domain 08 (P1) base rules — Multi-Floor Waiting Room (Pick Me Up style).
 * Kept free of I/O so the numbers are unit-testable and prototype tuning is visible in one place.
 *
 * Multi-floor & building rules:
 * - Each floor (zone) holds 8 building plots; base starts with Floor 1, up to 6 Floors (48 plots).
 * - Every 15 Master levels unlocks a higher floor (Lv.1 -> Floor 1, Lv.15 -> Floor 2, Lv.30 -> Floor 3, etc.),
 *   or a floor can be unlocked once World Level reaches `floor - 1`.
 * - Dormitory (`HOUSE`) can be promoted to `PARTY_MANSION` once Master reaches Level 30.
 * - `FORGE` is an active equipment crafting facility (not passive iron mining).
 */

export const PLOTS_PER_ZONE = 8;
export const MAX_BASE_ZONES = 6;
export const MASTER_LEVELS_PER_FLOOR = 15;
export const PARTY_MANSION_REQUIRED_MASTER_LEVEL = 30;
export const PARTY_MANSION_UPGRADE_COST_SILVER = 5000;
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

/**
 * Building-specific max workers by level (3-level standardized design):
 * - RECOVERY_CENTER (MEDICAL): 1 hero (opens 2/4/6 treatment slots)
 * - TRAINING_CENTER: Lv.1 = 3, Lv.2 = 5, Lv.3 = 7
 * - HALL_OF_MAGIC: 6 heroes total (2 per sub-wing)
 * - LIBRARY: 2 heroes (MAGE class only)
 * - ALCHEMY_WORKSHOP: 2 heroes
 * - MAGIC_RESEARCH_LAB: 2 heroes
 * - KITCHEN: Lv.1 = 1, Lv.2 = 2, Lv.3 = 3
 * - WAREHOUSE / HOUSE / PARTY_MANSION: 0 workers
 */
export function maxWorkersForBuildingLevel(code: string, level: number, defaultMaxWorkers = 0): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  switch (code) {
    case 'WAREHOUSE':
    case 'HOUSE':
    case 'PARTY_MANSION':
      return 0;
    case 'MEDICAL':
      return 1;
    case 'TRAINING_CENTER':
      return lvl === 1 ? 3 : lvl === 2 ? 5 : 7;
    case 'HALL_OF_MAGIC':
      return 6;
    case 'LIBRARY':
    case 'ALCHEMY_WORKSHOP':
    case 'MAGIC_RESEARCH_LAB':
      return 2;
    case 'KITCHEN':
    case 'FORGE':
      return lvl;
    default:
      return defaultMaxWorkers;
  }
}

/**
 * Standardized 3-level production profile for Library, Alchemy Workshop, and Kitchen:
 * - LIBRARY (requires MAGE worker):
 *   Lv.1 -> 100 Basic EXP Books/hr (SAMPLE_HERO_EXP_100)
 *   Lv.2 -> 50 Intermediate EXP Books/hr (SAMPLE_HERO_EXP_1000)
 *   Lv.3 -> 15 Advanced EXP Books/hr (SAMPLE_HERO_EXP_10000)
 * - ALCHEMY_WORKSHOP:
 *   Lv.1 -> 15 ENHANCEMENT_STONE/hr
 *   Lv.2 -> 30 ENHANCEMENT_STONE/hr
 *   Lv.3 -> 60 ENHANCEMENT_STONE/hr
 * - KITCHEN:
 *   Lv.1 -> 20 FOOD/hr
 *   Lv.2 -> 40 FOOD/hr
 *   Lv.3 -> 80 FOOD/hr
 */
export function buildingProductionForLevel(
  code: string,
  level: number,
): { resourceType: string; ratePerHour: number; capacity: number } | null {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  if (code === 'LIBRARY') {
    if (lvl === 1) return { resourceType: 'SAMPLE_HERO_EXP_100', ratePerHour: 100, capacity: 1000 };
    if (lvl === 2) return { resourceType: 'SAMPLE_HERO_EXP_1000', ratePerHour: 50, capacity: 500 };
    return { resourceType: 'SAMPLE_HERO_EXP_10000', ratePerHour: 15, capacity: 150 };
  }
  if (code === 'ALCHEMY_WORKSHOP') {
    const rate = lvl === 1 ? 15 : lvl === 2 ? 30 : 60;
    return { resourceType: 'ENHANCEMENT_STONE', ratePerHour: rate, capacity: rate * 10 };
  }
  if (code === 'KITCHEN') {
    const rate = lvl === 1 ? 20 : lvl === 2 ? 40 : 80;
    return { resourceType: 'FOOD', ratePerHour: rate, capacity: rate * 10 };
  }
  return null;
}

/** Direct EXP per hour granted to MAGE class heroes stationed/studying in the Library. */
export function libraryMageExpPerHour(level: number): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  if (lvl === 1) return 25_000;
  if (lvl === 2) return 1_250_000;
  return 16_500_000;
}

/** Treatment slots unlocked at Recovery Center (MEDICAL) per level (2 / 4 / 6). */
export function recoveryCenterTreatmentSlots(level: number): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  return lvl * 2;
}

/** Resident resting capacity for Dormitory (HOUSE: 5/7/10) and Party Mansion (5). */
export function dormitoryResidentCapacity(code: string, level: number): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  if (code === 'PARTY_MANSION') return 5;
  if (code === 'HOUSE') return lvl === 1 ? 5 : lvl === 2 ? 7 : 10;
  if (code === 'MEDICAL') return recoveryCenterTreatmentSlots(lvl);
  return 0;
}

/**
 * Stamina & Morale recovery multiplier:
 * - HOUSE (Dormitory): Lv.1 = 1.0x, Lv.2 = 1.5x, Lv.3 = 2.0x
 * - PARTY_MANSION (Independent building): x2 of House Lv.3 = 4.0x
 */
export function dormitoryRecoveryMultiplier(code: string, level: number): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  if (code === 'PARTY_MANSION') return 4.0;
  if (code === 'HOUSE') return lvl === 1 ? 1.0 : lvl === 2 ? 1.5 : 2.0;
  return 1.0;
}

/** Warehouse inventory slot expansion (+100 slots per level: +100 / +200 / +300). */
export function warehouseBonusSlotsForLevel(level: number): number {
  const lvl = Math.min(3, Math.max(1, Math.floor(level)));
  return lvl * 100;
}

/** Maximum constructible instances for limited buildings (e.g. Training Center max 2 unlocked by Master level). */
export function maxConstructibleCountForType(code: string, masterLevel: number): number | null {
  const mLvl = Math.max(1, Math.floor(masterLevel));
  if (code === 'TRAINING_CENTER') {
    return mLvl >= 30 ? 2 : 1;
  }
  return null;
}
