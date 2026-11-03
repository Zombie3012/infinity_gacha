import { and, asc, eq, gt } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  masters,
  worlds,
  dungeonTemplates,
  dungeonFloors,
  dungeonInstances,
  currencyTransactions,
  masterSummonInventory,
  masterLevelConfigs,
} from '../../database/drizzle-schema.js';
import { dungeonConfigService, FloorBaseReward, FloorFirstClearReward } from './dungeon-config.service.js';
import { worldSeedService, ProceduralRoom } from './world-seed.service.js';

export class DungeonExplorationError extends Error {
  constructor(message: string, public readonly statusCode = 400) {
    super(message);
    this.name = 'DungeonExplorationError';
  }
}

export type FloorProgressInfo = {
  id: string;
  floorNumber: number;
  name: string;
  recommendedPower: number;
  status: 'CLEARED' | 'CURRENT' | 'UNLOCKED' | 'LOCKED';
  isUnlocked: boolean;
  unlockReason?: string;
  baseRewards: FloorBaseReward;
  firstClearRewards: FloorFirstClearReward;
  isFirstClearAvailable: boolean;
};

export type DungeonRewardSummary = {
  silverReward: number;
  bossBonusSilver: number;
  firstClearSilver: number;
  totalSilver: number;
  masterExpReward: number;
  firstClearScrolls: { normalScrolls?: number; specialScrolls?: number };
  masterLevelUps: { fromLevel: number; toLevel: number }[];
};

export class DungeonExplorationService {
  /**
   * FUN-07-04-001: View floor list with lock/unlock and cleared status.
   */
  public async getFloorList(masterId: string, templateCode: string = 'QUIET_FOREST'): Promise<{
    template: typeof dungeonTemplates.$inferSelect;
    currentWorldFloor: number;
    floors: FloorProgressInfo[];
  }> {
    const templateWithFloors = await dungeonConfigService.getTemplateWithFloors(templateCode);
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new DungeonExplorationError('Master không tồn tại.', 404);

    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
    const currentWorldFloor = world?.currentFloor ?? 1;

    const floors: FloorProgressInfo[] = templateWithFloors.floors.map(floor => {
      const unlockCheck = dungeonConfigService.checkFloorUnlocked(floor, master.level, currentWorldFloor);
      let status: FloorProgressInfo['status'] = 'LOCKED';
      if (currentWorldFloor > floor.floorNumber) {
        status = 'CLEARED';
      } else if (currentWorldFloor === floor.floorNumber) {
        status = 'CURRENT';
      } else if (unlockCheck.isUnlocked) {
        status = 'UNLOCKED';
      }

      const isFirstClearAvailable = currentWorldFloor <= floor.floorNumber;

      return {
        id: floor.id,
        floorNumber: floor.floorNumber,
        name: floor.name,
        recommendedPower: floor.recommendedPower,
        status,
        isUnlocked: unlockCheck.isUnlocked,
        unlockReason: unlockCheck.reason,
        baseRewards: floor.baseRewards as FloorBaseReward,
        firstClearRewards: floor.firstClearRewards as FloorFirstClearReward,
        isFirstClearAvailable,
      };
    });

    return {
      template: templateWithFloors,
      currentWorldFloor,
      floors,
    };
  }

  /**
   * FUN-07-04-003 & FUN-07-05-001: Enter a floor, initializing or resuming Dungeon Instance.
   */
  public async enterFloor(masterId: string, templateCode: string, floorNumber: number) {
    const templateWithFloors = await dungeonConfigService.getTemplateWithFloors(templateCode);
    const targetFloor = templateWithFloors.floors.find(f => f.floorNumber === floorNumber);
    if (!targetFloor) throw new DungeonExplorationError(`Không tìm thấy tầng ${floorNumber}.`, 404);

    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new DungeonExplorationError('Master không tồn tại.', 404);

    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
    if (!world) throw new DungeonExplorationError('Hãy khởi tạo World trước khi vào Dungeon.', 409);

    // FUN-07-04-002: Validate Floor Unlock Requirement
    const unlockCheck = dungeonConfigService.checkFloorUnlocked(targetFloor, master.level, world.currentFloor);
    if (!unlockCheck.isUnlocked) {
      throw new DungeonExplorationError(unlockCheck.reason ?? 'Tầng này hiện đang bị khóa.', 403);
    }

    // Check for existing ACTIVE instance
    const [existing] = await db.select().from(dungeonInstances)
      .where(and(eq(dungeonInstances.masterId, masterId), eq(dungeonInstances.status, 'ACTIVE'))).limit(1);

    if (existing) {
      if (existing.dungeonFloorId === targetFloor.id) {
        return existing;
      }
      // If entering a different floor, abandon the previous active one
      await db.update(dungeonInstances)
        .set({ status: 'ABANDONED', completedAt: new Date() })
        .where(eq(dungeonInstances.id, existing.id));
    }

    // FUN-07-02-004 & FUN-07-03-001..005: Reconstruct floor deterministically from World Seed
    const reconstruction = worldSeedService.reconstructFloor(
      world.worldSeed,
      floorNumber,
      world.difficultyMultiplier,
      world.seedAlgorithmVersion ?? 1
    );

    const instanceId = uuidv4();
    const [newInstance] = await db.insert(dungeonInstances).values({
      id: instanceId,
      masterId,
      worldId: world.id,
      dungeonFloorId: targetFloor.id,
      worldSeed: world.worldSeed,
      seedAlgorithmVersion: world.seedAlgorithmVersion ?? 1,
      floorNumber,
      status: 'ACTIVE',
      currentRoomIndex: 0,
      floorState: {
        rooms: reconstruction.rooms,
        difficultyMultiplier: reconstruction.difficultyMultiplier,
      },
      createdAt: new Date(),
    }).returning();

    return newInstance;
  }

