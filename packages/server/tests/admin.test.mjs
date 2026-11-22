import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RateGuard } from '../dist/modules/admin/security.service.js';
import {
  CONFIG_KEYS,
  isConfigKey,
  nextVersion,
  validateConfigValue,
  validateOperatorId,
} from '../dist/modules/admin/system-config.service.js';

const opts = { windowMs: 1000, threshold: 100, blockMs: 5000, alertCooldownMs: 60000 };

test('DM-14 Anti-cheat - RateGuard thresholds', async (t) => {
  await t.test('stays quiet below the configured threshold', () => {
    const guard = new RateGuard(opts);
    for (let i = 0; i < 99; i += 1) {
      const verdict = guard.observe('acc-1', 1000 + i);
      assert.equal(verdict.exceeded, false);
      assert.equal(verdict.blocked, false);
    }
  });

  await t.test('raises HIGH at the threshold and blocks the account', () => {
    const guard = new RateGuard(opts);
    let verdict;
    for (let i = 0; i < 100; i += 1) verdict = guard.observe('acc-1', 1000 + i);
    assert.equal(verdict.exceeded, true);
    assert.equal(verdict.severity, 'HIGH');
    assert.equal(verdict.shouldAlert, true);
    assert.equal(verdict.blocked, true);
    assert.equal(guard.isBlocked('acc-1', 1000 + 101), true);
  });

  await t.test('escalates to CRITICAL at twice the threshold', () => {
    const guard = new RateGuard(opts);
    let verdict;
    for (let i = 0; i < 200; i += 1) verdict = guard.observe('acc-2', 1000 + i);
    assert.equal(verdict.severity, 'CRITICAL');
  });

  await t.test('suppresses duplicate alerts inside the cooldown window', () => {
    const guard = new RateGuard(opts);
    let alerts = 0;
    for (let i = 0; i < 150; i += 1) {
      if (guard.observe('acc-3', 1000 + i).shouldAlert) alerts += 1;
    }
    assert.equal(alerts, 1);
  });

  await t.test('block expires after blockMs and window resets', () => {
    const guard = new RateGuard(opts);
    for (let i = 0; i < 100; i += 1) guard.observe('acc-4', 1000 + i);
    const blockedUntil = guard.observe('acc-4', 1099).blockedUntil;
    assert.equal(guard.isBlocked('acc-4', 3000), true);
    assert.equal(guard.isBlocked('acc-4', blockedUntil), false);
    const fresh = guard.observe('acc-4', blockedUntil + 1);
    assert.equal(fresh.count, 1);
  });

  await t.test('prune drops idle accounts only', () => {
    const guard = new RateGuard(opts);
    guard.observe('idle-a', 1000);
    guard.observe('idle-b', 1000);
    guard.observe('active', 21000);
    assert.equal(guard.size(), 3);
    assert.equal(guard.prune(21100), 2);
    assert.equal(guard.size(), 1);
  });
});

test('DM-14 Configuration - validation helpers', async (t) => {
  await t.test('accepts a plain JSON object', () => {
    const value = { tacticalBuffCooldownSeconds: 15, description: 'Battle cooldown' };
    assert.deepEqual(validateConfigValue(value), value);
  });

  await t.test('rejects non-object payloads', () => {
    for (const bad of [null, [], 'text', 42, undefined]) {
      assert.throws(() => validateConfigValue(bad), /must be a JSON object/);
    }
  });

  await t.test('rejects payloads over 16 KB', () => {
    assert.throws(() => validateConfigValue({ blob: 'x'.repeat(17 * 1024) }), /exceeds/);
  });

  await t.test('versions increment per config key', () => {
    assert.equal(nextVersion([]), 1);
    assert.equal(nextVersion([1]), 2);
    assert.equal(nextVersion([1, 2, 7]), 8);
  });

  await t.test('operator codes are constrained', () => {
    assert.equal(validateOperatorId(' ACT-06 '), 'ACT-06');
    assert.throws(() => validateOperatorId('a'), /2-64/);
    assert.throws(() => validateOperatorId('bad actor!'), /2-64/);
  });

  await t.test('only approved config keys are accepted', () => {
    for (const key of CONFIG_KEYS) assert.equal(isConfigKey(key), true);
    assert.equal(isConfigKey('NOT_A_RULE'), false);
    assert.equal(isConfigKey('GACHA_PITY'), false);
  });
});
