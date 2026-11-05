import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BASE_STAT_BUDGET, CAPS, affinityMultiplier, budgetAtLevel, classGrowthPoints,
  computeHeroBaseStats, deriveStats, eligibleClasses, growthCompensation, mulberry32,
  rollBaseStats, rollElementAffinity, rollSummonClass, trainingPointsForLevel, TARGET_BUDGET,
} from '../dist/combat/stats.js';
import {
  applyShield, elementMultiplierFor, finalCritMultiplier, hitChance, lifestealAmount,
  mitigatedDamage, resolveAttack, statusDuration,
} from '../dist/combat/damage.js';

const alwaysZero = () => 0;

test('Combat v2 - derived stats from STR/INT/STA/AGI', async (t) => {
  const base = { str: 100, int: 50, sta: 200, agi: 60 };
  const stats = deriveStats(base, 'WARRIOR');

  await t.test('survival and offensive formulas follow the spec', () => {
    assert.equal(stats.maxHp, 4_000);         // 20 * STA
    assert.equal(stats.maxMp, 500);           // 10 * INT
    assert.equal(stats.atk, 280);             // 2.5 * STR + 0.5 * AGI
    assert.equal(stats.matk, 150);            // 3 * INT
    assert.equal(stats.def, 100);             // 0.5 * STA
    assert.equal(stats.mdef, 25);             // 0.5 * INT
    assert.equal(stats.hpRegen, 20);          // 0.1 * STA
    assert.equal(stats.mpRegen, 5);           // 0.1 * INT
  });

  await t.test('crit rate is class base + AGI and caps at 100%', () => {
    assert.equal(stats.critRate, 8);          // Warrior 5 + AGI 60 * 0.05
    assert.equal(deriveStats({ ...base, agi: 200 }, 'THIEF').critRate, 60); // 50 + 10
    assert.equal(deriveStats({ ...base, agi: 2_000 }, 'THIEF').critRate, CAPS.critRate);
    assert.equal(CAPS.critRate, 100);
    assert.equal(stats.critDamage, 150);
    assert.equal(stats.evasion, 3);           // AGI 60 * 0.05%
  });

  await t.test('offsets from equipment and buffs are clamped', () => {
    const boosted = deriveStats(base, 'ARCHER', { damageReduction: 120, lifesteal: 99, armorPen: 95 });
    assert.equal(boosted.damageReduction, CAPS.damageReduction);
    assert.equal(boosted.lifesteal, CAPS.lifesteal);
    assert.equal(boosted.armorPen, CAPS.armorPen);
  });
});

test('Combat v2 - growth compensation', async (t) => {
  await t.test('every rarity starts at its own budget', () => {
    assert.equal(budgetAtLevel(1, 1), BASE_STAT_BUDGET[1]);
    assert.equal(budgetAtLevel(5, 1), BASE_STAT_BUDGET[5]);
  });

  await t.test('every rarity reaches 672 points at level 50', () => {
    for (const star of [1, 2, 3, 4, 5]) {
      assert.equal(Math.round(budgetAtLevel(star, 50)), TARGET_BUDGET);
    }
    assert.equal(trainingPointsForLevel(50), 147); // 3 per level
  });

  await t.test('low rarity catches up quadratically', () => {
    // Formula: 100 + 8*9 + 180*(9/49)^2 = 178.07
    assert.ok(Math.abs(budgetAtLevel(1, 10) - 178.07) < 0.01);
    assert.ok(growthCompensation(1, 25) > 0);
    assert.equal(growthCompensation(5, 25), 0); // 5-star needs no compensation
    assert.equal(growthCompensation(5, 50), 0);
  });

  await t.test('class growth distributes automatic points by multiplier', () => {
    const warrior = classGrowthPoints(100, 'WARRIOR');
    assert.equal(warrior.str + warrior.int + warrior.sta + warrior.agi, 100);
    assert.ok(warrior.str > warrior.int);
    const mage = classGrowthPoints(100, 'MAGE');
    assert.ok(mage.int > mage.str);
  });

  await t.test('a levelled Hero spends exactly its budget', () => {
    // Level-1 template stats already sum to the rarity budget.
    const base = { str: 70, int: 70, sta: 70, agi: 70 }; // 5-star: 280
    const stats = computeHeroBaseStats({
      templateBase: base, star: 5, level: 50, heroClass: 'WARRIOR', training: { str: 147 },
    });
    const total = stats.str + stats.int + stats.sta + stats.agi;
    assert.ok(Math.abs(total - TARGET_BUDGET) <= 1);
    const lowStar = computeHeroBaseStats({
      templateBase: { str: 25, int: 25, sta: 25, agi: 25 }, // 1-star: 100
      star: 1, level: 50, heroClass: 'THIEF', training: { agi: 147 },
    });
    const lowTotal = lowStar.str + lowStar.int + lowStar.sta + lowStar.agi;
    assert.ok(Math.abs(lowTotal - TARGET_BUDGET) <= 1);
  });
});

