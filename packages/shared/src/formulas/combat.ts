/**
 * Standard damage calculation formula with defense mitigation.
 * Damage = Math.max(1, Math.floor(attack * (100 / (100 + defense)) * critMultiplier))
 */
export function calculateDamage(
  attack: number,
  defense: number,
  isCritical: boolean = false,
  critDamageBonus: number = 0.5 // +50% default base crit damage -> 1.5x total
): { damage: number; isCritical: boolean } {
  const effectiveDefense = Math.max(0, defense);
  const mitigationMultiplier = 100 / (100 + effectiveDefense);
  const critMultiplier = isCritical ? 1.0 + critDamageBonus : 1.0;

  const rawDamage = attack * mitigationMultiplier * critMultiplier;
  const finalDamage = Math.max(1, Math.floor(rawDamage));

  return {
    damage: finalDamage,
    isCritical,
  };
}

/**
 * Calculates Euclidean march ETA in seconds between two points on the world grid.
 */
export function calculateMarchETASeconds(
  originX: number,
  originY: number,
  targetX: number,
  targetY: number,
  secondsPerTile: number = 30,
  speedMultiplier: number = 1.0
): number {
  const dx = targetX - originX;
  const dy = targetY - originY;
  const distance = Math.sqrt(dx * dx + dy * dy);

  const duration = (distance * secondsPerTile) / Math.max(0.1, speedMultiplier);
  return Math.ceil(duration);
}

export type CombatElement = 'FIRE' | 'WATER' | 'WIND' | 'EARTH' | 'LIGHT' | 'DARK' | 'LIGHTNING' | 'NEUTRAL';

/**
 * Calculates elemental advantage multiplier.
 * FIRE > WIND > EARTH > WATER > FIRE (1.25x advantage, 0.8x disadvantage)
 * LIGHTNING > WATER (1.25x), EARTH > LIGHTNING (1.25x)
 * LIGHT <-> DARK (mutual advantage 1.25x)
 */
export function calculateElementMultiplier(attackerElement?: string, defenderElement?: string): number {
  if (!attackerElement || !defenderElement) return 1.0;
  const a = attackerElement.toUpperCase();
  const d = defenderElement.toUpperCase();
  if (a === d) return 1.0;

  // Elemental cycle: FIRE > WIND > EARTH > WATER > FIRE
  if (a === 'FIRE' && d === 'WIND') return 1.25;
  if (a === 'WIND' && d === 'EARTH') return 1.25;
  if (a === 'EARTH' && d === 'WATER') return 1.25;
  if (a === 'WATER' && d === 'FIRE') return 1.25;

  // Reverse disadvantage
  if (a === 'WIND' && d === 'FIRE') return 0.8;
  if (a === 'EARTH' && d === 'WIND') return 0.8;
  if (a === 'WATER' && d === 'EARTH') return 0.8;
  if (a === 'FIRE' && d === 'WATER') return 0.8;

  // Lightning interactions
  if (a === 'LIGHTNING' && d === 'WATER') return 1.25;
  if (a === 'WATER' && d === 'LIGHTNING') return 0.8;
  if (a === 'LIGHTNING' && d === 'EARTH') return 0.8;
  if (a === 'EARTH' && d === 'LIGHTNING') return 1.25;

  // Light & Dark (mutual advantage)
  if ((a === 'LIGHT' && d === 'DARK') || (a === 'DARK' && d === 'LIGHT')) return 1.25;

  return 1.0;
}
