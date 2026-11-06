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

export const FANTASY_FIRST_NAMES: readonly string[] = [
  'Aaron', 'Jenna', 'Velkist', 'Eolka', 'Roderick', 'Catio', 'Nerissa', 'Kael',
  'Asher', 'Lyra', 'Vane', 'Freya', 'Cedric', 'Elira', 'Dorian', 'Sylas',
  'Mirella', 'Gareth', 'Orin', 'Thalia', 'Kieran', 'Seraphina', 'Rowan', 'Alaric',
  'Isolde', 'Lucian', 'Astrid', 'Viktor', 'Elena', 'Cassian', 'Valeria', 'Tristan',
  'Aria', 'Darius', 'Selene', 'Gideon', 'Maeve', 'Evander', 'Iris', 'Magnus',
  'Cora', 'Zephyr', 'Leif', 'Soren', 'Yvette', 'Bryn', 'Riven', 'Nadia',
  'Cain', 'Vera', 'Aldous', 'Reina', 'Stellan', 'Fiona', 'Callum', 'Tessa',
  'Oberon', 'Niamh', 'Malakai', 'Liora', 'Bastian', 'Sable', 'Torin', 'Vesper',
  'Eamon', 'Caelum', 'Nyx', 'Garrick', 'Aveline', 'Draven', 'Sorrel', 'Theron',
  'Kallisto', 'Elowen', 'Corvus', 'Halcyon', 'Fenris', 'Zarek', 'Miriam', 'Kaelen',
];

export const FANTASY_SURNAMES: readonly string[] = [
  'Thorne', 'Blackwood', 'Vael', 'Ashford', 'Mercer', 'Hale', 'Falk', 'Moreau',
  'Rook', 'Frost', 'Vale', 'Belmont', 'Crowe', 'Voss', 'Laurent', 'Ward',
  'Klein', 'Reid', 'Hart', 'Solis', 'Richter', 'Brandt', 'Sterling', 'Cross',
  'Lind', 'Nightingale', 'Ironwood', 'Grimshaw', 'Ravencrest', 'Stroud', 'Locke',
  'Varga', 'Hawke', 'Morrow', 'Crest', 'Dusk', 'Storm', 'Flint', 'Wren',
  'Bane', 'Holloway', 'Cinder', 'Gale', 'Winter', 'Stone', 'Vance', 'Lark', 'Briar',
];

export const PROCEDURAL_ARCHETYPES: readonly BaseStats[] = [
  { str: 0.42, int: 0.12, sta: 0.28, agi: 0.18 }, // Might / Vanguard
  { str: 0.26, int: 0.12, sta: 0.18, agi: 0.44 }, // Swift / Assassin
  { str: 0.12, int: 0.46, sta: 0.20, agi: 0.22 }, // Arcane / Scholar
  { str: 0.26, int: 0.14, sta: 0.44, agi: 0.16 }, // Bastion / Guardian
  { str: 0.34, int: 0.14, sta: 0.18, agi: 0.34 }, // Skirmisher / Duelist
  { str: 0.26, int: 0.34, sta: 0.18, agi: 0.22 }, // Spellblade / Mystic
  { str: 0.28, int: 0.16, sta: 0.18, agi: 0.38 }, // Ranger / Marksman
  { str: 0.25, int: 0.25, sta: 0.25, agi: 0.25 }, // Balanced / All-Rounder
];

export function generateFantasyHeroName(random: () => number = Math.random): string {
  const firstIdx = Math.floor(random() * FANTASY_FIRST_NAMES.length) % FANTASY_FIRST_NAMES.length;
  const firstName = FANTASY_FIRST_NAMES[firstIdx];
  if (random() < 0.55) {
    const lastIdx = Math.floor(random() * FANTASY_SURNAMES.length) % FANTASY_SURNAMES.length;
    const lastName = FANTASY_SURNAMES[lastIdx];
    if (lastName.toLowerCase() !== firstName.toLowerCase()) {
      return `${firstName} ${lastName}`;
    }
  }
  return firstName;
}

export function rollRandomArchetypeWeights(
  heroClass: HeroClass = 'UNCLASSIFIED',
  random: () => number = Math.random,
): BaseStats {
  if (heroClass === 'MAGE') {
    return { str: 0.12, int: 0.46, sta: 0.20, agi: 0.22 };
  }
  const idx = Math.floor(random() * PROCEDURAL_ARCHETYPES.length) % PROCEDURAL_ARCHETYPES.length;
  return PROCEDURAL_ARCHETYPES[idx];
}

export interface GeneratedHero {
  name: string;
  star: StarRating;
  base: BaseStats;
  derived: DerivedStats;
  heroClass: HeroClass;
  combatRole: CombatRole;
  elementAffinity: ElementAffinity | null;
  playable: boolean;
}

export interface GenerateHeroInput {
  name?: string;
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

export function generateHero(input: GenerateHeroInput): GeneratedHero {
  const random = input.random ?? Math.random;
  const bannerKind = input.bannerKind ?? 'STANDARD';
  const classOptions = input.classOptions && input.classOptions.length > 0
    ? input.classOptions as HeroClass[]
    : undefined;

  // Keep a stable RNG order: class, base stats, affinity, then fantasy name.
  const heroClass = rollSummonClass(input.star, bannerKind, random, classOptions);
  const weights = input.archetypeWeights ?? rollRandomArchetypeWeights(heroClass, random);
  const base = rollBaseStats(input.star, weights, random);
  const elementAffinity = heroClass === 'MAGE' ? rollElementAffinity(random) : null;
  const derived = deriveStats(base, heroClass, input.offsets ?? {});
  const name = input.name?.trim() ? input.name.trim() : generateFantasyHeroName(random);

  return {
    name,
    star: input.star,
    base,
    derived,
    heroClass,
    combatRole: input.combatRole ?? roleForClass(heroClass),
    elementAffinity,
    playable: isStarEnabled(input.star),
  };
}
