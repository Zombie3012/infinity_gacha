/**
 * Combat v2 generation adapter for the server.
 *
 * Turns a Hero template row into the persisted Hero shape. Until the Combat v2
 * engine replaces the legacy one, the four base stats are stored next to the
 * legacy HP/ATK/DEF/SPD columns, which are mirrored from the derived values so
 * existing combat, PvP and leaderboard code keeps working.
 */

import {
  generateHero, isStarEnabled,
  type BaseStats, type CombatRole, type DerivedStats, type ElementAffinity,
  type HeroClass, type StarRating,
} from '@infiniti-gacha/shared';

export const HERO_STAR_LOCKED = 'ERR_HERO_STAR_LOCKED';

export interface HeroTemplateLike {
  code: string;
  defaultRarity: number;
  heroClass: string;
  archetypeWeights?: { str: number; int: number; sta: number; agi: number } | null;
  classOptions?: string[] | null;
  combatRole?: string | null;
}

/** Legacy class taxonomy still used by the P0 combat/skill tables. */
export function legacyClassFor(heroClass: HeroClass): string {
  switch (heroClass) {
    case 'THIEF':
      return 'ASSASSIN';
    case 'SPEARMAN':
      return 'WARRIOR';
    case 'UNCLASSIFIED':
      return 'UNCLASSIFIED';
    default:
      return heroClass;
  }
}

function normalizedBannerKind(bannerType: string): 'STANDARD' | 'SPECIAL' | 'LIMITED' {
  if (bannerType === 'SPECIAL') return 'SPECIAL';
  if (bannerType === 'LIMITED') return 'LIMITED';
  return 'STANDARD';
}

export interface SummonedHeroBuild {
  star: StarRating;
  base: BaseStats;
  derived: DerivedStats;
  heroClass: HeroClass;
  classCode: HeroClass;
  combatRole: CombatRole;
  elementAffinity: ElementAffinity | null;
  legacyClass: string;
  legacySpeed: number;
}

export function buildSummonedHero(input: {
  template: HeroTemplateLike;
  bannerKind?: string;
  random?: () => number;
}): SummonedHeroBuild {
  const star = Math.max(1, Math.min(7, Math.floor(input.template.defaultRarity))) as StarRating;
  if (!isStarEnabled(star)) throw new Error(HERO_STAR_LOCKED);

  const generated = generateHero({
    star,
    bannerKind: normalizedBannerKind(input.bannerKind ?? 'STANDARD'),
    archetypeWeights: input.template.archetypeWeights ?? undefined,
    classOptions: input.template.classOptions ?? undefined,
    combatRole: (input.template.combatRole as CombatRole | null | undefined) ?? undefined,
    random: input.random,
  });

  return {
    star,
    base: generated.base,
    derived: generated.derived,
    heroClass: generated.heroClass,
    classCode: generated.heroClass,
    combatRole: generated.combatRole,
    elementAffinity: generated.elementAffinity,
    legacyClass: legacyClassFor(generated.heroClass),
    // Legacy turn order still reads `speed`; map it from AGI until the v2 engine ships.
    legacySpeed: Math.round(60 + generated.base.agi),
  };
}

export function affinityColumns(affinity: ElementAffinity) {
  return {
    fire: affinity.FIRE,
    water: affinity.WATER,
    wind: affinity.WIND,
    earth: affinity.EARTH,
    light: affinity.LIGHT,
    dark: affinity.DARK,
    lightning: affinity.LIGHTNING,
  };
}
