import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  abandonAt, canClaim, canUnlockGlobal, isDiscoverable, protectionUntil, shieldUntil,
  territoryYield, tileDistance, upgradeCost, MAX_TERRITORIES,
} from '../dist/modules/world/world-rules.js';

test('P3 World - unlock eligibility', async (t) => {
  await t.test('level 15 and floor 10 are both required', () => {
    assert.equal(canUnlockGlobal({ masterLevel: 15, clearedFloor: 10 }).ok, true);
    assert.equal(canUnlockGlobal({ masterLevel: 14, clearedFloor: 10 }).reason, 'ERR_WORLD_LEVEL_REQUIRED');
    assert.equal(canUnlockGlobal({ masterLevel: 15, clearedFloor: 9 }).reason, 'ERR_WORLD_FLOOR_REQUIRED');
  });
});

test('P3 World - discovery radius', async (t) => {
  const base = { x: 100, y: 100 };

  await t.test('tiles inside the base radius are discovered automatically', () => {
    assert.equal(isDiscoverable({ x: 105, y: 105 }, base, []), true);
    assert.equal(isDiscoverable({ x: 106, y: 100 }, base, []), false);
  });

  await t.test('tiles adjacent to a known tile become discoverable', () => {
    assert.equal(isDiscoverable({ x: 106, y: 100 }, base, [{ x: 105, y: 100 }]), true);
    assert.equal(isDiscoverable({ x: 108, y: 108 }, base, [{ x: 105, y: 100 }]), false);
  });

  await t.test('distance is Chebyshev (king moves)', () => {
    assert.equal(tileDistance({ x: 0, y: 0 }, { x: 3, y: 1 }), 3);
  });
});

test('P3 World - territory economy', async (t) => {
  await t.test('yield grows 50% per level', () => {
    assert.equal(territoryYield(100, 1), 100);
    assert.equal(territoryYield(100, 2), 150);
    assert.equal(territoryYield(100, 3), 200);
  });

  await t.test('upgrade cost scales with the current level', () => {
    assert.equal(upgradeCost(1), 1500);
    assert.equal(upgradeCost(3), 4500);
  });

  await t.test('the 10-territory cap is enforced', () => {
    assert.equal(canClaim(9, false).ok, true);
    assert.equal(canClaim(MAX_TERRITORIES, false).reason, 'ERR_TERRITORY_LIMIT_REACHED');
    assert.equal(canClaim(0, true).reason, 'ERR_TERRITORY_ALREADY_OWNED');
  });

  await t.test('timers match the spec durations', () => {
    const now = new Date('2026-11-04T00:00:00Z');
    assert.equal(protectionUntil(now).getTime() - now.getTime(), 30 * 60_000);
    assert.equal(abandonAt(now).getTime() - now.getTime(), 10 * 60_000);
    assert.equal(shieldUntil(now).getTime() - now.getTime(), 48 * 3_600_000);
  });
});
