import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  clampProgress,
  dailyPeriodKey,
  isClaimable,
  normalizeReward,
  periodKeyFor,
  selectDailyQuestCodes,
  statusFor,
  weeklyPeriodKey,
} from '../dist/modules/quest/quest-rules.js';

test('DM-12 Quests - periods', async (t) => {
  await t.test('daily keys roll over at 00:00 UTC+7', () => {
    assert.equal(dailyPeriodKey(new Date('2026-11-04T16:59:00Z')), '2026-11-04');
    assert.equal(dailyPeriodKey(new Date('2026-11-04T17:00:00Z')), '2026-11-05');
  });

  await t.test('scenario 16.2: weekly keys start on Thursday 00:00 UTC+7', () => {
    // 2026-11-04 is a Wednesday, so the week started on Thursday 2026-10-29.
    assert.equal(weeklyPeriodKey(new Date('2026-11-04T03:00:00Z')), 'W2026-10-29');
    // Thursday 2026-11-05 00:00 UTC+7 = 2026-11-04T17:00Z starts a new week.
    assert.equal(weeklyPeriodKey(new Date('2026-11-04T17:00:00Z')), 'W2026-11-05');
  });

  await t.test('main and side quests use an empty period key', () => {
    assert.equal(periodKeyFor('MAIN', new Date()), '');
    assert.equal(periodKeyFor('SIDE', new Date()), '');
  });
});

test('DM-12 Quests - progress and status', async (t) => {
  await t.test('progress is capped at the objective target', () => {
    assert.equal(clampProgress(0, 3, 2), 2);
    assert.equal(clampProgress(1, 1, 5), 2);
  });

  await t.test('quests flip to COMPLETED when the target is met', () => {
    assert.equal(statusFor(0, 2, 'ACTIVE'), 'ACTIVE');
    assert.equal(statusFor(2, 2, 'ACTIVE'), 'COMPLETED');
    assert.equal(statusFor(2, 2, 'CLAIMED'), 'CLAIMED');
    assert.equal(isClaimable('COMPLETED'), true);
    assert.equal(isClaimable('ACTIVE'), false);
  });

  await t.test('daily quest selection is deterministic for a date and returns five codes', () => {
    const pool = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    const date = new Date('2026-11-04T03:00:00Z');
    const first = selectDailyQuestCodes(pool, date, 5);
    assert.equal(first.length, 5);
    assert.deepEqual(first, selectDailyQuestCodes(pool, date, 5));
    assert.notDeepEqual(first, selectDailyQuestCodes(pool, new Date('2026-11-05T03:00:00Z'), 5));
  });

  await t.test('rewards are normalised', () => {
    const reward = normalizeReward({ silver: 500, gems: 10, items: [{ itemId: 'FOOD', quantity: 2 }, { itemId: '', quantity: 1 }] });
    assert.equal(reward.silver, 500);
    assert.equal(reward.gems, 10);
    assert.deepEqual(reward.items, [{ itemId: 'FOOD', quantity: 2 }]);
  });
});
