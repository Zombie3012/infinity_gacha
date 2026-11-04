import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canClaimCleared, expeditionProgress, resolveGuardianBattle, travelSeconds, validateParty,
} from '../dist/modules/world/expedition-rules.js';

test('P3 Expeditions - party validation', async (t) => {
  await t.test('a party needs 1–5 distinct Heroes', () => {
    assert.equal(validateParty(['a']).ok, true);
    assert.equal(validateParty(['a', 'b', 'c', 'd', 'e']).ok, true);
    assert.equal(validateParty([]).reason, 'ERR_EXPEDITION_EMPTY');
    assert.equal(validateParty(['a', 'b', 'c', 'd', 'e', 'f']).reason, 'ERR_EXPEDITION_TOO_MANY_HEROES');
    assert.equal(validateParty(['a', 'a']).reason, 'ERR_EXPEDITION_DUPLICATE_HERO');
  });
});

test('P3 Expeditions - travel and battles', async (t) => {
  await t.test('travel time is 30s per tile with a 30s floor', () => {
    assert.equal(travelSeconds(0), 30);
    assert.equal(travelSeconds(1), 30);
    assert.equal(travelSeconds(4), 120);
  });

  await t.test('the guardian falls when party power matches the threshold', () => {
    assert.equal(resolveGuardianBattle(1000, 1000).won, true);
    assert.equal(resolveGuardianBattle(940, 1000).won, false);
    assert.equal(resolveGuardianBattle(500, 0).won, true);
    assert.equal(resolveGuardianBattle(1500, 1000).ratio, 1.5);
  });

  await t.test('claiming requires a cleared tile', () => {
    assert.equal(canClaimCleared(true).ok, true);
    assert.equal(canClaimCleared(false).reason, 'ERR_TERRITORY_NOT_CLEARED');
  });

  await t.test('progress reports travel vs return countdowns', () => {
    const now = new Date('2026-11-04T00:00:00Z');
    const travelling = expeditionProgress('TRAVELING', new Date(now.getTime() + 30_000), null, now);
    assert.equal(travelling.phase, 'TRAVELING');
    assert.equal(travelling.secondsRemaining, 30);

    const returning = expeditionProgress('RETURNING', now, new Date(now.getTime() + 60_000), now);
    assert.equal(returning.phase, 'RETURNING');
    assert.equal(returning.secondsRemaining, 60);

    const done = expeditionProgress('COMPLETED', now, null, now);
    assert.equal(done.phase, 'DONE');
  });
});
