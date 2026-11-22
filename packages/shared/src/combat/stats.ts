/**
 * Combat v2 — stat system (shared, pure functions).
 *
 * Base stats: STR / INT / STA / AGI.
 * Everything else is derived at runtime from those four stats plus class,
 * equipment, skills, buffs and training. No derived stat is persisted.
 *
 * Growth model (owner decision 2026-11-05):
 *   Budget(L) = Budget(1) + 8 * (L - 1) + Compensation(L)
 *   Compensation(L) = (672 - Budget(1) - 392) * ((L - 1) / 49)^2
 * Rarities 1-5 reach 672 total stat points at level 50; 6-7 keep their higher base budgets.
 *
 * Speed was removed as a balance lever; turn order is AGI-based (one action
 * per unit per round), so no attack/cast/move speed stats exist here.
 */

export type BaseStatKey = 'str' | 'int' | 'sta' | 'agi';

export interface BaseStats {
  str: number;
  int: number;
  sta: number;
  agi: number;
}

export type StarRating = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type HeroClass = 'UNCLASSIFIED' | 'WARRIOR' | 'THIEF' | 'SPEARMAN' | 'ARCHER' | 'MAGE';

export type DamageElement = 'FIRE' | 'WATER' | 'WIND' | 'EARTH' | 'LIGHT' | 'DARK' | 'LIGHTNING';

export type BannerKind = 'STANDARD' | 'SPECIAL' | 'LIMITED';

export interface Caps {
  critRate: number;
  critDamage: number;
  evasion: number;
  blockRate: number;
  blockEffect: number;
  damageReduction: number;
  tenacity: number;
  lifesteal: number;
  armorPen: number;
  magicPen: number;
  hitChanceMin: number;
  hitChanceMax: number;
}

/** Owner decision: crit rate may reach 100%. */
export const CAPS: Caps = {
  critRate: 100,
  critDamage: 300,
  evasion: 75,
  blockRate: 75,
  blockEffect: 85,
  damageReduction: 70,
  tenacity: 70,
  lifesteal: 50,
  armorPen: 80,
  magicPen: 80,
  hitChanceMin: 5,
  hitChanceMax: 98,
};

export const BASE_STAT_KEYS: BaseStatKey[] = ['str', 'int', 'sta', 'agi'];

export const BASE_STAT_BUDGET: Record<StarRating, number> = {
  1: 100,
  2: 130,
  3: 170,
  4: 220,
  5: 280,
  6: 350,
  7: 430,
};

/** All Heroes and items use the same seven-star rarity scale. */
export const ENABLED_STARS: StarRating[] = [1, 2, 3, 4, 5, 6, 7];
export const LOCKED_STARS: StarRating[] = [];
export const MAX_HERO_LEVEL = 70;

/** Total stat points every rarity shares at level 50. */
export const TARGET_LEVEL = 50;
export const TARGET_BUDGET = 672;
/** 8 points per level = 5 automatic (class growth) + 3 training. */
export const GROWTH_PER_LEVEL = 8;
export const AUTO_GROWTH_PER_LEVEL = 5;
export const TRAINING_PER_LEVEL = 3;

/** Level-1 roll: 75% archetype weights + 25% wildcard, then ±15% noise. */
export const ROLL_WILDCARD_SHARE = 0.25;
export const ROLL_NOISE = 0.15;
export const ROLL_MIN_STAT = 8;
export const ROLL_MAX_SHARE = 0.45;

/** Class growth multipliers (owner-approved table). */
export const CLASS_GROWTH: Record<HeroClass, BaseStats> = {
  UNCLASSIFIED: { str: 1.0, int: 1.0, sta: 1.0, agi: 1.0 },
  WARRIOR: { str: 1.2, int: 0.7, sta: 1.15, agi: 0.9 },
  THIEF: { str: 0.95, int: 0.75, sta: 0.85, agi: 1.3 },
  SPEARMAN: { str: 1.2, int: 0.65, sta: 0.95, agi: 1.1 },
  ARCHER: { str: 0.95, int: 0.75, sta: 0.85, agi: 1.3 },
  MAGE: { str: 0.6, int: 1.35, sta: 0.85, agi: 0.95 },
};

/** Owner decision: Thief crits at 50%, every other class at 5%. */
export const CLASS_BASE_CRIT: Record<HeroClass, number> = {
  UNCLASSIFIED: 5,
  WARRIOR: 5,
  THIEF: 50,
  SPEARMAN: 5,
  ARCHER: 5,
  MAGE: 5,
};

