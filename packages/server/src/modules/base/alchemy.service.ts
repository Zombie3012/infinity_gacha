import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuid } from 'uuid';
import { db } from '../../database/db.js';
import type { GameTransaction } from '../../database/transaction.js';
import { alchemyResearch, baseBuildings, heroConsumables, heroes, heroInjuries, heroTreatments, masterItems, masters, pveHeroReservations, pveSquads, worlds, currencyTransactions } from '../../database/drizzle-schema.js';
import { ALCHEMY_TECH, HERB, POTION_NAMES, POTION_CRAFT_SILVER, POTION_CRAFT_HERBS, MANA_RESTORE_RATIO, validateConsumables, type ConsumableConfig } from './alchemy-rules.js';
import { PveError } from '../pve/pve.service.js';
import { isV2Origin } from '../hero/hero-progression.js';

export async function addItem(tx: GameTransaction, masterId: string, itemId: string, quantity: number) {
  if (!quantity) return;
  await tx.insert(masterItems).values({ id: uuid(), masterId, itemId, quantity })
    .onConflictDoUpdate({ target: [masterItems.masterId, masterItems.itemId], set: { quantity: sql`${masterItems.quantity} + ${quantity}` } });
}
async function spend(tx: GameTransaction, masterId: string, silver: number, herbs: number, operation: string) {
  const [m] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
  const [h] = await tx.select().from(masterItems).where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, HERB))).for('update');
  if (Number(m?.silverCoins ?? 0) < silver || (h?.quantity ?? 0) < herbs) throw new PveError('ERR_ALCHEMY_MISSING_RESOURCES');
  await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${silver}` }).where(eq(masters.id, masterId));
  await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${herbs}` }).where(eq(masterItems.id, h!.id));
  await tx.insert(currencyTransactions).values({id:uuid(),masterId,currencyType:'SILVER',amountDelta:-BigInt(silver),transactionType:operation});
}
async function requireHall(tx: GameTransaction, masterId: string) {
  const [hall] = await tx.select().from(baseBuildings).where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, 'HALL_OF_MAGIC'), eq(baseBuildings.status, 'READY')));
  if (!hall) throw new PveError('ERR_ALCHEMY_HALL_REQUIRED');
}
export const alchemyService = {
  async state(masterId: string) {
    const learned = (await db.select().from(alchemyResearch).where(eq(alchemyResearch.masterId, masterId))).map(r => r.code);
    const stock = await db.select().from(masterItems).where(eq(masterItems.masterId, masterId));
    const configs = await db.select().from(heroConsumables).where(eq(heroConsumables.masterId, masterId));
    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).orderBy(asc(worlds.createdAt),asc(worlds.id)).limit(1);
    return { technologies: ALCHEMY_TECH.map(t => ({ ...t, researched: learned.includes(t.code) })),
      recipes: ALCHEMY_TECH.filter(t => t.itemId).map(t => ({ code: t.itemId!, name: POTION_NAMES[t.itemId!], unlocked: learned.includes(t.code), silver: POTION_CRAFT_SILVER, herbItemId: HERB, herbs: POTION_CRAFT_HERBS })),
      stock, loadouts: configs, futureBranches: [{ code: 'SKY_HARBOR', name: 'Bến Thiên Hành', planned: true, milestoneReached: (world?.currentFloor ?? 1) > 25, requiredClearedFloor: 25 }] };
  },
  async research(tx: GameTransaction, masterId: string, code: string) {
    await requireHall(tx, masterId);
    const tech = ALCHEMY_TECH.find(t => t.code === code);
    if (!tech) throw new PveError('ERR_ALCHEMY_TECH_NOT_FOUND', 404);
    const learned = (await tx.select().from(alchemyResearch).where(eq(alchemyResearch.masterId, masterId))).map(r => r.code);
    if (learned.includes(code)) throw new PveError('ERR_ALCHEMY_ALREADY_RESEARCHED');
    if (tech.prerequisite && !learned.includes(tech.prerequisite)) throw new PveError('ERR_ALCHEMY_PREREQUISITE');
    await spend(tx, masterId, tech.silver, tech.herbs, 'ALCHEMY_RESEARCH');
    await tx.insert(alchemyResearch).values({ masterId, code });
    return { code, researched: true };
  },
  async craft(tx: GameTransaction, masterId: string, code: string, quantity: number) {
    await requireHall(tx, masterId);
    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 99) throw new PveError('ERR_ALCHEMY_QUANTITY', 400);
    const tech = ALCHEMY_TECH.find(t => t.itemId === code);
    if (!tech) throw new PveError('ERR_ALCHEMY_RECIPE_NOT_FOUND', 404);
    if (!(await tx.select().from(alchemyResearch).where(and(eq(alchemyResearch.masterId, masterId), eq(alchemyResearch.code, tech.code)))).length) throw new PveError('ERR_ALCHEMY_RECIPE_LOCKED');
    await spend(tx, masterId, POTION_CRAFT_SILVER * quantity, POTION_CRAFT_HERBS * quantity, 'ALCHEMY_CRAFT');
    await addItem(tx, masterId, code, quantity);
    return { itemId: code, quantity };
  },
  async configure(tx: GameTransaction, masterId: string, heroId: string, input: unknown) {
    let config: ConsumableConfig;
    try { config = validateConsumables(input); } catch { throw new PveError('ERR_CONSUMABLE_CONFIG', 400); }
    const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
    if (!hero || hero.hp <= 0 || ['DEAD','DISABLED'].includes(hero.state)) throw new PveError('ERR_PVE_HERO_UNAVAILABLE');
    if ((await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.heroId, heroId))).length) throw new PveError('ERR_PVE_HERO_DEPLOYED');
    await tx.insert(heroConsumables).values({ heroId, masterId, config }).onConflictDoUpdate({ target: heroConsumables.heroId, set: { config } });
    return { heroId, config };
  },
  async use(tx: GameTransaction, masterId: string, heroId: string, itemId: string, slotIndex?: number) {
    const [hero] = await tx.select().from(heroes).where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update');
    if (!hero || hero.hp <= 0 || ['DEAD','DISABLED'].includes(hero.state)) throw new PveError('ERR_PVE_HERO_UNAVAILABLE');
    const [reservation] = await tx.select().from(pveHeroReservations).where(eq(pveHeroReservations.heroId, heroId));
    const [bag] = await tx.select().from(heroConsumables).where(eq(heroConsumables.heroId, heroId)).for('update');
    if (reservation) {
      const [squad] = await tx.select().from(pveSquads).where(eq(pveSquads.id, reservation.squadId));
      if (squad?.status === 'FIGHTING') throw new PveError('ERR_PVE_SQUAD_FIGHTING');
      await tx.execute(sql`select set_config('app.pve_map_id', ${reservation.mapId}, true)`);
    }
    if (!['MEDICINE','MANA_POTION','STRENGTH_POTION'].includes(itemId)) throw new PveError('ERR_ALCHEMY_ITEM', 400);
    const mpPct = isV2Origin(hero.originStats) ? hero.currentMpPct : hero.mp / Math.max(1,hero.maxMp);
    if (itemId === 'MANA_POTION' && (hero.maxMp <= 0 || mpPct >= 1)) throw new PveError('ERR_COMBAT_MP_FULL');
    if (itemId === 'STRENGTH_POTION' && bag?.strengthReady) throw new PveError('ERR_COMBAT_BUFF_ACTIVE');
    if (itemId === 'MEDICINE' && hero.hp >= hero.maxHp && !(await tx.select().from(heroInjuries).where(and(eq(heroInjuries.heroId,heroId),sql`${heroInjuries.healedAt} IS NULL`))).length) throw new PveError('ERR_COMBAT_HP_FULL');
    if (reservation) {
      if (!bag || bag.squadId !== reservation.squadId || !Number.isInteger(slotIndex) || slotIndex! < 0 || slotIndex! > 4) throw new PveError('ERR_CONSUMABLE_SLOT', 400);
      const slot = bag.config.slots[slotIndex!];
      if (!slot || slot.itemId !== itemId || slot.quantity < 1) throw new PveError('ERR_CONSUMABLE_STOCK');
      slot.quantity--;
      if (!slot.quantity) bag.config.slots[slotIndex!] = null;
      await tx.update(heroConsumables).set({config:bag.config}).where(eq(heroConsumables.heroId, heroId));
    } else {
      const spent = await tx.update(masterItems).set({quantity:sql`${masterItems.quantity} - 1`})
        .where(and(eq(masterItems.masterId,masterId),eq(masterItems.itemId,itemId),sql`${masterItems.quantity} > 0`)).returning();
      if (!spent.length) throw new PveError('ERR_CONSUMABLE_STOCK');
    }
    if (itemId === 'MANA_POTION') {
      const pct = Math.min(1, mpPct + MANA_RESTORE_RATIO);
      await tx.update(heroes).set({mp:Math.round(hero.maxMp*pct),currentMpPct:pct}).where(eq(heroes.id,heroId));
    } else if (itemId === 'STRENGTH_POTION') {
      if (bag) await tx.update(heroConsumables).set({strengthReady:true}).where(eq(heroConsumables.heroId,heroId));
      else await tx.insert(heroConsumables).values({heroId,masterId,strengthReady:true,config:{slots:[null,null,null,null,null],autoManaBelow:30,autoStrength:true}});
    } else {
      await tx.update(heroInjuries).set({healedAt:new Date(),healedBy:'EMERGENCY'}).where(and(eq(heroInjuries.heroId,heroId),sql`${heroInjuries.healedAt} IS NULL`));
      await tx.update(heroTreatments).set({status:'COMPLETED',completedAt:new Date()}).where(and(eq(heroTreatments.heroId,heroId),inArray(heroTreatments.status,['ACTIVE','QUEUED'])));
      await tx.update(heroes).set({hp:hero.maxHp,currentHpPct:1,state:'HEALTHY'}).where(eq(heroes.id,heroId));
    }
    return {heroId,itemId,used:1};
  },
};

