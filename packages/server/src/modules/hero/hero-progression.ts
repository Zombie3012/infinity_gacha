/**
 * Combat v2 — Hero progression helpers (pure, no database access).
 *
 * A Hero stores its level-1 rolled stats (`originStats`) plus its training
 * allocation. Current base stats are always recomputed from:
 *   origin + automatic class growth + growth compensation + training
 * so class changes can be applied retroactively without losing the roll.
 */

import {
  computeHeroBaseStats, deriveStats, eligibleClasses, trainingPointsForLevel,
  type BaseStats, type DerivedStats, type HeroClass, type StarRating,
} from '@infiniti-gacha/shared';

export const CLASS_CHANGE_LEVEL = 20;
export const CLASS_CHANGE_SILVER = 50_000;
export const CLASS_CHANGE_ITEM = 'CLASS_CHANGE_TOKEN';
export const MAX_STAT_SHARE_OF_BUDGET = 0.6;
export const TRAINABLE_CLASSES: HeroClass[] = ['WARRIOR', 'THIEF', 'SPEARMAN', 'ARCHER', 'MAGE'];

export class ProgressionError extends Error {
  constructor(message: string, readonly statusCode = 409) {
    super(message);
    this.name = 'ProgressionError';
  }
}

export interface ProgressionSnapshot {
  base: BaseStats;
  derived: DerivedStats;
  hp: number;
  maxHp: number;
  mp: number;
  maxMp: number;
  attack: number;
  defense: number;
  speed: number;
  training: BaseStats;
  trainingRemaining: number;
}

export function originOf(value: Partial<BaseStats> | null | undefined): BaseStats {
  return {
    str: Math.max(0, Math.round(value?.str ?? 0)),
    int: Math.max(0, Math.round(value?.int ?? 0)),
    sta: Math.max(0, Math.round(value?.sta ?? 0)),
    agi: Math.max(0, Math.round(value?.agi ?? 0)),
  };
}

export function trainingOf(value: Partial<BaseStats> | null | undefined): BaseStats {
  return originOf(value);
}

export function isV2Origin(origin: Partial<BaseStats> | null | undefined): boolean {
  const value = originOf(origin);
  return value.str + value.int + value.sta + value.agi > 0;
}

export function trainingTotal(training: Partial<BaseStats>): number {
  return (training.str ?? 0) + (training.int ?? 0) + (training.sta ?? 0) + (training.agi ?? 0);
}

export function trainingRemaining(level: number, training: Partial<BaseStats>): number {
  return Math.max(0, trainingPointsForLevel(level) - trainingTotal(training));
}

/** Recomputes all persisted v2 stats for a level/class/training combination. */
export function progressionFor(input: {
  origin: Partial<BaseStats>;
  star: StarRating;
  level: number;
  classCode: HeroClass;
  training?: Partial<BaseStats> | null;
  hpPct?: number;
  mpPct?: number;
  /** Each awakening rank permanently grants +10 to every base stat. */
  awakeningRank?: number;
}): ProgressionSnapshot {
  const training = trainingOf(input.training);
  const origin = originOf(input.origin);
  const awakeningBonus = 10 * Math.max(0, Math.floor(input.awakeningRank ?? 0));
  const base = computeHeroBaseStats({
    templateBase: {
      str: origin.str + awakeningBonus, int: origin.int + awakeningBonus,
      sta: origin.sta + awakeningBonus, agi: origin.agi + awakeningBonus,
    },
    star: input.star,
    level: input.level,
    heroClass: input.classCode,
    training,
  });
  const derived = deriveStats(base, input.classCode);
  const hpPct = Math.max(0, Math.min(1, input.hpPct ?? 1));
  const mpPct = Math.max(0, Math.min(1, input.mpPct ?? 1));

  return {
    base,
    derived,
    maxHp: derived.maxHp,
    hp: Math.max(0, Math.min(derived.maxHp, Math.round(derived.maxHp * hpPct))),
    maxMp: derived.maxMp,
    mp: Math.max(0, Math.min(derived.maxMp, Math.round(derived.maxMp * mpPct))),
    attack: derived.atk,
    defense: derived.def,
    // Legacy turn order still reads speed; derived from AGI until the v2 engine ships.
    speed: Math.round(60 + base.agi),
    training,
    trainingRemaining: trainingRemaining(input.level, training),
  };
}

/** Spends training points on one stat, respecting the 60% per-stat ceiling. */
export function allocateTraining(input: {
  origin: Partial<BaseStats>;
  star: StarRating;
  level: number;
  classCode: HeroClass;
  training?: Partial<BaseStats> | null;
  stat: string;
  points: number;
  hpPct?: number;
  mpPct?: number;
}): { snapshot: ProgressionSnapshot; training: BaseStats } {
  const stat = input.stat as keyof BaseStats;
  if (!['str', 'int', 'sta', 'agi'].includes(stat)) {
    throw new ProgressionError('ERR_HERO_STAT_INVALID', 400);
  }
  const points = Math.floor(input.points);
  if (!Number.isFinite(points) || points < 1) throw new ProgressionError('ERR_HERO_TRAINING_POINTS_INVALID', 400);

  const current = trainingOf(input.training);
  const remaining = trainingRemaining(input.level, current);
  if (points > remaining) throw new ProgressionError('ERR_HERO_NO_TRAINING_POINTS', 409);

  const next: BaseStats = { ...current, [stat]: current[stat] + points };
  const snapshot = progressionFor({
    origin: input.origin,
    star: input.star,
    level: input.level,
    classCode: input.classCode,
    training: next,
    hpPct: input.hpPct,
    mpPct: input.mpPct,
  });

  const total = snapshot.base.str + snapshot.base.int + snapshot.base.sta + snapshot.base.agi;
  if (snapshot.base[stat] > total * MAX_STAT_SHARE_OF_BUDGET) {
    throw new ProgressionError('ERR_HERO_STAT_CAP', 409);
  }

  return { snapshot, training: next };
}

/** Class change conditions (owner decision: resources + items + stats). */
export function classChangeCheck(input: {
  level: number;
  star: StarRating;
  base: BaseStats;
  currentClass: HeroClass;
  targetClass: string;
  silver: bigint | number;
  itemQuantity: number;
}): { ok: boolean; reason?: string } {
  if (!TRAINABLE_CLASSES.includes(input.targetClass as HeroClass)) {
    return { ok: false, reason: 'ERR_CLASS_INVALID' };
  }
  if (input.targetClass === input.currentClass) return { ok: false, reason: 'ERR_CLASS_SAME' };
  if (input.level < CLASS_CHANGE_LEVEL) return { ok: false, reason: 'ERR_CLASS_LEVEL_REQUIRED' };
  if (!eligibleClasses(input.base, input.level, input.star).includes(input.targetClass as HeroClass)) {
    return { ok: false, reason: 'ERR_CLASS_NOT_ELIGIBLE' };
  }
  if (Number(input.silver) < CLASS_CHANGE_SILVER) {
    return { ok: false, reason: 'ERR_CLASS_INSUFFICIENT_SILVER' };
  }
  if (input.itemQuantity < 1) return { ok: false, reason: 'ERR_CLASS_ITEM_REQUIRED' };
  return { ok: true };
}
