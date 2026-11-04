/**
 * Domain 13 (P3) PvP rules — Heroes fight Heroes, there is no army.
 *
 * Sample tuning:
 * - an owned tile cannot be attacked while its 30-minute claim protection is up
 * - a Master's 48-hour Novice Shield blocks attacks on every tile they own
 * - the defender fights with the power of their five strongest Heroes, plus 20%
 *   for defending and 10% per territory level
 * - the winner is decided by power ratio with a small deterministic swing
 * - an attacker that wins takes ownership; the territory keeps its level but
 *   receives a fresh protection window
 */

import { MAX_TERRITORIES } from './world-rules.js';

export const DEFENDER_BONUS = 1.2;
export const LEVEL_BONUS_PER_LEVEL = 0.1;
export const PVP_SWING = 0.1;
export const PROTECTION_MINUTES_AFTER_CAPTURE = 30;

export interface AttackCheck {
  ok: boolean;
  reason?: 'ERR_TERRITORY_PROTECTED' | 'ERR_TARGET_SHIELDED' | 'ERR_TARGET_OWN_TERRITORY' | 'ERR_TARGET_UNOWNED';
}

export function canAttack(input: {
  tileOwned: boolean;
  ownedBySelf: boolean;
  territoryProtectedUntil: Date | null;
  ownerShieldUntil: Date | null;
  now: Date;
}): AttackCheck {
  if (!input.tileOwned) return { ok: false, reason: 'ERR_TARGET_UNOWNED' };
  if (input.ownedBySelf) return { ok: false, reason: 'ERR_TARGET_OWN_TERRITORY' };
  if (input.territoryProtectedUntil && input.territoryProtectedUntil > input.now) {
    return { ok: false, reason: 'ERR_TERRITORY_PROTECTED' };
  }
  if (input.ownerShieldUntil && input.ownerShieldUntil > input.now) {
    return { ok: false, reason: 'ERR_TARGET_SHIELDED' };
  }
  return { ok: true };
}

export function defenderPower(heroPower: number, territoryLevel: number): number {
  return Math.round(heroPower * DEFENDER_BONUS * (1 + LEVEL_BONUS_PER_LEVEL * Math.max(0, Math.floor(territoryLevel) - 1)));
}

/** Deterministic swing derived from the battle seed keeps replays stable. */
export function resolvePvp(attackerPower: number, defenderStrength: number, seed: string): {
  winner: 'ATTACKER' | 'DEFENDER';
  rounds: number;
  attackerEffective: number;
  defenderEffective: number;
} {
  let hash = 2166136261;
  for (const char of seed) {
    hash ^= char.charCodeAt(0);
    hash = Math.imul(hash, 16777619);
  }
  const swing = 1 + ((Math.abs(hash) % 200) / 1000 - 0.1); // 0.9 .. 1.1
  const attackerEffective = Math.round(attackerPower * swing);
  const defenderEffective = Math.round(defenderStrength * (2 - swing));
  const winner = attackerEffective >= defenderEffective ? 'ATTACKER' : 'DEFENDER';
  const ratio = defenderEffective <= 0 ? 5 : attackerEffective / defenderEffective;
  const rounds = Math.max(3, Math.min(20, Math.round(12 / Math.max(0.4, ratio))));
  return { winner, rounds, attackerEffective, defenderEffective };
}

export function canHoldMoreTerritories(ownedCount: number): boolean {
  return ownedCount < MAX_TERRITORIES;
}

export function protectionAfterCapture(now: Date, minutes = PROTECTION_MINUTES_AFTER_CAPTURE): Date {
  return new Date(now.getTime() + minutes * 60_000);
}
