import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_BASE_ZONES,
  accruedStored,
  capacityForLevel,
  demolishRefundSilver,
  expansionCostSilver,
  expansionRequiredWorldLevel,
  levelRateMultiplier,
  plotsForZones,
  productionRatePerHour,
  upgradeCostSilver,
  upgradeMaterials,
  worldLevelForFloor,
} from '../dist/modules/base/base-rules.js';
import { workerBoostForLevel } from '../dist/modules/base/building.service.js';

test('DM-08 Base - world progress and expansion', async (t) => {
  await t.test('world level rises every three cleared floors', () => {
    assert.equal(worldLevelForFloor(1), 1);
    assert.equal(worldLevelForFloor(3), 1);
    assert.equal(worldLevelForFloor(4), 2);
    assert.equal(worldLevelForFloor(7), 3);
    assert.equal(worldLevelForFloor(999), 10);
  });

  await t.test('each zone holds eight plots, capped at six zones', () => {
    assert.equal(plotsForZones(1), 8);
    assert.equal(plotsForZones(3), 24);
    assert.equal(plotsForZones(MAX_BASE_ZONES + 5), 48);
  });

  await t.test('zone 3 costs 5,000 Silver and requires world level 2 (scenario 7.1)', () => {
    assert.equal(expansionCostSilver(1), 2000);
    assert.equal(expansionCostSilver(2), 5000);
    assert.equal(expansionRequiredWorldLevel(3), 2);
    assert.equal(expansionRequiredWorldLevel(2), 1);
  });
});

test('DM-08 Base - production and capacity', async (t) => {
  await t.test('workers add their boost on top of the base rate (scenario 8.2)', () => {
    assert.equal(productionRatePerHour(100, 1, []), 100);
    assert.equal(productionRatePerHour(100, 1, [1.2]), 120);
    assert.equal(productionRatePerHour(100, 1, [1.2, 1.1]), 130);
  });

  await t.test('each level adds 60% of the base rate (scenario 7.2)', () => {
    assert.equal(levelRateMultiplier(1), 1);
    assert.equal(levelRateMultiplier(2), 1.6);
    assert.equal(productionRatePerHour(50, 2, []), 80);
    assert.equal(capacityForLevel(500, 2), 1000);
  });

  await t.test('offline production fills to capacity and pauses (scenario 8.1)', () => {
    const start = new Date('2026-01-01T00:00:00Z');
    const tenHours = new Date(start.getTime() + 10 * 3600_000);
    const twelveHours = new Date(start.getTime() + 12 * 3600_000);

    const atTen = accruedStored(0, 100, start, 1000, tenHours);
    assert.equal(atTen.stored, 1000);
    assert.equal(atTen.atCapacity, true);

    const atTwelve = accruedStored(0, 100, start, 1000, twelveHours);
    assert.equal(atTwelve.stored, 1000, 'stored resources must not be lost while paused');
    assert.equal(atTwelve.atCapacity, true);
  });

  await t.test('partial production accrues proportionally', () => {
    const start = new Date('2026-01-01T00:00:00Z');
    const result = accruedStored(0, 60, start, 1000, new Date(start.getTime() + 90 * 60_000));
    assert.equal(result.stored, 90);
    assert.equal(result.atCapacity, false);
  });
});

test('DM-08 Base - building economy', async (t) => {
  await t.test('upgrade cost grows with the target level', () => {
    assert.equal(upgradeCostSilver(1200, 2), 1800);
    assert.equal(upgradeCostSilver(1200, 3), 2700);
    assert.deepEqual(upgradeMaterials(2), [
      { itemId: 'WOOD', quantity: 20 },
      { itemId: 'STONE', quantity: 10 },
    ]);
  });

  await t.test('demolition refunds half of the invested Silver', () => {
    assert.equal(demolishRefundSilver(1200, 1), 600);
    assert.equal(demolishRefundSilver(1200, 2), Math.floor((1200 + 1800) * 0.5));
  });

  await t.test('worker efficiency is +5% per Hero level, capped at +25%', () => {
    assert.equal(workerBoostForLevel(1), 1.05);
    assert.equal(workerBoostForLevel(4), 1.2);
    assert.equal(workerBoostForLevel(20), 1.25);
  });
});
