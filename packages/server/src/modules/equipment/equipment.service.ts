import { and, asc, eq } from 'drizzle-orm';
import { db } from '../../database/db.js';
import {
  equipmentInstances, equipmentTemplates, heroes, masters, worlds,
} from '../../database/drizzle-schema.js';

export class EquipmentError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

export class EquipmentService {
  public async list(masterId: string) {
    return db.select({ equipment: equipmentInstances, template: equipmentTemplates })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .where(eq(equipmentInstances.masterId, masterId)).orderBy(asc(equipmentInstances.location), asc(equipmentTemplates.slotType), asc(equipmentTemplates.name));
  }

  public async equip(masterId: string, itemId: string, heroId: string) {
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new EquipmentError('Hero not found for this Master.', 404);
      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) throw new EquipmentError('Only an active Hero can equip an item.', 409);
      const [item] = await tx.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.id, itemId), eq(equipmentInstances.masterId, masterId))).for('update').limit(1);
      if (!item) throw new EquipmentError('Equipment not found.', 404);
      if (item.location !== 'INVENTORY') throw new EquipmentError('Pick up floor drops before equipping them.', 409);
      const [template] = await tx.select().from(equipmentTemplates).where(eq(equipmentTemplates.code, item.templateCode)).limit(1);
      if (!template) throw new EquipmentError('Equipment configuration not found.', 409);
      const conflicts = await tx.select({ equipment: equipmentInstances })
        .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
        .where(and(
          eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.equippedHeroId, heroId),
          eq(equipmentInstances.location, 'EQUIPPED'), eq(equipmentTemplates.slotType, template.slotType),
        )).for('update');
      for (const conflict of conflicts) await tx.update(equipmentInstances).set({
        location: 'INVENTORY', equippedHeroId: null, dropWorldId: null, dropFloor: null, droppedAt: null,
      }).where(eq(equipmentInstances.id, conflict.equipment.id));
      const [equipped] = await tx.update(equipmentInstances).set({
        location: 'EQUIPPED', equippedHeroId: heroId, dropWorldId: null, dropFloor: null, droppedAt: null, pickedUpAt: null,
      }).where(eq(equipmentInstances.id, item.id)).returning();
      const hpGear = await tx.select({ bonusHp: equipmentTemplates.bonusHp })
        .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
        .where(and(eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.equippedHeroId, heroId), eq(equipmentInstances.location, 'EQUIPPED')));
      const maxHp = hero.maxHp + hpGear.reduce((sum, row) => sum + row.bonusHp, 0);
      await tx.update(heroes).set({ hp: Math.min(hero.hp, maxHp), updatedAt: new Date() }).where(eq(heroes.id, heroId));
      return { equipment: equipped, template };
    });
  }

  public async unequip(masterId: string, itemId: string) {
    return db.transaction(async tx => {
      const [item] = await tx.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.id, itemId), eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.location, 'EQUIPPED')))
        .for('update').limit(1);
      if (!item || !item.equippedHeroId) throw new EquipmentError('Equipped item not found.', 404);
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, item.equippedHeroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      await tx.update(equipmentInstances).set({ location: 'INVENTORY', equippedHeroId: null })
        .where(eq(equipmentInstances.id, item.id));
      if (hero) {
        const hpGear = await tx.select({ bonusHp: equipmentTemplates.bonusHp })
          .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
          .where(and(eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.equippedHeroId, hero.id), eq(equipmentInstances.location, 'EQUIPPED')));
        const maxHp = hero.maxHp + hpGear.reduce((sum, row) => sum + row.bonusHp, 0);
        await tx.update(heroes).set({ hp: Math.min(hero.hp, maxHp), updatedAt: new Date() }).where(eq(heroes.id, hero.id));
      }
      return { ...item, location: 'INVENTORY', equippedHeroId: null };
    });
  }

  public async floorDrops(masterId: string) {
    return db.select({ equipment: equipmentInstances, template: equipmentTemplates, floor: equipmentInstances.dropFloor })
      .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
      .innerJoin(worlds, eq(equipmentInstances.dropWorldId, worlds.id))
      .where(and(eq(worlds.masterId, masterId), eq(equipmentInstances.location, 'FLOOR_DROP')))
      .orderBy(asc(equipmentInstances.dropFloor), asc(equipmentInstances.droppedAt));
  }

  public async pickUp(masterId: string, itemId: string) {
    return db.transaction(async tx => {
      const [item] = await tx.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.id, itemId), eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.location, 'FLOOR_DROP')))
        .for('update').limit(1);
      if (!item || !item.dropWorldId) throw new EquipmentError('Floor drop not found in this Master\'s World.', 404);
      const [world] = await tx.select().from(worlds)
        .where(and(eq(worlds.id, item.dropWorldId), eq(worlds.masterId, masterId))).limit(1);
      if (!world) throw new EquipmentError('Floor drop is not in this Master\'s World.', 404);
      const [updated] = await tx.update(equipmentInstances).set({
        location: 'INVENTORY', dropWorldId: null, dropFloor: null, pickedUpAt: new Date(),
      }).where(eq(equipmentInstances.id, item.id)).returning();
      return updated;
    });
  }
}
