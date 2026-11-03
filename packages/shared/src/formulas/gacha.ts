import { GAME_CONSTANTS } from '../constants/index.js';

export interface PityRateOptions {
  /** Base 5-star chance on rolls before the escalation window. */
  baseRate?: number;
  /** Last roll that still uses the base rate. */
  thresholdStart?: number;
  /** Roll that guarantees a 5-star. */
  guaranteeRoll?: number;
  /** Polynomial exponent applied across the escalation window. */
  exponent?: number;
}

/**
 * Calculates the 5-star probability on roll `n` (1-indexed) based on the Pity-70 polynomial formula.
 *
 * Formula:
 * - For roll 1 to `thresholdStart`: P(n) = baseRate (0.4% by default)
 * - For the escalation window: P(n) = baseRate + (1 - baseRate) * ((n - thresholdStart) / (guaranteeRoll - thresholdStart))^exponent
 * - For `guaranteeRoll` and beyond: P(n) = 1.0 (100% guarantee)
 *
 * Coefficients default to the approved constants, but callers may pass the
 * active versioned `GACHA_PITY` configuration (FUN-14-03-002) instead.
 *
 * @param rollIndexInPity - Current roll number in pity cycle (1 to 70)
 * @param options - Optional coefficient overrides
 * @returns probability between baseRate and 1.0
 */
export function calculateFiveStarRate(rollIndexInPity: number, options: PityRateOptions = {}): number {
  if (rollIndexInPity < 1) {
    throw new Error('Roll index must be at least 1');
  }

  const { BASE_FIVE_STAR_RATE, PITY_THRESHOLD_START, PITY_GUARANTEE_ROLL } = GAME_CONSTANTS.GACHA;
  const baseRate = options.baseRate ?? BASE_FIVE_STAR_RATE;
  const thresholdStart = options.thresholdStart ?? PITY_THRESHOLD_START;
  const guaranteeRoll = options.guaranteeRoll ?? PITY_GUARANTEE_ROLL;
  const exponent = options.exponent ?? 4;

  if (rollIndexInPity <= thresholdStart) {
    return baseRate;
  }

  if (rollIndexInPity >= guaranteeRoll) {
    return 1.0;
  }

  // Polynomial escalation inside the pity window.
  const span = Math.max(1, guaranteeRoll - thresholdStart);
  const delta = (rollIndexInPity - thresholdStart) / span;
  const escalation = (1.0 - baseRate) * Math.pow(delta, exponent);
  return baseRate + escalation;
}

/**
 * Determines whether a roll results in a 5-star hero.
 *
 * @param rollIndexInPity - Current roll counter
 * @param randomValue - Random float in range [0, 1), defaults to Math.random()
 * @param options - Optional coefficient overrides passed to `calculateFiveStarRate`
 */
export function rollForFiveStar(rollIndexInPity: number, randomValue = Math.random(), options: PityRateOptions = {}): boolean {
  const threshold = calculateFiveStarRate(rollIndexInPity, options);
  return randomValue < threshold;
}
