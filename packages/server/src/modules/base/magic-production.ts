import { and, asc, eq, sql } from 'drizzle-orm';
import { v4 as uuid } from 'uuid';
import { db } from '../../database/db.js';
import type { GameDatabase, GameTransaction } from '../../database/transaction.js';
import { baseBuildings, buildingWorkerAssignments, heroes, magicProductionNodes, masterItems, masters } from '../../database/drizzle-schema.js';
import { accruedStored, buildingProductionForLevel } from './base-rules.js';

export const RETIRED_MAGIC_BUILDINGS = ['LIBRARY', 'ALCHEMY_WORKSHOP', 'MAGIC_RESEARCH_LAB'];
const WINGS = ['LIBRARY', 'ALCHEMY_WORKSHOP'];

export async function magicSnapshot(connection: GameDatabase, buildingId: string, now = new Date()) {
  const workers = await connection.select({ id: heroes.id, classCode: heroes.classCode, hp: heroes.hp, state: heroes.state,
    boost: buildingWorkerAssignments.efficiencyBoost }).from(buildingWorkerAssignments)
    .innerJoin(heroes, eq(heroes.id, buildingWorkerAssignments.heroInstanceId))
    .where(eq(buildingWorkerAssignments.buildingId, buildingId)).orderBy(asc(buildingWorkerAssignments.assignedAt), asc(buildingWorkerAssignments.id));
  const living = workers.filter(w => w.hp > 0 && !['DEAD','DISABLED'].includes(w.state));
  const library = living.filter(w => w.classCode === 'MAGE').slice(0, 2);
  const libraryIds = new Set(library.map(w => w.id));
  const alchemy = living.filter(w => !libraryIds.has(w.id)).slice(0, 2);
  const nodes = await connection.select().from(magicProductionNodes).where(eq(magicProductionNodes.buildingId, buildingId));
  return nodes.map(node => {
    const assigned = node.wing === 'LIBRARY' ? library : alchemy;
    const rate = node.wing === 'LIBRARY' && !assigned.length ? 0
      : node.baseRatePerHour * (1 + assigned.reduce((sum, w) => sum + Math.max(0, w.boost - 1), 0));
    const accrued = accruedStored(node.currentStored, rate, node.lastHarvestAt, node.maxCapacity, now);
    return { ...node, ratePerHour: rate, capacity: node.maxCapacity, stored: accrued.stored, atCapacity: accrued.atCapacity,
      workerIds: assigned.map(w => w.id), requiresMageWorker: node.wing === 'LIBRARY' };
  });
}

/** Keep production in the Hall; the wing codes describe functions, never buildable plots. */
export async function updateMagicProduction(tx: GameTransaction, hall: typeof baseBuildings.$inferSelect, level: number, now: Date) {
  const old = await magicSnapshot(tx, hall.id, now);
  for (const wing of WINGS) {
    const profile = buildingProductionForLevel(wing, level)!;
    const node = old.find(row => row.wing === wing);
    let stored = node?.stored ?? 0;
    if (node && node.resourceType !== profile.resourceType && stored > 0) {
      // Preserve the old tier's output; never convert basic books into advanced books.
      const quantity = Math.ceil(stored);
      await tx.insert(masterItems).values({id: uuid(), masterId: hall.masterId, itemId: node.resourceType, quantity, updatedAt: now})
        .onConflictDoUpdate({target:[masterItems.masterId,masterItems.itemId],set:{quantity:sql`${masterItems.quantity} + ${quantity}`,updatedAt:now}});
      stored = 0;
    }
    await tx.insert(magicProductionNodes).values({id:node?.id ?? uuid(),buildingId:hall.id,wing,resourceType:profile.resourceType,
      baseRatePerHour:profile.ratePerHour,maxCapacity:profile.capacity,currentStored:Math.min(stored,profile.capacity),lastHarvestAt:now})
      .onConflictDoUpdate({target:[magicProductionNodes.buildingId,magicProductionNodes.wing],set:{resourceType:profile.resourceType,
        baseRatePerHour:profile.ratePerHour,maxCapacity:profile.capacity,currentStored:Math.min(stored,profile.capacity),lastHarvestAt:now}});
  }
}

export async function collectMagic(masterId: string, buildingId: string) {
  return db.transaction(async tx => {
    await tx.select({id:masters.id}).from(masters).where(eq(masters.id,masterId)).for('update');
    const [hall] = await tx.select().from(baseBuildings).where(and(eq(baseBuildings.id,buildingId),eq(baseBuildings.masterId,masterId))).for('update');
    if (!hall || hall.buildingType !== 'HALL_OF_MAGIC' || hall.status !== 'READY') return null;
    const now = new Date(), nodes = await magicSnapshot(tx,buildingId,now);
    const resources: {resourceType:string;collected:number;wing:string}[] = [];
    for (const node of nodes) {
      const amount = Math.floor(node.stored);
      if (amount > 0) {
        await tx.insert(masterItems).values({id:uuid(),masterId,itemId:node.resourceType,quantity:amount,updatedAt:now})
          .onConflictDoUpdate({target:[masterItems.masterId,masterItems.itemId],set:{quantity:sql`${masterItems.quantity} + ${amount}`,updatedAt:now}});
        resources.push({resourceType:node.resourceType,collected:amount,wing:node.wing});
      }
      await tx.update(magicProductionNodes).set({currentStored:node.stored-amount,lastHarvestAt:now}).where(eq(magicProductionNodes.id,node.id));
    }
    return {collected:resources.reduce((sum,r)=>sum+r.collected,0),resourceType:'MAGIC_OUTPUT',resources,
      atCapacity:nodes.some(n=>n.atCapacity),workerIds:[...new Set(nodes.flatMap(n=>n.workerIds))]};
  });
}
