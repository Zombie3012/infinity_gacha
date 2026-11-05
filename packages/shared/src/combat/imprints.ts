/**
 * Combat v2 — imprint abilities (shared, pure functions).
 *
 * An imprint definition carries its combat Hook in `ability_code` plus a JSON
 * `ability_params` blob. The three rank levels scale the numeric magnitudes
 * (1x / 2x / 3x) so designers can keep a single definition row per imprint.
 *
 * Every effect is optional: an imprint without an ability code only contributes
 * the flat stat bonuses that are already stored on the definition row.
 */

import { CAPS, clamp } from './stats.js';

export type ImprintAbilityCode =
  | 'LOW_HP_EMPOWER'
  | 'PHOENIX_REVIVE'
  | 'CC_RESISTANCE'
  | 'CRIT_EVASION'
  | 'ARCANE_EMPOWER'
  | 'ACCURACY_EMPOWER';

export const IMPRINT_ABILITY_CODES: readonly ImprintAbilityCode[] = [
  'LOW_HP_EMPOWER',
  'PHOENIX_REVIVE',
  'CC_RESISTANCE',
  'CRIT_EVASION',
  'ARCANE_EMPOWER',
  'ACCURACY_EMPOWER',
];

export function isImprintAbilityCode(value: unknown): value is ImprintAbilityCode {
  return typeof value === 'string' && (IMPRINT_ABILITY_CODES as readonly string[]).includes(value);
}

/** Raw parameters read from `imprint_definitions.ability_params`. */
export interface ImprintAbilityParams {
  /** LOW_HP_EMPOWER / PHOENIX_REVIVE trigger, % of MaxHP (default 30). */
  hpThresholdPct?: number;
  /** LOW_HP_EMPOWER: extra final damage while below the threshold, in %. */
  damageBonus?: number;
  /** LOW_HP_EMPOWER: extra Tenacity while below the threshold, in %. */
  tenacity?: number;
  /** PHOENIX_REVIVE: % of MaxHP restored when the revive triggers. */
  hpPct?: number;
  /** PHOENIX_REVIVE: revives per battle (default 1, never scaled by rank). */
  times?: number;
  /** CRIT_EVASION: flat percentage points. */
  critRate?: number;
  evasion?: number;
  /** ARCANE_EMPOWER: MATK bonus in % and MP restored per round in % of MaxMP. */
  matkPercent?: number;
  mpRegenPct?: number;
  /** ACCURACY_EMPOWER: ATK bonus in % and flat accuracy points. */
  atkPercent?: number;
  accuracy?: number;
}

/** One owned imprint as stored in `hero_imprints` + its definition. */
export interface ImprintAbilityRow {
  abilityCode?: string | null;
  abilityParams?: Record<string, unknown> | null;
  rankLevel?: number;
}

/** Aggregated, engine-ready effect bundle for a single Hero. */
export interface ImprintCombatEffects {
  critRate: number;
  evasion: number;
  accuracy: number;
  atkPercent: number;
  matkPercent: number;
  /** % of MaxMP restored at the end of every round. */
  mpRegenPct: number;
  /** Added to Tenacity, which `statusDuration()` uses for crowd control. */
  tenacity: number;
  lowHp: { hpThresholdPct: number; damageBonus: number; tenacity: number } | null;
  revive: { hpPct: number; times: number } | null;
}

export const EMPTY_IMPRINT_EFFECTS: ImprintCombatEffects = {
  critRate: 0,
  evasion: 0,
  accuracy: 0,
  atkPercent: 0,
  matkPercent: 0,
  mpRegenPct: 0,
  tenacity: 0,
  lowHp: null,
  revive: null,
};

/** Rank level 1-3; anything else is clamped into that range. */
export function imprintAbilityScale(rankLevel?: number): number {
  return clamp(Math.round(rankLevel ?? 1), 1, 3);
}