export async function reserveConsumables(tx: GameTransaction, masterId: string, squadId: string, heroIds: string[]) {
  const loadouts = await tx.select().from(heroConsumables).where(and(eq(heroConsumables.masterId, masterId), inArray(heroConsumables.heroId, heroIds))).for('update');
  for (const row of loadouts) {
    if (row.squadId) throw new PveError('ERR_CONSUMABLE_RESERVED');
    for (const slot of row.config.slots) if (slot) {
      const spent = await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${slot.quantity}` })
        .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, slot.itemId), sql`${masterItems.quantity} >= ${slot.quantity}`)).returning();
      if (!spent.length) throw new PveError('ERR_CONSUMABLE_STOCK');
    }
    await tx.update(heroConsumables).set({ squadId }).where(eq(heroConsumables.heroId, row.heroId));
  }
}
export async function returnConsumables(tx: GameTransaction, masterId: string, squadIds: string[]) {
  if (!squadIds.length) return;
  const rows = await tx.select().from(heroConsumables).where(and(eq(heroConsumables.masterId, masterId), inArray(heroConsumables.squadId, squadIds)));
  for (const row of rows) {
    for (const slot of row.config.slots) if (slot) await addItem(tx, masterId, slot.itemId, slot.quantity);
    await tx.update(heroConsumables).set({ squadId: null, config: { ...row.config, slots: [null,null,null,null,null] }, strengthReady: false }).where(eq(heroConsumables.heroId, row.heroId));
  }
}
