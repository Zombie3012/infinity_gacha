import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  applyActivity,
  applyDrift,
  baseFoodConsumption,
  checkActivityRefusal,
  fatigueState,
  housingCapacityFor,
  housingRecoveryMultiplierFor,
  hungerState,
  isImmobilised,
  rationsFor,
  starvationMultiplier,
} from '../dist/modules/survival/survival-rules.js';

const start = new Date('2026-01-01T00:00:00Z');
const after = (hours) => new Date(start.getTime() + hours * 3_600_000);

test('DM-09 Survival - hunger tracking', async (t) => {
  await t.test('scenario 9.1: 10 + 5 hours + 2 battles = 31 (Satisfied)', () => {
    const drift = applyDrift({ hungerScore: 10, fatigueScore: 0, isResting: false, lastTickAt: start }, after(5), true);
    assert.equal(drift.hungerScore, 15);
    const firstBattle = applyActivity(drift.hungerScore, drift.fatigueScore, 'BATTLE');
    const secondBattle = applyActivity(firstBattle.hungerScore, firstBattle.fatigueScore, 'BATTLE');
    assert.equal(secondBattle.hungerScore, 31);
    assert.equal(hungerState(31), 'SATISFIED');
  });

  await t.test('hunger states follow the approved tiers', () => {
    assert.equal(hungerState(0), 'FULL');
    assert.equal(hungerState(9), 'FULL');
    assert.equal(hungerState(39), 'SATISFIED');
    assert.equal(hungerState(45), 'HUNGRY');
    assert.equal(hungerState(85), 'STARVING');
    assert.equal(hungerState(100), 'CRITICAL');
  });

  await t.test('an empty warehouse doubles the hunger rate', () => {
    const withFood = applyDrift({ hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: start }, after(10), true);
    const withoutFood = applyDrift({ hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: start }, after(10), false);
    assert.equal(withFood.hungerScore, 10);
    assert.equal(withoutFood.hungerScore, 20);
  });

  await t.test('scenario 9.2: starving Heroes fight at 60% ATK/DEF', () => {
    assert.equal(starvationMultiplier(85), 0.6);
    assert.equal(starvationMultiplier(40), 1);
  });

  await t.test('critical hunger immobilises the Hero', () => {
    assert.equal(isImmobilised(100, 10), true);
    assert.equal(isImmobilised(10, 100), true);
    assert.equal(isImmobilised(99, 99), false);
  });

  await t.test('activity refusal thresholds for Tower (60), Dungeon (80) and Any (90)', () => {
    assert.equal(checkActivityRefusal(59, 59, 'TOWER').refused, false);
    assert.deepEqual(checkActivityRefusal(10, 60, 'TOWER'), { refused: true, reason: 'FATIGUE', threshold: 60 });
    assert.deepEqual(checkActivityRefusal(60, 10, 'TOWER'), { refused: true, reason: 'HUNGER', threshold: 60 });

    assert.equal(checkActivityRefusal(79, 79, 'DUNGEON').refused, false);
    assert.deepEqual(checkActivityRefusal(10, 80, 'DUNGEON'), { refused: true, reason: 'FATIGUE', threshold: 80 });
    assert.deepEqual(checkActivityRefusal(80, 10, 'DUNGEON'), { refused: true, reason: 'HUNGER', threshold: 80 });

    assert.equal(checkActivityRefusal(89, 89, 'ANY').refused, false);
    assert.deepEqual(checkActivityRefusal(10, 90, 'ANY'), { refused: true, reason: 'FATIGUE', threshold: 90 });
    assert.deepEqual(checkActivityRefusal(90, 10, 'ANY'), { refused: true, reason: 'HUNGER', threshold: 90 });
  });

  await t.test('housing capacities and recovery multipliers for Dormitory and Party Mansion', () => {
    assert.equal(housingCapacityFor('HOUSE', 1), 5);
    assert.equal(housingCapacityFor('HOUSE', 2), 7);
    assert.equal(housingCapacityFor('HOUSE', 3), 10);
    assert.equal(housingCapacityFor('PARTY_MANSION', 1), 5);
    assert.equal(housingRecoveryMultiplierFor('HOUSE', 1), 1.0);
    assert.equal(housingRecoveryMultiplierFor('HOUSE', 2), 1.5);
    assert.equal(housingRecoveryMultiplierFor('HOUSE', 3), 2.0);
    assert.equal(housingRecoveryMultiplierFor('PARTY_MANSION', 1), 4.0);
  });
});

test('DM-09 Survival - fatigue and resting', async (t) => {
  await t.test('scenario 10.2: four hours in a Dormitory bed removes 60 points', () => {
    const drift = applyDrift({ hungerScore: 0, fatigueScore: 80, isResting: true, lastTickAt: start }, after(4), true);
    assert.equal(drift.fatigueScore, 20);
    assert.equal(drift.fatigueState, 'NORMAL');
  });

  await t.test('awake Heroes gain 2 fatigue per hour', () => {
    const drift = applyDrift({ hungerScore: 0, fatigueScore: 0, isResting: false, lastTickAt: start }, after(5), true);
    assert.equal(drift.fatigueScore, 10);
  });

  await t.test('resting stops once fatigue reaches zero', () => {
    const drift = applyDrift({ hungerScore: 0, fatigueScore: 10, isResting: true, lastTickAt: start }, after(5), true);
    assert.equal(drift.fatigueScore, 0);
    assert.equal(drift.isResting, false);
  });

  await t.test('a labour shift adds +5 hunger and +8 fatigue (scenario 8.2)', () => {
    assert.deepEqual(applyActivity(10, 20, 'SHIFT'), { hungerScore: 15, fatigueScore: 28 });
  });

  await t.test('fatigue tiers reach OVEREXHAUSTED at 100', () => {
    assert.equal(fatigueState(0), 'RESTED');
    assert.equal(fatigueState(25), 'NORMAL');
    assert.equal(fatigueState(45), 'TIRED');
    assert.equal(fatigueState(65), 'EXHAUSTED');
    assert.equal(fatigueState(85), 'CRITICAL');
    assert.equal(fatigueState(100), 'OVEREXHAUSTED');
  });
});

test('DM-09 Survival - food logistics', async (t) => {
  await t.test('scenario 11.1: a four Hero dungeon run costs 40 rations', () => {
    assert.equal(rationsFor('DUNGEON', 4), 40);
    assert.equal(rationsFor('WAR', 4), 60);
    assert.equal(rationsFor('DUNGEON', 0), 0);
  });

  await t.test('base upkeep is two meals per Hero per day', () => {
    assert.equal(baseFoodConsumption(4, 24), 8);
    assert.equal(baseFoodConsumption(4, 12), 4);
  });
});
