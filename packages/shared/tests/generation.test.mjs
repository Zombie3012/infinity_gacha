import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateHero, roleForClass } from '../dist/combat/generation.js';
import { mulberry32 } from '../dist/combat/stats.js';

test('Combat v2 - summon generation', async (t) => {
  await t.test('a 5-star Hero uses the 280-point budget and is classed', () => {
    const hero = generateHero({
      star: 5,
      archetypeWeights: { str: 0.35, int: 0.15, sta: 0.3, agi: 0.2 },
      random: mulberry32(21),
    });
    const total = hero.base.str + hero.base.int + hero.base.sta + hero.base.agi;
    assert.equal(total, 280);
    assert.notEqual(hero.heroClass, 'UNCLASSIFIED');
    assert.equal(hero.playable, true);
    assert.equal(hero.derived.maxHp, 20 * hero.base.sta);
  });

  await t.test('1-2 star Heroes stay unclassified', () => {
    for (const star of [1, 2]) {
      for (let seed = 1; seed <= 20; seed += 1) {
        const hero = generateHero({ star, random: mulberry32(seed) });
        assert.equal(hero.heroClass, 'UNCLASSIFIED');
      }
    }
  });

  await t.test('class options constrain the roll', () => {
    const mage = generateHero({ star: 5, classOptions: ['MAGE'], random: mulberry32(4) });
    assert.equal(mage.heroClass, 'MAGE');
    assert.ok(mage.elementAffinity);
    const values = Object.values(mage.elementAffinity).sort((a, b) => b - a);
    assert.ok(values[0] >= 60);

    const warrior = generateHero({ star: 5, classOptions: ['WARRIOR'], random: mulberry32(4) });
    assert.equal(warrior.heroClass, 'WARRIOR');
    assert.equal(warrior.elementAffinity, null);
  });

  await t.test('derived offsets from equipment are applied', () => {
    const hero = generateHero({
      star: 3, classOptions: ['WARRIOR'], offsets: { hpBase: 100, atkBase: 50 }, random: mulberry32(8),
    });
    assert.equal(hero.derived.maxHp, 100 + 20 * hero.base.sta);
    assert.equal(hero.derived.atk, 50 + Math.round(2.5 * hero.base.str + 0.5 * hero.base.agi));
  });

  await t.test('6-7 star Heroes are generated but not playable yet', () => {
    const six = generateHero({ star: 6, random: mulberry32(3) });
    assert.equal(six.base.str + six.base.int + six.base.sta + six.base.agi, 350);
    assert.equal(six.playable, false);
    const seven = generateHero({ star: 7, random: mulberry32(3) });
    assert.equal(seven.base.str + seven.base.int + seven.base.sta + seven.base.agi, 430);
    assert.equal(seven.playable, false);
  });

  await t.test('class to combat-role mapping', () => {
    assert.equal(roleForClass('WARRIOR'), 'PHYSICAL_DPS');
    assert.equal(roleForClass('THIEF'), 'ASSASSIN');
    assert.equal(roleForClass('MAGE'), 'MAGIC_DPS');
    assert.equal(roleForClass('UNCLASSIFIED'), 'PHYSICAL_DPS');
  });
});