  /**
   * FUN-07-04-004 & FUN-07-05-002: Get active dungeon instance with progress.
   */
  public async getActiveInstance(masterId: string) {
    const [instance] = await db.select().from(dungeonInstances)
      .where(and(eq(dungeonInstances.masterId, masterId), eq(dungeonInstances.status, 'ACTIVE'))).limit(1);
    return instance ?? null;
  }

  /**
   * FUN-07-05-002..006: Explore / advance to next room, or clear current room.
   */
  public async exploreRoom(masterId: string, instanceId: string) {
    return db.transaction(async tx => {
      const [instance] = await tx.select().from(dungeonInstances)
        .where(and(eq(dungeonInstances.id, instanceId), eq(dungeonInstances.masterId, masterId))).for('update').limit(1);
      if (!instance) throw new DungeonExplorationError('Phiên thám hiểm Dungeon không tồn tại.', 404);
      if (instance.status !== 'ACTIVE') throw new DungeonExplorationError('Phiên thám hiểm này đã kết thúc.', 409);

      const state = instance.floorState;
      const currentIdx = instance.currentRoomIndex;
      const currentRoom = state.rooms[currentIdx];

      if (!currentRoom) {
        throw new DungeonExplorationError('Phòng hiện tại không hợp lệ.', 400);
      }

      // Mark current room as cleared
      currentRoom.cleared = true;
      let rewardSummary: DungeonRewardSummary | null = null;

      const isLastRoom = currentIdx >= state.rooms.length - 1;

      if (isLastRoom) {
        // FUN-07-05-006 & MOD-07-06: Complete Dungeon
        const [floor] = await tx.select().from(dungeonFloors)
          .where(eq(dungeonFloors.id, instance.dungeonFloorId)).limit(1);
        const [world] = await tx.select().from(worlds)
          .where(eq(worlds.id, instance.worldId)).for('update').limit(1);

        if (floor && world) {
          rewardSummary = await this.distributeFloorRewards(tx, masterId, world, floor, state.difficultyMultiplier);
        }

        await tx.update(dungeonInstances).set({
          status: 'COMPLETED',
          completedAt: new Date(),
          floorState: state,
        }).where(eq(dungeonInstances.id, instance.id));

        return {
          status: 'COMPLETED' as const,
          room: currentRoom,
          rewardSummary,
          isCompleted: true,
        };
      }

      // Advance to next room
      const nextRoomIndex = currentIdx + 1;
      await tx.update(dungeonInstances).set({
        currentRoomIndex: nextRoomIndex,
        floorState: state,
      }).where(eq(dungeonInstances.id, instance.id));

      return {
        status: 'ACTIVE' as const,
        clearedRoom: currentRoom,
        nextRoom: state.rooms[nextRoomIndex],
        isCompleted: false,
      };
    });
  }

  /**
   * FUN-07-04-006: Handle Floor Failure or manual Retreat.
   * Resets the active floor instance; Seed remains untouched.
   */
  public async handleFailure(masterId: string, instanceId: string) {
    const [instance] = await db.select().from(dungeonInstances)
      .where(and(eq(dungeonInstances.id, instanceId), eq(dungeonInstances.masterId, masterId))).limit(1);
    if (!instance) throw new DungeonExplorationError('Phiên thám hiểm Dungeon không tồn tại.', 404);
    if (instance.status !== 'ACTIVE') return instance;

    const [updated] = await db.update(dungeonInstances).set({
      status: 'FAILED',
      completedAt: new Date(),
    }).where(eq(dungeonInstances.id, instanceId)).returning();

    return updated;
  }

