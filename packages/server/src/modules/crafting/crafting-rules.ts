/**
 * Domain 10 (P1) crafting rules: material validation, enhancement and fusion.
 *
 * Sample tuning:
 * - crafting consumes the recipe materials plus Silver and requires the Forge
 *   building at (or above) the recipe's required level
 * - enhancement costs `level + 1` stones and 500 × (level + 1) Silver, and adds
 *   +10% of the template base stats per level
 * - fusion consumes three identical instances (same template and star) and
 *   produces one at the next star with base stats × 1.3
 */

export interface MaterialRequirement {
  itemId: string;
  quantity: number;
}

export interface CraftValidationInput {
  requiredMaterials: readonly MaterialRequirement[];
  owned: Record<string, number>;
  requiredSilver: number;
  silver: number;
  requiredForgeLevel: number;
  forgeLevel: number;
}

export interface CraftValidation {
  ok: boolean;
  missingMaterials: MaterialRequirement[];
  missingSilver: number;
  forgeLevelShort: number;
  reason?: 'ERR_CRAFT_MISSING_MATERIALS' | 'ERR_CRAFT_MISSING_SILVER' | 'ERR_CRAFT_FORGE_LEVEL';
}

export function validateCraft(input: CraftValidationInput): CraftValidation {
  const missingMaterials = input.requiredMaterials
    .map(row => ({ itemId: row.itemId, quantity: Math.max(0, row.quantity - (input.owned[row.itemId] ?? 0)) }))
    .filter(row => row.quantity > 0);
  const missingSilver = Math.max(0, input.requiredSilver - input.silver);
  const forgeLevelShort = Math.max(0, input.requiredForgeLevel - input.forgeLevel);

  if (missingMaterials.length > 0) {
    return { ok: false, missingMaterials, missingSilver, forgeLevelShort, reason: 'ERR_CRAFT_MISSING_MATERIALS' };
  }
  if (missingSilver > 0) {
    return { ok: false, missingMaterials: [], missingSilver, forgeLevelShort, reason: 'ERR_CRAFT_MISSING_SILVER' };
  }
  if (forgeLevelShort > 0) {
    return { ok: false, missingMaterials: [], missingSilver: 0, forgeLevelShort, reason: 'ERR_CRAFT_FORGE_LEVEL' };
  }
  return { ok: true, missingMaterials: [], missingSilver: 0, forgeLevelShort: 0 };
}

export function enhanceCost(currentLevel: number): { stones: number; silver: number } {
  const level = Math.max(0, Math.floor(currentLevel));
  return { stones: level + 1, silver: 500 * (level + 1) };
}

export function enhanceMultiplier(currentLevel: number): number {
  return Math.round((1 + 0.1 * Math.max(0, Math.floor(currentLevel))) * 100) / 100;
}

export function fusionMultiplierForStar(starLevel: number): number {
  return Math.round(Math.pow(1.3, Math.max(1, Math.floor(starLevel)) - 1) * 100) / 100;
}

/** Star growth and enhancement stack; enhancement must never overwrite fusion. */
export function effectiveMultiplier(starLevel: number, enhanceLevel: number): number {
  const star = fusionMultiplierForStar(starLevel);
  const enhance = 1 + 0.1 * Math.max(0, Math.floor(enhanceLevel));
  return Math.round(star * enhance * 100) / 100;
}

export function fusionRequirement(): number {
  return 3;
}

/** Crafted gear rolls a small, deterministic substat bonus inside recipe brackets. */
export function rollSubstats(seed: string, rarity: number): { hp: number; attack: number; defense: number; speed: number } {
  let hash = 2166136261;
  for (let index = 0; index < seed.length; index += 1) {
    hash ^= seed.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  const value = Math.abs(hash);
  const bracket = 1 + Math.max(1, Math.floor(rarity));
  return {
    hp: bracket * 2 + (value % 5),
    attack: bracket + (value % 3),
    defense: bracket + ((value >> 3) % 3),
    speed: (value >> 5) % 2,
  };
}

export function scaledBonus(base: number, statMultiplier: number, substat: number): number {
  return Math.round(base * Math.max(1, statMultiplier)) + Math.max(0, substat);
}
