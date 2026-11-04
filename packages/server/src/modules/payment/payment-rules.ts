import { createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Domain 11 (P2) IAP rules.
 *
 * The prototype cannot reach Apple/Google, so a store receipt is simulated with
 * HMAC-SHA256(`store:storeTransactionId`) keyed by PAYMENT_GATEWAY_SECRET. The
 * accounting rules (Gem debt settlement and refund claw-back) are real maths and
 * are unit-tested.
 */

export const SUPPORTED_STORES = ['APPLE', 'GOOGLE'] as const;
export type StoreType = (typeof SUPPORTED_STORES)[number];

export function isSupportedStore(value: string): value is StoreType {
  return (SUPPORTED_STORES as readonly string[]).includes(value);
}

export function receiptSignature(secret: string, store: string, storeTransactionId: string): string {
  return createHmac('sha256', secret).update(`${store}:${storeTransactionId}`).digest('hex');
}

export function verifyReceiptSignature(secret: string, store: string, storeTransactionId: string, supplied: string): boolean {
  if (!secret || !supplied) return false;
  const expected = Buffer.from(receiptSignature(secret, store, storeTransactionId));
  const actual = Buffer.from(supplied.trim().toLowerCase());
  if (expected.length !== actual.length) return false;
  return timingSafeEqual(expected, actual);
}

export interface GemSettlement {
  gems: number;
  gemDebt: number;
  debtSettled: number;
  credited: number;
}

/** Scenario 1.6: purchased Gems clear outstanding debt before they are spendable. */
export function settlePurchase(balanceGems: number, gemDebt: number, purchasedGems: number): GemSettlement {
  const balance = Math.max(0, Math.floor(balanceGems));
  const debt = Math.max(0, Math.floor(gemDebt));
  const purchase = Math.max(0, Math.floor(purchasedGems));
  const debtSettled = Math.min(debt, purchase);
  const credited = purchase - debtSettled;
  return { gems: balance + credited, gemDebt: debt - debtSettled, debtSettled, credited };
}

export interface RefundSettlement {
  gems: number;
  gemDebt: number;
  clawback: number;
  shortfall: number;
}

/** Scenario 2.1/2.2: a refund takes what is left and books the rest as Gem debt. */
export function settleRefund(balanceGems: number, gemDebt: number, refundGems: number): RefundSettlement {
  const balance = Math.max(0, Math.floor(balanceGems));
  const debt = Math.max(0, Math.floor(gemDebt));
  const refund = Math.max(0, Math.floor(refundGems));
  const clawback = Math.min(balance, refund);
  const shortfall = refund - clawback;
  return { gems: balance - clawback, gemDebt: debt + shortfall, clawback, shortfall };
}

export function formatPrice(amountCents: number, currency = 'USD'): string {
  const amount = Math.max(0, Math.floor(amountCents)) / 100;
  return `${currency === 'USD' ? '$' : ''}${amount.toFixed(2)}${currency === 'USD' ? '' : ` ${currency}`}`;
}

/** Refunds are only allowed against a completed, not-yet-refunded transaction. */
export function canRefund(status: string): boolean {
  return status === 'COMPLETED';
}
