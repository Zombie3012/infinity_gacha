import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateFiveStarRate, rollForFiveStar } from '../dist/formulas/gacha.js';
import { calculateDamage, calculateMarchETASeconds } from '../dist/formulas/combat.js';

test('Gacha Pity-70 Rate Calculations', async (t) => {
  await t.test('Roll 1 through 60 should have base rate of 0.004 (0.4%)', () => {
    assert.equal(calculateFiveStarRate(1), 0.004);
    assert.equal(calculateFiveStarRate(30), 0.004);
    assert.equal(calculateFiveStarRate(60), 0.004);
  });

  await t.test('Roll 61 through 69 should escalate polynomially', () => {
    const rate61 = calculateFiveStarRate(61);
    const rate65 = calculateFiveStarRate(65);
    const rate69 = calculateFiveStarRate(69);

    // Roll 61: 0.004 + 0.996 * (0.1)^4 = 0.004 + 0.0000996 = 0.0040996
    assert.ok(rate61 > 0.004 && rate61 < 0.005);

    // Rate at 65 should be noticeably higher
    // delta = 0.5, (0.5)^4 = 0.0625, escalation = 0.996 * 0.0625 = 0.06225 -> ~0.06625 (6.6%)
    assert.ok(rate65 > 0.06 && rate65 < 0.07);

    // Roll 69: delta = 0.9, (0.9)^4 = 0.6561, escalation = 0.996 * 0.6561 = 0.6535 -> ~0.6575 (65.7%)
    assert.ok(rate69 > 0.65 && rate69 < 0.66);

    // Strictly strictly increasing
    assert.ok(rate61 < rate65);
    assert.ok(rate65 < rate69);
  });

  await t.test('Roll 70 guarantees 5-star (1.0 / 100%)', () => {
    assert.equal(calculateFiveStarRate(70), 1.0);
    assert.equal(calculateFiveStarRate(75), 1.0);
    assert.equal(rollForFiveStar(70, 0.999), true);
  });
});

test('Combat Damage and Movement Calculations', async (t) => {
  await t.test('Damage calculation with defense mitigation', () => {
    // 100 attack vs 100 defense -> 100 * (100 / 200) = 50 damage
    const normal = calculateDamage(100, 100, false);
    assert.equal(normal.damage, 50);
    assert.equal(normal.isCritical, false);

    // Critical hit with default +50% bonus -> 50 * 1.5 = 75 damage
    const crit = calculateDamage(100, 100, true);
    assert.equal(crit.damage, 75);
    assert.equal(crit.isCritical, true);
  });

  await t.test('March ETA calculation', () => {
    // Distance from (0,0) to (3,4) is 5 tiles. 5 * 30s = 150 seconds
    const eta = calculateMarchETASeconds(0, 0, 3, 4, 30, 1.0);
    assert.equal(eta, 150);

    // With scout speed multiplier of 3.0x -> 150 / 3 = 50 seconds
    const scoutEta = calculateMarchETASeconds(0, 0, 3, 4, 30, 3.0);
    assert.equal(scoutEta, 50);
  });
});


test('Pity coefficients are configurable at runtime', async (t) => {
  await t.test('base rate override applies before the pity window', () => {
    assert.equal(calculateFiveStarRate(10, { baseRate: 0.01 }), 0.01);
    assert.equal(calculateFiveStarRate(60, { baseRate: 0.01 }), 0.01);
  });

  await t.test('custom exponent reshapes the escalation window', () => {
    const rate = calculateFiveStarRate(65, { baseRate: 0.004, thresholdStart: 60, guaranteeRoll: 70, exponent: 2 });
    // 0.004 + 0.996 * (5/10)^2 = 0.253
    assert.ok(Math.abs(rate - 0.253) < 1e-9);
  });

  await t.test('guarantee roll override still yields a guaranteed 5-star', () => {
    assert.equal(calculateFiveStarRate(50, { thresholdStart: 40, guaranteeRoll: 50 }), 1);
    assert.equal(rollForFiveStar(50, 0.999, { thresholdStart: 40, guaranteeRoll: 50 }), true);
  });
});