function num(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Folds every owned imprint into one effect bundle.
 *
 * The bundle is cumulative: two imprints that both raise crit simply add up,
 * and the shared stat caps are applied once at the end.
 */
export function combineImprintEffects(rows: readonly ImprintAbilityRow[]): ImprintCombatEffects {
  const effects: ImprintCombatEffects = {
    ...EMPTY_IMPRINT_EFFECTS,
    lowHp: null,
    revive: null,
  };
  let lowHpDamageBonus = 0;
  let lowHpTenacity = 0;
  let lowHpThreshold = 0;
  let reviveTimes = 0;
  let reviveHpPct = 0;

  for (const row of rows) {
    if (!isImprintAbilityCode(row.abilityCode)) continue;
    const params = (row.abilityParams ?? {}) as ImprintAbilityParams;
    const scale = imprintAbilityScale(row.rankLevel);

    switch (row.abilityCode) {
      case 'LOW_HP_EMPOWER': {
        lowHpThreshold = Math.max(lowHpThreshold, clamp(num(params.hpThresholdPct, 30), 1, 100));
        lowHpDamageBonus += clamp(num(params.damageBonus, 20), 0, 200) * scale;
        lowHpTenacity += clamp(num(params.tenacity, 10), 0, 100) * scale;
        break;
      }
      case 'PHOENIX_REVIVE': {
        reviveTimes = Math.max(reviveTimes, clamp(Math.round(num(params.times, 1)), 1, 3));
        reviveHpPct = Math.max(reviveHpPct, clamp(num(params.hpPct, 30), 1, 100) * scale);
        break;
      }
      case 'CC_RESISTANCE':
        effects.tenacity += clamp(num(params.tenacity, 10), 0, 100) * scale;
        break;
      case 'CRIT_EVASION':
        effects.critRate += clamp(num(params.critRate, 5), 0, 100) * scale;
        effects.evasion += clamp(num(params.evasion, 5), 0, 100) * scale;
        break;
      case 'ARCANE_EMPOWER':
        effects.matkPercent += clamp(num(params.matkPercent, 10), 0, 200) * scale;
        effects.mpRegenPct += clamp(num(params.mpRegenPct, 5), 0, 100) * scale;
        break;
      case 'ACCURACY_EMPOWER':
        effects.atkPercent += clamp(num(params.atkPercent, 8), 0, 200) * scale;
        effects.accuracy += clamp(num(params.accuracy, 5), 0, 100) * scale;
        break;
      default:
        break;
    }
  }

  effects.critRate = clamp(effects.critRate, 0, CAPS.critRate);
  effects.evasion = clamp(effects.evasion, 0, CAPS.evasion);
  effects.tenacity = clamp(effects.tenacity, 0, CAPS.tenacity);
  effects.atkPercent = clamp(effects.atkPercent, 0, 300);
  effects.matkPercent = clamp(effects.matkPercent, 0, 300);
  effects.mpRegenPct = clamp(effects.mpRegenPct, 0, 100);
  effects.accuracy = clamp(effects.accuracy, 0, 200);

  if (lowHpThreshold > 0 && (lowHpDamageBonus > 0 || lowHpTenacity > 0)) {
    effects.lowHp = {
      hpThresholdPct: lowHpThreshold,
      damageBonus: lowHpDamageBonus,
      tenacity: clamp(lowHpTenacity, 0, CAPS.tenacity),
    };
  }
  if (reviveTimes > 0) {
    effects.revive = { hpPct: clamp(reviveHpPct, 1, 100), times: reviveTimes };
  }

  return effects;
}

/** True when the bundle changes nothing (lets callers skip attaching it). */
export function isEmptyImprintEffects(effects: ImprintCombatEffects): boolean {
  return effects.critRate === 0
    && effects.evasion === 0
    && effects.accuracy === 0
    && effects.atkPercent === 0
    && effects.matkPercent === 0
    && effects.mpRegenPct === 0
    && effects.tenacity === 0
    && effects.lowHp === null
    && effects.revive === null;
}
