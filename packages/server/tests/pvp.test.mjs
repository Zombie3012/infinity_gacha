import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canAttack, canHoldMoreTerritories, defenderPower, protectionAfterCapture, resolvePvp,
} from '../dist/modules/world/pvp-rules.js';

const now = new Date('2026-11-04T00:00:00Z');

test('P3 PvP - attack eligibility', async (t) => {
  await t.test('unowned tiles are claimed, not attacked', () => {
    const check = canAttack({ tileOwned: false, ownedBySelf: false, territoryProtectedUntil: null, ownerShieldUntil: null, now });
    assert.equal(check.reason, 'ERR_TARGET_UNOWNED');
  });

  await t.test('a Master cannot attack their own territory', () => {
    const check = canAttack({ tileOwned: true, ownedBySelf: true, territoryProtectedUntil: null, ownerShieldUntil: null, now });
    assert.equal(check.reason, 'ERR_TARGET_OWN_TERRITORY');
  });

  await t.test('claim protection blocks attacks', () => {
    const check = canAttack({
      tileOwned: true, ownedBySelf: false,
      territoryProtectedUntil: new Date(now.getTime() + 60_000), ownerShieldUntil: null, now,
    });
    assert.equal(check.reason, 'ERR_TERRITORY_PROTECTED');
  });

  await t.test('the victim novice shield blocks attacks', () => {
    const check = canAttack({
      tileOwned: true, ownedBySelf: false, territoryProtectedUntil: null,
      ownerShieldUntil: new Date(now.getTime() + 3_600_000), now,
    });
    assert.equal(check.reason, 'ERR_TARGET_SHIELDED');
  });

  await t.test('an unprotected enemy tile is attackable', () => {
    assert.equal(canAttack({ tileOwned: true, ownedBySelf: false, territoryProtectedUntil: null, ownerShieldUntil: null, now }).ok, true);
  });
});

test('P3 PvP - battles', async (t) => {
  await t.test('defenders get +20% and +10% per territory level', () => {
    assert.equal(defenderPower(1000, 1), 1200);
    assert.equal(defenderPower(1000, 3), 1440);
  });

  await t.test('a much stronger attacker wins deterministically for the same seed', () => {
    const first = resolvePvp(10_000, 1_200, 'seed-a');
    const second = resolvePvp(10_000, 1_200, 'seed-a');
    assert.deepEqual(first, second);
    assert.equal(first.winner, 'ATTACKER');
    assert.ok(first.rounds >= 3 && first.rounds <= 20);
  });

  await t.test('an overwhelmed attacker loses', () => {
    assert.equal(resolvePvp(400, 5_000, 'seed-b').winner, 'DEFENDER');
  });

  await t.test('the 10-territory cap also gates PvP captures', () => {
    assert.equal(canHoldMoreTerritories(9), true);
    assert.equal(canHoldMoreTerritories(10), false);
  });

  await t.test('captured tiles receive a fresh protection window', () => {
    assert.equal(protectionAfterCapture(now).getTime() - now.getTime(), 30 * 60_000);
  });
});
