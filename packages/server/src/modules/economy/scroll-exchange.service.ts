import { and, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { currencyTransactions, masters, masterSummonInventory, weeklyScrollExchanges } from '../../database/drizzle-schema.js';
import { GAME_CONSTANTS } from '@infiniti-gacha/shared';

export class ScrollExchangeError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

export function getWeeklyExchangePeriodKey(now = new Date()): string {
  const utcPlusSeven = new Date(now.getTime() + 7 * 60 * 60 * 1000);
  const daysSinceThursday = (utcPlusSeven.getUTCDay() - 4 + 7) % 7;
  utcPlusSeven.setUTCDate(utcPlusSeven.getUTCDate() - daysSinceThursday);
  utcPlusSeven.setUTCHours(0, 0, 0, 0);
  return utcPlusSeven.toISOString().slice(0, 10);
}

export async function exchangeSilverForNormalScrolls(masterId: string, amount: number, now = new Date()) {
  if (!Number.isInteger(amount) || amount < 1 || amount > GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP) {
    throw new ScrollExchangeError('Số Thiên Thư cần đổi phải là số nguyên dương và không vượt quá giới hạn tuần.', 400);
  }

  const periodKey = getWeeklyExchangePeriodKey(now);
  const cost = BigInt(amount * GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_COST_SILVER);

  return db.transaction(async (tx) => {
    const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
    if (!master) throw new ScrollExchangeError('Không tìm thấy Master.', 404);

    const [exchange] = await tx.select().from(weeklyScrollExchanges)
      .where(and(eq(weeklyScrollExchanges.masterId, masterId), eq(weeklyScrollExchanges.periodKey, periodKey))).limit(1);
    const exchanged = exchange?.quantity ?? 0;
    if (exchanged + amount > GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP) {
      throw new ScrollExchangeError(`Đã đổi ${exchanged}/${GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP} Thiên Thư trong tuần này.`, 409);
    }
    if (master.silverCoins < cost) throw new ScrollExchangeError('Không đủ Xu Bạc.', 409);

    await tx.update(masters).set({ silverCoins: master.silverCoins - cost, updatedAt: now }).where(eq(masters.id, masterId));

    if (exchange) {
      await tx.update(weeklyScrollExchanges).set({ quantity: exchanged + amount, updatedAt: now }).where(eq(weeklyScrollExchanges.id, exchange.id));
    } else {
      await tx.insert(weeklyScrollExchanges).values({ id: uuidv4(), masterId, periodKey, quantity: amount, updatedAt: now });
    }

    await tx.insert(masterSummonInventory).values({ id: uuidv4(), masterId, scrollType: 'NORMAL', quantity: amount, updatedAt: now })
      .onConflictDoUpdate({
        target: [masterSummonInventory.masterId, masterSummonInventory.scrollType],
        set: { quantity: sql`${masterSummonInventory.quantity} + ${amount}`, updatedAt: now },
      });

    await tx.insert(currencyTransactions).values({
      id: uuidv4(), masterId, currencyType: 'SILVER', amountDelta: -cost,
      transactionType: 'SCROLL_EXCHANGE', referenceId: periodKey, createdAt: now,
    });

    return {
      amount,
      silverSpent: cost.toString(),
      remainingSilver: (master.silverCoins - cost).toString(),
      weeklyExchanged: exchanged + amount,
      weeklyLimit: GAME_CONSTANTS.GACHA.SCROLL_EXCHANGE_WEEKLY_CAP,
      periodKey,
    };
  });
}
