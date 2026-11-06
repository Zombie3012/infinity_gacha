import { and, asc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { survivalService } from '../survival/survival.service.js';
import {
  baseBuildings, baseProductionNodes, buildingTypes, buildingWorkerAssignments, heroes, masterItems, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  MAX_BASE_ZONES, PARTY_MANSION_REQUIRED_MASTER_LEVEL, PARTY_MANSION_UPGRADE_COST_SILVER,
  accruedStored, capacityForLevel, constructionSeconds, demolishRefundSilver,
  expansionCostSilver, expansionRequiredWorldLevel, plotsForZones, productionRatePerHour,
  requiredMasterLevelForFloor, unlockedLobbyFloorsForMasterLevel,
  upgradeCostSilver, upgradeMaterials, upgradeSeconds, worldLevelForFloor,
} from './base-rules.js';

export class BaseError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'BaseError';
  }
}

type ProductionProfile = { resourceType: string; ratePerHour: number; capacity: number };

const asProfile = (value: unknown): ProductionProfile | null => {
  if (!value || typeof value !== 'object') return null;
  const raw = value as Record<string, unknown>;
  if (typeof raw.resourceType !== 'string' || typeof raw.ratePerHour !== 'number' || typeof raw.capacity !== 'number') return null;
  return { resourceType: raw.resourceType, ratePerHour: raw.ratePerHour, capacity: raw.capacity };
};

/** Sample worker efficiency: +5% per Hero level, capped at +25%. */
export function workerBoostForLevel(level: number): number {
  const boost = 1 + Math.min(0.25, Math.max(0, Math.floor(level)) * 0.05);
  return Math.round(boost * 100) / 100;
}

export class BuildingService {
  private async world(masterId: string) {
    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
    if (!world) throw new BaseError('World chưa được khởi tạo.', 409);
    return world;
  }

  private async master(masterId: string) {
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new BaseError('Không tìm thấy Master.', 404);
    return master;
  }