/** Classed chance at summon; 1-2 star Heroes are always unclassified. */
export const SUMMON_CLASS_CHANCE: Record<StarRating, number> = {
  1: 0, 2: 0, 3: 0.4, 4: 0.7, 5: 1, 6: 1, 7: 1,
};

export const SUMMON_CLASS_WEIGHTS: { heroClass: HeroClass; weight: number }[] = [
  { heroClass: 'WARRIOR', weight: 35 },
  { heroClass: 'ARCHER', weight: 25 },
  { heroClass: 'THIEF', weight: 20 },
  { heroClass: 'SPEARMAN', weight: 15 },
  { heroClass: 'MAGE', weight: 5 },
];

export const MAGIC_ELEMENTS: DamageElement[] = ['FIRE', 'WATER', 'WIND', 'EARTH', 'LIGHT', 'DARK', 'LIGHTNING'];

export interface DerivedStats {
  maxHp: number;
  maxMp: number;
  atk: number;
  matk: number;
  def: number;
  mdef: number;
  hpRegen: number;
  mpRegen: number;
  critRate: number;
  critDamage: number;
  accuracy: number;
  evasion: number;
  blockRate: number;
  blockEffect: number;
  critResistance: number;
  critDamageReduction: number;
  damageReduction: number;
  tenacity: number;
  armorPen: number;
  magicPen: number;
  damageBonus: number;
  lifesteal: number;
}

export interface DerivedOffsets {
  hpBase?: number;
  mpBase?: number;
  atkBase?: number;
  matkBase?: number;
  defBase?: number;
  mdefBase?: number;
  hpRegenBase?: number;
  mpRegenBase?: number;
  /** Flat AGI from equipment/buffs; affects crit, evasion and the ATK formula. */
  agi?: number;
  critRate?: number;
  critDamage?: number;
  accuracy?: number;
  evasion?: number;
  blockRate?: number;
  blockEffect?: number;
  critResistance?: number;
  critDamageReduction?: number;
  damageReduction?: number;
  tenacity?: number;
  armorPen?: number;
  magicPen?: number;
  damageBonus?: number;
  lifesteal?: number;
}

export interface ElementAffinity {
  FIRE: number;
  WATER: number;
  WIND: number;
  EARTH: number;
  LIGHT: number;
  DARK: number;
  LIGHTNING: number;
}

export interface HeroBaseInput {
  templateBase: BaseStats;
  star: StarRating;
  level: number;
  heroClass: HeroClass;
  /** Player-allocated training points; never redistributed on class change. */
  training?: Partial<BaseStats>;
}

export function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

export function zeroStats(): BaseStats {
  return { str: 0, int: 0, sta: 0, agi: 0 };
}

export function statTotal(stats: BaseStats): number {
  return stats.str + stats.int + stats.sta + stats.agi;
}

export function isStarRating(value: number): value is StarRating {
  return Number.isInteger(value) && value >= 1 && value <= 7;
}

export function isStarEnabled(star: StarRating): boolean {
  return ENABLED_STARS.includes(star);
}

/** Rounds each stat while keeping the integer total equal to `total`. */
export function apportion(total: number, exact: readonly number[]): number[] {
  const target = Math.max(0, Math.round(total));
  const floors = exact.map(value => Math.max(0, Math.floor(value)));
  let remainder = target - floors.reduce((sum, value) => sum + value, 0);
  const order = exact
    .map((value, index) => ({ index, fraction: value - Math.floor(value) }))
    .sort((a, b) => b.fraction - a.fraction);
  const result = [...floors];
  let cursor = 0;
  while (remainder > 0 && order.length > 0) {
    result[order[cursor % order.length].index] += 1;
    remainder -= 1;
    cursor += 1;
  }
  while (remainder < 0 && order.length > 0) {
    const index = order[cursor % order.length].index;
    if (result[index] > 0) {
      result[index] -= 1;
      remainder += 1;
    }
    cursor += 1;
    if (cursor > order.length * target) break;
  }
  return result;
}

function statsFromArray(values: readonly number[]): BaseStats {
  return { str: values[0], int: values[1], sta: values[2], agi: values[3] };
}

