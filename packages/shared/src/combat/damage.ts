/**
 * Combat v2 — damage pipeline (shared, pure functions).
 *
 * Order (owner-approved):
 *   hit check -> raw damage -> penetration/defence mitigation ->
 *   element affinity -> damage bonus -> critical -> block -> damage reduction
 *   -> floor, minimum 1.
 *
 * The critical rate may reach 100%; critical damage is capped at 300%.
 * Speed is not part of combat; the engine gives each unit one action per round
 * and orders units by AGI.
 */

import { affinityMultiplier, CAPS, clamp, type DamageElement } from './stats.js';

export type DamageType = 'PHYSICAL' | 'MAGICAL' | 'TRUE';

export interface AttackerProfile {
  attack: number;
  damageType: DamageType;
  skillMultiplier: number;
  bonusDamage: number;
  /** Percent, e.g. 12.5 = +12.5% final damage. */
  damageBonus: number;
  critRate: number;
  /** Percent, e.g. 150 = 1.5x. */
  critDamage: number;
  /** Percentage points added to the 90% base hit chance. */
  accuracy: number;
  /** Percent penetration (0-80) and flat penetration. */
  penetrationPercent: number;
  penetrationFlat: number;
}

export interface DefenderProfile {
  defense: number;
  evasion: number;
  blockRate: number;
  blockEffect: number;
  critResistance: number;
  critDamageReduction: number;
  damageReduction: number;
}

export interface AttackOptions {
  elementMultiplier?: number;
  random?: () => number;
}

export interface AttackResult {
  hit: boolean;
  crit: boolean;
  blocked: boolean;
  hitChance: number;
  critChance: number;
  damage: number;
  /** Damage after defence mitigation, before crit/block/DR (for logs). */
  mitigated: number;
}

export function hitChance(accuracy: number, evasion: number): number {
  return clamp(90 + accuracy - evasion, CAPS.hitChanceMin, CAPS.hitChanceMax);
}

export function effectiveDefense(defense: number, penetrationPercent = 0, penetrationFlat = 0): number {
  const percent = clamp(penetrationPercent, 0, CAPS.armorPen) / 100;
  return Math.max(0, defense * (1 - percent) - Math.max(0, penetrationFlat));
}

export function mitigatedDamage(input: {
  attack: number;
  skillMultiplier: number;
  bonusDamage: number;
  defense: number;
  penetrationPercent?: number;
  penetrationFlat?: number;
  k?: number;
}): number {
  const k = Math.max(1, input.k ?? 500);
  const raw = Math.max(0, input.attack * input.skillMultiplier + input.bonusDamage);
  const defense = effectiveDefense(input.defense, input.penetrationPercent ?? 0, input.penetrationFlat ?? 0);
  return raw * (k / (defense + k));
}

/** Critical multiplier after the defender's crit-damage reduction, capped. */
export function finalCritMultiplier(critDamage: number, critDamageReduction: number): number {
  const reduced = critDamage * (1 - clamp(critDamageReduction, 0, 100) / 100);
  return clamp(reduced, 0, CAPS.critDamage) / 100;
}

export function resolveAttack(
  attacker: AttackerProfile,
  defender: DefenderProfile,
  options: AttackOptions = {},
): AttackResult {
  const random = options.random ?? Math.random;
  const chance = hitChance(attacker.accuracy, defender.evasion);
  const hit = random() * 100 < chance;
  const critChance = clamp(attacker.critRate - defender.critResistance, 0, CAPS.critRate);

  if (!hit) {
    return { hit: false, crit: false, blocked: false, hitChance: chance, critChance, damage: 0, mitigated: 0 };
  }

  const mitigated = attacker.damageType === 'TRUE'
    ? Math.max(0, attacker.attack * attacker.skillMultiplier + attacker.bonusDamage)
    : mitigatedDamage({
      attack: attacker.attack,
      skillMultiplier: attacker.skillMultiplier,
      bonusDamage: attacker.bonusDamage,
      defense: defender.defense,
      penetrationPercent: attacker.penetrationPercent,
      penetrationFlat: attacker.penetrationFlat,
    });

  let damage = mitigated;
  if (attacker.damageType === 'MAGICAL' && options.elementMultiplier !== undefined) {
    damage *= Math.max(0, options.elementMultiplier);
  }
  damage *= 1 + attacker.damageBonus / 100;

  const crit = random() * 100 < critChance;
  if (crit) damage *= finalCritMultiplier(attacker.critDamage, defender.critDamageReduction);

  const blocked = random() * 100 < clamp(defender.blockRate, 0, CAPS.blockRate);
  if (blocked) damage *= 1 - clamp(defender.blockEffect, 0, CAPS.blockEffect) / 100;

  damage *= 1 - clamp(defender.damageReduction, 0, CAPS.damageReduction) / 100;

  return {
    hit: true,
    crit,
    blocked,
    hitChance: chance,
    critChance,
    damage: Math.max(1, Math.floor(damage)),
    mitigated,
  };
}

/** Damage that reaches HP after shields (owner-approved shield rule). */
export function applyShield(damage: number, shieldHp: number): {
  toShield: number;
  toHp: number;
  shieldRemaining: number;
} {
  const safeDamage = Math.max(0, Math.floor(damage));
  const safeShield = Math.max(0, Math.floor(shieldHp));
  const toShield = Math.min(safeDamage, safeShield);
  return {
    toShield,
    toHp: safeDamage - toShield,
    shieldRemaining: safeShield - toShield,
  };
}

/** Lifesteal is calculated on HP damage, never on shield-absorbed damage. */
export function lifestealAmount(hpDamage: number, lifestealPercent: number): number {
  return Math.floor(Math.max(0, hpDamage) * clamp(lifestealPercent, 0, CAPS.lifesteal) / 100);
}

/** Status duration after Tenacity (capped at 70%). */
export function statusDuration(baseSeconds: number, tenacity: number): number {
  const reduction = clamp(tenacity, 0, CAPS.tenacity) / 100;
  return Math.max(0, baseSeconds * (1 - reduction));
}

/** Mage spell damage multiplier from affinity (0.8x ... 1.5x). */
export const elementMultiplierFor = affinityMultiplier;

export const ELEMENT_LABELS: Record<DamageElement, string> = {
  FIRE: 'Hỏa',
  WATER: 'Thủy',
  WIND: 'Phong',
  EARTH: 'Thổ',
  LIGHT: 'Quang',
  DARK: 'Ám',
  LIGHTNING: 'Lôi',
};
