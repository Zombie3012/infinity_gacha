import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  RANKING_SIZE, SEASON_DURATION_DAYS, WAR_DURATION_HOURS, WAR_POINTS, WONDER_HOLD_SECONDS,
  accumulateHold, contestOpensAt, decideWar, isContestOpen, isWonderTile, rankAlliances,
  seasonRewardFor, seasonWindow, warRewardFor, warWindow, wonderDefencePower, wonderPointsFor,
  wonderProgress,
} from '../dist/modules/world/conquest-rules.js';

const end = new Date('2026-12-01T00:00:00Z');

test('P3 Conquest - season window and Wonder contest', async (t) => {
  const start = new Date('2026-11-01T00:00:00Z');

  await t.test('a season lasts 30 days', () => {
    const window = seasonWindow(start);
    assert.equal((window.endTime.getTime() - start.getTime()) / 86_400_000, SEASON_DURATION_DAYS);
  });

  await t.test('the Wonder opens 3 days before the season ends', () => {
    assert.equal(contestOpensAt(end).toISOString(), '2026-11-28T00:00:00.000Z');
    assert.equal(isContestOpen({ startTime: start, endTime: end, status: 'ACTIVE' }, new Date('2026-11-27T23:59:59Z')), false);
    assert.equal(isContestOpen({ startTime: start, endTime: end, status: 'ACTIVE' }, new Date('2026-11-28T00:00:00Z')), true);
    assert.equal(isContestOpen({ startTime: start, endTime: end, status: 'CONCLUDED' }, new Date('2026-11-29T00:00:00Z')), false);
  });

  await t.test('holding accrues only inside the contest and caps at 8 hours', () => {
    const heldSince = new Date('2026-11-20T00:00:00Z');
    // Closed window: nothing accrues.
    assert.equal(accumulateHold(0, heldSince, heldSince, new Date('2026-11-27T00:00:00Z'), null), 0);
    // The clock starts at the window opening, not at the capture time.
    const opened = new Date('2026-11-28T00:00:00Z');
    assert.equal(
      accumulateHold(0, heldSince, heldSince, new Date('2026-11-28T01:00:00Z'), contestOpensAt(end)),
      3_600,
    );
    assert.equal(
      accumulateHold(WONDER_HOLD_SECONDS - 10, opened, opened, new Date('2026-11-29T00:00:00Z'), contestOpensAt(end)),
      WONDER_HOLD_SECONDS,
    );
  });

  await t.test('hourly holding pays conquest points exactly once per hour', () => {
    assert.equal(wonderPointsFor(0, 3_599), 0);
    assert.equal(wonderPointsFor(3_599, 3_600), 10);
    assert.equal(wonderPointsFor(7_000, 14_401), 30);
  });

  await t.test('progress is reported in seconds, percent and completion', () => {
    const half = wonderProgress(WONDER_HOLD_SECONDS / 2);
    assert.equal(half.percent, 50);
    assert.equal(half.remainingSeconds, WONDER_HOLD_SECONDS / 2);
    assert.equal(half.complete, false);
    assert.equal(wonderProgress(WONDER_HOLD_SECONDS + 500).complete, true);
  });
});

test('P3 Conquest - war resolution', async (t) => {
  await t.test('wars run for 24 hours', () => {
    const start = new Date('2026-11-04T00:00:00Z');
    assert.equal((warWindow(start).endsAt.getTime() - start.getTime()) / 3_600_000, WAR_DURATION_HOURS);
  });

  await t.test('the higher score wins and equal scores draw', () => {
    const base = { declaringAllianceId: 'A', targetAllianceId: 'B' };
    assert.equal(decideWar({ ...base, declaringPoints: 300, targetPoints: 200 }).winnerAllianceId, 'A');
    assert.equal(decideWar({ ...base, declaringPoints: 100, targetPoints: 250 }).winnerAllianceId, 'B');
    const draw = decideWar({ ...base, declaringPoints: 150, targetPoints: 150 });
    assert.equal(draw.winnerAllianceId, null);
    assert.equal(draw.draw, true);
  });

  await t.test('engagement points are fixed by rule', () => {
    assert.equal(WAR_POINTS.TERRITORY_CAPTURE, 100);
    assert.equal(WAR_POINTS.DEFENSE_HOLD, 50);
    assert.equal(WAR_POINTS.WONDER_SEIZURE, 500);
    assert.equal(WAR_POINTS.WAR_VICTORY, 300);
  });

  await t.test('winner and loser receive different rewards', () => {
    assert.ok(warRewardFor(true).silver > warRewardFor(false).silver);
    assert.ok(warRewardFor(true).gems > 0);
    assert.equal(warRewardFor(false).gems, 0);
  });

  await t.test('the Wonder defence is at least the guardian power', () => {
    assert.equal(wonderDefencePower(0), 25_000);
    assert.ok(wonderDefencePower(100_000) > 25_000);
  });
});

test('P3 Conquest - ranking and season rewards', async (t) => {
  await t.test('ranking sorts by points and shares a rank on ties', () => {
    const ranked = rankAlliances([
      { allianceId: 'C', name: 'Gamma', tag: 'G', points: 100 },
      { allianceId: 'A', name: 'Alpha', tag: 'A', points: 500 },
      { allianceId: 'B', name: 'Beta', tag: 'B', points: 100 },
    ]);
    assert.equal(ranked[0].allianceId, 'A');
    assert.equal(ranked[0].rank, 1);
    assert.equal(ranked[1].rank, 2);
    assert.equal(ranked[2].rank, 2);
    assert.equal(ranked.length, 3);
  });

  await t.test('ranking is capped at the display size', () => {
    const entries = Array.from({ length: 25 }, (_, index) => ({
      allianceId: `A${index}`, name: `Alliance ${index}`, tag: `A${index}`, points: index,
    }));
    assert.equal(rankAlliances(entries).length, RANKING_SIZE);
  });

  await t.test('the top three ranks pay seasonal bundles', () => {
    const first = seasonRewardFor(1);
    assert.equal(first.reward.specialScrolls, 10);
    assert.equal(first.frame, 'CONQUEROR_FRAME');
    assert.ok(seasonRewardFor(2).reward.silver > seasonRewardFor(3).reward.silver);
    assert.equal(seasonRewardFor(9), null);
  });

  await t.test('wonder tiles are recognised by terrain or resource type', () => {
    assert.equal(isWonderTile({ terrain: 'WONDER' }), true);
    assert.equal(isWonderTile({ terrain: 'PLAINS', resourceType: 'WONDER' }), true);
    assert.equal(isWonderTile({ terrain: 'PLAINS', resourceType: 'WOOD' }), false);
  });
});
