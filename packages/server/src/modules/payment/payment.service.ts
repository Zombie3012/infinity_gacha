import { and, desc, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { iapProducts, masterItems, masters, paymentTransactions } from '../../database/drizzle-schema.js';
import {
  canRefund, formatPrice, isSupportedStore, settlePurchase, settleRefund, verifyReceiptSignature,
} from './payment-rules.js';

export class PaymentError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'PaymentError';
  }
}

const shape = (row: typeof paymentTransactions.$inferSelect) => ({
  ...row,
  priceLabel: formatPrice(row.priceCents, row.currency),
});

export class PaymentService {
  private secret(): string {
    const secret = process.env.PAYMENT_GATEWAY_SECRET ?? '';
    if (!secret) throw new PaymentError('PAYMENT_GATEWAY_NOT_CONFIGURED', 503);
    return secret;
  }

  async products() {
    const rows = await db.select().from(iapProducts)
      .where(eq(iapProducts.isActive, true)).orderBy(iapProducts.sortOrder, iapProducts.code);
    return rows.map(row => ({ ...row, priceLabel: formatPrice(row.priceCents, row.currency) }));
  }

  /** Scenario 1.2: open a PENDING transaction that a store receipt can settle. */
  async checkout(masterId: string, productCode: string, storeInput: string) {
    const store = storeInput.toUpperCase();
    if (!isSupportedStore(store)) throw new PaymentError('Store không hỗ trợ (APPLE | GOOGLE).', 400);
    const [product] = await db.select().from(iapProducts).where(eq(iapProducts.code, productCode)).limit(1);
    if (!product || !product.isActive) throw new PaymentError('Gói nạp không tồn tại.', 404);

    const [row] = await db.insert(paymentTransactions).values({
      id: uuidv4(), masterId, productCode: product.code, store, status: 'PENDING',
      gems: product.gems, silver: product.silver, items: product.items,
      priceCents: product.priceCents, currency: product.currency, createdAt: new Date(),
    }).returning();

    return {
      transactionId: row.id,
      status: row.status,
      store,
      product: { code: product.code, name: product.name, priceLabel: formatPrice(product.priceCents, product.currency) },
    };
  }

  /**
   * Scenario 1.1 / 1.2: validate the store receipt, refuse replays, then grant.
   * Gems first clear any outstanding Gem debt (see settlement rules).
   */
  async confirmReceipt(masterId: string, input: { transactionId?: unknown; storeTransactionId?: unknown; receiptToken?: unknown }) {
    const transactionId = String(input.transactionId ?? '');
    const storeTransactionId = String(input.storeTransactionId ?? '').trim();
    const receiptToken = String(input.receiptToken ?? '');
    if (!/^[A-Za-z0-9_.:-]{3,128}$/.test(storeTransactionId)) throw new PaymentError('storeTransactionId không hợp lệ.', 400);

    const [transaction] = await db.select().from(paymentTransactions)
      .where(and(eq(paymentTransactions.id, transactionId), eq(paymentTransactions.masterId, masterId))).limit(1);
    if (!transaction) throw new PaymentError('Không tìm thấy giao dịch.', 404);
    if (transaction.status !== 'PENDING') throw new PaymentError('Giao dịch đã được xử lý.', 409);

    if (!verifyReceiptSignature(this.secret(), transaction.store, storeTransactionId, receiptToken)) {
      throw new PaymentError('ERR_IAP_INVALID_RECEIPT', 401);
    }

    const [duplicate] = await db.select({ id: paymentTransactions.id }).from(paymentTransactions)
      .where(and(eq(paymentTransactions.store, transaction.store), eq(paymentTransactions.storeTransactionId, storeTransactionId))).limit(1);
    if (duplicate) throw new PaymentError('ERR_IAP_DUPLICATE_RECEIPT', 409);

    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new PaymentError('Không tìm thấy Master.', 404);

    const settlement = settlePurchase(Number(master.gems), Number(master.gemDebt), transaction.gems);
    const now = new Date();

    await db.transaction(async tx => {
      await tx.update(masters).set({
        gems: BigInt(settlement.gems),
        gemDebt: BigInt(settlement.gemDebt),
        ...(transaction.silver > 0 ? { silverCoins: sql`${masters.silverCoins} + ${transaction.silver}` } : {}),
        updatedAt: now,
      }).where(eq(masters.id, masterId));
      for (const item of transaction.items) {
        await tx.insert(masterItems).values({
          id: uuidv4(), masterId, itemId: item.itemId, quantity: item.quantity, updatedAt: now,
        }).onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${item.quantity}`, updatedAt: now },
        });
      }
      await tx.update(paymentTransactions).set({
        status: 'COMPLETED', storeTransactionId, completedAt: now,
      }).where(eq(paymentTransactions.id, transaction.id));
    });

    return {
      transactionId: transaction.id,
      status: 'COMPLETED',
      gemsGranted: transaction.gems,
      gemDebtSettled: settlement.debtSettled,
      gemsCredited: settlement.credited,
      silverGranted: transaction.silver,
      items: transaction.items,
    };
  }

  async history(masterId: string) {
    const rows = await db.select().from(paymentTransactions)
      .where(eq(paymentTransactions.masterId, masterId))
      .orderBy(desc(paymentTransactions.createdAt)).limit(50);
    return rows.map(shape);
  }

  /** Scenarios 2.1/2.2: claw the Gems back and book the shortfall as Gem debt. */
  async refund(transactionId: string, reasonInput: unknown) {
    const reason = String(reasonInput ?? '').slice(0, 500);
    const [transaction] = await db.select().from(paymentTransactions).where(eq(paymentTransactions.id, transactionId)).limit(1);
    if (!transaction) throw new PaymentError('Không tìm thấy giao dịch.', 404);
    if (!canRefund(transaction.status)) throw new PaymentError('Chỉ hoàn tiền giao dịch đã hoàn tất.', 409);

    const [master] = await db.select().from(masters).where(eq(masters.id, transaction.masterId)).limit(1);
    if (!master) throw new PaymentError('Không tìm thấy Master.', 404);

    const settlement = settleRefund(Number(master.gems), Number(master.gemDebt), transaction.gems);
    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(masters).set({
        gems: BigInt(settlement.gems),
        gemDebt: BigInt(settlement.gemDebt),
        updatedAt: now,
      }).where(eq(masters.id, transaction.masterId));
      await tx.update(paymentTransactions).set({
        status: 'REFUNDED', refundedAt: now, refundReason: reason || 'OPERATOR_REFUND',
      }).where(eq(paymentTransactions.id, transaction.id));
    });

    return {
      transactionId: transaction.id,
      status: 'REFUNDED',
      gemsClawedBack: settlement.clawback,
      gemDebtAdded: settlement.shortfall,
      gemDebtTotal: settlement.gemDebt,
    };
  }

  async allTransactions() {
    const rows = await db.select().from(paymentTransactions)
      .orderBy(desc(paymentTransactions.createdAt)).limit(100);
    return rows.map(shape);
  }
}

export const paymentService = new PaymentService();
