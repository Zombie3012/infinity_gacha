import { and, asc, eq, gt, inArray, notInArray, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { heroEffectiveMaxLevel, type HeroClass, type StarRating } from '@infiniti-gacha/shared';
import { db } from '../../database/db.js';
import type { GameTransaction } from '../../database/transaction.js';
import { isV2Origin, originOf, progressionFor } from '../hero/hero-progression.js';
import { survivalService } from '../survival/survival.service.js';
import { assertHeroesActivityReadiness } from '../combat/combat-readiness.js';
import { RETIRED_MAGIC_BUILDINGS, magicSnapshot, updateMagicProduction, collectMagic } from './magic-production.js';
import {
  baseBuildings, baseProductionNodes, buildingTypes, buildingWorkerAssignments, heroLevelConfigs, heroes, heroSurvivalStates, masterItems, masters, worlds,
} from '../../database/drizzle-schema.js';
import {
  MAX_BASE_ZONES, PARTY_MANSION_REQUIRED_MASTER_LEVEL, PARTY_MANSION_UPGRADE_COST_SILVER,
  accruedStored, buildingProductionForLevel, capacityForLevel, demolishRefundSilver,
  dormitoryRecoveryMultiplier, dormitoryResidentCapacity, expansionCostSilver, expansionRequiredWorldLevel,
  libraryMageExpPerHour, maxConstructibleCountForType, maxWorkersForBuildingLevel, plotsForZones,
  productionRatePerHour, recoveryCenterTreatmentSlots, requiredMasterLevelForFloor, unlockedLobbyFloorsForMasterLevel,
  upgradeCostSilver, upgradeMaterials, warehouseBonusSlotsForLevel, worldLevelForFloor,
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

  /** Apply the new production profile without revaluing past production at the new rate. */
  private async updateProduction(tx: GameTransaction, building: typeof baseBuildings.$inferSelect,
    type: typeof buildingTypes.$inferSelect, level: number, now: Date) {
    if (building.buildingType === 'HALL_OF_MAGIC') return updateMagicProduction(tx, building, level, now);
    const profile = buildingProductionForLevel(building.buildingType, level) ?? asProfile(type.production);
    if (!profile) return;
    const [node] = await tx.select().from(baseProductionNodes).where(eq(baseProductionNodes.buildingId, building.id)).for('update');
    let stored = 0;
    if (node) {
      const workers = await tx.select({ boost: buildingWorkerAssignments.efficiencyBoost, classCode: heroes.classCode })
        .from(buildingWorkerAssignments).innerJoin(heroes, eq(heroes.id, buildingWorkerAssignments.heroInstanceId))
        .where(eq(buildingWorkerAssignments.buildingId, building.id));
      const oldProfile = buildingProductionForLevel(building.buildingType, building.level);
      const boosts = workers.map(worker => worker.boost);
      const share = boosts.reduce((sum, boost) => sum + Math.max(0, boost - 1), 0);
      const rate = building.buildingType === 'LIBRARY' && !workers.some(worker => worker.classCode === 'MAGE') ? 0
        : oldProfile ? oldProfile.ratePerHour * (1 + share) : productionRatePerHour(node.baseRatePerHour, building.level, boosts);
      stored = accruedStored(node.currentStored, rate, node.lastHarvestAt, node.maxCapacity, now).stored;
    }
    const capacity = buildingProductionForLevel(building.buildingType, level) ? profile.capacity : capacityForLevel(profile.capacity, level);
    await tx.insert(baseProductionNodes).values({ id: node?.id ?? uuidv4(), buildingId: building.id,
      resourceType: profile.resourceType, baseRatePerHour: profile.ratePerHour,
      maxCapacity: capacity, currentStored: Math.min(stored, capacity), lastHarvestAt: now,
    }).onConflictDoUpdate({ target: [baseProductionNodes.buildingId], set: {
      resourceType: profile.resourceType, baseRatePerHour: profile.ratePerHour, maxCapacity: capacity,
      currentStored: Math.min(stored, capacity), lastHarvestAt: now,
    } });
  }

  /** Complete legacy pending jobs immediately, once, regardless of their old deadline. */
  private async settle(masterId: string, now = new Date()) {
    const [pending] = await db.select({ id: baseBuildings.id }).from(baseBuildings)
      .where(and(eq(baseBuildings.masterId, masterId), inArray(baseBuildings.status, ['CONSTRUCTING', 'UPGRADING']))).limit(1);
    if (!pending) return;
    await db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const rows = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.masterId, masterId), inArray(baseBuildings.status, ['CONSTRUCTING', 'UPGRADING']))).for('update');
      for (const row of rows) {
        const [type] = await tx.select().from(buildingTypes).where(eq(buildingTypes.code, row.buildingType)).limit(1);
        if (!type) throw new BaseError('Building type not found.', 404);
        const level = row.status === 'UPGRADING' ? Math.min(type.maxLevel, row.level + 1) : row.level;
        await this.updateProduction(tx, row, type, level, now);
        await tx.update(baseBuildings).set({ status: 'READY', level, upgradeFinishesAt: null, updatedAt: now })
          .where(eq(baseBuildings.id, row.id));
      }
    });
  }

  async overview(masterId: string) {
    await this.settle(masterId);
    const master = await this.master(masterId);
    const world = await this.world(masterId);
    const worldLevel = worldLevelForFloor(world.currentFloor);
    const types = await db.select().from(buildingTypes).where(notInArray(buildingTypes.code, RETIRED_MAGIC_BUILDINGS)).orderBy(asc(buildingTypes.code));
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
      heroClass: heroes.classCode,
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
    const magic = new Map(await Promise.all(buildings.filter(b => b.buildingType === 'HALL_OF_MAGIC').map(async b => {
      let snapshot = await magicSnapshot(db,b.id,now);
      if (snapshot.length !== 2 || snapshot.some(n => n.resourceType !== buildingProductionForLevel(n.wing,b.level)?.resourceType
          || n.baseRatePerHour !== buildingProductionForLevel(n.wing,b.level)?.ratePerHour)) {
        await db.transaction(async tx => {
          await tx.select({id:masters.id}).from(masters).where(eq(masters.id,masterId)).for('update');
          const [fresh] = await tx.select().from(baseBuildings).where(eq(baseBuildings.id,b.id));
          if (fresh) await updateMagicProduction(tx,fresh,fresh.level,new Date());
        });
        snapshot = await magicSnapshot(db,b.id,new Date());
      }
      return [b.id,snapshot] as const;
    })));
    const rows = buildings.map(building => {
      const type = typeByCode.get(building.buildingType);
      const node = nodeByBuilding.get(building.id);
      const workers = workersByBuilding.get(building.id) ?? [];
      const levelProfile = buildingProductionForLevel(building.buildingType, building.level);
      const profile = levelProfile ?? asProfile(type?.production);
      const boosts = workers.map(worker => worker.efficiencyBoost);
      const workerShare = boosts.reduce((sum, boost) => sum + (Math.max(0, boost) - 1), 0);
      const hasMageWorker = workers.some(worker => String(worker.heroClass ?? '').toUpperCase() === 'MAGE');

      let rate = 0;
      if (profile) {
        if (building.buildingType === 'LIBRARY' && !hasMageWorker) {
          rate = 0; // Only MAGE class produces EXP books in the Library
        } else if (levelProfile) {
          rate = Math.max(0, levelProfile.ratePerHour * (1 + workerShare));
        } else {
          rate = productionRatePerHour(node?.baseRatePerHour ?? profile.ratePerHour, building.level, boosts);
        }
      }
      const capacity = levelProfile ? levelProfile.capacity : (node ? node.maxCapacity : profile ? capacityForLevel(profile.capacity, building.level) : 0);
      const accrued = node
        ? accruedStored(node.currentStored, rate, node.lastHarvestAt, capacity, now)
        : { stored: 0, atCapacity: false, hoursElapsed: 0 };
      const maxWorkers = maxWorkersForBuildingLevel(building.buildingType, building.level, type?.maxWorkers ?? 0);
      const magicProduction = magic.get(building.id);
      return {
        ...building,
        typeName: type?.name ?? building.buildingType,
        category: type?.category ?? 'PRODUCTION',
        maxLevel: building.buildingType === 'AIRSHIP_PORT' ? 5 : Math.min(3, type?.maxLevel ?? 3),
        maxWorkers,
        ratePerHour: Math.round(rate * 100) / 100,
        capacity,
        stored: accrued.stored,
        atCapacity: accrued.atCapacity,
        resourceType: levelProfile?.resourceType ?? node?.resourceType ?? profile?.resourceType ?? null,
        requiresMageWorker: building.buildingType === 'LIBRARY',
        mageExpPerHour: building.buildingType === 'LIBRARY' || building.buildingType === 'HALL_OF_MAGIC'
          ? libraryMageExpPerHour(building.level)
          : 0,
        residentCapacity: dormitoryResidentCapacity(building.buildingType, building.level),
        recoveryMultiplier: dormitoryRecoveryMultiplier(building.buildingType, building.level),
        treatmentSlots: building.buildingType === 'MEDICAL' ? recoveryCenterTreatmentSlots(building.level) : 0,
        warehouseBonusSlots: building.buildingType === 'WAREHOUSE' ? warehouseBonusSlotsForLevel(building.level) : 0,
        workers,
        ...(magicProduction ? { magicProduction, stored:magicProduction.reduce((s,n)=>s+n.stored,0),
          capacity:magicProduction.reduce((s,n)=>s+n.capacity,0),ratePerHour:magicProduction.reduce((s,n)=>s+n.ratePerHour,0),
          resourceType:'MAGIC_OUTPUT',atCapacity:magicProduction.some(n=>n.atCapacity) } : {}),
      };
    });

    const countByType = new Map<string, number>();
    for (const b of buildings) {
      countByType.set(b.buildingType, (countByType.get(b.buildingType) ?? 0) + 1);
    }

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
      buildingTypes: types.map(type => {
        const maxCount = maxConstructibleCountForType(type.code, master.level);
        const builtCount = countByType.get(type.code) ?? 0;
        const reqMasterLvl = type.code === 'PARTY_MANSION'
          ? PARTY_MANSION_REQUIRED_MASTER_LEVEL
          : (type.code === 'HALL_OF_MAGIC' || type.code === 'LIBRARY' || type.code === 'ALCHEMY_WORKSHOP' || type.code === 'MAGIC_RESEARCH_LAB')
            ? 15
            : 1;
        return {
          ...type,
          maxLevel: type.code === 'AIRSHIP_PORT' ? 5 : Math.min(3, type.maxLevel ?? 3),
          maxWorkers: maxWorkersForBuildingLevel(type.code, 1, type.maxWorkers ?? 0),
          production: buildingProductionForLevel(type.code, 1) ?? asProfile(type.production),
          requiredMasterLevel: reqMasterLvl,
          maxAllowedCount: maxCount,
          currentBuiltCount: builtCount,
          unlocked: (worldLevel >= type.requiredWorldLevel || master.level >= reqMasterLvl)
            && (type.code !== 'PARTY_MANSION' || master.level >= PARTY_MANSION_REQUIRED_MASTER_LEVEL)
            && (type.code !== 'AIRSHIP_PORT' || world.currentFloor >= 25)
            && (maxCount === null || builtCount < maxCount),
        };
      }),
      buildings: rows,
      plots,
    };
  }

  async construct(masterId: string, buildingTypeCode: unknown, plotIndexInput: unknown) {
    await this.settle(masterId);
    const code = typeof buildingTypeCode === 'string' ? buildingTypeCode : '';
    if (RETIRED_MAGIC_BUILDINGS.includes(code)) throw new BaseError('Chức năng này đã gộp vào Đại Sảnh Ma Thuật.',404);
    const plotIndex = Number(plotIndexInput);
    if (!Number.isInteger(plotIndex) || plotIndex < 1) throw new BaseError('plotIndex không hợp lệ.');

    const now = new Date();
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new BaseError('Master not found.', 404);
      const [world] = await tx.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
      if (!world) throw new BaseError('World not found.', 404);
      const worldLevel = worldLevelForFloor(world.currentFloor);
      const [type] = await tx.select().from(buildingTypes).where(eq(buildingTypes.code, code)).limit(1);
      if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
      if (type.code === 'PARTY_MANSION' && master.level < PARTY_MANSION_REQUIRED_MASTER_LEVEL) {
        throw new BaseError(`Party Mansion cần Master đạt cấp ${PARTY_MANSION_REQUIRED_MASTER_LEVEL}.`, 409);
      }
      if (type.code === 'AIRSHIP_PORT' && world.currentFloor < 25) {
        throw new BaseError('Bến Thiên Hành (Cảng Tàu Bay) mở khóa khi vượt Tháp tầng 25.', 409);
      }
      const requiredMasterLevel = type.code === 'HALL_OF_MAGIC' ? 15 : requiredMasterLevelForFloor(type.requiredWorldLevel + 1);
      if (worldLevel < type.requiredWorldLevel && master.level < requiredMasterLevel) {
        throw new BaseError(`Công trình cần World Level ${type.requiredWorldLevel}.`, 409);
      }
      const maxCount = maxConstructibleCountForType(type.code, master.level);
      if (maxCount !== null) {
        const existingOfType = await tx.select({ id: baseBuildings.id }).from(baseBuildings)
          .where(and(eq(baseBuildings.masterId, masterId), eq(baseBuildings.buildingType, type.code)));
        if (existingOfType.length >= maxCount) {
          throw new BaseError(`Đã đạt giới hạn tối đa ${maxCount} công trình ${type.name} ở cấp Master hiện tại.`, 409);
        }
      }
      const maxUnlockedPlots = plotsForZones(Math.max(world.baseZones, unlockedLobbyFloorsForMasterLevel(master.level)));
      if (plotIndex > maxUnlockedPlots) throw new BaseError('Ô đất chưa được mở khóa.', 409);

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
        status: 'READY',
        upgradeFinishesAt: null,
        createdAt: now,
        updatedAt: now,
      }).returning();
      await this.updateProduction(tx, building, type, 1, now);
      return { building, silverSpent: type.buildCostSilver };
    });
  }

  async upgrade(masterId: string, buildingId: string) {
    await this.settle(masterId);
    const now = new Date();
    return db.transaction(async tx => {
      const [master] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update');
      if (!master) throw new BaseError('Master not found.', 404);
      const [building] = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).for('update').limit(1);
      if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
      if (building.status !== 'READY') throw new BaseError('Công trình đang trong quá trình thi công.', 409);

      const [type] = await tx.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
      if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
      const targetLevel = building.level + 1;
      const maxLevel = type.code === 'AIRSHIP_PORT' ? 5 : Math.min(3, type.maxLevel ?? 3);
      if (targetLevel > maxLevel) throw new BaseError(`Công trình đã đạt cấp tối đa ${maxLevel}.`, 409);

      const silverCost = upgradeCostSilver(type.buildCostSilver, targetLevel);
      if (master.silverCoins < BigInt(silverCost)) throw new BaseError('Không đủ Xu Bạc để nâng cấp.', 409);
      const materials = type.code === 'AIRSHIP_PORT' ? [] : upgradeMaterials(targetLevel);
      if (materials.length > 0) {
        const owned = await tx.select().from(masterItems)
          .where(and(eq(masterItems.masterId, masterId), inArray(masterItems.itemId, materials.map(row => row.itemId)))).for('update');
        const ownedByItem = new Map(owned.map(row => [row.itemId, row.quantity]));
        const missing = materials.filter(row => (ownedByItem.get(row.itemId) ?? 0) < row.quantity);
        if (missing.length > 0) {
          throw new BaseError(`Thiếu nguyên liệu: ${missing.map(row => `${row.itemId} ×${row.quantity}`).join(', ')}.`, 409);
        }
      }

      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${silverCost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      for (const material of materials) {
        await tx.update(masterItems).set({ quantity: sql`${masterItems.quantity} - ${material.quantity}`, updatedAt: now })
          .where(and(eq(masterItems.masterId, masterId), eq(masterItems.itemId, material.itemId)));
      }
      const [row] = await tx.update(baseBuildings).set({
        status: 'READY',
        level: targetLevel,
        upgradeFinishesAt: null,
        updatedAt: now,
      }).where(eq(baseBuildings.id, building.id)).returning();
      await this.updateProduction(tx, building, type, targetLevel, now);
      return { building: row, silverSpent: silverCost, materialsSpent: materials, targetLevel };
    });
  }

  async demolish(masterId: string, buildingId: string) {
    await this.settle(masterId);
    return db.transaction(async tx => {
      await tx.select({id:masters.id}).from(masters).where(eq(masters.id,masterId)).for('update');
      const [building] = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
      if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
      if (building.status !== 'READY') throw new BaseError('Không thể phá dỡ công trình đang thi công.', 409);

      const [type] = await tx.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
      if (!type) throw new BaseError('Loại công trình không tồn tại.', 404);
      const refund = demolishRefundSilver(type.buildCostSilver, building.level);
      const now = new Date();

      if (building.buildingType === 'HOUSE' || building.buildingType === 'PARTY_MANSION') {
        await tx.update(heroSurvivalStates)
          .set({ housingBuildingId: null, isResting: false })
          .where(eq(heroSurvivalStates.housingBuildingId, building.id));
      }
      await tx.delete(baseBuildings).where(eq(baseBuildings.id, building.id));
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} + ${refund}`, updatedAt: now })
          .where(eq(masters.id, masterId));
      return { demolished: building.id, refundSilver: refund };
    });
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
    if (building.buildingType === 'HALL_OF_MAGIC') {
      const result = await collectMagic(masterId, building.id);
      if (!result) throw new BaseError('Đại sảnh chưa sẵn sàng.',409);
      const shift = result.collected > 0 ? await survivalService.applyShift(masterId,result.workerIds) : {ejected:[]};
      return {...result,ejectedWorkers:shift.ejected};
    }
    const [node] = await db.select().from(baseProductionNodes).where(eq(baseProductionNodes.buildingId, building.id)).limit(1);
    if (!node) throw new BaseError('Công trình chưa có cấu hình sản xuất.', 409);

    const assignments = await db.select({
      id: buildingWorkerAssignments.id,
      heroInstanceId: buildingWorkerAssignments.heroInstanceId,
      efficiencyBoost: buildingWorkerAssignments.efficiencyBoost,
      heroClass: heroes.classCode,
    }).from(buildingWorkerAssignments)
      .innerJoin(heroes, eq(heroes.id, buildingWorkerAssignments.heroInstanceId))
      .where(eq(buildingWorkerAssignments.buildingId, building.id));

    const hasMageWorker = assignments.some(row => String(row.heroClass ?? '').toUpperCase() === 'MAGE');
    if (building.buildingType === 'LIBRARY' && !hasMageWorker) {
      throw new BaseError('Thư Viện Ma Thuật cần ít nhất 1 Hero hệ Pháp Sư (MAGE) làm việc để sản xuất Sách EXP.', 409);
    }

    const levelProfile = buildingProductionForLevel(building.buildingType, building.level);
    const boosts = assignments.map(row => row.efficiencyBoost);
    const workerShare = boosts.reduce((sum, boost) => sum + (Math.max(0, boost) - 1), 0);
    const rate = levelProfile
      ? Math.max(0, levelProfile.ratePerHour * (1 + workerShare))
      : productionRatePerHour(node.baseRatePerHour, building.level, boosts);
    const maxCap = levelProfile ? levelProfile.capacity : node.maxCapacity;
    const resType = levelProfile ? levelProfile.resourceType : node.resourceType;

    const now = new Date();
    const accrued = accruedStored(node.currentStored, rate, node.lastHarvestAt, maxCap, now);
    const amount = Math.floor(accrued.stored);
    if (amount <= 0) return { collected: 0, resourceType: resType, atCapacity: false };

    await db.transaction(async tx => {
      await tx.insert(masterItems).values({ id: uuidv4(), masterId, itemId: resType, quantity: amount, updatedAt: now })
        .onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${amount}`, updatedAt: now },
        });
      await tx.update(baseProductionNodes).set({
        resourceType: resType,
        baseRatePerHour: levelProfile ? levelProfile.ratePerHour : node.baseRatePerHour,
        maxCapacity: maxCap,
        currentStored: 0,
        lastHarvestAt: now,
      }).where(eq(baseProductionNodes.id, node.id));
    });

    // A harvest counts as one labour shift for every assigned Hero (DM-09).
    const shift = await survivalService.applyShift(masterId, assignments.map(row => row.heroInstanceId));

    return {
      collected: amount, resourceType: resType, atCapacity: accrued.atCapacity,
      ejectedWorkers: shift.ejected,
    };
  }

  async assignWorker(masterId: string, buildingId: string, heroId: unknown) {
    await this.settle(masterId);
    if (typeof heroId !== 'string' || !heroId) throw new BaseError('heroId là bắt buộc.');
    return db.transaction(async tx => {
      await tx.select({ id: masters.id }).from(masters).where(eq(masters.id, masterId)).for('update');
      const [building] = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
      if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
      if (building.status !== 'READY') throw new BaseError('Công trình chưa sẵn sàng.', 409);

      const [type] = await tx.select().from(buildingTypes).where(eq(buildingTypes.code, building.buildingType)).limit(1);
      const maxWorkers = maxWorkersForBuildingLevel(building.buildingType, building.level, type?.maxWorkers ?? 0);
      if (maxWorkers <= 0) throw new BaseError('Công trình này không nhận Hero làm việc.', 409);

      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new BaseError('Không tìm thấy Hero.', 404);
      if (hero.state === 'DEAD' || hero.state === 'DISABLED' || hero.hp <= 0) throw new BaseError('Hero không còn sống hoặc đang chờ hồi sinh.', 409);

      if (building.buildingType === 'LIBRARY' && String(hero.classCode ?? '').toUpperCase() !== 'MAGE') {
        throw new BaseError('Chỉ Hero hệ Pháp Sư (MAGE) mới được phân công vào Thư Viện Ma Thuật.', 409);
      }

      const current = await tx.select().from(buildingWorkerAssignments).where(eq(buildingWorkerAssignments.buildingId, building.id));
      if (current.length >= maxWorkers) throw new BaseError(`Công trình chỉ nhận tối đa ${maxWorkers} Hero ở cấp hiện tại.`, 409);
      const [already] = await tx.select({ id: buildingWorkerAssignments.id }).from(buildingWorkerAssignments)
        .where(eq(buildingWorkerAssignments.heroInstanceId, hero.id)).limit(1);
      if (already) throw new BaseError('Hero đang làm việc ở công trình khác.', 409);

      try {
        await assertHeroesActivityReadiness(tx, masterId, [hero.id], new Date(), 'ANY');
      } catch {
        throw new BaseError('Hero quá mệt hoặc quá đói (≥90), từ chối nhận việc.', 409);
      }

      if (building.buildingType === 'HALL_OF_MAGIC') await updateMagicProduction(tx,building,building.level,new Date());
      const [assignment] = await tx.insert(buildingWorkerAssignments).values({
        id: uuidv4(), buildingId: building.id, heroInstanceId: hero.id,
        efficiencyBoost: workerBoostForLevel(hero.level), assignedAt: new Date(),
      }).returning();
      return { assignment, boost: assignment.efficiencyBoost };
    });
  }

  /**
   * Allows a MAGE class Hero to study directly in the Library (or Hall of Magic),
   * gaining direct EXP according to the Library's level:
   * - Level 1: +25,000 EXP/hr
   * - Level 2: +1,250,000 EXP/hr
   * - Level 3: +16,500,000 EXP/hr
   */
  async studyMageInLibrary(masterId: string, buildingId: string, heroId: unknown, hoursInput: unknown = 1) {
    await this.settle(masterId);
    if (typeof heroId !== 'string' || !heroId) throw new BaseError('heroId là bắt buộc.');
    const hours = Math.max(1, Math.min(12, Math.floor(Number(hoursInput) || 1)));

    const [building] = await db.select().from(baseBuildings)
      .where(and(eq(baseBuildings.id, buildingId), eq(baseBuildings.masterId, masterId))).limit(1);
    if (!building) throw new BaseError('Không tìm thấy công trình.', 404);
    if (building.buildingType !== 'LIBRARY' && building.buildingType !== 'HALL_OF_MAGIC') {
      throw new BaseError('Chỉ Thư Viện Ma Thuật hoặc Đại Sảnh Ma Thuật mới hỗ trợ Pháp Sư tu luyện tăng cấp.', 409);
    }
    if (building.status !== 'READY') throw new BaseError('Công trình chưa sẵn sàng.', 409);

    const expPerHour = libraryMageExpPerHour(building.level);
    const expGain = BigInt(expPerHour) * BigInt(hours);

    const result = await db.transaction(async tx => {
      const [hero] = await tx.select().from(heroes)
        .where(and(eq(heroes.id, heroId), eq(heroes.masterId, masterId))).for('update').limit(1);
      if (!hero) throw new BaseError('Không tìm thấy Hero.', 404);
      if (String(hero.classCode ?? '').toUpperCase() !== 'MAGE') {
        throw new BaseError('Chỉ Hero hệ Pháp Sư (MAGE) mới có thể tăng cấp trực tiếp trong Thư Viện Ma Thuật.', 409);
      }
      if (hero.state === 'DEAD' || hero.state === 'DISABLED') {
        throw new BaseError('Hero hiện không thể tu luyện.', 409);
      }

      const heroLevelCap = heroEffectiveMaxLevel(hero.rarity, hero.promotionRank);
      if (hero.level >= heroLevelCap) {
        throw new BaseError(`Hero đã đạt trần cấp độ hiện tại (Lv.${heroLevelCap}). Hãy Thăng Sao / Đột Phá trước.`, 409);
      }

      const growthConfigs = await tx.select().from(heroLevelConfigs)
        .where(and(gt(heroLevelConfigs.level, hero.level), lte(heroLevelConfigs.level, heroLevelCap)))
        .orderBy(heroLevelConfigs.level);

      const totalExp = BigInt(hero.exp) + expGain;
      let level = hero.level;
      let maxHp = hero.maxHp;
      let hp = hero.hp;
      let attack = hero.attack;
      let defense = hero.defense;
      let speed = hero.speed;

      for (const config of growthConfigs) {
        if (totalExp < config.cumulativeExpRequired) continue;
        const previousMaxHp = maxHp;
        maxHp = Math.floor(maxHp * config.statGrowthMultiplier);
        hp = Math.min(maxHp, hp + maxHp - previousMaxHp);
        attack = Math.floor(attack * config.statGrowthMultiplier);
        defense = Math.floor(defense * config.statGrowthMultiplier);
        speed = Math.floor(speed * config.statGrowthMultiplier);
        level = config.level;
      }

      const isV2 = isV2Origin(hero.originStats);
      const updateValues = isV2
        ? (() => {
          const snapshot = progressionFor({
            origin: originOf(hero.originStats),
            star: hero.rarity as StarRating,
            level,
            classCode: hero.classCode as HeroClass,
            training: hero.trainingStats,
            awakeningRank: hero.awakeningRank,
            hpPct: hero.currentHpPct,
            mpPct: hero.currentMpPct,
          });
          return {
            exp: totalExp,
            level,
            baseStr: snapshot.base.str,
            baseInt: snapshot.base.int,
            baseSta: snapshot.base.sta,
            baseAgi: snapshot.base.agi,
            maxHp: snapshot.maxHp,
            hp: snapshot.hp,
            attack: snapshot.attack,
            defense: snapshot.defense,
            speed: snapshot.speed,
            mp: snapshot.mp,
            maxMp: snapshot.maxMp,
            updatedAt: new Date(),
          };
        })()
        : { exp: totalExp, level, maxHp, hp, attack, defense, speed, updatedAt: new Date() };

      const [updated] = await tx.update(heroes).set(updateValues).where(eq(heroes.id, hero.id)).returning();
      return {
        heroId: updated.id,
        heroName: updated.name,
        previousLevel: hero.level,
        level: updated.level,
        maxLevel: heroLevelCap,
        expGained: expGain.toString(),
        totalExp: updated.exp.toString(),
        libraryLevel: building.level,
        expPerHour,
      };
    });

    return result;
  }

  async removeWorker(masterId: string, buildingId: string, heroId: string) {
    return db.transaction(async tx => {
      await tx.select({id:masters.id}).from(masters).where(eq(masters.id,masterId)).for('update');
      const [building] = await tx.select().from(baseBuildings)
        .where(and(eq(baseBuildings.id,buildingId),eq(baseBuildings.masterId,masterId))).limit(1);
      if (!building) throw new BaseError('Không tìm thấy công trình.',404);
      if (building.buildingType === 'HALL_OF_MAGIC') await updateMagicProduction(tx,building,building.level,new Date());
      const deleted = await tx.delete(buildingWorkerAssignments)
        .where(and(eq(buildingWorkerAssignments.buildingId,buildingId),eq(buildingWorkerAssignments.heroInstanceId,heroId))).returning();
      if (!deleted.length) throw new BaseError('Hero không làm việc tại công trình này.',404);
      return {removed:heroId};
    });
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
