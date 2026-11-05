/**
 * Combat v2 — Hero generation (pure).
 *
 * A summoned Hero receives:
 *   - four base stats rolled from the rarity budget and the template archetype
 *   - a class roll (Unclassified for 1-2 star, weighted for 3+ star)
 *   - a Mage-only element affinity table
 *   - derived stats calculated from the four base stats
 *
 * 6-7 star Heroes can be generated for future content but the caller must gate
 * them with `isStarEnabled`; this function does not block data generation.
 */

import {
  deriveStats, isStarEnabled, rollBaseStats, rollElementAffinity, rollSummonClass,
  type BannerKind, type BaseStats, type DerivedOffsets, type DerivedStats,
  type ElementAffinity, type HeroClass, type StarRating,
} from './stats.js';

export type CombatRole = 'TANK' | 'PHYSICAL_DPS' | 'MAGIC_DPS' | 'ASSASSIN' | 'SUPPORT';

export interface GeneratedHero {
  star: StarRating;
  base: BaseStats;
  derived: DerivedStats;
  heroClass: HeroClass;
  combatRole: CombatRole;
  elementAffinity: ElementAffinity | null;
  playable: boolean;
}

export interface GenerateHeroInput {
  star: StarRating;
  bannerKind?: BannerKind;
  archetypeWeights?: Partial<BaseStats>;
  classOptions?: string[] | null;
  combatRole?: CombatRole;
  offsets?: DerivedOffsets;
  random?: () => number;
}

export function roleForClass(heroClass: HeroClass): CombatRole {
  switch (heroClass) {
    case 'WARRIOR':
      return 'PHYSICAL_DPS';
    case 'THIEF':
      return 'ASSASSIN';
    case 'SPEARMAN':
      return 'PHYSICAL_DPS';
    case 'ARCHER':
      return 'PHYSICAL_DPS';
    case 'MAGE':
      return 'MAGIC_DPS';
    default:
      return 'PHYSICAL_DPS';
  }
}

const DEFAULT_WEIGHTS: BaseStats = { str: 0.25, int: 0.25, sta: 0.25, agi: 0.25 };

export function generateHero(input: GenerateHeroInput): GeneratedHero {
  const random = input.random ?? Math.random;
  const bannerKind = input.bannerKind ?? 'STANDARD';
  const classOptions = input.classOptions && input.classOptions.length > 0
    ? input.classOptions as HeroClass[]
    : undefined;

  // Keep a stable RNG order: class, base stats, affinity.
  const heroClass = rollSummonClass(input.star, bannerKind, random, classOptions);
  const base = rollBaseStats(input.star, input.archetypeWeights ?? DEFAULT_WEIGHTS, random);
  const elementAffinity = heroClass === 'MAGE' ? rollElementAffinity(random) : null;
  const derived = deriveStats(base, heroClass, input.offsets ?? {});

  return {
    star: input.star,
    base,
    derived,
    heroClass,
    combatRole: input.combatRole ?? roleForClass(heroClass),
    elementAffinity,
    playable: isStarEnabled(input.star),
  };
}
