import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  LOYALTY_START,
  affinityGainForVictory,
  assignTraits,
  disobedienceChance,
  loyaltyCombatMultiplier,
  loyaltyState,
  relationshipTier,
  resonanceMultiplier,
} from '../dist/modules/personality/personality-rules.js';

test('DM-03 Personality - traits and loyalty', async (t) => {
  await t.test('scenario 2.1: every Hero receives four traits and loyalty 50', () => {
    const traits = assignTraits('hero-abc-123');
    assert.ok(traits.coreTrait);
    assert.ok(traits.socialTrait);
    assert.ok(traits.behavioralTrait);
    assert.ok(traits.specialTrait);
    assert.ok(traits.favoriteFood);
    assert.equal(LOYALTY_START, 50);
    assert.equal(loyaltyState(LOYALTY_START), 'NORMAL');
  });

  await t.test('trait assignment is deterministic for an instance', () => {
    assert.deepEqual(assignTraits('hero-abc-123'), assignTraits('hero-abc-123'));
  });

  await t.test('loyalty states follow the approved thresholds', () => {
    assert.equal(loyaltyState(0), 'DANGER');
    assert.equal(loyaltyState(19), 'DANGER');
    assert.equal(loyaltyState(20), 'NORMAL');
    assert.equal(loyaltyState(79), 'NORMAL');
    assert.equal(loyaltyState(80), 'DEVOTED');
  });

  await t.test('scenario 2.2: DANGER Heroes lose 20–50% stats and may disobey', () => {
    assert.equal(loyaltyCombatMultiplier(0), 0.5);
    assert.ok(loyaltyCombatMultiplier(19) > 0.78 && loyaltyCombatMultiplier(19) < 0.8);
    assert.equal(loyaltyCombatMultiplier(50), 1);
    assert.equal(disobedienceChance(0), 0.3);
    assert.equal(disobedienceChance(50), 0);
  });

  await t.test('DEVOTED Heroes get a small combat bonus', () => {
    assert.equal(loyaltyCombatMultiplier(85), 1.05);
  });
});

test('DM-03 Personality - relationships', async (t) => {
  await t.test('scenario 3.1: five shared victories add 10 affinity', () => {
    assert.equal(affinityGainForVictory(1) * 5, 10);
  });

  await t.test('relationship tiers unlock at the documented affinity', () => {
    assert.equal(relationshipTier(0), 'STRANGER');
    assert.equal(relationshipTier(25), 'ACQUAINTANCE');
    assert.equal(relationshipTier(50), 'COMRADE');
    assert.equal(relationshipTier(80), 'TRUSTED_ALLY');
    assert.equal(relationshipTier(-1), 'RIVAL');
  });

  await t.test('COMRADE and above grant a +5% resonance bonus', () => {
    assert.equal(resonanceMultiplier('COMRADE'), 1.05);
    assert.equal(resonanceMultiplier('TRUSTED_ALLY'), 1.05);
    assert.equal(resonanceMultiplier('STRANGER'), 1);
  });
});
