import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_BASE_ZONES,
  accruedStored,
  buildingProductionForLevel,
  capacityForLevel,
  demolishRefundSilver,
  dormitoryRecoveryMultiplier,
  dormitoryResidentCapacity,
  expansionCostSilver,
  expansionRequiredWorldLevel,
  levelRateMultiplier,
  libraryMageExpPerHour,
  maxConstructibleCountForType,
  maxWorkersForBuildingLevel,
  plotsForZones,
  productionRatePerHour,
  recoveryCenterTreatmentSlots,
  upgradeCostSilver,
  upgradeMaterials,
  warehouseBonusSlotsForLevel,
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

  await t.test('two base floors each hold eight plots', () => {
    assert.equal(plotsForZones(1), 8);
    assert.equal(plotsForZones(3), 16);
    assert.equal(plotsForZones(MAX_BASE_ZONES + 5), 16);
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

  await t.test('standardized 3-level building rules match specification', () => {
    // Recovery Center: 1 hero, 2/4/6 slots
    assert.equal(maxWorkersForBuildingLevel('MEDICAL', 1), 1);
    assert.deepEqual([1, 2, 3].map(recoveryCenterTreatmentSlots), [2, 4, 6]);

    // Training Center: 3/5/7 heroes, one additional building per 10 floors cleared
    assert.deepEqual([1, 2, 3].map(lvl => maxWorkersForBuildingLevel('TRAINING_CENTER', lvl)), [3, 5, 7]);
    assert.equal(maxConstructibleCountForType('TRAINING_CENTER', 1), 1);
    assert.equal(maxConstructibleCountForType('TRAINING_CENTER', 10), 1);
    assert.equal(maxConstructibleCountForType('TRAINING_CENTER', 11), 2);
    assert.equal(maxConstructibleCountForType('TRAINING_CENTER', 21), 3);

    // Hall of Magic & 3 sub-wings: 6 total (2 per sub-wing)
    assert.equal(maxWorkersForBuildingLevel('HALL_OF_MAGIC', 1), 6);
    assert.equal(maxWorkersForBuildingLevel('LIBRARY', 1), 2);
    assert.equal(maxWorkersForBuildingLevel('ALCHEMY_WORKSHOP', 1), 2);
    assert.equal(maxWorkersForBuildingLevel('MAGIC_RESEARCH_LAB', 1), 2);

    // Library EXP books & Mage direct EXP/hr (25k / 1.25M / 16.5M)
    assert.deepEqual(buildingProductionForLevel('LIBRARY', 1), { resourceType: 'SAMPLE_HERO_EXP_100', ratePerHour: 100, capacity: 1000 });
    assert.deepEqual(buildingProductionForLevel('LIBRARY', 2), { resourceType: 'SAMPLE_HERO_EXP_1000', ratePerHour: 50, capacity: 500 });
    assert.deepEqual(buildingProductionForLevel('LIBRARY', 3), { resourceType: 'SAMPLE_HERO_EXP_10000', ratePerHour: 15, capacity: 150 });
    assert.deepEqual([1, 2, 3].map(libraryMageExpPerHour), [25_000, 1_250_000, 16_500_000]);

    // Alchemy Workshop: 15/30/60 enhancement stones/hr
    assert.deepEqual([1, 2, 3].map(lvl => buildingProductionForLevel('ALCHEMY_WORKSHOP', lvl)?.ratePerHour), [15, 30, 60]);

    // Kitchen: 1/2/3 workers, 20/40/80 food/hr
    assert.deepEqual([1, 2, 3].map(lvl => maxWorkersForBuildingLevel('KITCHEN', lvl)), [1, 2, 3]);
    assert.deepEqual([1, 2, 3].map(lvl => buildingProductionForLevel('KITCHEN', lvl)?.ratePerHour), [20, 40, 80]);

    // Warehouse: 0 workers, +100/+200/+300 slots
    assert.equal(maxWorkersForBuildingLevel('WAREHOUSE', 1), 0);
    assert.deepEqual([1, 2, 3].map(warehouseBonusSlotsForLevel), [100, 200, 300]);

    // Dormitory (HOUSE: 5/7/10 residents, 1.0x/1.5x/2.0x) & Party Mansion (5 residents, 4.0x = x2 of House Lv.3)
    assert.deepEqual([1, 2, 3].map(lvl => dormitoryResidentCapacity('HOUSE', lvl)), [5, 7, 10]);
    assert.deepEqual([1, 2, 3].map(lvl => dormitoryRecoveryMultiplier('HOUSE', lvl)), [1.0, 1.5, 2.0]);
    assert.equal(dormitoryResidentCapacity('PARTY_MANSION', 1), 5);
    assert.equal(dormitoryRecoveryMultiplier('PARTY_MANSION', 1), 4.0);
  });
});
