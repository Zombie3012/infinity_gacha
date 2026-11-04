import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canRefund,
  formatPrice,
  isSupportedStore,
  receiptSignature,
  settlePurchase,
  settleRefund,
  verifyReceiptSignature,
} from '../dist/modules/payment/payment-rules.js';

const secret = 'test-payment-secret';

test('P2 IAP - receipt verification', async (t) => {
  await t.test('scenario 1.1: a valid store receipt verifies', () => {
    const signature = receiptSignature(secret, 'APPLE', 'TX_APPLE_88888');
    assert.equal(verifyReceiptSignature(secret, 'APPLE', 'TX_APPLE_88888', signature), true);
  });

  await t.test('a receipt for another transaction or store is rejected', () => {
    const signature = receiptSignature(secret, 'APPLE', 'TX_APPLE_88888');
    assert.equal(verifyReceiptSignature(secret, 'GOOGLE', 'TX_APPLE_88888', signature), false);
    assert.equal(verifyReceiptSignature(secret, 'APPLE', 'TX_OTHER', signature), false);
    assert.equal(verifyReceiptSignature('', 'APPLE', 'TX_APPLE_88888', signature), false);
  });

  await t.test('only Apple and Google stores are accepted', () => {
    assert.equal(isSupportedStore('APPLE'), true);
    assert.equal(isSupportedStore('GOOGLE'), true);
    assert.equal(isSupportedStore('STEAM'), false);
  });

  await t.test('prices render with two decimals', () => {
    assert.equal(formatPrice(999), '$9.99');
    assert.equal(formatPrice(1999, 'USD'), '$19.99');
    assert.equal(formatPrice(1000, 'EUR'), '10.00 EUR');
  });
});

test('P2 IAP - Gem debt accounting', async (t) => {
  await t.test('purchased Gems clear debt before they are credited', () => {
    const result = settlePurchase(0, 300, 1000);
    assert.equal(result.debtSettled, 300);
    assert.equal(result.credited, 700);
    assert.equal(result.gems, 700);
    assert.equal(result.gemDebt, 0);
  });

  await t.test('without debt the full purchase is credited', () => {
    assert.deepEqual(settlePurchase(150, 0, 1000), { gems: 1150, gemDebt: 0, debtSettled: 0, credited: 1000 });
  });

  await t.test('scenario 2.1: refund with enough balance just debits the wallet', () => {
    assert.deepEqual(settleRefund(1500, 0, 1000), { gems: 500, gemDebt: 0, clawback: 1000, shortfall: 0 });
  });

  await t.test('scenario 2.2: refund after spending books the shortfall as Gem debt', () => {
    assert.deepEqual(settleRefund(200, 0, 1000), { gems: 0, gemDebt: 800, clawback: 200, shortfall: 800 });
  });

  await t.test('existing debt is preserved and increased by a new shortfall', () => {
    const result = settleRefund(100, 50, 400);
    assert.equal(result.gems, 0);
    assert.equal(result.gemDebt, 350);
  });

  await t.test('only completed transactions can be refunded', () => {
    assert.equal(canRefund('COMPLETED'), true);
    assert.equal(canRefund('REFUNDED'), false);
    assert.equal(canRefund('PENDING'), false);
  });
});
