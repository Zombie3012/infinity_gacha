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

async function activeValue(key: 'BATTLE_RULES' | 'GACHA_RULES' | 'DEATH_RULES' | 'DUNGEON_RULES' | 'SEED_ALGORITHM'): Promise<Record<string, unknown>> {
  try {
    const active = await systemConfigService.getActive(key);
    return active?.value ?? {};
  } catch (error) {
    console.error('[config] falling back to constants for', key, error);
    return {};
  }
}

export async function getBattleRules(): Promise<BattleRules> {
  const value = await activeValue('BATTLE_RULES');
  return {
    tacticalBuffCooldownSeconds: clampInteger(value.tacticalBuffCooldownSeconds, GAME_CONSTANTS.COMBAT.TACTICAL_BUFF_COOLDOWN_SECONDS, 0, 600),
  };
}
