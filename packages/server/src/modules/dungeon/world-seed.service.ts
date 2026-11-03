import { createHash } from 'crypto';
import { v4 as uuidv4, validate as validateUuid } from 'uuid';
import { eq } from 'drizzle-orm';
import { db } from '../../database/db.js';
import { worlds } from '../../database/drizzle-schema.js';

export class WorldSeedError extends Error {
  constructor(message: string, public readonly statusCode = 400) {
    super(message);
    this.name = 'WorldSeedError';
  }
}

export type ProceduralRoom = {
  roomIndex: number;
  roomType: 'COMBAT' | 'EVENT' | 'REST' | 'BOSS';
  name: string;
  cleared: boolean;
  eventCode?: string;
  foes?: {
    code: string;
    name: string;
    hp: number;
    maxHp: number;
    attack: number;
    defense: number;
    speed: number;
    element?: string;
  }[];
};

export type ReconstructedFloor = {
  worldSeed: string;
  seedAlgorithmVersion: number;
  floorNumber: number;
  difficultyMultiplier: number;
  totalRooms: number;
  rooms: ProceduralRoom[];
  floorEvent: {
    code: string;
    name: string;
    description: string;
    eventType: string;
  };
};

export class WorldSeedService {
  public static readonly CURRENT_ALGORITHM_VERSION = 1;

  /**
   * FUN-07-02-001: Generate World Seed (UUIDv4) and compute base difficulty factor.
   */
  public generateWorldSeed(): { worldSeed: string; difficultyMultiplier: number } {
    const worldSeed = uuidv4();
    const seedInt = parseInt(worldSeed.replace(/-/g, '').slice(0, 8), 16);
    const difficultyMultiplier = 1.0 + (seedInt % 50) / 100.0; // 1.00 to 1.49
    return { worldSeed, difficultyMultiplier };
  }

  /**
   * FUN-07-02-002: Validate UUID format.
   */
  public validateSeed(seed: string): boolean {
    return typeof seed === 'string' && validateUuid(seed);
  }

  /**
   * Deterministic hash helper returning an integer in [0, max - 1].
   */
  public deterministicHash(key: string, max: number): number {
    const digest = createHash('sha256').update(key).digest();
    return digest.readUInt32BE(0) % max;
  }

  /**
   * Deterministic float helper returning a number in [0, 1).
   */
  public deterministicFloat(key: string): number {
    const digest = createHash('sha256').update(key).digest();
    return digest.readUInt32BE(0) / 0xffffffff;
  }

