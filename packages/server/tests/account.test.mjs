import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  hashRecoveryToken,
  isRecoveryTokenUsable,
  isSupportedProvider,
  maskUsername,
  providerSignature,
  recoveryExpiry,
  verifyProviderSignature,
} from '../dist/modules/auth/account-rules.js';

const secret = 'test-secret';

test('DM-01 Account - provider link verification', async (t) => {
  await t.test('signatures are deterministic and verifiable', () => {
    const signature = providerSignature(secret, 'GOOGLE', 'google_uid_999');
    assert.equal(signature, providerSignature(secret, 'GOOGLE', 'google_uid_999'));
    assert.equal(verifyProviderSignature(secret, 'GOOGLE', 'google_uid_999', signature), true);
  });

  await t.test('a tampered signature or id is rejected', () => {
    const signature = providerSignature(secret, 'GOOGLE', 'google_uid_999');
    assert.equal(verifyProviderSignature(secret, 'APPLE', 'google_uid_999', signature), false);
    assert.equal(verifyProviderSignature(secret, 'GOOGLE', 'google_uid_999', 'deadbeef'), false);
    assert.equal(verifyProviderSignature('', 'GOOGLE', 'google_uid_999', signature), false);
  });

  await t.test('only Google and Apple are supported', () => {
    assert.equal(isSupportedProvider('GOOGLE'), true);
    assert.equal(isSupportedProvider('APPLE'), true);
    assert.equal(isSupportedProvider('STEAM'), false);
  });
});

test('DM-01 Account - recovery tokens', async (t) => {
  const now = new Date('2026-11-04T00:00:00Z');

  await t.test('tokens are stored hashed, never in clear text', () => {
    const token = 'ABC12345';
    const hash = hashRecoveryToken(token);
    assert.notEqual(hash, token);
    assert.equal(hash.length, 64);
    assert.equal(hashRecoveryToken(' abc12345 '), hash, 'input is normalised before hashing');
  });

  await t.test('tokens expire after 24 hours', () => {
    const expires = recoveryExpiry(now);
    assert.equal(expires.toISOString(), '2026-11-05T00:00:00.000Z');
    assert.equal(isRecoveryTokenUsable({ expiresAt: expires, usedAt: null }, now), true);
    assert.equal(isRecoveryTokenUsable({ expiresAt: expires, usedAt: null }, new Date('2026-11-05T00:00:01Z')), false);
  });

  await t.test('a used token cannot be redeemed twice', () => {
    const expires = recoveryExpiry(now);
    assert.equal(isRecoveryTokenUsable({ expiresAt: expires, usedAt: now }, now), false);
  });

  await t.test('recovery hints mask the username', () => {
    assert.equal(maskUsername('dragonmaster'), 'dr*********r');
    assert.equal(maskUsername('ab'), 'a***');
  });
});