function normalizeWeights(weights: Partial<BaseStats>): BaseStats {
  const raw: BaseStats = {
    str: Math.max(0, Number(weights.str ?? 0)),
    int: Math.max(0, Number(weights.int ?? 0)),
    sta: Math.max(0, Number(weights.sta ?? 0)),
    agi: Math.max(0, Number(weights.agi ?? 0)),
  };
  const total = statTotal(raw);
  if (total <= 0) return { str: 0.25, int: 0.25, sta: 0.25, agi: 0.25 };
  return { str: raw.str / total, int: raw.int / total, sta: raw.sta / total, agi: raw.agi / total };
}

/**
 * Total stat points a rarity reaches at level 50. 1-5 star Heroes share the
 * 672-point target; 6-7 star Heroes keep the same per-level growth and simply
 * start (and finish) higher, so their L50 budget continues the star curve.
 */
export function targetBudgetAt50(star: StarRating): number {
  return Math.max(TARGET_BUDGET, BASE_STAT_BUDGET[star] + GROWTH_PER_LEVEL * (TARGET_LEVEL - 1));
}

/**
 * Growth compensation: lower rarities receive extra points while levelling so
 * rarities 1-5 reach the same 672-point budget at level 50.
 */
export function growthCompensation(star: StarRating, level: number): number {
  const safeLevel = clamp(Math.floor(level) || 1, 1, TARGET_LEVEL);
  const base = BASE_STAT_BUDGET[star];
  const compensationPool = Math.max(0, targetBudgetAt50(star) - base - GROWTH_PER_LEVEL * (TARGET_LEVEL - 1));
  const progress = (safeLevel - 1) / (TARGET_LEVEL - 1);
  return compensationPool * progress * progress;
}

/** Total stat points available at `level` (base + normal growth + compensation). */
export function budgetAtLevel(star: StarRating, level: number): number {
  const safeLevel = clamp(Math.floor(level) || 1, 1, MAX_HERO_LEVEL);
  return BASE_STAT_BUDGET[star] + GROWTH_PER_LEVEL * (safeLevel - 1) + growthCompensation(star, safeLevel);
}

/** Player-directed points earned by levelling to `level`. */
export function trainingPointsForLevel(level: number): number {
  const safeLevel = clamp(Math.floor(level) || 1, 1, MAX_HERO_LEVEL);
  return TRAINING_PER_LEVEL * (safeLevel - 1);
}

/** Automatic growth spread by class multipliers (largest-remainder rounding). */
export function classGrowthPoints(points: number, heroClass: HeroClass): BaseStats {
  const weights = normalizeWeights(CLASS_GROWTH[heroClass] ?? CLASS_GROWTH.UNCLASSIFIED);
  const total = Math.max(0, points);
  const exact = BASE_STAT_KEYS.map(key => total * weights[key]);
  return statsFromArray(apportion(Math.round(total), exact));
}

/**
 * Level-1 stat roll: template archetype weights mixed with a wildcard share so
 * unusual builds (a Thief-rolled Hero with high INT) can appear.
 */
export function rollBaseStats(
  star: StarRating,
  archetypeWeights: Partial<BaseStats>,
  random: () => number = Math.random,
): BaseStats {
  const budget = BASE_STAT_BUDGET[star];
  const weights = normalizeWeights(archetypeWeights);
  const raw = BASE_STAT_KEYS.map(key => {
    const mixed = (1 - ROLL_WILDCARD_SHARE) * weights[key] + ROLL_WILDCARD_SHARE / 4;
    const noise = 1 - ROLL_NOISE + 2 * ROLL_NOISE * random();
    return mixed * noise;
  });
  const rawTotal = raw.reduce((sum, value) => sum + value, 0) || 1;
  const min = ROLL_MIN_STAT;
  const max = budget * ROLL_MAX_SHARE;

  let floats = raw.map(value => (value / rawTotal) * budget);
  for (let iteration = 0; iteration < 12; iteration += 1) {
    floats = floats.map(value => clamp(value, min, max));
    const difference = budget - floats.reduce((sum, value) => sum + value, 0);
    if (Math.abs(difference) < 1e-9) break;
    const eligible = floats
      .map((value, index) => (value > min + 1e-9 && value < max - 1e-9 ? index : -1))
      .filter(index => index >= 0);
    if (eligible.length === 0) break;
    const share = difference / eligible.length;
    for (const index of eligible) floats[index] += share;
  }

  const rounded = apportion(budget, floats);
  // Keep the hard cap after rounding by moving points to the largest stat.
  const ceiling = Math.floor(max);
  for (let index = 0; index < rounded.length; index += 1) {
    while (rounded[index] > ceiling) {
      const receiver = rounded
        .map((value, position) => (position !== index && value < ceiling ? position : -1))
        .find(position => position >= 0);
      if (receiver === undefined) break;
      rounded[index] -= 1;
      rounded[receiver] += 1;
    }
  }
  return statsFromArray(rounded);
}

