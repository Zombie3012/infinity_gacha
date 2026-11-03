import { and, desc, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  masters,
  masterSummonInventory,
  currencyTransactions,
  weeklyScrollExchanges,
} from '../../database/drizzle-schema.js';
import { GAME_CONSTANTS } from '@infiniti-gacha/shared';
import { getWeeklyExchangePeriodKey } from './scroll-exchange.service.js';

export class CurrencyError extends Error {
  constructor(message: string, public readonly statusCode = 400) {
    super(message);
    this.name = 'CurrencyError';
  }
}

export class CurrencyService {
  /**
   * FUN-11-01-001: View Currency balances (Silver & Summon Tickets).
   */
  public async getBalances(masterId: string) {
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new CurrencyError('Master không tồn tại.', 404);

    const scrolls = await db.select().from(masterSummonInventory)
      .where(eq(masterSummonInventory.masterId, masterId));

    const periodKey = getWeeklyExchangePeriodKey();
    const [exchange] = await db.select().from(weeklyScrollExchanges)
      .where(and(eq(weeklyScrollExchanges.masterId, masterId), eq(weeklyScrollExchanges.periodKey, periodKey))).limit(1);

    const normalScrolls = scrolls.find(s => s.scrollType === 'NORMAL')?.quantity ?? 0;
    const specialScrolls = scrolls.find(s => s.scrollType === 'SPECIAL')?.quantity ?? 0;

    return {
      masterId,
      silverCoins: master.silverCoins.toString(),
      summonTickets: {
        normal: normalScrolls,
        special: specialScrolls,
      },
      weeklyExchange: {
        periodKey,
        exchanged: exchange?.quantity ?? 0,
        weeklyCap: GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP,
        remainingCap: Math.max(0, GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP - (exchange?.quantity ?? 0)),
      },
    };
  }

  /**
   * FUN-11-01-004: Validate Balance.
   */
  public async validateBalance(masterId: string, required: { silver?: bigint | number; normalScrolls?: number; specialScrolls?: number }): Promise<boolean> {
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) return false;

    if (required.silver !== undefined) {
      const requiredSilver = BigInt(required.silver);
      if (master.silverCoins < requiredSilver) return false;
    }

    if (required.normalScrolls !== undefined || required.specialScrolls !== undefined) {
      const scrolls = await db.select().from(masterSummonInventory).where(eq(masterSummonInventory.masterId, masterId));
      if (required.normalScrolls !== undefined) {
        const has = scrolls.find(s => s.scrollType === 'NORMAL')?.quantity ?? 0;
        if (has < required.normalScrolls) return false;
      }
      if (required.specialScrolls !== undefined) {
        const has = scrolls.find(s => s.scrollType === 'SPECIAL')?.quantity ?? 0;
        if (has < required.specialScrolls) return false;
      }
    }

    return true;
  }

  /**
   * FUN-11-01-002: Add Currency (Silver or Tickets).
   */
  public async addCurrency(
    masterId: string,
    params: { silverDelta?: bigint | number; scrollType?: 'NORMAL' | 'SPECIAL'; scrollDelta?: number; transactionType: string }
  ) {
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new CurrencyError('Master không tồn tại.', 404);

      if (params.silverDelta && params.silverDelta > 0) {
        const delta = BigInt(params.silverDelta);
        const nextSilver = master.silverCoins + delta;
        await tx.update(masters).set({ silverCoins: nextSilver, updatedAt: new Date() }).where(eq(masters.id, masterId));

        await tx.insert(currencyTransactions).values({
          id: uuidv4(),
          masterId,
          currencyType: 'SILVER',
          amountDelta: delta,
          transactionType: params.transactionType,
          createdAt: new Date(),
        });
      }

      if (params.scrollType && params.scrollDelta && params.scrollDelta > 0) {
        await tx.insert(masterSummonInventory).values({
          id: uuidv4(),
          masterId,
          scrollType: params.scrollType,
          quantity: params.scrollDelta,
          updatedAt: new Date(),
        }).onConflictDoUpdate({
          target: [masterSummonInventory.masterId, masterSummonInventory.scrollType],
          set: {
            quantity: sql`${masterSummonInventory.quantity} + ${params.scrollDelta}`,
            updatedAt: new Date(),
          },
        });
      }

      return this.getBalances(masterId);
    });
  }

  /**
   * FUN-11-01-003: Deduct Currency (Silver or Tickets).
   */
  public async deductCurrency(
    masterId: string,
    params: { silverCost?: bigint | number; scrollType?: 'NORMAL' | 'SPECIAL'; scrollCost?: number; transactionType: string }
  ) {
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new CurrencyError('Master không tồn tại.', 404);

      if (params.silverCost && params.silverCost > 0) {
        const cost = BigInt(params.silverCost);
        if (master.silverCoins < cost) {
          throw new CurrencyError('Không đủ Xu Bạc.', 409);
        }
        const nextSilver = master.silverCoins - cost;

        await tx.update(masters).set({ silverCoins: nextSilver, updatedAt: new Date() }).where(eq(masters.id, masterId));

        await tx.insert(currencyTransactions).values({
          id: uuidv4(),
          masterId,
          currencyType: 'SILVER',
          amountDelta: -cost,
          transactionType: params.transactionType,
          createdAt: new Date(),
        });
      }

      if (params.scrollType && params.scrollCost && params.scrollCost > 0) {
        const [scrollRow] = await tx.select().from(masterSummonInventory)
          .where(and(eq(masterSummonInventory.masterId, masterId), eq(masterSummonInventory.scrollType, params.scrollType))).for('update').limit(1);

        if (!scrollRow || scrollRow.quantity < params.scrollCost) {
          throw new CurrencyError(`Không đủ vé triệu hồi ${params.scrollType}.`, 409);
        }

        await tx.update(masterSummonInventory).set({
          quantity: scrollRow.quantity - params.scrollCost,
          updatedAt: new Date(),
        }).where(eq(masterSummonInventory.id, scrollRow.id));
      }

      return this.getBalances(masterId);
    });
  }

  /**
   * FUN-11-01-005: View Currency Transactions history.
   */
  public async listTransactions(masterId: string, limit = 50) {
    return db.select().from(currencyTransactions)
      .where(eq(currencyTransactions.masterId, masterId))
      .orderBy(desc(currencyTransactions.createdAt))
      .limit(limit);
  }
}

export const currencyService = new CurrencyService();
