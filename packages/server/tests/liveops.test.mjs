import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  acceptsClaims,
  acceptsProgress,
  combatPower,
  eventPhase,
  eventWindow,
  majorCooldownViolated,
  overlapsStandard,
  rankCombatPower,
  rankDungeonProgress,
  rewardForRank,
  topCombatPower,
} from '../dist/modules/liveops/liveops-rules.js';

const day = 86_400_000;
const start = new Date('2026-11-10T00:00:00+07:00');

test('P2 LiveOps - event windows', async (t) => {
  await t.test('scenario 3.1: a STANDARD event lasts 14 days plus 48h of claims', () => {
    const { endAt, claimDeadline } = eventWindow(start, 'STANDARD');
    assert.equal(endAt.toISOString(), new Date(start.getTime() + 14 * day).toISOString());
    assert.equal(claimDeadline.getTime() - endAt.getTime(), 48 * 3_600_000);
  });

  await t.test('event phases follow scheduled → active → grace → ended', () => {
    const { endAt, claimDeadline } = eventWindow(start, 'STANDARD');
    assert.equal(eventPhase(start, endAt, claimDeadline, new Date(start.getTime() - day)), 'SCHEDULED');
    assert.equal(eventPhase(start, endAt, claimDeadline, new Date(start.getTime() + day)), 'ACTIVE');
    assert.equal(eventPhase(start, endAt, claimDeadline, new Date(endAt.getTime() + 3_600_000)), 'GRACE');
    assert.equal(eventPhase(start, endAt, claimDeadline, new Date(claimDeadline.getTime() + 1)), 'ENDED');
  });

  await t.test('scenario 3.4: progress stops at end_at but claims stay open', () => {
    const { endAt, claimDeadline } = eventWindow(start, 'STANDARD');
    const inGrace = new Date(endAt.getTime() + 3_600_000);
    assert.equal(acceptsProgress(start, endAt, inGrace), false);
    assert.equal(acceptsClaims(claimDeadline, inGrace), true);
  });

  await t.test('scenario 3.2: overlapping STANDARD events are detected', () => {
    const first = { startAt: start, endAt: new Date(start.getTime() + 14 * day) };
    const second = { startAt: new Date(start.getTime() + 9 * day), endAt: new Date(start.getTime() + 23 * day) };
    assert.equal(overlapsStandard(second, [first]), true);
    const later = { startAt: new Date(start.getTime() + 20 * day), endAt: new Date(start.getTime() + 34 * day) };
    assert.equal(overlapsStandard(later, [first]), false);
  });

  await t.test('scenario 3.3: MAJOR events need seven clear days', () => {
    const previousEnd = new Date('2026-11-15T00:00:00+07:00');
    assert.equal(majorCooldownViolated(new Date('2026-11-18T00:00:00+07:00'), previousEnd), true);
    assert.equal(majorCooldownViolated(new Date('2026-11-23T00:00:00+07:00'), previousEnd), false);
    assert.equal(majorCooldownViolated(start, null), false);
  });
});

test('P2 LiveOps - leaderboards', async (t) => {
  await t.test('scenario 4.1: same floor ranks the faster clear higher', () => {
    const ranked = rankDungeonProgress([
      { masterId: 'A', floor: 50, rounds: 12, combatPower: 0 },
      { masterId: 'B', floor: 50, rounds: 9, combatPower: 0 },
    ]);
    assert.equal(ranked[0].masterId, 'B');
    assert.equal(ranked[1].masterId, 'A');
  });

  await t.test('higher floors always rank above lower floors', () => {
    const ranked = rankDungeonProgress([
      { masterId: 'A', floor: 49, rounds: 1, combatPower: 0 },
      { masterId: 'B', floor: 50, rounds: 40, combatPower: 0 },
    ]);
    assert.equal(ranked[0].masterId, 'B');
  });

  await t.test('scenario 4.2: combat power sums five strongest Heroes', () => {
    const hero = { hp: 1000, attack: 100, defense: 80, speed: 40 };
    assert.equal(combatPower(hero), 100 * 3 + 80 * 2 + 40 * 2 + 100);
    const heroes = Array.from({ length: 7 }, (_, index) => ({ hp: 1000, attack: 100 + index, defense: 80, speed: 40 }));
    const top5 = heroes.slice(2).reduce((sum, row) => sum + combatPower(row), 0);
    assert.equal(topCombatPower(heroes, 5), top5);
  });

  await t.test('combat power ranking sorts descending', () => {
    const ranked = rankCombatPower([
      { masterId: 'A', floor: 1, rounds: 0, combatPower: 150000 },
      { masterId: 'B', floor: 1, rounds: 0, combatPower: 180000 },
    ]);
    assert.equal(ranked[0].masterId, 'B');
    assert.equal(ranked[0].rank, 1);
  });

  await t.test('season rewards shrink by tier and stop after rank 50', () => {
    assert.deepEqual(rewardForRank(1), { silver: 50000, gems: 300 });
    assert.equal(rewardForRank(3)?.gems, 150);
    assert.equal(rewardForRank(10)?.gems, 80);
    assert.equal(rewardForRank(50)?.gems, 20);
    assert.equal(rewardForRank(51), null);
  });
});
