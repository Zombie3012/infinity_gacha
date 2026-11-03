import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  baseBuildings, craftingRecipes, equipmentInstances, equipmentTemplates, masterItems, masters,
} from '../../database/drizzle-schema.js';
import {
  effectiveMultiplier, enhanceCost, fusionMultiplierForStar, fusionRequirement, rollSubstats, scaledBonus, validateCraft,
} from './crafting-rules.js';

export class CraftingError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'CraftingError';
  }
}

const STONE_ITEM = 'ENHANCEMENT_STONE';

const instanceStats = (template: typeof equipmentTemplates.$inferSelect, instance: typeof equipmentInstances.$inferSelect) => ({
  hp: scaledBonus(template.bonusHp, instance.statMultiplier, instance.substats.hp),
  attack: scaledBonus(template.bonusAttack, instance.statMultiplier, instance.substats.attack),
  defense: scaledBonus(template.bonusDefense, instance.statMultiplier, instance.substats.defense),
  speed: scaledBonus(template.bonusSpeed, instance.statMultiplier, instance.substats.speed),
});

export class CraftingService {
  private async forgeLevel(masterId: string) {
    const [forge] = await db.select({ level: baseBuildings.level }).from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, 'FORGE'))).limit(1);
    return forge?.level ?? 0;
  }

  private async ownedItems(masterId: string) {
    const rows = await db.select({ itemId: masterItems.itemId, quantity: masterItems.quantity })
      .from(masterItems).where(eq(masterItems.masterId, masterId));
    return Object.fromEntries(rows.map(row => [row.itemId, row.quantity]));
  }

  async overview(masterId: string) {
    const [master] = await db.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new CraftingError('Không tìm thấy Master.', 404);
    const forgeLevel = await this.forgeLevel(masterId);
    const owned = await this.ownedItems(masterId);
    const recipes = await db.select().from(craftingRecipes).where(eq(craftingRecipes.isActive, true)).orderBy(asc(craftingRecipes.code));
    const templates = await db.select().from(equipmentTemplates).orderBy(asc(equipmentTemplates.code));
    const templateByCode = new Map(templates.map(row => [row.code, row]));

    const instances = await db.select().from(equipmentInstances)
      .where(eq(equipmentInstances.masterId, masterId)).orderBy(asc(equipmentInstances.templateCode));

    const equipment = instances.map(instance => {
      const template = templateByCode.get(instance.templateCode);
      return {
        id: instance.id,
        templateCode: instance.templateCode,
        name: template?.name ?? instance.templateCode,
        slotType: template?.slotType ?? 'UNKNOWN',
        rarity: template?.rarity ?? 1,
        location: instance.location,
        starLevel: instance.starLevel,
        enhanceLevel: instance.enhanceLevel,
        statMultiplier: instance.statMultiplier,
        substats: instance.substats,
        stats: template ? instanceStats(template, instance) : { hp: 0, attack: 0, defense: 0, speed: 0 },
        upgradeCost: enhanceCost(instance.enhanceLevel),
      };
    });

    const recipeViews = recipes.map(recipe => {
      const validation = validateCraft({
        requiredMaterials: recipe.requiredMaterials,
        owned,
        requiredSilver: recipe.craftFeeSilver,
        silver: Number(master.silverCoins),
        requiredForgeLevel: recipe.requiredForgeLevel,
        forgeLevel,
      });
      return {
        ...recipe,
        targetName: templateByCode.get(recipe.targetTemplateCode)?.name ?? recipe.targetTemplateCode,
        forgeLevel,
        validation,
      };
    });

    return {
      forgeLevel,
      silverCoins: master.silverCoins.toString(),
      enhancementStones: owned[STONE_ITEM] ?? 0,
      materials: owned,
      recipes: recipeViews,
      equipment,
      fusionRequirement: fusionRequirement(),
    };
  }

  /** Scenario 12.1: consume materials + Silver and roll a new equipment instance. */
  async craft(masterId: string, recipeCode: string) {
    const [recipe] = await db.select().from(craftingRecipes).where(eq(craftingRecipes.code, recipeCode)).limit(1);
    if (!recipe || !recipe.isActive) throw new CraftingError('Công thức không tồn tại.', 404);
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new CraftingError('Không tìm thấy Master.', 404);
    const forgeLevel = await this.forgeLevel(masterId);
    const owned = await this.ownedItems(masterId);

    const validation = validateCraft({
      requiredMaterials: recipe.requiredMaterials,
      owned,
      requiredSilver: recipe.craftFeeSilver,
      silver: Number(master.silverCoins),
      requiredForgeLevel: recipe.requiredForgeLevel,
      forgeLevel,
    });
    if (!validation.ok) throw new CraftingError(validation.reason ?? 'ERR_CRAFT_INVALID', 409);

    const [template] = await db.select().from(equipmentTemplates).where(eq(equipmentTemplates.code, recipe.targetTemplateCode)).limit(1);
    if (!template) throw new CraftingError('Trang bị đích không tồn tại.', 404);

    const now = new Date();
    const instanceId = uuidv4();
    await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${recipe.craftFeeSilver}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      for (const material of recipe.requiredMaterials) {
        await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${material.quantity}`, updatedAt: now })
          .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, material.itemId)));
      }
      await tx.insert(equipmentInstances).values({
        id: instanceId,
        masterId,
        templateCode: recipe.targetTemplateCode,
        location: 'INVENTORY',
        starLevel: 1,
        enhanceLevel: 0,
        statMultiplier: 1,
        substats: rollSubstats(`${instanceId}:${recipe.code}`, template.rarity),
        createdAt: now,
      });
    });

    return { instanceId, templateCode: recipe.targetTemplateCode, name: template.name, silverSpent: recipe.craftFeeSilver, materialsSpent: recipe.requiredMaterials };
  }

  async enhance(masterId: string, instanceId: string) {
    const [instance] = await db.select().from(equipmentInstances)
      .where(and(eq(equipmentInstances.id, instanceId), eq(equipmentInstances.masterId, masterId))).limit(1);
    if (!instance) throw new CraftingError('Không tìm thấy trang bị.', 404);
    if (instance.enhanceLevel >= 15) throw new CraftingError('Trang bị đã đạt cấp tăng cường tối đa.', 409);

    const cost = enhanceCost(instance.enhanceLevel);
    const [master] = await db.select({ silverCoins: masters.silverCoins }).from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master || Number(master.silverCoins) < cost.silver) throw new CraftingError('ERR_CRAFT_MISSING_SILVER', 409);
    const owned = await this.ownedItems(masterId);
    if ((owned[STONE_ITEM] ?? 0) < cost.stones) throw new CraftingError('ERR_CRAFT_MISSING_MATERIALS', 409);

    const nextLevel = instance.enhanceLevel + 1;
    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${cost.silver}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${cost.stones}`, updatedAt: now })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, STONE_ITEM)));
      await tx.update(equipmentInstances).set({
        enhanceLevel: nextLevel,
        statMultiplier: effectiveMultiplier(instance.starLevel, nextLevel),
      }).where(eq(equipmentInstances.id, instanceId));
    });

    return {
      instanceId, enhanceLevel: nextLevel,
      statMultiplier: effectiveMultiplier(instance.starLevel, nextLevel),
      silverSpent: cost.silver, stonesSpent: cost.stones,
    };
  }

  /** Scenario 12.2: three identical instances become one at the next star (+30%). */
  async fuse(masterId: string, templateCode: string, starLevelInput: unknown) {
    const starLevel = Math.max(1, Math.floor(Number(starLevelInput) || 1));
    const required = fusionRequirement();
    const candidates = await db.select().from(equipmentInstances)
      .where(and(
        eq(equipmentInstances.masterId, masterId),
        eq(equipmentInstances.templateCode, templateCode),
        eq(equipmentInstances.starLevel, starLevel),
        eq(equipmentInstances.location, 'INVENTORY'),
      )).orderBy(asc(equipmentInstances.enhanceLevel)).limit(required);
    if (candidates.length < required) {
      throw new CraftingError(`Cần ${required} trang bị ${templateCode} ${starLevel} sao trong túi.`, 409);
    }

    const consumed = candidates.map(row => row.id);
    const newId = uuidv4();
    const now = new Date();
    await db.transaction(async tx => {
      await tx.delete(equipmentInstances).where(inArray(equipmentInstances.id, consumed));
      await tx.insert(equipmentInstances).values({
        id: newId,
        masterId,
        templateCode,
        location: 'INVENTORY',
        starLevel: starLevel + 1,
        enhanceLevel: 0,
        statMultiplier: fusionMultiplierForStar(starLevel + 1),
        substats: { hp: 0, attack: 0, defense: 0, speed: 0 },
        createdAt: now,
      });
    });

    return {
      instanceId: newId,
      templateCode,
      starLevel: starLevel + 1,
      statMultiplier: fusionMultiplierForStar(starLevel + 1),
      consumed,
    };
  }
}

export const craftingService = new CraftingService();