/** Base stats after levelling, class growth and training. */
export function computeHeroBaseStats(input: HeroBaseInput): BaseStats {
  const level = clamp(Math.floor(input.level) || 1, 1, MAX_HERO_LEVEL);
  const gainedLevels = level - 1;
  const compensation = Math.round(growthCompensation(input.star, level));
  const automatic = classGrowthPoints(AUTO_GROWTH_PER_LEVEL * gainedLevels + compensation, input.heroClass);
  const training = input.training ?? {};
  return {
    str: input.templateBase.str + automatic.str + Math.max(0, Math.round(training.str ?? 0)),
    int: input.templateBase.int + automatic.int + Math.max(0, Math.round(training.int ?? 0)),
    sta: input.templateBase.sta + automatic.sta + Math.max(0, Math.round(training.sta ?? 0)),
    agi: input.templateBase.agi + automatic.agi + Math.max(0, Math.round(training.agi ?? 0)),
  };
}

/**
 * Derived stats from the four base stats.
 * Offsets cover template baselines, equipment and temporary bonuses.
 */
export function deriveStats(
  base: BaseStats,
  heroClass: HeroClass = 'UNCLASSIFIED',
  offsets: DerivedOffsets = {},
): DerivedStats {
  const agi = Math.max(0, base.agi + (offsets.agi ?? 0));
  const critRate = (CLASS_BASE_CRIT[heroClass] ?? 5) + agi * 0.05 + (offsets.critRate ?? 0);
  return {
    maxHp: Math.round((offsets.hpBase ?? 0) + 20 * base.sta),
    maxMp: Math.round((offsets.mpBase ?? 0) + 10 * base.int),
    atk: Math.round((offsets.atkBase ?? 0) + 2.5 * base.str + 0.5 * agi),
    matk: Math.round((offsets.matkBase ?? 0) + 3.0 * base.int),
    def: Math.round((offsets.defBase ?? 0) + 0.5 * base.sta),
    mdef: Math.round((offsets.mdefBase ?? 0) + 0.5 * base.int),
    hpRegen: Math.round(((offsets.hpRegenBase ?? 0) + 0.1 * base.sta) * 10) / 10,
    mpRegen: Math.round(((offsets.mpRegenBase ?? 0) + 0.1 * base.int) * 10) / 10,
    critRate: Math.round(clamp(critRate, 0, CAPS.critRate) * 10) / 10,
    critDamage: Math.round(clamp(150 + (offsets.critDamage ?? 0), 0, CAPS.critDamage) * 10) / 10,
    accuracy: Math.round(clamp(offsets.accuracy ?? 0, 0, 100) * 10) / 10,
    evasion: Math.round(clamp(agi * 0.05 + (offsets.evasion ?? 0), 0, CAPS.evasion) * 10) / 10,
    blockRate: Math.round(clamp(offsets.blockRate ?? 0, 0, CAPS.blockRate) * 10) / 10,
    blockEffect: Math.round(clamp(offsets.blockEffect ?? 0, 0, CAPS.blockEffect) * 10) / 10,
    critResistance: Math.round(clamp(offsets.critResistance ?? 0, 0, 100) * 10) / 10,
    critDamageReduction: Math.round(clamp(offsets.critDamageReduction ?? 0, 0, 100) * 10) / 10,
    damageReduction: Math.round(clamp(offsets.damageReduction ?? 0, 0, CAPS.damageReduction) * 10) / 10,
    tenacity: Math.round(clamp(offsets.tenacity ?? 0, 0, CAPS.tenacity) * 10) / 10,
    armorPen: Math.round(clamp(offsets.armorPen ?? 0, 0, CAPS.armorPen) * 10) / 10,
    magicPen: Math.round(clamp(offsets.magicPen ?? 0, 0, CAPS.magicPen) * 10) / 10,
    damageBonus: Math.round((offsets.damageBonus ?? 0) * 10) / 10,
    lifesteal: Math.round(clamp(offsets.lifesteal ?? 0, 0, CAPS.lifesteal) * 10) / 10,
  };
}

