/**
 * Combat v2 — Hero Star Promotion system (Pick Me Up style).
 *
 * Rules:
 * 1. Target hero must be at maximum level for their current star rank.
 * 2. Promotion from N★ to (N+1)★ requires exactly N fodder heroes of the same N★ rank.
 * 3. Fodders are consumed (sacrificed); their equipment is unequipped safely.
 * 4. Star rating increases by 1 (up to 7★ enabled).
 * 5. Max level increases by 10 (e.g. 1★ max 10, 2★ max 20, 3★ max 30, 4★ max 40, 5★ max 50).
 * 6. Origin stats scale with the new star budget, recomputing derived stats.
 * 7. Imprint slots expand according to the new star rank.
 */

import {
  BASE_STAT_BUDGET, apportion,
  type BaseStats, type StarRating,
} from './stats.js';

export const MAX_PROMOTABLE_STAR = 7;

export const STAR_MAX_LEVEL: Record<number, number> = {
  1: 10,
  2: 20,
  3: 30,
  4: 40,
  5: 50,
  6: 60,
  7: 70,
};

export const STAR_PROMOTION_COST_SILVER: Record<number, number> = {
  1: 10_000,
  2: 25_000,
  3: 50_000,
  4: 100_000,
  5: 250_000,
  6: 500_000,
};

export const BREAKTHROUGH_SILVER_COST: Record<number, number> = {
  1: 5_000,
  2: 15_000,
  3: 30_000,
  4: 50_000,
  5: 100_000,
  6: 200_000,
};

/**
 * Returns the maximum level achievable at a given star rank (Star Ceiling).
 * Default is star * 10 (1★ = 10, 2★ = 20, 3★ = 30, 4★ = 40, 5★ = 50).
 */
export function starMaxLevel(star: number): number {
  return STAR_MAX_LEVEL[star] ?? Math.max(10, Math.min(70, Math.floor(star) * 10));
}

/**
 * Returns breakthrough level cap for a given promotion/breakthrough rank.
 * Rank 0 = 10, Rank 1 = 20, Rank 2 = 30, Rank 3 = 40, Rank 4 = 50.
 */
export function breakthroughMaxLevel(promotionRank = 0): number {
  const safeRank = Math.max(0, Math.floor(promotionRank));
  return Math.min(70, (safeRank + 1) * 10);
}

/**
 * Calculates effective max level under the dual-cap system:
 * min(Star Ceiling, Breakthrough Cap).
 * - Fresh 5★ at rank 0: min(50, 10) = 10 (must breakthrough to unlock 20)
 * - 1★ at rank 0: min(10, 10) = 10 (needs both star promotion and breakthrough to reach 20)
 */
export function heroEffectiveMaxLevel(star: number, promotionRank = 0): number {
  const starCeiling = starMaxLevel(star);
  const btCap = breakthroughMaxLevel(promotionRank);
  return Math.min(starCeiling, btCap);
}

/**
 * Checks if target hero is eligible for level breakthrough (Đột Phá Cấp).
 */
export function checkBreakthroughEligibility(input: {
  currentStar: number;
  currentLevel: number;
  promotionRank: number;
  isLocked?: boolean;
  state?: string;
}): { eligible: boolean; reason?: string; requiredLevel?: number; requiredStar?: number } {
  if (input.state === 'DEAD') {
    return { eligible: false, reason: 'ERR_HERO_PERMANENTLY_DEAD' };
  }
  if (input.state === 'DISABLED') {
    return { eligible: false, reason: 'ERR_HERO_DISABLED' };
  }
  if (input.isLocked) {
    return { eligible: false, reason: 'ERR_HERO_LOCKED' };
  }
  if (input.promotionRank >= 6) {
    return { eligible: false, reason: 'ERR_HERO_MAX_BREAKTHROUGH' };
  }
  const nextRank = input.promotionRank + 1;
  const requiredLevel = nextRank * 10;
  const requiredStar = nextRank + 1;

  if (input.currentStar < requiredStar) {
    return { eligible: false, reason: 'ERR_HERO_STAR_TOO_LOW', requiredLevel, requiredStar };
  }
  if (input.currentLevel < requiredLevel) {
    return { eligible: false, reason: 'ERR_HERO_LEVEL_NOT_MAX', requiredLevel, requiredStar };
  }
  return { eligible: true, requiredLevel, requiredStar };
}

/**
 * Returns number of fodder heroes required to promote from currentStar to (currentStar + 1).
 * In Pick Me Up: N★ requires exactly N heroes of N★.
 */
export function requiredFodderCount(currentStar: number): number {
  return Math.max(1, Math.floor(currentStar));
}

/**
 * Returns Silver coin cost required for star promotion.
 */
export function starPromotionCost(currentStar: number): number {
  return STAR_PROMOTION_COST_SILVER[currentStar] ?? (currentStar * 25_000);
}

/**
 * Checks if target hero is eligible to be promoted.
 */
export function checkStarPromotionEligibility(input: {
  currentStar: number;
  currentLevel: number;
  isLocked?: boolean;
  state?: string;
}): { eligible: boolean; reason?: string } {
  if (input.state === 'DEAD') {
    return { eligible: false, reason: 'ERR_HERO_PERMANENTLY_DEAD' };
  }
  if (input.state === 'DISABLED') {
    return { eligible: false, reason: 'ERR_HERO_DISABLED' };
  }
  if (input.isLocked) {
    return { eligible: false, reason: 'ERR_HERO_LOCKED' };
  }
  if (input.currentStar >= MAX_PROMOTABLE_STAR) {
    return { eligible: false, reason: 'ERR_HERO_MAX_STAR' };
  }
  const maxLevel = starMaxLevel(input.currentStar);
  if (input.currentLevel < maxLevel) {
    return { eligible: false, reason: 'ERR_HERO_LEVEL_NOT_MAX' };
  }
  return { eligible: true };
}

/**
 * Scales origin stats up to the next star rating budget while preserving the stat distribution.
 */
export function promoteOriginStats(
  currentOrigin: BaseStats,
  currentStar: StarRating,
  nextStar: StarRating,
): BaseStats {
  const curBudget = BASE_STAT_BUDGET[currentStar] ?? 100;
  const nextBudget = BASE_STAT_BUDGET[nextStar] ?? curBudget;
  const delta = Math.max(0, nextBudget - curBudget);
  if (delta <= 0) return { ...currentOrigin };

  const total = currentOrigin.str + currentOrigin.int + currentOrigin.sta + currentOrigin.agi || 1;
  const weights = [
    currentOrigin.str / total,
    currentOrigin.int / total,
    currentOrigin.sta / total,
    currentOrigin.agi / total,
  ];
  const additions = apportion(delta, weights.map(w => delta * w));
  return {
    str: currentOrigin.str + additions[0],
    int: currentOrigin.int + additions[1],
    sta: currentOrigin.sta + additions[2],
    agi: currentOrigin.agi + additions[3],
  };
}
