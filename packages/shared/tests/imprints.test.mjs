import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  EMPTY_IMPRINT_EFFECTS, combineImprintEffects, imprintAbilityScale,
  isEmptyImprintEffects, isImprintAbilityCode,
} from '../dist/combat/imprints.js';
import { CAPS } from '../dist/combat/stats.js';

test('Imprint abilities - aggregation', async (t) => {
  await t.test('no ability imprints produce an empty bundle', () => {
    const effects = combineImprintEffects([{ abilityCode: '', abilityParams: null, rankLevel: 1 }]);
    assert.deepEqual(effects, EMPTY_IMPRINT_EFFECTS);
    assert.equal(isEmptyImprintEffects(effects), true);
    assert.equal(isImprintAbilityCode('PHOENIX_REVIVE'), true);
    assert.equal(isImprintAbilityCode('NOT_A_HOOK'), false);
  });

  await t.test('rank level scales the magnitudes and is clamped to 1-3', () => {
    const rankOne = combineImprintEffects([{
      abilityCode: 'CRIT_EVASION', abilityParams: { critRate: 5, evasion: 4 }, rankLevel: 1,
    }]);
    const rankThree = combineImprintEffects([{
      abilityCode: 'CRIT_EVASION', abilityParams: { critRate: 5, evasion: 4 }, rankLevel: 3,
    }]);
    assert.equal(rankOne.critRate, 5);
    assert.equal(rankThree.critRate, 15);
    assert.equal(rankThree.evasion, 12);
    assert.equal(imprintAbilityScale(0), 1);
    assert.equal(imprintAbilityScale(9), 3);
  });

  await t.test('shared caps apply after combining every owned imprint', () => {
    const effects = combineImprintEffects([
      { abilityCode: 'CRIT_EVASION', abilityParams: { critRate: 60, evasion: 50 }, rankLevel: 3 },
      { abilityCode: 'CRIT_EVASION', abilityParams: { critRate: 60, evasion: 50 }, rankLevel: 3 },
    ]);
    assert.equal(effects.critRate, CAPS.critRate);
    assert.equal(effects.evasion, CAPS.evasion);
  });

  await t.test('conditional and revive hooks keep their trigger parameters', () => {
    const effects = combineImprintEffects([
      { abilityCode: 'LOW_HP_EMPOWER', abilityParams: { hpThresholdPct: 40, damageBonus: 15, tenacity: 20 }, rankLevel: 2 },
      { abilityCode: 'PHOENIX_REVIVE', abilityParams: { hpPct: 30, times: 1 }, rankLevel: 2 },
      { abilityCode: 'ARCANE_EMPOWER', abilityParams: { matkPercent: 10, mpRegenPct: 5 }, rankLevel: 1 },
      { abilityCode: 'ACCURACY_EMPOWER', abilityParams: { atkPercent: 8, accuracy: 5 }, rankLevel: 3 },
    ]);
    assert.deepEqual(effects.lowHp, { hpThresholdPct: 40, damageBonus: 30, tenacity: 40 });
    assert.deepEqual(effects.revive, { hpPct: 60, times: 1 });
    assert.equal(effects.matkPercent, 10);
    assert.equal(effects.mpRegenPct, 5);
    assert.equal(effects.atkPercent, 24);
    assert.equal(effects.accuracy, 15);
    assert.equal(isEmptyImprintEffects(effects), false);
  });

  await t.test('an unknown ability code is ignored instead of throwing', () => {
    const effects = combineImprintEffects([{
      abilityCode: 'FUTURE_HOOK', abilityParams: { anything: 1 }, rankLevel: 1,
    }]);
    assert.deepEqual(effects, EMPTY_IMPRINT_EFFECTS);
  });
});
