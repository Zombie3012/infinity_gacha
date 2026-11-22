import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { masterItems, masters, shopItems, shopPurchaseLimits, shopPurchases, itemTemplates,
  equipmentTemplates, equipmentInstances, masterSummonInventory, currencyTransactions } from '../../database/drizzle-schema.js';
import { dailyPeriodKey, isAvailableNow, resolvePurchaseQuantity, totalSilverFor } from './shop-rules.js';
import { rollSubstats } from '../crafting/crafting-rules.js';

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
  category: 'CONSUMABLE' | 'MATERIAL' | 'SCROLL' | 'DEVELOPMENT' | 'FOOD' | 'EQUIPMENT';
  priceSilver?: number;
  dailyLimit?: number;
  rotationDays?: number[];
  isActive?: boolean;
  sortOrder?: number;
}

interface ShopPurchaseResult {
  purchaseId: string; itemCode: string; itemId: string; purchased: number; requested: number;
  silverSpent: number; remainingSilver: string; remainingToday: number | null;
  limitReached: boolean; warning: string | null; equipmentInstanceIds: string[];
  replayed?: boolean;
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
    const templates = items.length ? await db.select({ code: itemTemplates.code, rarity: itemTemplates.rarity }).from(itemTemplates)
      .where(inArray(itemTemplates.code, items.map(item => item.itemId))) : [];
    const rarities = new Map(templates.map(item => [item.code, item.rarity]));
    const gear = await db.select({ code: equipmentTemplates.code, rarity: equipmentTemplates.rarity }).from(equipmentTemplates);
    const gearRarities = new Map(gear.map(item => [item.code, item.rarity]));
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
            rarity: Math.max(1, Math.min(7, item.category === 'EQUIPMENT' ? gearRarities.get(item.itemId) ?? 1 : rarities.get(item.itemId) ?? 1)),
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
    const [template] = item.category === 'EQUIPMENT'
      ? await db.select({ rarity: equipmentTemplates.rarity }).from(equipmentTemplates).where(eq(equipmentTemplates.code, item.itemId)).limit(1)
      : await db.select({ rarity: itemTemplates.rarity }).from(itemTemplates).where(eq(itemTemplates.code, item.itemId)).limit(1);
    const limits = await this.limitsFor(masterId, periodKey);
    const bought = limits.get(item.code) ?? 0;
    return {
      ...item,
      rarity: Math.max(1, Math.min(7, template?.rarity ?? 1)),
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
  async purchase(masterId: string, code: string, quantityInput: unknown, now = new Date(), idempotencyKey?: string): Promise<ShopPurchaseResult> {
    const quantity = quantityInput === undefined ? 1 : Number(quantityInput);
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 99) throw new ShopError('ERR_SHOP_QUANTITY_INVALID', 400);
    if (idempotencyKey !== undefined && (!idempotencyKey.trim() || idempotencyKey.length > 80)) throw new ShopError('ERR_SHOP_KEY_INVALID', 400);
    const periodKey = dailyPeriodKey(now);
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      if (!master) throw new ShopError('Không tìm thấy Master.', 404);
      if (idempotencyKey) {
        const [previous] = await tx.select().from(shopPurchases)
          .where(and(eq(shopPurchases.masterId, masterId), eq(shopPurchases.idempotencyKey, idempotencyKey))).limit(1);
        if (previous) {
          if (previous.itemCode !== code || previous.quantity !== quantity) throw new ShopError('ERR_SHOP_KEY_CONFLICT', 409);
          return { ...previous.result as unknown as ShopPurchaseResult, replayed: true };
        }
      }
      const [item] = await tx.select().from(shopItems).where(eq(shopItems.code, code)).for('share').limit(1);
      if (!item || !item.isActive) throw new ShopError('Mặt hàng không khả dụng.', 404);
      if (!isAvailableNow(item.rotationDays, now)) throw new ShopError('ERR_SHOP_ITEM_ROTATED_OUT', 409);
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
      const equipmentInstanceIds: string[] = [];
      if (item.category === 'EQUIPMENT') {
        const [template] = await tx.select().from(equipmentTemplates).where(eq(equipmentTemplates.code, item.itemId)).limit(1);
        if (!template) throw new ShopError('ERR_SHOP_EQUIPMENT_UNAVAILABLE', 409);
        for (let i = 0; i < resolution.allowed; i++) {
          const id = uuidv4(); equipmentInstanceIds.push(id);
          await tx.insert(equipmentInstances).values({ id, masterId, templateCode: template.code, location: 'INVENTORY',
            starLevel: 1, enhanceLevel: 0, statMultiplier: 1, substats: rollSubstats(id, template.rarity), createdAt: now });
        }
      } else if (item.category === 'SCROLL') {
        if (!['NORMAL','LIMITED'].includes(item.itemId)) throw new ShopError('ERR_SHOP_SCROLL_UNAVAILABLE', 409);
        await tx.insert(masterSummonInventory).values({ id: uuidv4(), masterId, scrollType: item.itemId, quantity: resolution.allowed, updatedAt: now })
          .onConflictDoUpdate({ target: [masterSummonInventory.masterId, masterSummonInventory.scrollType],
            set: { quantity: sql`${masterSummonInventory.quantity} + ${resolution.allowed}`, updatedAt: now } });
      } else {
        await tx.insert(masterItems).values({
          id: uuidv4(), masterId, itemId: item.itemId, quantity: resolution.allowed, updatedAt: now,
        }).onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${resolution.allowed}`, updatedAt: now },
        });
      }
      await tx.insert(shopPurchaseLimits).values({
        id: limitRow?.id ?? uuidv4(), masterId, shopItemCode: code, periodKey,
        quantity: bought + resolution.allowed,
      }).onConflictDoUpdate({
        target: [shopPurchaseLimits.masterId, shopPurchaseLimits.shopItemCode, shopPurchaseLimits.periodKey],
        set: { quantity: bought + resolution.allowed },
      });

      const purchaseId = uuidv4();
      await tx.insert(currencyTransactions).values({ id: uuidv4(), masterId, currencyType: 'SILVER', amountDelta: -BigInt(silverCost),
        transactionType: 'SHOP_PURCHASE', referenceId: purchaseId, createdAt: now });
      const result: ShopPurchaseResult = {
        purchaseId,
        itemCode: code,
        itemId: item.itemId,
        purchased: resolution.allowed,
        requested: quantity,
        silverSpent: silverCost,
        remainingSilver: (master.silverCoins - BigInt(silverCost)).toString(),
        equipmentInstanceIds,
        remainingToday: remaining === null ? null : remaining - resolution.allowed,
        limitReached: resolution.blocked,
        warning: resolution.blocked ? 'ERR_SHOP_DAILY_LIMIT_EXCEEDED' : null,
      };
      if (idempotencyKey) await tx.insert(shopPurchases).values({ id: purchaseId, masterId, idempotencyKey, itemCode: code,
        quantity, result: { ...result }, createdAt: now });
      return { ...result, replayed: false };
    });
  }

  async upsertItem(input: ShopItemInput) {
    input = { ...input, priceSilver: input.priceSilver ?? 1 };
    const code = typeof input.code === 'string' ? input.code.trim() : '';
    if (!/^[A-Z0-9_]{2,50}$/.test(code)) throw new ShopError('code phải là chữ in hoa/số/underscore (2–50 ký tự).');
    if (!Number.isSafeInteger(input.priceSilver) || input.priceSilver! < 0) throw new ShopError('priceSilver không hợp lệ.');
    const days = Array.isArray(input.rotationDays) ? input.rotationDays.filter(day => Number.isInteger(day) && day >= 0 && day <= 6) : [];
    const [row] = await db.insert(shopItems).values({
      code,
      name: input.name,
      description: input.description,
      itemId: input.itemId,
      category: input.category,
      priceSilver: BigInt(input.priceSilver!),
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
        priceSilver: BigInt(input.priceSilver!),
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
