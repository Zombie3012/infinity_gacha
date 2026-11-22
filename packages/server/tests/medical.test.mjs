import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bedCapacityForLevel,
  classifyInjury,
  injuryMultiplier,
  revivedHpPercent, RESURRECTION_GEM_ITEM,
  treatmentSeconds,
} from '../dist/modules/medical/medical-rules.js';

const day = 86_400_000;

test('DM-04 Medical - injury classification', async (t) => {
  await t.test('zero or negative HP is not a surviving injury', () => {
    assert.equal(classifyInjury(0), null);
    assert.equal(classifyInjury(-10), null);
  });
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

test('Resurrection requires the seven-star gem and restores full HP', () => {
  assert.equal(RESURRECTION_GEM_ITEM, 'RESURRECTION_GEM_7');
  assert.equal(revivedHpPercent(), 1);
});
