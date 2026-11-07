import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bedCapacityForLevel,
  classifyInjury,
  injuryMultiplier,
  resurrectionQuote,
  treatmentSeconds,
} from '../dist/modules/medical/medical-rules.js';

const day = 86_400_000;

test('DM-04 Medical - injury classification', async (t) => {
  await t.test('scenario 4.1: below 15% HP is SEVERE with a 25% penalty and 2h timer', () => {
    const profile = classifyInjury(12);
    assert.deepEqual(profile, { severity: 'SEVERE', penaltyPercent: 25, naturalHealSeconds: 7200 });
  });

  await t.test('injury tiers follow surviving HP', () => {
    assert.equal(classifyInjury(20)?.severity, 'MODERATE');
    assert.equal(classifyInjury(20)?.penaltyPercent, 15);
    assert.equal(classifyInjury(40)?.severity, 'MINOR');
    assert.equal(classifyInjury(40)?.naturalHealSeconds, 1800);
    assert.equal(classifyInjury(75), null);
  });

  await t.test('penalties convert to combat multipliers', () => {
    assert.equal(injuryMultiplier(25), 0.75);
    assert.equal(injuryMultiplier(0), 1);
  });
});

test('DM-04 Medical - facility and treatment', async (t) => {
  await t.test('scenario 5.1: Recovery Center has 2/4/6 treatment slots for levels 1/2/3', () => {
    assert.equal(bedCapacityForLevel(1), 2);
    assert.equal(bedCapacityForLevel(2), 4);
    assert.equal(bedCapacityForLevel(3), 6);
  });

  await t.test('higher facility levels shorten treatment but never below 20%', () => {
    assert.equal(treatmentSeconds(7200, 1), 7200);
    assert.equal(treatmentSeconds(7200, 3), 4320);
    assert.equal(treatmentSeconds(7200, 20), 1440);
  });
});

test('DM-04 Medical - divine grace resurrection', async (t) => {
  const now = new Date('2026-03-01T00:00:00Z');

  await t.test('scenario 6.1: first resurrection costs 1 tear and 10,000 Silver', () => {
    const quote = resurrectionQuote(0, now, now);
    assert.equal(quote.tears, 1);
    assert.equal(quote.silver, 10000);
    assert.equal(quote.cycleReset, false);
  });

  await t.test('the cost grows with each resurrection inside the cycle', () => {
    const quote = resurrectionQuote(2, new Date(now.getTime() - 5 * day), now);
    assert.equal(quote.tears, 3);
    assert.equal(quote.silver, 30000);
  });

  await t.test('scenario 6.2: after 30 days the cycle resets to the base cost', () => {
    const quote = resurrectionQuote(3, new Date(now.getTime() - 31 * day), now);
    assert.equal(quote.cycleReset, true);
    assert.equal(quote.tears, 1);
    assert.equal(quote.silver, 10000);
  });
});
