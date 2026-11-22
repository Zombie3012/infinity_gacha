import { and, asc, desc, eq, gt, inArray } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  masterItems,
  masterSummonInventory,
  masters,
  heroes,
  heroLevelConfigs,
  heroDevelopmentConfigs,
  currencyTransactions,
  itemTemplates,
} from '../../database/drizzle-schema.js';

export class InventoryError extends Error {
  constructor(message: string, public readonly statusCode = 400) {
    super(message);
    this.name = 'InventoryError';
  }
}

export type ItemCategory = 'DEVELOPMENT' | 'MATERIAL' | 'CONSUMABLE' | 'TICKET';

export type ItemMetadata = {
  itemId: string;
  name: string;
  description: string;
  category: ItemCategory;
  rarity: number;
  sellPrice: number;
  canUse: boolean;
};

export const KNOWN_ITEM_DEFINITIONS: Record<string, ItemMetadata> = {
  RESURRECTION_GEM_7: {
    itemId: 'RESURRECTION_GEM_7', name: 'Ngọc hồi sinh 7★',
    description: 'Dùng tại Sử Điện Anh Hùng để hồi sinh một Hero tử trận. Không khôi phục trang bị đã rơi.',
    category: 'CONSUMABLE', rarity: 7, sellPrice: 0, canUse: false,
  },
  TELEPORT_STONE: {
    itemId: 'TELEPORT_STONE', name: 'Đá dịch chuyển',
    description: 'Tạo điểm thu hồi dùng chung tới hết tầng, cho phép thoát truy đuổi; không dùng tại tầng cấm thu hồi.',
    category: 'CONSUMABLE', rarity: 3, sellPrice: 0, canUse: false,
  },
  SAMPLE_HERO_EXP_100: {
    itemId: 'SAMPLE_HERO_EXP_100',
    name: 'Sách EXP Hero Sơ Cấp (+1,000)',
    description: 'Bí tịch truyền thụ kinh nghiệm sơ cấp, gia tăng 1,000 EXP cho một Hero.',
    category: 'DEVELOPMENT',
    rarity: 2,
    sellPrice: 50,
    canUse: true,
  },
  SAMPLE_HERO_EXP_1000: {
    itemId: 'SAMPLE_HERO_EXP_1000',
    name: 'Sách EXP Hero Trung Cấp (+100,000)',
    description: 'Bí tịch truyền thụ kinh nghiệm trung cấp, gia tăng 100,000 EXP cho một Hero.',
    category: 'DEVELOPMENT',
    rarity: 3,
    sellPrice: 200,
    canUse: true,
  },
  SAMPLE_HERO_EXP_10000: {
    itemId: 'SAMPLE_HERO_EXP_10000',
    name: 'Sách EXP Hero Cao Cấp (+10,000,000)',
    description: 'Bí tịch truyền thụ kinh nghiệm cao cấp, gia tăng 10,000,000 EXP cho một Hero.',
    category: 'DEVELOPMENT',
    rarity: 4,
    sellPrice: 1000,
    canUse: true,
  },
  SAMPLE_HERO_PROMOTION_SEAL: {
    itemId: 'SAMPLE_HERO_PROMOTION_SEAL',
    name: 'Ấn Thăng Bậc Hero',
    description: 'Linh ấn dùng để mở khóa giới hạn cấp độ cao hơn cho Hero.',
    category: 'DEVELOPMENT',
    rarity: 3,
    sellPrice: 200,
    canUse: false,
  },
  SAMPLE_HERO_AWAKENING_CORE: {
    itemId: 'SAMPLE_HERO_AWAKENING_CORE',
    name: 'Lõi Thức Tỉnh Hero',
    description: 'Tinh hoa năng lượng đánh thức tiềm năng tối thượng của Hero.',
    category: 'DEVELOPMENT',
    rarity: 4,
    sellPrice: 500,
    canUse: false,
  },
  SAMPLE_HERO_SKILL_BOOK: {
    itemId: 'SAMPLE_HERO_SKILL_BOOK',
    name: 'Sách Kỹ Năng Hero',
    description: 'Sách hướng dẫn nâng cao cấp độ kỹ năng chiến đấu của Hero.',
    category: 'DEVELOPMENT',
    rarity: 3,
    sellPrice: 300,
    canUse: false,
  },
  SAMPLE_TRASH_DULL_SHARD: {
    itemId: 'SAMPLE_TRASH_DULL_SHARD',
    name: 'Mảnh Pha Lê Mờ',
    description: 'Mảnh khoáng thạch thô sơ, có thể bán lấy Bạc.',
    category: 'MATERIAL',
    rarity: 1,
    sellPrice: 20,
    canUse: false,
  },
  SAMPLE_TRASH_TORN_SCROLL: {
    itemId: 'SAMPLE_TRASH_TORN_SCROLL',
    name: 'Giấy Phù Rách',
    description: 'Tàn tích của bùa chú đã tiêu hao, có thể bán cho thương nhân.',
    category: 'MATERIAL',
    rarity: 1,
    sellPrice: 20,
    canUse: false,
  },
  SAMPLE_TRASH_BROKEN_CHARM: {
    itemId: 'SAMPLE_TRASH_BROKEN_CHARM',
    name: 'Mảnh Bùa Vỡ',
    description: 'Mảnh vỡ kim loại không còn ma lực, có thể tái chế đổi Bạc.',
    category: 'MATERIAL',
    rarity: 1,
    sellPrice: 20,
    canUse: false,
  },
};

