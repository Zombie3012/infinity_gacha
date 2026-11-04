import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  COMPENSATION_LIMITS,
  hasCompensationValue,
  isRestrictionStatus,
  isValidContentCode,
  normalizeCompensation,
  validateCompensation,
} from '../dist/modules/admin/admin-rules.js';

test('P2 Admin - account restriction', async (t) => {
  await t.test('only SUSPENDED and BANNED are operator restrictions', () => {
    assert.equal(isRestrictionStatus('SUSPENDED'), true);
    assert.equal(isRestrictionStatus('BANNED'), true);
    assert.equal(isRestrictionStatus('ACTIVE'), false);
    assert.equal(isRestrictionStatus('deleted'), false);
  });
});

test('P2 Admin - compensation payloads', async (t) => {
  await t.test('compensation is normalised and empty rows are dropped', () => {
    const value = normalizeCompensation({
      silver: 5000,
      gems: 10,
      items: [{ itemId: 'food', quantity: 2 }, { itemId: 'WOOD', quantity: 0 }, { itemId: 'BAD ID', quantity: 3 }],
    });
    assert.equal(value.silver, 5000);
    assert.equal(value.gems, 10);
    assert.deepEqual(value.items, [{ itemId: 'FOOD', quantity: 2 }]);
    assert.equal(hasCompensationValue(value), true);
  });

  await t.test('an empty compensation is rejected', () => {
    assert.equal(hasCompensationValue(normalizeCompensation({})), false);
  });

  await t.test('caps protect against mistyped payloads', () => {
    assert.equal(validateCompensation({ silver: COMPENSATION_LIMITS.silver, gems: 0, items: [] }), null);
    assert.equal(validateCompensation({ silver: COMPENSATION_LIMITS.silver + 1, gems: 0, items: [] }), 'ERR_COMPENSATION_SILVER_TOO_HIGH');
    assert.equal(validateCompensation({ silver: 0, gems: COMPENSATION_LIMITS.gems + 1, items: [] }), 'ERR_COMPENSATION_GEMS_TOO_HIGH');
    assert.equal(validateCompensation({ silver: 0, gems: 0, items: [{ itemId: 'FOOD', quantity: COMPENSATION_LIMITS.itemQuantity + 1 }] }), 'ERR_COMPENSATION_ITEM_TOO_HIGH');
  });

  await t.test('content codes are uppercase identifiers', () => {
    assert.equal(isValidContentCode('HERO_KNIGHT_01'), true);
    assert.equal(isValidContentCode('lowercase'), false);
    assert.equal(isValidContentCode('WITH SPACE'), false);
  });
});
