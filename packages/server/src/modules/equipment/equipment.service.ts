import { and, asc, eq } from 'drizzle-orm';
import { db } from '../../database/db.js';
import {
  equipmentInstances, equipmentTemplates, heroes, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  aggregateEquipment, type EquipmentItemInput, type EquipmentV2Stats,
} from '@infiniti-gacha/shared';
import { isV2Origin } from '../hero/hero-progression.js';

export class EquipmentError extends Error {
  constructor(message: string, public readonly statusCode: number) { super(message); }
}

async function syncHeroEquippedHp(tx: any, masterId: string, hero: typeof heroes.$inferSelect) {
  const gearRows = await tx.select({ item: equipmentInstances, template: equipmentTemplates })
    .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
    .where(and(eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.equippedHeroId, hero.id), eq(equipmentInstances.location, 'EQUIPPED')));

  let bonusMaxHp = 0;
  if (isV2Origin(hero.originStats)) {
    const items: EquipmentItemInput[] = gearRows.map((row: any) => ({
      slotType: row.template.slotType,
      bonusHp: row.template.bonusHp,
      bonusAttack: row.template.bonusAttack,
      bonusDefense: row.template.bonusDefense,
      bonusSpeed: row.template.bonusSpeed,
      bonusStr: row.template.bonusStr,
      bonusInt: row.template.bonusInt,
      bonusSta: row.template.bonusSta,
      bonusAgi: row.template.bonusAgi,
      bonusMatk: row.template.bonusMatk,
      bonusMdef: row.template.bonusMdef,
      v2Stats: (row.template.v2Stats as EquipmentV2Stats) ?? null,
      statMultiplier: row.item.statMultiplier ?? 1,
      substats: (row.item.substats as EquipmentV2Stats) ?? null,
    }));
    const agg = aggregateEquipment(items);
    bonusMaxHp = 20 * agg.baseStats.sta + (agg.derivedOffsets.hpBase ?? 0);
  } else {
    bonusMaxHp = gearRows.reduce((sum: number, row: any) => sum + row.template.bonusHp, 0);
  }
  const effectiveMaxHp = hero.maxHp + bonusMaxHp;
  await tx.update(heroes).set({ hp: Math.min(hero.hp, effectiveMaxHp), updatedAt: new Date() }).where(eq(heroes.id, hero.id));
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
      await syncHeroEquippedHp(tx, masterId, hero);
      return { equipment: equipped, template };
    });
  }

  public async unequip(masterId: string, itemId: string) {
    return db.transaction(async tx => {
      // Follow the same Master -> Hero/item order as PvE settlement and equip.
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      const [item] = await tx.select().from(equipmentInstances)
        .where(and(eq(equipmentInstances.id, itemId), eq(equipmentInstances.masterId, masterId), eq(equipmentInstances.location, 'EQUIPPED')))
        .for('update').limit(1);
      if (!item || !item.equippedHeroId) throw new EquipmentError('Equipped item not found.', 404);
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, item.equippedHeroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      await tx.update(equipmentInstances).set({ location: 'INVENTORY', equippedHeroId: null })
        .where(eq(equipmentInstances.id, item.id));
      if (hero) {
        await syncHeroEquippedHp(tx, masterId, hero);
      }
      return { ...item, location: 'INVENTORY', equippedHeroId: null };
    });
  }

  public async quickEquip(masterId: string, heroId: string) {
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new EquipmentError('Hero not found for this Master.', 404);
      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) {
        throw new EquipmentError('Only an active Hero can equip items.', 409);
      }

      const currentEquipped = await tx.select({ equipment: equipmentInstances, template: equipmentTemplates })
        .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
        .where(and(
          eq(equipmentInstances.masterId, masterId),
          eq(equipmentInstances.equippedHeroId, heroId),
          eq(equipmentInstances.location, 'EQUIPPED')
        )).for('update');

      const unequipped = await tx.select({ equipment: equipmentInstances, template: equipmentTemplates })
        .from(equipmentInstances).innerJoin(equipmentTemplates, eq(equipmentInstances.templateCode, equipmentTemplates.code))
        .where(and(
          eq(equipmentInstances.masterId, masterId),
          eq(equipmentInstances.location, 'INVENTORY')
        )).for('update');

      const calcScore = (row: { equipment: typeof equipmentInstances.$inferSelect; template: typeof equipmentTemplates.$inferSelect }) => {
        const v2 = (row.template.v2Stats ?? {}) as Record<string, number>;
        const v2Total = Object.values(v2).reduce((sum: number, v: any) => sum + (typeof v === 'number' ? v : 0), 0);
        return (row.template.rarity * 1000)
          + (row.equipment.enhanceLevel * 100)
          + (row.template.bonusAttack * 3)
          + (row.template.bonusMatk * 3)
          + (row.template.bonusDefense * 2)
          + (row.template.bonusHp * 0.2)
          + (row.template.bonusSpeed * 2)
          + (row.template.bonusStr * 2)
          + (row.template.bonusInt * 2)
          + (row.template.bonusSta * 2)
          + (row.template.bonusAgi * 2)
          + v2Total;
      };

      const equippedBySlot = new Map<string, typeof currentEquipped[0]>();
      for (const row of currentEquipped) {
        equippedBySlot.set(row.template.slotType, row);
      }

      const bestCandidatesBySlot = new Map<string, typeof unequipped[0]>();
      for (const row of unequipped) {
        const slot = row.template.slotType;
        const currentBest = bestCandidatesBySlot.get(slot);
        if (!currentBest || calcScore(row) > calcScore(currentBest)) {
          bestCandidatesBySlot.set(slot, row);
        }
      }

      let equipCount = 0;
      const equippedList: typeof unequipped = [];

      for (const [slot, candidate] of bestCandidatesBySlot.entries()) {
        const current = equippedBySlot.get(slot);
        const candScore = calcScore(candidate);
        const currScore = current ? calcScore(current) : -1;

        if (candScore > currScore) {
          if (current) {
            await tx.update(equipmentInstances).set({
              location: 'INVENTORY',
              equippedHeroId: null,
            }).where(eq(equipmentInstances.id, current.equipment.id));
          }
          const [updated] = await tx.update(equipmentInstances).set({
            location: 'EQUIPPED',
            equippedHeroId: heroId,
          }).where(eq(equipmentInstances.id, candidate.equipment.id)).returning();

          equippedList.push({ equipment: updated, template: candidate.template });
          equipCount++;
        }
      }

      await syncHeroEquippedHp(tx, masterId, hero);
      return { ok: true, equippedCount: equipCount, equipped: equippedList };
    });
  }

  public async quickUnequip(masterId: string, heroId: string) {
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new EquipmentError('Hero not found for this Master.', 404);

      const items = await tx.select().from(equipmentInstances)
        .where(and(
          eq(equipmentInstances.masterId, masterId),
          eq(equipmentInstances.equippedHeroId, heroId),
          eq(equipmentInstances.location, 'EQUIPPED')
        )).for('update');

      if (items.length > 0) {
        await tx.update(equipmentInstances).set({
          location: 'INVENTORY',
          equippedHeroId: null
        }).where(and(
          eq(equipmentInstances.masterId, masterId),
          eq(equipmentInstances.equippedHeroId, heroId),
          eq(equipmentInstances.location, 'EQUIPPED')
        ));
      }

      await syncHeroEquippedHp(tx, masterId, hero);
      return { ok: true, unequippedCount: items.length };
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