  /** Finish construction/upgrade timers whose deadline has passed. */
  private async settle(masterId: string, now = new Date()) {
    const pending = await db.select().from(baseBuildings).where(and(
      eq(baseBuildings.masterId, masterId),
      inArray(baseBuildings.status, ['CONSTRUCTING', 'UPGRADING']),
    ));
    const due = pending.filter(row => row.upgradeFinishesAt && row.upgradeFinishesAt <= now);
    if (due.length === 0) return;

    const typeCodes = [...new Set(due.map(row => row.buildingType))];
    const types = await db.select().from(buildingTypes).where(inArray(buildingTypes.code, typeCodes));
    const typeByCode = new Map(types.map(row => [row.code, row]));

    for (const row of due) {
      const type = typeByCode.get(row.buildingType);
      if (row.status === 'CONSTRUCTING') {
        await db.update(baseBuildings).set({ status: 'READY', upgradeFinishesAt: null, updatedAt: now })
          .where(eq(baseBuildings.id, row.id));
        const profile = asProfile(type?.production);
        if (profile) {
          await db.insert(baseProductionNodes).values({
            id: uuidv4(),
            buildingId: row.id,
            resourceType: profile.resourceType,
            baseRatePerHour: profile.ratePerHour,
            currentStored: 0,
            maxCapacity: capacityForLevel(profile.capacity, 1),
            lastHarvestAt: now,
          }).onConflictDoNothing();
        }
      } else {
        const level = Math.min(type?.maxLevel ?? 5, row.level + 1);
        await db.update(baseBuildings).set({ status: 'READY', level, upgradeFinishesAt: null, updatedAt: now })
          .where(eq(baseBuildings.id, row.id));
        const profile = asProfile(type?.production);
        if (profile) {
          await db.update(baseProductionNodes).set({ maxCapacity: capacityForLevel(profile.capacity, level) })
            .where(eq(baseProductionNodes.buildingId, row.id));
        }
      }
    }
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const master = await this.master(masterId);
    const world = await this.world(masterId);
    const worldLevel = worldLevelForFloor(world.currentFloor);
    const types = await db.select().from(buildingTypes).orderBy(asc(buildingTypes.code));
    const buildings = await db.select().from(baseBuildings)
      .where(eq(baseBuildings.masterId, masterId)).orderBy(asc(baseBuildings.plotIndex));
    const nodes = buildings.length === 0 ? [] : await db.select().from(baseProductionNodes)
      .where(inArray(baseProductionNodes.buildingId, buildings.map(row => row.id)));
    const assignments = buildings.length === 0 ? [] : await db.select({
      id: buildingWorkerAssignments.id,
      buildingId: buildingWorkerAssignments.buildingId,
      heroInstanceId: buildingWorkerAssignments.heroInstanceId,
      efficiencyBoost: buildingWorkerAssignments.efficiencyBoost,
      heroName: heroes.name,
      heroLevel: heroes.level,
      heroState: heroes.state,
    }).from(buildingWorkerAssignments)
      .innerJoin(heroes, eq(heroes.id, buildingWorkerAssignments.heroInstanceId))
      .where(inArray(buildingWorkerAssignments.buildingId, buildings.map(row => row.id)));

    const now = new Date();
    const nodeByBuilding = new Map(nodes.map(node => [node.buildingId, node]));
    const workersByBuilding = new Map<string, typeof assignments>();
    for (const assignment of assignments) {
      const list = workersByBuilding.get(assignment.buildingId) ?? [];
      list.push(assignment);
      workersByBuilding.set(assignment.buildingId, list);
    }

    const typeByCode = new Map(types.map(type => [type.code, type]));
    const plots = Array.from({ length: plotsForZones(world.baseZones) }, (_, index) => index + 1);
    const rows = buildings.map(building => {
      const type = typeByCode.get(building.buildingType);
      const node = nodeByBuilding.get(building.id);
      const workers = workersByBuilding.get(building.id) ?? [];
      const profile = asProfile(type?.production);
      const boosts = workers.map(worker => worker.efficiencyBoost);
      const rate = profile ? productionRatePerHour(node?.baseRatePerHour ?? profile.ratePerHour, building.level, boosts) : 0;
      const capacity = node ? node.maxCapacity : profile ? capacityForLevel(profile.capacity, building.level) : 0;
      const accrued = node
        ? accruedStored(node.currentStored, rate, node.lastHarvestAt, capacity, now)
        : { stored: 0, atCapacity: false, hoursElapsed: 0 };
      return {
        ...building,
        typeName: type?.name ?? building.buildingType,
        category: type?.category ?? 'PRODUCTION',
        maxLevel: type?.maxLevel ?? 5,
        maxWorkers: type?.maxWorkers ?? 0,
        ratePerHour: Math.round(rate * 100) / 100,
        capacity,
        stored: accrued.stored,
        atCapacity: accrued.atCapacity,
        resourceType: node?.resourceType ?? profile?.resourceType ?? null,
        workers,
      };
    });

    const nextZone = world.baseZones + 1;
    const canExpandZone = nextZone <= MAX_BASE_ZONES;
    const unlockedLobbyFloors = Math.max(world.baseZones, unlockedLobbyFloorsForMasterLevel(master.level));
    return {
      master: {
        id: master.id,
        level: master.level,
        silverCoins: master.silverCoins.toString(),
      },
      world: {
        id: world.id,
        currentFloor: world.currentFloor,
        worldLevel,
        baseZones: world.baseZones,
        plots: plotsForZones(world.baseZones),
        unlockedLobbyFloors,
      },
      expansion: {
        canExpand: canExpandZone,
        nextZone: canExpandZone ? nextZone : null,
        costSilver: canExpandZone ? expansionCostSilver(world.baseZones) : null,
        requiredWorldLevel: canExpandZone ? expansionRequiredWorldLevel(nextZone) : null,
        requiredMasterLevel: canExpandZone ? requiredMasterLevelForFloor(nextZone) : null,
        maxZones: MAX_BASE_ZONES,
      },
      buildingTypes: types.map(type => ({
        ...type,
        production: asProfile(type.production),
        requiredMasterLevel: type.code === 'PARTY_MANSION' ? PARTY_MANSION_REQUIRED_MASTER_LEVEL : 1,
        unlocked: worldLevel >= type.requiredWorldLevel && (type.code !== 'PARTY_MANSION' || master.level >= PARTY_MANSION_REQUIRED_MASTER_LEVEL),
      })),
      buildings: rows,
      plots,
    };
  }

