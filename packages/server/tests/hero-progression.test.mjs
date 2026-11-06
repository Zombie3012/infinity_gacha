import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CLASS_CHANGE_ITEM, CLASS_CHANGE_SILVER, ProgressionError, allocateTraining, classChangeCheck,
  isV2Origin, progressionFor, trainingRemaining, trainingTotal,
} from '../dist/modules/hero/hero-progression.js';

const origin5 = { str: 70, int: 70, sta: 70, agi: 70 }; // 280 budget

test('Combat v2 - progression recompute', async (t) => {
  await t.test('level 50 recomputes base stats from origin and training', () => {
    const snapshot = progressionFor({
      origin: origin5, star: 5, level: 50, classCode: 'WARRIOR', training: { str: 147 },
      hpPct: 0.5, mpPct: 0.5,
    });
    const total = snapshot.base.str + snapshot.base.int + snapshot.base.sta + snapshot.base.agi;
    assert.ok(Math.abs(total - 672) <= 1);
    assert.equal(snapshot.maxHp, 20 * snapshot.base.sta);
    assert.equal(snapshot.hp, Math.round(snapshot.maxHp * 0.5));
    assert.equal(snapshot.maxMp, 10 * snapshot.base.int);
    assert.equal(snapshot.speed, 60 + snapshot.base.agi);
    assert.equal(snapshot.trainingRemaining, 0);
  });

  await t.test('class change retroactively redistributes automatic growth only', () => {
    const warrior = progressionFor({ origin: origin5, star: 5, level: 50, classCode: 'WARRIOR' });
    const mage = progressionFor({ origin: origin5, star: 5, level: 50, classCode: 'MAGE' });
    assert.ok(mage.base.int > warrior.base.int);
    assert.ok(warrior.base.str > mage.base.str);
    // Training points are untouched by the class swap.
    assert.equal(trainingTotal(warrior.training), 0);
  });

  await t.test('training points are bounded by level', () => {
    assert.equal(trainingRemaining(10, { str: 0, int: 0, sta: 0, agi: 0 }), 27); // 3 * 9
    assert.equal(trainingRemaining(10, { str: 10, int: 0, sta: 0, agi: 0 }), 17);
    assert.equal(trainingRemaining(1, {}), 0);
  });

  await t.test('allocateTraining updates one stat and keeps the budget', () => {
    const { snapshot, training } = allocateTraining({
      origin: origin5, star: 5, level: 20, classCode: 'WARRIOR', stat: 'int', points: 10,
    });
    assert.equal(training.int, 10);
    const total = snapshot.base.str + snapshot.base.int + snapshot.base.sta + snapshot.base.agi;
    assert.ok(Math.abs(total - 385) <= 1); // 280 + 5*19 auto + 10 trained
  });

  await t.test('invalid training requests are refused', () => {
    assert.throws(
      () => allocateTraining({ origin: origin5, star: 5, level: 10, classCode: 'WARRIOR', stat: 'luk', points: 1 }),
      error => error instanceof ProgressionError && error.message === 'ERR_HERO_STAT_INVALID',
    );
    assert.throws(
      () => allocateTraining({ origin: origin5, star: 5, level: 10, classCode: 'WARRIOR', stat: 'str', points: 0 }),
      error => error.message === 'ERR_HERO_TRAINING_POINTS_INVALID',
    );
    assert.throws(
      () => allocateTraining({ origin: origin5, star: 5, level: 5, classCode: 'WARRIOR', stat: 'str', points: 99 }),
      error => error.message === 'ERR_HERO_NO_TRAINING_POINTS',
    );
  });

  await t.test('awakening ranks add +10 to every base stat permanently', () => {
    const base = progressionFor({ origin: origin5, star: 5, level: 30, classCode: 'WARRIOR' });
    const awakened = progressionFor({
      origin: origin5, star: 5, level: 30, classCode: 'WARRIOR', awakeningRank: 2,
    });
    assert.equal(awakened.base.str - base.base.str, 20);
    assert.equal(awakened.base.int - base.base.int, 20);
    assert.equal(awakened.base.sta - base.base.sta, 20);
    assert.equal(awakened.base.agi - base.base.agi, 20);
    assert.ok(awakened.maxHp > base.maxHp);
  });

  await t.test('equipment base stats and offsets are integrated into snapshot', () => {
    const unequipped = progressionFor({ origin: origin5, star: 5, level: 30, classCode: 'WARRIOR' });
    const equipped = progressionFor({
      origin: origin5,
      star: 5,
      level: 30,
      classCode: 'WARRIOR',
      equipmentBase: { str: 25, sta: 15 },
      equipmentOffsets: { hpBase: 100, critRate: 5, lifesteal: 10 },
    });
    assert.equal(equipped.base.str - unequipped.base.str, 25);
    assert.equal(equipped.base.sta - unequipped.base.sta, 15);
    // sta increases maxHp by 15 * 20 = 300, plus flat hpBase 100 => 400 total HP increase
    assert.equal(equipped.maxHp - unequipped.maxHp, 400);
    assert.equal(equipped.derived.critRate - unequipped.derived.critRate, 5);
    assert.equal(equipped.derived.lifesteal, 10);
  });

  await t.test('v2 detection separates new Heroes from legacy demo rows', () => {
    assert.equal(isV2Origin(origin5), true);
    assert.equal(isV2Origin({ str: 0, int: 0, sta: 0, agi: 0 }), false);
    assert.equal(isV2Origin(null), false);
  });
});

test('Combat v2 - class change conditions', async (t) => {
  const agiHero = { str: 40, int: 30, sta: 40, agi: 60 }; // AGI 35%
  const base = {
    level: 20, star: 3, base: agiHero, currentClass: 'UNCLASSIFIED', targetClass: 'THIEF',
    silver: CLASS_CHANGE_SILVER, itemQuantity: 1,
  };

  await t.test('eligible Heroes pay Silver and one class token', () => {
    assert.deepEqual(classChangeCheck(base), { ok: true });
    assert.equal(CLASS_CHANGE_ITEM, 'CLASS_CHANGE_TOKEN');
  });

  await t.test('rejects wrong level, class, stats, funds and items', () => {
    assert.equal(classChangeCheck({ ...base, level: 19 }).reason, 'ERR_CLASS_LEVEL_REQUIRED');
    assert.equal(classChangeCheck({ ...base, targetClass: 'MAGE' }).reason, 'ERR_CLASS_NOT_ELIGIBLE');
    assert.equal(classChangeCheck({ ...base, targetClass: 'THIEF', currentClass: 'THIEF' }).reason, 'ERR_CLASS_SAME');
    assert.equal(classChangeCheck({ ...base, targetClass: 'DRAGON' }).reason, 'ERR_CLASS_INVALID');
    assert.equal(classChangeCheck({ ...base, silver: CLASS_CHANGE_SILVER - 1 }).reason, 'ERR_CLASS_INSUFFICIENT_SILVER');
    assert.equal(classChangeCheck({ ...base, itemQuantity: 0 }).reason, 'ERR_CLASS_ITEM_REQUIRED');
  });

  await t.test('Mage requires an INT-heavy distribution and 3+ stars', () => {
    const intHero = { str: 30, int: 70, sta: 40, agi: 30 };
    assert.equal(classChangeCheck({ ...base, base: intHero, targetClass: 'MAGE' }).ok, true);
    assert.equal(classChangeCheck({ ...base, base: intHero, star: 2, targetClass: 'MAGE' }).reason, 'ERR_CLASS_NOT_ELIGIBLE');
  });
});
