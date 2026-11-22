import { test } from 'node:test';
import assert from 'node:assert/strict';
import { calculateDamage, calculateMarchETASeconds } from '../dist/formulas/combat.js';

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