  /**
   * MOD-07-06: Calculate & Distribute Rewards (Silver, Master EXP, Summon Scrolls).
   */
  private async distributeFloorRewards(
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    tx: any,
    masterId: string,
    world: typeof worlds.$inferSelect,
    floor: typeof dungeonFloors.$inferSelect,
    difficultyMultiplier: number
  ): Promise<DungeonRewardSummary> {
    const baseRewards = floor.baseRewards as FloorBaseReward;
    const firstClearRewards = floor.firstClearRewards as FloorFirstClearReward;

    // FUN-07-06-001: Calculate Floor Reward
    const silverReward = Math.floor(baseRewards.silver * difficultyMultiplier);
    const masterExpReward = Math.floor(baseRewards.masterExp * difficultyMultiplier);

    // FUN-07-06-002: Calculate Boss Reward (20% bonus silver on floor completion)
    const bossBonusSilver = Math.floor(silverReward * 0.2);

    // FUN-07-06-003: First Clear Reward if cleared for the first time
    const isFirstClear = world.currentFloor <= floor.floorNumber;
    const firstClearSilver = isFirstClear ? (firstClearRewards.silver ?? 0) : 0;
    const totalSilver = silverReward + bossBonusSilver + firstClearSilver;

    // FUN-07-06-004: Distribute Dungeon Reward
    // 1. Silver & Master EXP
    const [masterRecord] = await tx.select().from(masters).where(eq(masters.id, masterId)).for('update').limit(1);
    const masterLevelUps: { fromLevel: number; toLevel: number }[] = [];

    if (masterRecord) {
      let masterExp = masterRecord.exp + BigInt(masterExpReward);
      let masterLevel = masterRecord.level;
      const masterGrowth = await tx.select().from(masterLevelConfigs)
        .where(gt(masterLevelConfigs.level, masterRecord.level)).orderBy(asc(masterLevelConfigs.level));

      for (const config of masterGrowth) {
        if (masterExp < config.expRequired || config.level <= masterLevel) continue;
        masterExp -= config.expRequired;
        masterLevel = config.level;
      }
      if (masterLevel > masterRecord.level) {
        masterLevelUps.push({ fromLevel: masterRecord.level, toLevel: masterLevel });
      }

      await tx.update(masters).set({
        silverCoins: masterRecord.silverCoins + BigInt(totalSilver),
        exp: masterExp,
        level: masterLevel,
        updatedAt: new Date(),
      }).where(eq(masters.id, masterId));

      await tx.insert(currencyTransactions).values({
        id: uuidv4(),
        masterId,
        currencyType: 'SILVER',
        amountDelta: BigInt(totalSilver),
        transactionType: isFirstClear ? 'DUNGEON_FLOOR_FIRST_CLEAR' : 'DUNGEON_FLOOR_CLEAR',
        createdAt: new Date(),
      });
    }

    // 2. First Clear Summon Scrolls
    if (isFirstClear && firstClearRewards.normalScrolls) {
      const [existingScroll] = await tx.select().from(masterSummonInventory)
        .where(and(eq(masterSummonInventory.masterId, masterId), eq(masterSummonInventory.scrollType, 'NORMAL'))).limit(1);
      if (existingScroll) {
        await tx.update(masterSummonInventory).set({
          quantity: existingScroll.quantity + firstClearRewards.normalScrolls,
          updatedAt: new Date(),
        }).where(eq(masterSummonInventory.id, existingScroll.id));
      } else {
        await tx.insert(masterSummonInventory).values({
          id: uuidv4(),
          masterId,
          scrollType: 'NORMAL',
          quantity: firstClearRewards.normalScrolls,
          updatedAt: new Date(),
        });
      }
    }

    if (isFirstClear && firstClearRewards.specialScrolls) {
      const [existingScroll] = await tx.select().from(masterSummonInventory)
        .where(and(eq(masterSummonInventory.masterId, masterId), eq(masterSummonInventory.scrollType, 'SPECIAL'))).limit(1);
      if (existingScroll) {
        await tx.update(masterSummonInventory).set({
          quantity: existingScroll.quantity + firstClearRewards.specialScrolls,
          updatedAt: new Date(),
        }).where(eq(masterSummonInventory.id, existingScroll.id));
      } else {
        await tx.insert(masterSummonInventory).values({
          id: uuidv4(),
          masterId,
          scrollType: 'SPECIAL',
          quantity: firstClearRewards.specialScrolls,
          updatedAt: new Date(),
        });
      }
    }

    // 3. Advance World currentFloor if cleared highest floor
    if (world.currentFloor <= floor.floorNumber) {
      await tx.update(worlds).set({
        currentFloor: floor.floorNumber + 1,
      }).where(eq(worlds.id, world.id));
    }

    return {
      silverReward,
      bossBonusSilver,
      firstClearSilver,
      totalSilver,
      masterExpReward,
      firstClearScrolls: {
        normalScrolls: isFirstClear ? firstClearRewards.normalScrolls : undefined,
        specialScrolls: isFirstClear ? firstClearRewards.specialScrolls : undefined,
      },
      masterLevelUps,
    };
  }
}

export const dungeonExplorationService = new DungeonExplorationService();
