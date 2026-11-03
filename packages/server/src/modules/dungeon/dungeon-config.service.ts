import { eq, asc } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { dungeonTemplates, dungeonFloors } from '../../database/drizzle-schema.js';

export class DungeonConfigError extends Error {
  constructor(message: string, public readonly statusCode = 400) {
    super(message);
    this.name = 'DungeonConfigError';
  }
}

export type FloorUnlockRequirement = {
  requiredMasterLevel?: number;
  previousFloorCleared?: boolean;
};

export type FloorBaseReward = {
  silver: number;
  masterExp: number;
  dropItems?: { itemCode: string; dropRate: number; minQuantity: number; maxQuantity: number }[];
};

export type FloorFirstClearReward = {
  silver?: number;
  normalScrolls?: number;
  specialScrolls?: number;
};

export class DungeonConfigService {
  /**
   * FUN-07-01-001 / FUN-07-01-002: Ensure default templates and floors exist.
   */
  public async ensureDefaultConfigs(): Promise<void> {
    const existing = await db.select().from(dungeonTemplates).limit(1);
    if (existing.length > 0) return;

    // Seed QUIET_FOREST
    const forestId = uuidv4();
    await db.insert(dungeonTemplates).values({
      id: forestId,
      code: 'QUIET_FOREST',
      name: 'Khu Rừng Yên Tĩnh (Quiet Forest)',
      description: 'Vùng đất ngoại ô u ám, nơi chứa đựng các sinh vật nguyên sinh và tàn quân phiến loạn.',
      totalFloors: 10,
      minMasterLevel: 1,
      createdAt: new Date(),
    });

    const floorConfigs = [
      { floor: 1, name: 'Bìa rừng tĩnh lặng', power: 100, minLvl: 1, baseSilver: 100, baseExp: 300, fcSilver: 500, fcNormal: 1, fcSpecial: 0 },
      { floor: 2, name: 'Lối mòn phủ rêu', power: 160, minLvl: 1, baseSilver: 150, baseExp: 350, fcSilver: 600, fcNormal: 1, fcSpecial: 0 },
      { floor: 3, name: 'Đầm lầy sương mù', power: 240, minLvl: 1, baseSilver: 200, baseExp: 400, fcSilver: 700, fcNormal: 1, fcSpecial: 0 },
      { floor: 4, name: 'Hang thổ phỉ', power: 350, minLvl: 2, baseSilver: 260, baseExp: 450, fcSilver: 850, fcNormal: 1, fcSpecial: 0 },
      { floor: 5, name: 'Cây cổ thụ nghìn năm', power: 500, minLvl: 2, baseSilver: 350, baseExp: 550, fcSilver: 1200, fcNormal: 2, fcSpecial: 0 },
      { floor: 6, name: 'Hẻm núi đá xám', power: 650, minLvl: 2, baseSilver: 420, baseExp: 650, fcSilver: 1500, fcNormal: 2, fcSpecial: 0 },
      { floor: 7, name: 'Dòng suối phát quang', power: 800, minLvl: 3, baseSilver: 500, baseExp: 750, fcSilver: 1800, fcNormal: 2, fcSpecial: 0 },
      { floor: 8, name: 'Tàn tích miếu thờ cổ', power: 950, minLvl: 3, baseSilver: 600, baseExp: 850, fcSilver: 2200, fcNormal: 3, fcSpecial: 0 },
      { floor: 9, name: 'Lãnh địa Golem khổng lồ', power: 1100, minLvl: 3, baseSilver: 700, baseExp: 950, fcSilver: 2500, fcNormal: 3, fcSpecial: 0 },
      { floor: 10, name: 'Thánh địa Hộ Vệ Rừng Sâu', power: 1300, minLvl: 4, baseSilver: 900, baseExp: 1200, fcSilver: 4000, fcNormal: 5, fcSpecial: 1 },
    ];

    for (const fc of floorConfigs) {
      await db.insert(dungeonFloors).values({
        id: uuidv4(),
        dungeonTemplateId: forestId,
        floorNumber: fc.floor,
        name: fc.name,
        recommendedPower: fc.power,
        unlockRequirements: {
          requiredMasterLevel: fc.minLvl,
          previousFloorCleared: fc.floor > 1,
        },
        baseRewards: {
          silver: fc.baseSilver,
          masterExp: fc.baseExp,
        },
        firstClearRewards: {
          silver: fc.fcSilver,
          normalScrolls: fc.fcNormal,
          specialScrolls: fc.fcSpecial,
        },
        createdAt: new Date(),
      });
    }
  }

  /**
   * FUN-07-01-001: List all Dungeon Templates.
   */
  public async listTemplates() {
    await this.ensureDefaultConfigs();
    return db.select().from(dungeonTemplates).orderBy(asc(dungeonTemplates.minMasterLevel));
  }

  /**
   * FUN-07-01-002: Get a Dungeon Template with all floors.
   */
  public async getTemplateWithFloors(templateIdOrCode: string) {
    await this.ensureDefaultConfigs();
    const [template] = await db.select().from(dungeonTemplates)
      .where(eq(dungeonTemplates.code, templateIdOrCode)).limit(1)
      .then(rows => rows.length ? rows : db.select().from(dungeonTemplates).where(eq(dungeonTemplates.id, templateIdOrCode)).limit(1));

    if (!template) throw new DungeonConfigError('Không tìm thấy cấu hình Dungeon.', 404);

    const floors = await db.select().from(dungeonFloors)
      .where(eq(dungeonFloors.dungeonTemplateId, template.id))
      .orderBy(asc(dungeonFloors.floorNumber));

    return {
      ...template,
      floors,
    };
  }

  /**
   * FUN-07-01-003: Check if a floor is unlocked for a Master.
   */
  public checkFloorUnlocked(
    floor: typeof dungeonFloors.$inferSelect,
    masterLevel: number,
    worldCurrentFloor: number
  ): { isUnlocked: boolean; reason?: string } {
    const reqs = floor.unlockRequirements as FloorUnlockRequirement;
    if (reqs.requiredMasterLevel && masterLevel < reqs.requiredMasterLevel) {
      return {
        isUnlocked: false,
        reason: `Yêu cầu Master cấp độ ${reqs.requiredMasterLevel} trở lên (Hiện tại: Lv.${masterLevel}).`,
      };
    }

    if (reqs.previousFloorCleared && worldCurrentFloor < floor.floorNumber) {
      return {
        isUnlocked: false,
        reason: `Cần vượt qua Tầng ${floor.floorNumber - 1} để mở khóa tầng này.`,
      };
    }

    return { isUnlocked: true };
  }

  /**
   * FUN-07-01-004: Get rewards configuration for a floor.
   */
  public getFloorRewards(floor: typeof dungeonFloors.$inferSelect): {
    baseRewards: FloorBaseReward;
    firstClearRewards: FloorFirstClearReward;
  } {
    return {
      baseRewards: floor.baseRewards as FloorBaseReward,
      firstClearRewards: floor.firstClearRewards as FloorFirstClearReward,
    };
  }
}

export const dungeonConfigService = new DungeonConfigService();
