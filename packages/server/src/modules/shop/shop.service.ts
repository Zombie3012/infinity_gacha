import { and, asc, eq, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { masterItems, masters, shopItems, shopPurchaseLimits } from '../../database/drizzle-schema.js';
import { dailyPeriodKey, isAvailableNow, resolvePurchaseQuantity, totalSilverFor } from './shop-rules.js';

export class ShopError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ShopError';
  }
}

export interface ShopItemInput {
  code: string;
  name: string;
  description: string;
  itemId: string;
  category: 'CONSUMABLE' | 'MATERIAL' | 'SCROLL';
  priceSilver: number;
  dailyLimit?: number;
  rotationDays?: number[];
  isActive?: boolean;
  sortOrder?: number;
}

export class ShopService {
  private async limitsFor(masterId: string, periodKey: string) {
    const rows = await db.select().from(shopPurchaseLimits)
      .where(and(eq(shopPurchaseLimits.masterId, masterId), eq(shopPurchaseLimits.periodKey, periodKey)));
    return new Map(rows.map(row => [row.shopItemCode, row.quantity]));
  }

  async catalog(masterId: string, now = new Date()) {
    const periodKey = dailyPeriodKey(now);
    const limits = await this.limitsFor(masterId, periodKey);
    const items = await db.select().from(shopItems)
      .where(eq(shopItems.isActive, true)).orderBy(asc(shopItems.sortOrder), asc(shopItems.code));
    return {
      periodKey,
      items: items
        .filter(item => isAvailableNow(item.rotationDays, now))
        .map(item => {
          const bought = limits.get(item.code) ?? 0;
          return {
            code: item.code,
            name: item.name,
            description: item.description,
            itemId: item.itemId,
            category: item.category,
            priceSilver: item.priceSilver.toString(),
            dailyLimit: item.dailyLimit,
            purchasedToday: bought,
            remainingToday: item.dailyLimit > 0 ? Math.max(0, item.dailyLimit - bought) : null,
          };
        }),
      rotatedOut: items.filter(item => !isAvailableNow(item.rotationDays, now)).map(item => item.code),
    };
  }

  async detail(masterId: string, code: string, now = new Date()) {
    const periodKey = dailyPeriodKey(now);
    const [item] = await db.select().from(shopItems).where(eq(shopItems.code, code)).limit(1);
    if (!item) throw new ShopError('Không tìm thấy mặt hàng.', 404);
    const limits = await this.limitsFor(masterId, periodKey);
    const bought = limits.get(item.code) ?? 0;
    return {
      ...item,
      priceSilver: item.priceSilver.toString(),
      available: item.isActive && isAvailableNow(item.rotationDays, now),
      purchasedToday: bought,
      remainingToday: item.dailyLimit > 0 ? Math.max(0, item.dailyLimit - bought) : null,
    };
  }

  /**
   * Scenario 13.1: buy as many units as the daily limit still allows and report
   * ERR_SHOP_DAILY_LIMIT_EXCEEDED for the remainder instead of failing outright.
   */
  async purchase(masterId: string, code: string, quantityInput: unknown, now = new Date()) {
    const quantity = Math.max(1, Math.min(99, Math.floor(Number(quantityInput) || 1)));
    const periodKey = dailyPeriodKey(now);
    const [item] = await db.select().from(shopItems).where(eq(shopItems.code, code)).limit(1);
    if (!item || !item.isActive) throw new ShopError('Mặt hàng không khả dụng.', 404);
    if (!isAvailableNow(item.rotationDays, now)) throw new ShopError('ERR_SHOP_ITEM_ROTATED_OUT', 409);

    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new ShopError('Không tìm thấy Master.', 404);

    return db.transaction(async tx => {
      const [limitRow] = await tx.select().from(shopPurchaseLimits)
        .where(and(
          eq(shopPurchaseLimits.masterId, masterId),
          eq(shopPurchaseLimits.shopItemCode, code),
          eq(shopPurchaseLimits.periodKey, periodKey),
        )).for('update').limit(1);
      const bought = limitRow?.quantity ?? 0;
      const remaining = item.dailyLimit > 0 ? Math.max(0, item.dailyLimit - bought) : null;
      const resolution = resolvePurchaseQuantity(remaining, quantity);
      if (resolution.allowed === 0) throw new ShopError('ERR_SHOP_DAILY_LIMIT_EXCEEDED', 409);

      const silverCost = totalSilverFor(Number(item.priceSilver), resolution.allowed);
      if (master.silverCoins < BigInt(silverCost)) throw new ShopError('ERR_SHOP_INSUFFICIENT_FUNDS', 409);

      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${silverCost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      await tx.insert(masterItems).values({
        id: uuidv4(), masterId, itemId: item.itemId, quantity: resolution.allowed, updatedAt: now,
      }).onConflictDoUpdate({
        target: [masterItems.masterId, masterItems.itemId],
        set: { quantity: sql`${masterItems.quantity} + ${resolution.allowed}`, updatedAt: now },
      });
      await tx.insert(shopPurchaseLimits).values({
        id: limitRow?.id ?? uuidv4(), masterId, shopItemCode: code, periodKey,
        quantity: bought + resolution.allowed,
      }).onConflictDoUpdate({
        target: [shopPurchaseLimits.id],
        set: { quantity: bought + resolution.allowed },
      });

      return {
        itemCode: code,
        itemId: item.itemId,
        purchased: resolution.allowed,
        requested: quantity,
        silverSpent: silverCost,
        remainingToday: remaining === null ? null : remaining - resolution.allowed,
        limitReached: resolution.blocked,
        warning: resolution.blocked ? 'ERR_SHOP_DAILY_LIMIT_EXCEEDED' : null,
      };
    });
  }

  async upsertItem(input: ShopItemInput) {
    const code = typeof input.code === 'string' ? input.code.trim() : '';
    if (!/^[A-Z0-9_]{2,50}$/.test(code)) throw new ShopError('code phải là chữ in hoa/số/underscore (2–50 ký tự).');
    if (!Number.isFinite(input.priceSilver) || input.priceSilver < 0) throw new ShopError('priceSilver không hợp lệ.');
    const days = Array.isArray(input.rotationDays) ? input.rotationDays.filter(day => Number.isInteger(day) && day >= 0 && day <= 6) : [];
    const [row] = await db.insert(shopItems).values({
      code,
      name: input.name,
      description: input.description,
      itemId: input.itemId,
      category: input.category,
      priceSilver: BigInt(Math.floor(input.priceSilver)),
      dailyLimit: Math.max(0, Math.floor(input.dailyLimit ?? 0)),
      rotationDays: days,
      isActive: input.isActive !== false,
      sortOrder: Math.floor(input.sortOrder ?? 100),
    }).onConflictDoUpdate({
      target: [shopItems.code],
      set: {
        name: input.name,
        description: input.description,
        itemId: input.itemId,
        category: input.category,
        priceSilver: BigInt(Math.floor(input.priceSilver)),
        dailyLimit: Math.max(0, Math.floor(input.dailyLimit ?? 0)),
        rotationDays: days,
        isActive: input.isActive !== false,
        sortOrder: Math.floor(input.sortOrder ?? 100),
      },
    }).returning();
    return { ...row, priceSilver: row.priceSilver.toString() };
  }

  async listAll() {
    const rows = await db.select().from(shopItems).orderBy(asc(shopItems.sortOrder), asc(shopItems.code));
    return rows.map(row => ({ ...row, priceSilver: row.priceSilver.toString() }));
  }
}

export const shopService = new ShopService();