export class InventoryService {
  /**
   * FUN-10-01-001 & FUN-10-01-002 & FUN-10-01-003: View, Filter, and Sort Inventory.
   */
  public async listInventory(masterId: string, options?: {
    category?: string;
    sort?: 'QUANTITY_DESC' | 'RARITY_DESC' | 'NAME_ASC';
  }) {
    const rawItems = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), gt(masterItems.quantity, 0)));

    const scrolls = await db.select().from(masterSummonInventory)
      .where(and(eq(masterSummonInventory.masterId, masterId), gt(masterSummonInventory.quantity, 0)));

    const catalogue = rawItems.length ? await db.select().from(itemTemplates).where(inArray(itemTemplates.code, rawItems.map(r => r.itemId))) : [];
    const catalogueByCode = new Map(catalogue.map(row => [row.code, row]));
    let items = rawItems.map(row => {
      const def = KNOWN_ITEM_DEFINITIONS[row.itemId] ?? {
        itemId: row.itemId,
        name: row.itemId,
        description: 'Vật phẩm nguyên liệu.',
        category: 'MATERIAL',
        rarity: 1,
        sellPrice: 10,
        canUse: false,
      };

      const template = catalogueByCode.get(row.itemId);
      return {
        id: row.id,
        quantity: row.quantity,
        updatedAt: row.updatedAt,
        ...def,
        ...(template ? { name: template.name, description: template.description, category: template.category as ItemCategory,
          rarity: Math.max(1, Math.min(7, template.rarity)) } : {}),
      };
    });

    // Filter by Category
    if (options?.category && options.category !== 'ALL') {
      items = items.filter(item => item.category === options.category);
    }

    // Sort
    const sort = options?.sort ?? 'QUANTITY_DESC';
    if (sort === 'QUANTITY_DESC') {
      items.sort((a, b) => b.quantity - a.quantity || b.rarity - a.rarity);
    } else if (sort === 'RARITY_DESC') {
      items.sort((a, b) => b.rarity - a.rarity || b.quantity - a.quantity);
    } else if (sort === 'NAME_ASC') {
      items.sort((a, b) => a.name.localeCompare(b.name));
    }

    return {
      items,
      summonScrolls: scrolls.map(s => ({
        scrollType: s.scrollType,
        quantity: s.quantity,
      })),
    };
  }

  /**
   * FUN-10-01-004: Add Item to Inventory.
   */
  public async addItem(masterId: string, itemId: string, quantity: number) {
    if (quantity <= 0) throw new InventoryError('Số lượng cộng phải lớn hơn 0.', 400);

    return db.transaction(async tx => {
      const [existing] = await tx.select().from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).for('update').limit(1);

      if (existing) {
        const [updated] = await tx.update(masterItems).set({
          quantity: existing.quantity + quantity,
          updatedAt: new Date(),
        }).where(eq(masterItems.id, existing.id)).returning();
        return updated;
      }

      const [created] = await tx.insert(masterItems).values({
        id: uuidv4(),
        masterId,
        itemId,
        quantity,
        updatedAt: new Date(),
      }).returning();
      return created;
    });
  }

  /**
   * FUN-10-01-005: Remove Item from Inventory.
   */
  public async removeItem(masterId: string, itemId: string, quantity: number) {
    if (quantity <= 0) throw new InventoryError('Số lượng trừ phải lớn hơn 0.', 400);

    return db.transaction(async tx => {
      const [existing] = await tx.select().from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).for('update').limit(1);

      if (!existing || existing.quantity < quantity) {
        throw new InventoryError(`Không đủ số lượng vật phẩm ${itemId} trong kho (Hiện có: ${existing?.quantity ?? 0}).`, 400);
      }

      const nextQuantity = existing.quantity - quantity;
      const [updated] = await tx.update(masterItems).set({
        quantity: nextQuantity,
        updatedAt: new Date(),
      }).where(eq(masterItems.id, existing.id)).returning();
      return updated;
    });
  }

  /**
   * FUN-10-01-006: Use Item (e.g. Sách EXP cho Hero).
   */
  public async useItem(masterId: string, itemId: string, quantity: number, targetHeroId?: string) {
    if (quantity <= 0) throw new InventoryError('Số lượng sử dụng phải lớn hơn 0.', 400);

    const def = KNOWN_ITEM_DEFINITIONS[itemId];
    if (!def || !def.canUse) {
      throw new InventoryError(`Vật phẩm ${itemId} không thể sử dụng trực tiếp.`, 400);
    }

    return db.transaction(async tx => {
      const [inventoryRow] = await tx.select().from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).for('update').limit(1);

      if (!inventoryRow || inventoryRow.quantity < quantity) {
        throw new InventoryError(`Không đủ vật phẩm trong kho (Hiện có: ${inventoryRow?.quantity ?? 0}).`, 400);
      }

      if (itemId === 'SAMPLE_HERO_EXP_100' || itemId === 'SAMPLE_HERO_EXP_1000' || itemId === 'SAMPLE_HERO_EXP_10000') {
        if (!targetHeroId) throw new InventoryError('Cần chọn Hero để sử dụng sách EXP.', 400);

        const [hero] = await tx.select().from(heroes)
          .where(and(eq(heroes.id, targetHeroId), eq(heroes.masterId, masterId))).for('update').limit(1);

        if (!hero) throw new InventoryError('Hero không tồn tại hoặc không thuộc quyền sở hữu.', 404);
        if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) {
          throw new InventoryError('Không thể sử dụng vật phẩm cho Hero đã tử trận hoặc vô hiệu hóa.', 409);
        }

        const expPerBook = itemId === 'SAMPLE_HERO_EXP_10000' ? 10000000n : (itemId === 'SAMPLE_HERO_EXP_1000' ? 100000n : 1000n);
        const expGained = expPerBook * BigInt(quantity);
        const totalExp = BigInt(hero.exp) + expGained;

        // Get promotion cap
        const [devConfig] = await tx.select().from(heroDevelopmentConfigs)
          .where(and(eq(heroDevelopmentConfigs.action, 'PROMOTION'), eq(heroDevelopmentConfigs.rank, hero.promotionRank ?? 0))).limit(1);
        const maxLevelCap = devConfig?.maxLevelAfter ?? 20;

        let currentLevel = hero.level;
        let hp = hero.hp;
        let maxHp = hero.maxHp;
        let attack = hero.attack;
        let defense = hero.defense;
        let speed = hero.speed;

        const levelConfigs = await tx.select().from(heroLevelConfigs)
          .where(gt(heroLevelConfigs.level, currentLevel)).orderBy(asc(heroLevelConfigs.level));

        for (const config of levelConfigs) {
          if (config.level > maxLevelCap) break;
          if (totalExp < config.cumulativeExpRequired) break;
          currentLevel = config.level;
          maxHp = Math.floor(maxHp * config.statGrowthMultiplier);
          hp = maxHp;
          attack = Math.floor(attack * config.statGrowthMultiplier);
          defense = Math.floor(defense * config.statGrowthMultiplier);
          speed = Math.floor(speed * config.statGrowthMultiplier);
        }

        await tx.update(heroes).set({
          exp: totalExp,
          level: currentLevel,
          hp,
          maxHp,
          attack,
          defense,
          speed,
          updatedAt: new Date(),
        }).where(eq(heroes.id, hero.id));

        await tx.update(masterItems).set({
          quantity: inventoryRow.quantity - quantity,
          updatedAt: new Date(),
        }).where(eq(masterItems.id, inventoryRow.id));

        return {
          itemId,
          quantityUsed: quantity,
          heroId: hero.id,
          heroName: hero.name,
          fromLevel: hero.level,
          toLevel: currentLevel,
          currentExp: totalExp.toString(),
        };
      }

      throw new InventoryError(`Chưa hỗ trợ sử dụng vật phẩm ${itemId}.`, 400);
    });
  }

  /**
   * FUN-10-01-007: Sell Item for Silver Coins.
   */
  public async sellItem(masterId: string, itemId: string, quantity: number) {
    if (quantity <= 0) throw new InventoryError('Số lượng bán phải lớn hơn 0.', 400);

    const def = KNOWN_ITEM_DEFINITIONS[itemId];
    if (!def || def.sellPrice <= 0) {
      throw new InventoryError(`Vật phẩm ${itemId} không thể bán.`, 400);
    }

    return db.transaction(async tx => {
      const [inventoryRow] = await tx.select().from(masterItems)
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, itemId))).for('update').limit(1);

      if (!inventoryRow || inventoryRow.quantity < quantity) {
        throw new InventoryError(`Không đủ số lượng vật phẩm trong kho để bán (Hiện có: ${inventoryRow?.quantity ?? 0}).`, 400);
      }

      const [masterRecord] = await tx.select().from(masters)
        .where(eq(masters.id, masterId)).for('update').limit(1);
      if (!masterRecord) throw new InventoryError('Master không tồn tại.', 404);

      const silverEarned = def.sellPrice * quantity;
      const nextSilver = masterRecord.silverCoins + BigInt(silverEarned);

      // Deduct items
      await tx.update(masterItems).set({
        quantity: inventoryRow.quantity - quantity,
        updatedAt: new Date(),
      }).where(eq(masterItems.id, inventoryRow.id));

      // Add silver to master
      await tx.update(masters).set({
        silverCoins: nextSilver,
        updatedAt: new Date(),
      }).where(eq(masters.id, masterId));

      // Record transaction
      await tx.insert(currencyTransactions).values({
        id: uuidv4(),
        masterId,
        currencyType: 'SILVER',
        amountDelta: BigInt(silverEarned),
        transactionType: 'ITEM_SOLD',
        createdAt: new Date(),
      });

      return {
        itemId,
        quantitySold: quantity,
        unitPrice: def.sellPrice,
        silverEarned,
        newSilverBalance: nextSilver.toString(),
      };
    });
  }
}

export const inventoryService = new InventoryService();
