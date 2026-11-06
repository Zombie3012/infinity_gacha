/**
 * Combat v2 — Equipment stat system (pure, shared functions).
 *
 * Equipment contributes:
 * 1. Base stats: STR, INT, STA, AGI (scaled by enhance/fusion multiplier).
 * 2. Derived stats & combat offsets: HP, MP, ATK, MATK, DEF, MDEF,
 *    CritRate, CritDamage, Accuracy, Evasion, BlockRate, BlockEffect,
 *    DamageReduction, Tenacity, ArmorPen, MagicPen, DamageBonus, Lifesteal,
 *    HPRegen, MPRegen.
 */

import {
  type BaseStats, type DerivedOffsets,
} from './stats.js';

export type EquipmentSlot = 'MAIN_HAND' | 'OFF_HAND' | 'CHEST' | 'HELMET' | 'BOOTS' | 'ACCESSORY';

export interface EquipmentV2Stats {
  str?: number;
  int?: number;
  sta?: number;
  agi?: number;
  hp?: number;
  mp?: number;
  atk?: number;
  matk?: number;
  def?: number;
  mdef?: number;
  critRate?: number;
  critDamage?: number;
  accuracy?: number;
  evasion?: number;
  blockRate?: number;
  blockEffect?: number;
  damageReduction?: number;
  tenacity?: number;
  armorPen?: number;
  magicPen?: number;
  damageBonus?: number;
  lifesteal?: number;
  hpRegen?: number;
  mpRegen?: number;
  [key: string]: number | undefined;
}

export interface EquipmentItemInput {
  slotType: string;
  bonusHp?: number;
  bonusAttack?: number;
  bonusDefense?: number;
  bonusSpeed?: number;
  bonusStr?: number;
  bonusInt?: number;
  bonusSta?: number;
  bonusAgi?: number;
  bonusMatk?: number;
  bonusMdef?: number;
  v2Stats?: Partial<EquipmentV2Stats> | null;
  statMultiplier?: number;
  substats?: Partial<EquipmentV2Stats> | null;
}

export interface AggregatedEquipmentStats {
  baseStats: BaseStats;
  derivedOffsets: DerivedOffsets;
}

/**
 * Aggregates a list of equipped items for a Hero into base stat bonuses and derived offsets.
 */