  async construct(masterId: string, buildingTypeCode: unknown, plotIndexInput: unknown) {
    await this.settle(masterId);
    const code = typeof buildingTypeCode === 'string' ? buildingTypeCode : '';
    const plotIndex = Number(plotIndexInput);
    if (!Number.isInteger(plotIndex) || plotIndex < 1) throw new BaseError('plotIndex không hợp lệ.');

    const master = await this.master(masterId);
    const world = await this.world(masterId);
    const worldLevel = worldLevelForFloor(world.currentFloor);
    const [type] = await db.select().from(buildingTypes).where(eq(buildingTypes.code, code)).limit(1);
    if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
    if (type.code === 'PARTY_MANSION' && master.level < PARTY_MANSION_REQUIRED_MASTER_LEVEL) {
      throw new BaseError(`Party Mansion cần Master đạt cấp ${PARTY_MANSION_REQUIRED_MASTER_LEVEL}.`, 409);
    }
    if (worldLevel < type.requiredWorldLevel && master.level < requiredMasterLevelForFloor(type.requiredWorldLevel + 1)) {
      throw new BaseError(`Công trình cần World Level ${type.requiredWorldLevel}.`, 409);
    }
    const maxUnlockedPlots = plotsForZones(Math.max(world.baseZones, unlockedLobbyFloorsForMasterLevel(master.level)));
    if (plotIndex > maxUnlockedPlots) throw new BaseError('Ô đất chưa được mở khóa.', 409);

    const now = new Date();
    const created = await db.transaction(async tx => {
      const [existing] = await tx.select({ id: baseBuildings.id }).from(baseBuildings)
        .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.plotIndex, plotIndex))).limit(1);
      if (existing) throw new BaseError('Ô đất đã có công trình.', 409);
      if (master.silverCoins < BigInt(type.buildCostSilver)) throw new BaseError('Không đủ Xu Bạc để xây dựng.', 409);

      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${type.buildCostSilver}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      const [building] = await tx.insert(baseBuildings).values({
        id: uuidv4(),
        masterId,
        buildingType: type.code,
        plotIndex,
        level: 1,
        durability: 100,
        status: 'CONSTRUCTING',
        upgradeFinishesAt: new Date(now.getTime() + constructionSeconds(1) * 1000),
        createdAt: now,
        updatedAt: now,
      }).returning();
      return building;
    });

    return { building: created, silverSpent: type.buildCostSilver };
  }

  async upgrade(masterId: string, buildingId: string) {
    await this.settle(masterId);
    const master = await this.master(masterId);
    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.status !== 'READY') throw new BaseError('Công trình đang trong quá trình thi công.', 409);

    const [type] = await db.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
    if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
    const targetLevel = building.level + 1;
    if (targetLevel > type.maxLevel) throw new BaseError(`Công trình đã đạt cấp tối đa ${type.maxLevel}.`, 409);

    const silverCost = upgradeCostSilver(type.buildCostSilver, targetLevel);
    if (master.silverCoins < BigInt(silverCost)) throw new BaseError('Không đủ Xu Bạc để nâng cấp.', 409);
    const materials = upgradeMaterials(targetLevel);
    const owned = await db.select().from(masterItems)
      .where(and(eq(masterItems.masterId, masterId), inArray(masterItems.itemId, materials.map(row => row.itemId))));
    const ownedByItem = new Map(owned.map(row => [row.itemId, row.quantity]));
    const missing = materials.filter(row => (ownedByItem.get(row.itemId) ?? 0) < row.quantity);
    if (missing.length > 0) {
      throw new BaseError(`Thiếu nguyên liệu: ${missing.map(row => `${row.itemId} ×${row.quantity}`).join(', ')}.`, 409);
    }

    const now = new Date();
    const updated = await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${silverCost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      for (const material of materials) {
        await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${material.quantity}`, updatedAt: now })
          .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, material.itemId)));
      }
      const [row] = await tx.update(baseBuildings).set({
        status: 'UPGRADING',
        upgradeFinishesAt: new Date(now.getTime() + upgradeSeconds(targetLevel) * 1000),
        updatedAt: now,
      }).where(eq(baseBuildings.id, building.id)).returning();
      return row;
    });

    return { building: updated, silverSpent: silverCost, materialsSpent: materials, targetLevel };
  }

  async demolish(masterId: string, buildingId: string) {
    await this.settle(masterId);
    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.status !== 'READY') throw new BaseError('Không thể phá dỡ công trình đang thi công.', 409);

    const [type] = await db.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
    if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
    const refund = demolishRefundSilver(type.buildCostSilver, building.level);
    const now = new Date();

    await db.transaction(async tx => {
      await tx.delete(baseBuildings).where(eq(baseBuildings.id, building.id));
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} + ${refund}`, updatedAt: now })
        .where(eq(masters.id, masterId));
    });

    return { demolished: building.id, refundSilver: refund };
  }

  async configureProduction(masterId: string, buildingId: string, resourceType: unknown) {
    await this.settle(masterId);
    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.status !== 'READY') throw new BaseError('Công trình chưa sẵn sàng.', 409);

    const [type] = await db.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
    const profile = asProfile(type?.production);
    if (!profile) throw new BaseError('Công trình này không sản xuất tài nguyên.', 409);
    const requested = typeof resourceType === 'string' && resourceType ? resourceType : profile.resourceType;
    if (requested !== profile.resourceType) {
      throw new BaseError(`Công trình chỉ sản xuất ${profile.resourceType}.`, 400);
    }

    const [node] = await db.select().from(baseProductionNodes).where(eq(baseProductionNodes.buildingId, building.id)).limit(1);
    const now = new Date();
    if (!node) {
      const [created] = await db.insert(baseProductionNodes).values({
        id: uuidv4(), buildingId: building.id, resourceType: requested,
        baseRatePerHour: profile.ratePerHour, currentStored: 0,
        maxCapacity: capacityForLevel(profile.capacity, building.level), lastHarvestAt: now,
      }).returning();
      return created;
    }
    const [updated] = await db.update(baseProductionNodes).set({ resourceType: requested, lastHarvestAt: now })
      .where(eq(baseProductionNodes.id, node.id)).returning();
    return updated;
  }

  async collect(masterId: string, buildingId: string) {
    await this.settle(masterId);
    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    const [node] = await db.select().from(baseProductionNodes).where(eq(baseProductionNodes.buildingId, building.id)).limit(1);
    if (!node) throw new BaseError('Công trình chưa có cấu hình sản xuất.', 409);

    const assignments = await db.select().from(buildingWorkerAssignments).where(eq(buildingWorkerAssignments.buildingId, building.id));
    const rate = productionRatePerHour(node.baseRatePerHour, building.level, assignments.map(row => row.efficiencyBoost));
    const now = new Date();
    const accrued = accruedStored(node.currentStored, rate, node.lastHarvestAt, node.maxCapacity, now);
    const amount = Math.floor(accrued.stored);
    if (amount <= 0) return { collected: 0, resourceType: node.resourceType, atCapacity: false };

    await db.transaction(async tx => {
      await tx.insert(masterItems).values({ id: uuidv4(), masterId, itemId: node.resourceType, quantity: amount, updatedAt: now })
        .onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${amount}`, updatedAt: now },
        });
      await tx.update(baseProductionNodes).set({ currentStored: 0, lastHarvestAt: now })
        .where(eq(baseProductionNodes.id, node.id));
    });

    // A harvest counts as one labour shift for every assigned Hero (DM-09).
    const shift = await survivalService.applyShift(masterId, assignments.map(row => row.heroInstanceId));

    return {
      collected: amount, resourceType: node.resourceType, atCapacity: accrued.atCapacity,
      ejectedWorkers: shift.ejected,
    };
  }

  async assignWorker(masterId: string, buildingId: string, heroId: unknown) {
    await this.settle(masterId);
    if (typeof heroId !== 'string' || !heroId) throw new BaseError('heroId là bắt buộc.');
    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.status !== 'READY') throw new BaseError('Công trình chưa sẵn sàng.', 409);

    const [type] = await db.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
    const maxWorkers = type?.maxWorkers ?? 0;
    if (maxWorkers <= 0) throw new BaseError('Công trình này không nhận Hero làm việc.', 409);

    const [hero] = await db.select().from(heroes)
      .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).limit(1);
    if (!hero) throw new BaseError('Không tìm thấy Hero.', 404);
    if (hero.state === 'DEAD') throw new BaseError('Hero đã tử trận.', 409);

    const current = await db.select().from(buildingWorkerAssignments).where(eq(buildingWorkerAssignments.buildingId, building.id));
    if (current.length >= maxWorkers) throw new BaseError(`Công trình chỉ nhận tối đa ${maxWorkers} Hero.`, 409);
    const [already] = await db.select({ id: buildingWorkerAssignments.id }).from(buildingWorkerAssignments)
      .where(eq(buildingWorkerAssignments.heroInstanceId, hero.id)).limit(1);
    if (already) throw new BaseError('Hero đang làm việc ở công trình khác.', 409);

    const [assignment] = await db.insert(buildingWorkerAssignments).values({
      id: uuidv4(), buildingId: building.id, heroInstanceId: hero.id,
      efficiencyBoost: workerBoostForLevel(hero.level), assignedAt: new Date(),
    }).returning();
    return { assignment, boost: assignment.efficiencyBoost };
  }

  async removeWorker(masterId: string, buildingId: string, heroId: string) {
    const [building] = await db.select({ id: baseBuildings.id }).from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    const deleted = await db.delete(buildingWorkerAssignments)
      .where(and(eq(buildingWorkerAssignments.buildingId, buildingId), eq(buildingWorkerAssignments.heroInstanceId, heroId)))
      .returning({ id: buildingWorkerAssignments.id });
    if (deleted.length === 0) throw new BaseError('Hero không làm việc tại công trình này.', 404);
    return { removed: heroId };
  }

  async expand(masterId: string) {
    await this.settle(masterId);
    const master = await this.master(masterId);
    const world = await this.world(masterId);
    if (world.baseZones >= MAX_BASE_ZONES) throw new BaseError('Căn cứ đã mở rộng tối đa.', 409);

    const nextZone = world.baseZones + 1;
    const worldLevel = worldLevelForFloor(world.currentFloor);
    const requiredWl = expansionRequiredWorldLevel(nextZone);
    const requiredMasterLvl = requiredMasterLevelForFloor(nextZone);
    if (worldLevel < requiredWl && master.level < requiredMasterLvl) {
      throw new BaseError(`Cần Master Level ${requiredMasterLvl} hoặc World Level ${requiredWl} để mở Tầng ${nextZone}.`, 409);
    }
    const cost = expansionCostSilver(world.baseZones);
    if (master.silverCoins < BigInt(cost)) throw new BaseError('Không đủ Xu Bạc để mở rộng.', 409);

    const now = new Date();
    await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${cost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      await tx.update(worlds).set({ baseZones: nextZone }).where(eq(worlds.id, world.id));
    });

    return { zones: nextZone, plots: plotsForZones(nextZone), silverSpent: cost };
  }

  /**
   * Promotes an existing Dormitory (`HOUSE`) into a `PARTY_MANSION` (Biệt Thự Tổ Đội)
   * once the Master reaches Level 30.
   */
  async promoteToPartyMansion(masterId: string, buildingId: string) {
    await this.settle(masterId);
    const master = await this.master(masterId);
    if (master.level < PARTY_MANSION_REQUIRED_MASTER_LEVEL) {
      throw new BaseError(`Cần Master đạt cấp ${PARTY_MANSION_REQUIRED_MASTER_LEVEL} để nâng cấp Nhà Nghỉ thành Party Mansion.`, 409);
    }

    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.buildingType !== 'HOUSE') {
      throw new BaseError('Chỉ có thể nâng cấp Nhà Nghỉ (HOUSE) thành Party Mansion.', 409);
    }
    if (building.status !== 'READY') {
      throw new BaseError('Công trình đang trong quá trình thi công.', 409);
    }
    if (master.silverCoins < BigInt(PARTY_MANSION_UPGRADE_COST_SILVER)) {
      throw new BaseError('Không đủ Xu Bạc để nâng cấp lên Party Mansion.', 409);
    }

    const now = new Date();
    const updated = await db.transaction(async tx => {
      await tx.update(masters)
        .set({ silverCoins: sql`${masters.silverCoins} - ${PARTY_MANSION_UPGRADE_COST_SILVER}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      const [row] = await tx.update(baseBuildings)
        .set({ buildingType: 'PARTY_MANSION', status: 'READY', updatedAt: now })
        .where(eq(baseBuildings.id, building.id))
        .returning();
      return row;
    });

    return { building: updated, silverSpent: PARTY_MANSION_UPGRADE_COST_SILVER };
  }
}

export const buildingService = new BuildingService();