test('Combat v2 - random stat roll', async (t) => {
  const weights = { str: 0.25, int: 0.1, sta: 0.2, agi: 0.45 }; // Thief archetype

  await t.test('respects the budget, minimum and per-stat cap', () => {
    for (let seed = 1; seed <= 50; seed += 1) {
      const stats = rollBaseStats(5, weights, mulberry32(seed));
      const total = stats.str + stats.int + stats.sta + stats.agi;
      assert.equal(total, BASE_STAT_BUDGET[5]);
      for (const value of Object.values(stats)) {
        assert.ok(value >= 8, `stat ${value} below minimum`);
        assert.ok(value <= 280 * 0.45 + 1, `stat ${value} above cap`);
      }
    }
  });

  await t.test('the same seed always produces the same Hero', () => {
    const first = rollBaseStats(4, weights, mulberry32(1234));
    const second = rollBaseStats(4, weights, mulberry32(1234));
    assert.deepEqual(first, second);
  });

  await t.test('the wildcard share produces unusual builds', () => {
    const rolls = Array.from({ length: 200 }, (_, index) => rollBaseStats(5, weights, mulberry32(index + 1)));
    const highInt = rolls.filter(stats => stats.int >= 45).length;
    assert.ok(highInt > 0, 'expected at least one high-INT roll from a Thief archetype');
  });
});

test('Combat v2 - class rules', async (t) => {
  await t.test('qualification is based on stat share at level 20+', () => {
    const agiHero = { str: 80, int: 40, sta: 80, agi: 200 };
    const agiClasses = eligibleClasses(agiHero, 20, 3);
    assert.ok(agiClasses.includes('THIEF'));
    assert.ok(agiClasses.includes('ARCHER'));

    const intHero = { str: 40, int: 200, sta: 80, agi: 80 };
    assert.ok(eligibleClasses(intHero, 20, 3).includes('MAGE'));
    assert.equal(eligibleClasses(intHero, 20, 2).includes('MAGE'), false);
    assert.deepEqual(eligibleClasses(intHero, 19, 3), []);
  });

  await t.test('1-2 star summons are never classed', () => {
    const random = mulberry32(7);
    for (let index = 0; index < 100; index += 1) {
      assert.equal(rollSummonClass(1, 'LIMITED', random), 'UNCLASSIFIED');
      assert.equal(rollSummonClass(2, 'LIMITED', random), 'UNCLASSIFIED');
    }
  });

  await t.test('5-star summons are always classed', () => {
    const random = mulberry32(99);
    for (let index = 0; index < 100; index += 1) {
      assert.notEqual(rollSummonClass(5, 'STANDARD', random), 'UNCLASSIFIED');
    }
  });

  await t.test('Mage only appears on SPECIAL/LIMITED banners', () => {
    const standard = mulberry32(5);
    let standardMages = 0;
    for (let index = 0; index < 2_000; index += 1) {
      if (rollSummonClass(5, 'STANDARD', standard) === 'MAGE') standardMages += 1;
    }
    assert.equal(standardMages, 0);

    const special = mulberry32(5);
    let specialMages = 0;
    for (let index = 0; index < 2_000; index += 1) {
      if (rollSummonClass(5, 'SPECIAL', special) === 'MAGE') specialMages += 1;
    }
    assert.ok(specialMages > 0);
  });
});

test('Combat v2 - Mage element affinity', async (t) => {
  await t.test('rolls one primary and one secondary affinity', () => {
    const affinity = rollElementAffinity(mulberry32(42));
    const values = Object.values(affinity).sort((a, b) => b - a);
    assert.ok(values[0] >= 60 && values[0] <= 90);
    assert.ok(values[1] >= 30 && values[1] <= 60);
    assert.ok(values.slice(2).every(value => value <= 25));
  });

  await t.test('affinity maps to the approved damage table', () => {
    assert.equal(affinityMultiplier(90), 1.5);
    assert.equal(affinityMultiplier(70), 1.3);
    assert.equal(affinityMultiplier(50), 1.15);
    assert.equal(affinityMultiplier(30), 1.0);
    assert.equal(affinityMultiplier(10), 0.8);
    assert.equal(elementMultiplierFor(85), 1.5);
  });
});