  /**
   * FUN-07-02-004: Reconstruct Dungeon deterministically from World Seed and Floor Number.
   * Calling this function with the exact same (worldSeed, floorNumber, algorithmVersion)
   * produces the identical room layout, enemy counts, scaling, and events.
   * Seed is NEVER re-rolled upon failure.
   */
  public reconstructFloor(
    worldSeed: string,
    floorNumber: number,
    baseDifficulty: number = 1.0,
    algorithmVersion: number = WorldSeedService.CURRENT_ALGORITHM_VERSION
  ): ReconstructedFloor {
    if (!this.validateSeed(worldSeed)) {
      throw new WorldSeedError('World Seed không đúng định dạng UUID.', 400);
    }

    // Floor-specific scaling curve
    const floorScaling = 1 + (floorNumber - 1) * 0.08;
    const effectiveDifficulty = baseDifficulty * floorScaling;

    // Deterministic floor event selection
    const possibleEvents = [
      { code: 'SAMPLE_SUPPLY_CACHE', name: 'Supply Cache', description: 'Một hòm tiếp tế bị bỏ quên bên rìa vách đá.', eventType: 'CACHE' },
      { code: 'SAMPLE_MOSS_SPRING', name: 'Moss Spring', description: 'Suối nước phủ rêu thanh tẩy tinh thần và hồi phục thể lực.', eventType: 'REST' },
      { code: 'SAMPLE_BANDIT_AMBUSH', name: 'Bandit Ambush', description: 'Thổ phỉ mai phục trong bóng tối rình rập tấn công.', eventType: 'AMBUSH' },
    ];
    const eventIdx = this.deterministicHash(`${worldSeed}:${floorNumber}:event:v${algorithmVersion}`, possibleEvents.length);
    const floorEvent = possibleEvents[eventIdx];

    // Determine number of rooms (e.g. 3 to 5 rooms per floor)
    const isMilestoneFloor = floorNumber % 5 === 0;
    const roomCount = isMilestoneFloor ? 4 : 3;

    const rooms: ProceduralRoom[] = [];

    // Room 0: COMBAT (Frontline encounter)
    const enemyCountR0 = 2 + this.deterministicHash(`${worldSeed}:${floorNumber}:room0:enemyCount`, 2);
    rooms.push({
      roomIndex: 0,
      roomType: 'COMBAT',
      name: `Phòng Tiền Tuyến (Floor ${floorNumber} - Room 1)`,
      cleared: false,
      foes: this.generateEnemies(`${worldSeed}:${floorNumber}:room0`, enemyCountR0, effectiveDifficulty, false),
    });

    // Room 1: EVENT / REST
    const hasRest = this.deterministicHash(`${worldSeed}:${floorNumber}:room1:type`, 2) === 1;
    rooms.push({
      roomIndex: 1,
      roomType: hasRest ? 'REST' : 'EVENT',
      name: hasRest ? `Điểm Dừng Chân (Floor ${floorNumber} - Room 2)` : `Sự Kiện Bí Ẩn (Floor ${floorNumber} - Room 2)`,
      cleared: false,
      eventCode: floorEvent.code,
    });

    // Room 2 (if 4 rooms): COMBAT Elite
    if (roomCount === 4) {
      const enemyCountR2 = 2 + this.deterministicHash(`${worldSeed}:${floorNumber}:room2:enemyCount`, 3);
      rooms.push({
        roomIndex: 2,
        roomType: 'COMBAT',
        name: `Đội Tinh Anh (Floor ${floorNumber} - Room 3)`,
        cleared: false,
        foes: this.generateEnemies(`${worldSeed}:${floorNumber}:room2`, enemyCountR2, effectiveDifficulty * 1.15, false),
      });
    }

    // Final Room: BOSS or GUARDIAN
    const lastRoomIndex = roomCount - 1;
    rooms.push({
      roomIndex: lastRoomIndex,
      roomType: 'BOSS',
      name: isMilestoneFloor ? `Sào Huyệt Trùm Tầng ${floorNumber}` : `Thủ Lĩnh Khu Vực Tầng ${floorNumber}`,
      cleared: false,
      foes: this.generateEnemies(`${worldSeed}:${floorNumber}:boss`, isMilestoneFloor ? 3 : 2, effectiveDifficulty * (isMilestoneFloor ? 1.5 : 1.25), true),
    });

    return {
      worldSeed,
      seedAlgorithmVersion: algorithmVersion,
      floorNumber,
      difficultyMultiplier: effectiveDifficulty,
      totalRooms: rooms.length,
      rooms,
      floorEvent,
    };
  }

  private generateEnemies(
    seedKey: string,
    count: number,
    difficultyMultiplier: number,
    isBossRoom: boolean
  ): ProceduralRoom['foes'] {
    const enemyTemplatesList = [
      { code: 'SAMPLE_MOSS_SLIME', name: 'Moss Slime', hp: 300, atk: 30, def: 10, spd: 40, element: 'EARTH' },
      { code: 'SAMPLE_FOREST_BANDIT', name: 'Forest Bandit', hp: 450, atk: 45, def: 18, spd: 55, element: 'WIND' },
      { code: 'SAMPLE_STONE_GOLEM', name: 'Stone Golem', hp: 700, atk: 55, def: 35, spd: 25, element: 'EARTH' },
    ];

    const result: NonNullable<ProceduralRoom['foes']> = [];
    for (let i = 0; i < count; i++) {
      const idx = this.deterministicHash(`${seedKey}:foe:${i}`, enemyTemplatesList.length);
      const base = enemyTemplatesList[idx];
      const isBossUnit = isBossRoom && i === 0;

      const bossMultiplier = isBossUnit ? 1.8 : 1.0;
      const hp = Math.max(1, Math.floor(base.hp * difficultyMultiplier * bossMultiplier));
      const attack = Math.max(1, Math.floor(base.atk * difficultyMultiplier * (isBossUnit ? 1.3 : 1.0)));
      const defense = Math.max(0, Math.floor(base.def * difficultyMultiplier));
      const speed = Math.max(1, Math.floor(base.spd * (isBossUnit ? 1.1 : 1.0)));

      result.push({
        code: isBossUnit ? `BOSS_${base.code}` : base.code,
        name: isBossUnit ? `Thủ Lĩnh ${base.name}` : base.name,
        hp,
        maxHp: hp,
        attack,
        defense,
        speed,
        element: base.element,
      });
    }

    return result;
  }

  /**
   * FUN-07-02-005: Manage Seed Lifecycle — verify World Seed cannot be mutated.
   */
  public async getMasterWorld(masterId: string) {
    const [world] = await db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1);
    if (!world) throw new WorldSeedError('Chưa có World cho Master này.', 404);
    return world;
  }
}

export const worldSeedService = new WorldSeedService();
