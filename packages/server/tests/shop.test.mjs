import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  dailyPeriodKey,
  isAvailableNow,
  isExpired,
  localWeekday,
  mailExpiresAt,
  normalizeAttachments,
  resolvePurchaseQuantity,
  totalSilverFor,
} from '../dist/modules/shop/shop-rules.js';

test('DM-11 Shop - purchase limits and rotation', async (t) => {
  await t.test('scenario 13.1: four of five daily units bought, requesting two yields one', () => {
    const result = resolvePurchaseQuantity(1, 2);
    assert.equal(result.allowed, 1);
    assert.equal(result.blocked, true);
  });

  await t.test('within the limit the full request is allowed', () => {
    assert.deepEqual(resolvePurchaseQuantity(5, 2), { allowed: 2, blocked: false });
  });

  await t.test('an exhausted limit blocks the purchase entirely', () => {
    assert.deepEqual(resolvePurchaseQuantity(0, 3), { allowed: 0, blocked: true });
  });

  await t.test('unlimited items ignore the counter', () => {
    assert.deepEqual(resolvePurchaseQuantity(null, 7), { allowed: 7, blocked: false });
  });

  await t.test('daily period keys follow UTC+7 midnight', () => {
    assert.equal(dailyPeriodKey(new Date('2026-11-04T16:59:00Z')), '2026-11-04');
    assert.equal(dailyPeriodKey(new Date('2026-11-04T17:00:00Z')), '2026-11-05');
  });

  await t.test('rotating items are only purchasable on their weekdays', () => {
    const sunday = new Date('2026-11-01T03:00:00Z');
    assert.equal(localWeekday(sunday), 0);
    assert.equal(isAvailableNow([0, 6], sunday), true);
    assert.equal(isAvailableNow([1], sunday), false);
    assert.equal(isAvailableNow([], sunday), true);
  });

  await t.test('purchase totals multiply price by quantity', () => {
    assert.equal(totalSilverFor(500, 3), 1500);
  });
});

test('DM-11 Mailbox - attachments and expiry', async (t) => {
  await t.test('scenario 14.1 attachments are normalised', () => {
    const attachments = normalizeAttachments({ silver: 5000, items: [{ itemId: 'FOOD', quantity: 2 }, { itemId: '', quantity: 3 }, { itemId: 'WOOD', quantity: 0 }] });
    assert.equal(attachments.silver, 5000);
    assert.deepEqual(attachments.items, [{ itemId: 'FOOD', quantity: 2 }]);
  });

  await t.test('mail expires 30 days after it is sent', () => {
    const sent = new Date('2026-10-01T00:00:00Z');
    const expires = mailExpiresAt(sent);
    assert.equal(expires.toISOString().slice(0, 10), '2026-10-31');
    assert.equal(isExpired(expires, new Date('2026-11-15T00:00:00Z')), true);
    assert.equal(isExpired(expires, new Date('2026-10-15T00:00:00Z')), false);
  });
});