test('Combat v2 - damage pipeline', async (t) => {
  const attacker = {
    attack: 380, damageType: 'PHYSICAL', skillMultiplier: 1.5, bonusDamage: 50, damageBonus: 0,
    critRate: 100, critDamage: 150, accuracy: 0, penetrationPercent: 20, penetrationFlat: 0,
  };
  const defender = {
    defense: 200, evasion: 0, blockRate: 100, blockEffect: 50,
    critResistance: 0, critDamageReduction: 0, damageReduction: 0,
  };

  await t.test('reproduces the documented example (352 damage)', () => {
    const result = resolveAttack(attacker, defender, { random: alwaysZero });
    assert.equal(result.hit, true);
    assert.equal(result.crit, true);
    assert.equal(result.blocked, true);
    assert.ok(Math.abs(result.mitigated - 469.6969) < 0.01);
    assert.equal(result.damage, 352);
  });

  await t.test('hit chance is 90% +/- accuracy/evasion, clamped 5-98%', () => {
    assert.equal(hitChance(0, 10), 80);
    assert.equal(hitChance(100, 0), 98);
    assert.equal(hitChance(0, 200), CAPS.hitChanceMin);
  });

  await t.test('crit rate can reach 100% and resistance lowers it', () => {
    const result = resolveAttack({ ...attacker, critRate: 250 }, { ...defender, blockRate: 0 }, { random: alwaysZero });
    assert.equal(result.critChance, 100);
    const resisted = resolveAttack(
      { ...attacker, critRate: 60 },
      { ...defender, critResistance: 30, blockRate: 0 },
      { random: alwaysZero },
    );
    assert.equal(resisted.critChance, 30);
  });

  await t.test('crit damage is capped at 300% and reduced by the defender', () => {
    assert.equal(finalCritMultiplier(400, 0), 3);
    assert.equal(finalCritMultiplier(200, 30), 1.4);
  });

  await t.test('damage bonus, DR and true damage follow the pipeline', () => {
    const boosted = resolveAttack(
      { ...attacker, critRate: 0, damageBonus: 20 },
      { ...defender, blockRate: 0, damageReduction: 50 },
      { random: alwaysZero },
    );
    assert.equal(boosted.damage, Math.floor(469.6969 * 1.2 * 0.5));

    const trueDamage = resolveAttack(
      { ...attacker, damageType: 'TRUE', attack: 500, skillMultiplier: 1, bonusDamage: 0, critRate: 0 },
      { ...defender, defense: 100_000, blockRate: 0 },
      { random: alwaysZero },
    );
    assert.equal(trueDamage.damage, 500);
  });

  await t.test('magical attacks use the Mage affinity multiplier', () => {
    const spell = resolveAttack(
      { ...attacker, damageType: 'MAGICAL', critRate: 0, attack: 300 },
      { ...defender, blockRate: 0 },
      { random: alwaysZero, elementMultiplier: 1.5 },
    );
    assert.ok(spell.damage > 0);
    assert.equal(spell.damage, Math.floor(500 * (500 / 660) * 1.5));
  });

  await t.test('penetration lowers the effective defence', () => {
    assert.equal(mitigatedDamage({
      attack: 380, skillMultiplier: 1.5, bonusDamage: 50, defense: 1_000,
      penetrationPercent: 20, penetrationFlat: 50,
    }), Math.round(620 * (500 / 1_250) * 1e6) / 1e6);
  });
});

test('Combat v2 - shields, lifesteal and status', async (t) => {
  await t.test('shields absorb damage before HP', () => {
    assert.deepEqual(applyShield(500, 200), { toShield: 200, toHp: 300, shieldRemaining: 0 });
    assert.deepEqual(applyShield(100, 300), { toShield: 100, toHp: 0, shieldRemaining: 200 });
  });

  await t.test('lifesteal only counts HP damage and caps at 50%', () => {
    assert.equal(lifestealAmount(300, 10), 30);
    assert.equal(lifestealAmount(300, 99), 150);
  });

  await t.test('tenacity reduces status duration and caps at 70%', () => {
    assert.equal(statusDuration(10, 30), 7);
    assert.ok(Math.abs(statusDuration(10, 99) - 3) < 1e-9);
  });
});