/**
 * Combat Power v2: one comparable score across physical/magical/support builds.
 * ATK/MATK carry the most weight, then defences, HP and percentage stats.
 */
export function combatPowerV2(stats: DerivedStats): number {
  return Math.round(
    stats.atk * 2
    + stats.matk * 2
    + stats.def * 1.5
    + stats.mdef * 1.5
    + stats.maxHp / 8
    + stats.critRate * 6
    + stats.critDamage * 2
    + stats.evasion * 4
    + stats.blockRate * 4
    + stats.blockEffect * 2
    + stats.damageReduction * 8
    + stats.accuracy * 2,
  );
}

/**
 * Class qualification from stat distribution (owner-approved: class does not
 * lock skills, so a high-INT Thief can still cast Mage spells).
 * 1-2 star Heroes can never become Mages (Mage is gacha-only).
 */
export function eligibleClasses(base: BaseStats, level: number, star: StarRating): HeroClass[] {
  if (level < 20) return [];
  const total = statTotal(base) || 1;
  const shares = { str: base.str / total, int: base.int / total, sta: base.sta / total, agi: base.agi / total };
  const classes: HeroClass[] = [];
  if (shares.str >= 0.35) classes.push('WARRIOR');
  if (shares.agi >= 0.35) classes.push('THIEF');
  if (shares.str >= 0.25 && shares.agi >= 0.25) classes.push('SPEARMAN');
  if (shares.agi >= 0.3) classes.push('ARCHER');
  if (star >= 3 && shares.int >= 0.35) classes.push('MAGE');
  return classes;
}

/** Weighted class roll at summon, independent of summon payment method. */
export function rollSummonClass(
  star: StarRating,
  bannerKind: BannerKind = 'STANDARD',
  random: () => number = Math.random,
  options?: HeroClass[],
): HeroClass {
  if (SUMMON_CLASS_CHANCE[star] <= 0) return 'UNCLASSIFIED';
  if (random() >= SUMMON_CLASS_CHANCE[star]) return 'UNCLASSIFIED';

  const allowed = options && options.length > 0 ? new Set(options) : null;
  // Owner decision: Mage can appear on every banner, including STANDARD.
  // `bannerKind` is kept for future banner-specific modifiers.
  void bannerKind;
  const pool = SUMMON_CLASS_WEIGHTS
    .filter(entry => !allowed || allowed.has(entry.heroClass))
    .map(entry => ({ ...entry }));
  if (pool.length === 0) return 'UNCLASSIFIED';

  const total = pool.reduce((sum, entry) => sum + entry.weight, 0);
  let cursor = random() * total;
  for (const entry of pool) {
    cursor -= entry.weight;
    if (cursor <= 0) return entry.heroClass;
  }
  return pool[pool.length - 1].heroClass;
}

/** Element affinity is a Mage-only table. Primary 60-90, secondary 30-60. */
export function rollElementAffinity(random: () => number = Math.random): ElementAffinity {
  const indexes = MAGIC_ELEMENTS.map((_, index) => index);
  const primaryIndex = Math.floor(random() * indexes.length) % indexes.length;
  const primary = clamp(60 + Math.round(30 * random()), 60, 90);

  const secondaryPool = indexes.filter(index => index !== primaryIndex);
  const secondaryIndex = secondaryPool[Math.floor(random() * secondaryPool.length) % secondaryPool.length];
  const secondary = clamp(30 + Math.round(30 * random()), 30, 60);

  const affinity = {} as ElementAffinity;
  for (const element of MAGIC_ELEMENTS) {
    affinity[element] = clamp(Math.round(25 * random()), 0, 25);
  }
  affinity[MAGIC_ELEMENTS[primaryIndex]] = primary;
  affinity[MAGIC_ELEMENTS[secondaryIndex]] = secondary;
  return affinity;
}

/** Mage affinity damage multiplier (owner-approved table). */
export function affinityMultiplier(affinity: number): number {
  if (affinity >= 80) return 1.5;
  if (affinity >= 60) return 1.3;
  if (affinity >= 40) return 1.15;
  if (affinity >= 20) return 1.0;
  return 0.8;
}

/** Deterministic RNG so battle replays and stat rolls stay stable. */
export function mulberry32(seed: number): () => number {
  let state = seed >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let value = state;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}
