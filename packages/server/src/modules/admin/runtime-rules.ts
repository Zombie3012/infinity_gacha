import { GAME_CONSTANTS } from '@infiniti-gacha/shared';
import { systemConfigService } from './system-config.service.js';

/**
 * Bridges versioned configuration (DM-14) into gameplay code.
 *
 * Values are read through `SystemConfigService.getActive()`, which caches for a
 * few seconds and is invalidated whenever an operator activates a version, so a
 * published change applies without restarting the server. Missing, malformed or
 * unreachable configuration falls back to the approved constants so gameplay
 * never breaks because of the admin plane.
 */

export interface PityRules {
  baseRate: number;
  thresholdStart: number;
  guaranteeRoll: number;
  exponent: number;
}

export interface BattleRules {
  tacticalBuffCooldownSeconds: number;
}

const clampNumber = (value: unknown, fallback: number, min: number, max: number): number => {
  const parsed = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(Math.max(parsed, min), max);
};

const clampInteger = (value: unknown, fallback: number, min: number, max: number): number =>
  Math.round(clampNumber(value, fallback, min, max));

async function activeValue(key: 'GACHA_PITY' | 'BATTLE_RULES' | 'GACHA_RULES' | 'DEATH_RULES' | 'DUNGEON_RULES' | 'SEED_ALGORITHM'): Promise<Record<string, unknown>> {
  try {
    const active = await systemConfigService.getActive(key);
    return active?.value ?? {};
  } catch (error) {
    console.error('[config] falling back to constants for', key, error);
    return {};
  }
}

export async function getPityRules(): Promise<PityRules> {
  const value = await activeValue('GACHA_PITY');
  const thresholdStart = clampInteger(value.thresholdStart, GAME_CONSTANTS.GACHA.PITY_THRESHOLD_START, 1, 199);
  const guaranteeRoll = clampInteger(value.guaranteeRoll, GAME_CONSTANTS.GACHA.PITY_GUARANTEE_ROLL, thresholdStart + 1, 500);
  return {
    baseRate: clampNumber(value.baseRate, GAME_CONSTANTS.GACHA.BASE_FIVE_STAR_RATE, 0.0001, 0.5),
    thresholdStart,
    guaranteeRoll,
    exponent: clampNumber(value.exponentK, 4, 1, 12),
  };
}

export async function getBattleRules(): Promise<BattleRules> {
  const value = await activeValue('BATTLE_RULES');
  return {
    tacticalBuffCooldownSeconds: clampInteger(value.tacticalBuffCooldownSeconds, GAME_CONSTANTS.COMBAT.TACTICAL_BUFF_COOLDOWN_SECONDS, 0, 600),
  };
}