export function aggregateEquipment(items: readonly EquipmentItemInput[]): AggregatedEquipmentStats {
  const base: BaseStats = { str: 0, int: 0, sta: 0, agi: 0 };
  const offsets: DerivedOffsets = {
    hpBase: 0,
    mpBase: 0,
    atkBase: 0,
    matkBase: 0,
    defBase: 0,
    mdefBase: 0,
    hpRegenBase: 0,
    mpRegenBase: 0,
    agi: 0,
    critRate: 0,
    critDamage: 0,
    accuracy: 0,
    evasion: 0,
    blockRate: 0,
    blockEffect: 0,
    damageReduction: 0,
    tenacity: 0,
    armorPen: 0,
    magicPen: 0,
    damageBonus: 0,
    lifesteal: 0,
  };

  for (const item of items) {
    const mult = Math.max(1, item.statMultiplier ?? 1);
    const v2 = item.v2Stats ?? {};
    const sub = item.substats ?? {};

    // 1. Base stats (STR, INT, STA, AGI)
    const rawStr = (item.bonusStr ?? 0) + (v2.str ?? 0);
    const rawInt = (item.bonusInt ?? 0) + (v2.int ?? 0);
    const rawSta = (item.bonusSta ?? 0) + (v2.sta ?? 0);
    const rawAgi = (item.bonusAgi ?? 0) + (v2.agi ?? 0);

    base.str += Math.round(rawStr * mult) + (sub.str ?? 0);
    base.int += Math.round(rawInt * mult) + (sub.int ?? 0);
    base.sta += Math.round(rawSta * mult) + (sub.sta ?? 0);
    base.agi += Math.round(rawAgi * mult) + (sub.agi ?? 0);

    // Speed from legacy templates also adds to flat AGI
    if (item.bonusSpeed || sub.speed) {
      const spd = Math.round((item.bonusSpeed ?? 0) * mult) + (sub.speed ?? 0);
      offsets.agi = (offsets.agi ?? 0) + spd;
    }

    // 2. Flat Combat Offsets (HP, MP, ATK, MATK, DEF, MDEF)
    const rawHp = (item.bonusHp ?? 0) + (v2.hp ?? 0);
    const rawAtk = (item.bonusAttack ?? 0) + (v2.atk ?? 0);
    const rawMatk = (item.bonusMatk ?? 0) + (v2.matk ?? 0);
    const rawDef = (item.bonusDefense ?? 0) + (v2.def ?? 0);
    const rawMdef = (item.bonusMdef ?? 0) + (v2.mdef ?? 0);
    const rawMp = v2.mp ?? 0;

    offsets.hpBase = (offsets.hpBase ?? 0) + Math.round(rawHp * mult) + (sub.hp ?? 0);
    offsets.atkBase = (offsets.atkBase ?? 0) + Math.round(rawAtk * mult) + (sub.atk ?? sub.attack ?? 0);
    offsets.matkBase = (offsets.matkBase ?? 0) + Math.round(rawMatk * mult) + (sub.matk ?? 0);
    offsets.defBase = (offsets.defBase ?? 0) + Math.round(rawDef * mult) + (sub.def ?? sub.defense ?? 0);
    offsets.mdefBase = (offsets.mdefBase ?? 0) + Math.round(rawMdef * mult) + (sub.mdef ?? 0);
    offsets.mpBase = (offsets.mpBase ?? 0) + Math.round(rawMp * mult) + (sub.mp ?? 0);

    // 3. Percentage and Special Offsets (Crit, Evasion, Penetration, Block, DR, etc.)
    offsets.critRate = (offsets.critRate ?? 0) + (v2.critRate ?? 0) + (sub.critRate ?? 0);
    offsets.critDamage = (offsets.critDamage ?? 0) + (v2.critDamage ?? 0) + (sub.critDamage ?? 0);
    offsets.accuracy = (offsets.accuracy ?? 0) + (v2.accuracy ?? 0) + (sub.accuracy ?? 0);
    offsets.evasion = (offsets.evasion ?? 0) + (v2.evasion ?? 0) + (sub.evasion ?? 0);
    offsets.blockRate = (offsets.blockRate ?? 0) + (v2.blockRate ?? 0) + (sub.blockRate ?? 0);
    offsets.blockEffect = (offsets.blockEffect ?? 0) + (v2.blockEffect ?? 0) + (sub.blockEffect ?? 0);
    offsets.damageReduction = (offsets.damageReduction ?? 0) + (v2.damageReduction ?? 0) + (sub.damageReduction ?? 0);
    offsets.tenacity = (offsets.tenacity ?? 0) + (v2.tenacity ?? 0) + (sub.tenacity ?? 0);
    offsets.armorPen = (offsets.armorPen ?? 0) + (v2.armorPen ?? 0) + (sub.armorPen ?? 0);
    offsets.magicPen = (offsets.magicPen ?? 0) + (v2.magicPen ?? 0) + (sub.magicPen ?? 0);
    offsets.damageBonus = (offsets.damageBonus ?? 0) + (v2.damageBonus ?? 0) + (sub.damageBonus ?? 0);
    offsets.lifesteal = (offsets.lifesteal ?? 0) + (v2.lifesteal ?? 0) + (sub.lifesteal ?? 0);
    offsets.hpRegenBase = (offsets.hpRegenBase ?? 0) + (v2.hpRegen ?? 0) + (sub.hpRegen ?? 0);
    offsets.mpRegenBase = (offsets.mpRegenBase ?? 0) + (v2.mpRegen ?? 0) + (sub.mpRegen ?? 0);
  }

  return { baseStats: base, derivedOffsets: offsets };
}
