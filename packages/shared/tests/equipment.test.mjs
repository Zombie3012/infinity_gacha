import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  aggregateEquipment,
  deriveStats,
} from '../dist/index.js';

test('Combat v2 - Equipment System', async (t) => {
  await t.test('aggregateEquipment combines base stats and derived offsets', () => {
    const items = [
      {
        slotType: 'MAIN_HAND',
        bonusAttack: 25,
        bonusStr: 10,
        v2Stats: { armorPen: 5, critRate: 4 },
        statMultiplier: 1.0,
      },
      {
        slotType: 'CHEST',
        bonusHp: 80,
        bonusDefense: 15,
        bonusSta: 12,
        v2Stats: { damageReduction: 4 },
        statMultiplier: 1.2, // e.g. enhanced or higher star
      },
      {
        slotType: 'ACCESSORY',
        bonusAgi: 8,
        v2Stats: { lifesteal: 6, evasion: 5 },
        substats: { critRate: 2, hp: 20 },
      },
    ];

    const aggregated = aggregateEquipment(items);

    // Base stats:
    // STR: 10
    // STA: 12 * 1.2 = 14
    // AGI: 8
    assert.equal(aggregated.baseStats.str, 10);
    assert.equal(aggregated.baseStats.sta, 14);
    assert.equal(aggregated.baseStats.agi, 8);
    assert.equal(aggregated.baseStats.int, 0);

    // Offsets:
    // ATK: 25
    // DEF: 15 * 1.2 = 18
    // HP: 80 * 1.2 + 20 = 116
    assert.equal(aggregated.derivedOffsets.atkBase, 25);
    assert.equal(aggregated.derivedOffsets.defBase, 18);
    assert.equal(aggregated.derivedOffsets.hpBase, 116);

    // Percent stats:
    assert.equal(aggregated.derivedOffsets.armorPen, 5);
    assert.equal(aggregated.derivedOffsets.critRate, 6); // 4 + 2
    assert.equal(aggregated.derivedOffsets.damageReduction, 4);
    assert.equal(aggregated.derivedOffsets.lifesteal, 6);
    assert.equal(aggregated.derivedOffsets.evasion, 5);
  });

  await t.test('deriveStats correctly incorporates equipment base and derived offsets', () => {
    const heroBase = { str: 40, int: 20, sta: 30, agi: 30 };
    const items = [
      {
        slotType: 'MAIN_HAND',
        bonusAttack: 30,
        bonusStr: 15,
        v2Stats: { critRate: 10, armorPen: 12 },
      },
    ];
    const { baseStats: equipBase, derivedOffsets: equipOffsets } = aggregateEquipment(items);

    const effectiveBase = {
      str: heroBase.str + equipBase.str,
      int: heroBase.int + equipBase.int,
      sta: heroBase.sta + equipBase.sta,
      agi: heroBase.agi + equipBase.agi,
    };

    const derived = deriveStats(effectiveBase, 'WARRIOR', equipOffsets);

    // STR is 55 (40 + 15)
    // ATK = 30 (atkBase) + 2.5 * 55 + 0.5 * 30 = 30 + 137.5 + 15 = 182.5 -> 183
    assert.equal(derived.atk, 183);

    // CritRate = classBase (5) + AGI * 0.05 (1.5) + equip (10) = 16.5
    assert.equal(derived.critRate, 16.5);
    assert.equal(derived.armorPen, 12);
  });
});
