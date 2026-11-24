import { and, between, eq, inArray, ne, notInArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { masterWorldStatus, worldDungeons, worldTiles } from '../../database/drizzle-schema.js';
import { clampGridY, PLANET_GRID_WIDTH } from './planet-grid-rules.js';

export type DungeonRank = 'D' | 'C' | 'B' | 'A' | 'S';

interface DungeonTemplate {
  rank: DungeonRank;
  names: string[];
  bosses: string[];
  minPower: number;
  maxPower: number;
  maxPartySize: number;
  silverReward: number;
  durationMinutes: number;
  weight: number;
}

const TEMPLATES: DungeonTemplate[] = [
  {
    rank: 'D',
    names: ['Hang Động Rạn Nứt', 'Hầm Mộ Hoang Phế', 'Khe Nứt Ma Thú'],
    bosses: ['Thủ Lĩnh Goblin Bóng Đêm', 'Sói Đá Cổ Đại', 'Xác Ướp Gác Đền'],
    minPower: 800,
    maxPower: 1600,
    maxPartySize: 5,
    silverReward: 1200,
    durationMinutes: 180,
    weight: 30,
  },
  {
    rank: 'C',
    names: ['Phế Tích Đền Cổ', 'Hầm Ngục Hỏa Diệm', 'Mê Cung Đá Ngầm'],
    bosses: ['Hiệp Sĩ Giáp Hư Không', 'Hỏa Long Con', 'Pháp Sư Xương Trắng'],
    minPower: 1800,
    maxPower: 3400,
    maxPartySize: 5,
    silverReward: 2500,
    durationMinutes: 210,
    weight: 28,
  },
  {
    rank: 'B',
    names: ['Tháp Quỷ Nổi', 'Đấu Trường Bị Nguyền', 'Vực Thẳm Băng Giá'],
    bosses: ['Tướng Quân Quỷ Thép', 'Băng Ma Nữ Vương', 'Kỵ Sĩ Hắc Ám'],
    minPower: 3600,
    maxPower: 6500,
    maxPartySize: 5,
    silverReward: 4800,
    durationMinutes: 240,
    weight: 22,
  },
  {
    rank: 'A',
    names: ['Pháo Đài Ma Tộc (Raid)', 'Lăng Mộ Đế Vương (Raid)', 'Cổng Hư Không (Raid)'],
    bosses: ['Đại Tướng Ma Tộc', 'Huyết Long Cổ Đại', 'Chúa Tể Hư Không'],
    minPower: 7500,
    maxPower: 13000,
    maxPartySize: 15,
    silverReward: 9500,
    durationMinutes: 300,
    weight: 14,
  },
  {
    rank: 'S',
    names: ['Thánh Địa Diệt Thế (Đại Raid)', 'Cung Điện Hỗn Mang (Đại Raid)'],
    bosses: ['Thần Long Hủy Diệt', 'Ma Đế Vĩnh Hằng'],
    minPower: 14500,
    maxPower: 24000,
    maxPartySize: 15,
    silverReward: 18000,
    durationMinutes: 360,
    weight: 6,
  },
];

const TARGET_GLOBAL_DUNGEONS = 24;
const MAX_GLOBAL_DUNGEONS = 260;

function pickTemplate(seed: number, zoneTier = 1): DungeonTemplate {
  // Higher inland zone tiers favor higher-rank Raid dungeons
  const weighted = TEMPLATES.map(tpl => {
    let w = tpl.weight;
    if (zoneTier >= 3 && (tpl.rank === 'A' || tpl.rank === 'S')) w *= 2;
    else if (zoneTier === 2 && (tpl.rank === 'B' || tpl.rank === 'A')) w = Math.round(w * 1.5);
    return { tpl, w };
  });
  const totalWeight = weighted.reduce((sum, item) => sum + item.w, 0);
  let cursor = Math.abs(seed) % totalWeight;
  for (const item of weighted) {
    if (cursor < item.w) return item.tpl;
    cursor -= item.w;
  }
  return TEMPLATES[0];
}

export class WorldDungeonService {
  private async expireOverdue(now: Date) {
    await db.update(worldDungeons).set({ status: 'EXPIRED' }).where(and(
      eq(worldDungeons.status, 'ACTIVE'),
      sql`${worldDungeons.expiresAt} <= ${now}`,
    ));
  }

  private async spawnOnTiles(
    freeTiles: Array<typeof worldTiles.$inferSelect>,
    needed: number,
    now: Date,
  ): Promise<Array<typeof worldDungeons.$inferSelect>> {
    const created: Array<typeof worldDungeons.$inferSelect> = [];
    const baseSeed = Math.floor(now.getTime() / 1000);
    const pool = [...freeTiles];

    for (let i = 0; i < needed && pool.length > 0; i++) {
      const pickIndex = (baseSeed * 31 + i * 17) % pool.length;
      const [tile] = pool.splice(pickIndex, 1);
      if (!tile) break;

      const tpl = pickTemplate(baseSeed + tile.x * 13 + tile.y * 7 + i * 29, tile.zoneTier ?? 1);
      const name = tpl.names[(tile.x + tile.y + i) % tpl.names.length];
      const bossName = tpl.bosses[(tile.x * 3 + tile.y + i) % tpl.bosses.length];
      const powerSpan = Math.max(1, tpl.maxPower - tpl.minPower);
      const recommendedPower = tpl.minPower + ((tile.x * 97 + tile.y * 53 + i * 41) % powerSpan);
      const expiresAt = new Date(now.getTime() + tpl.durationMinutes * 60_000);

      const [row] = await db.insert(worldDungeons).values({
        id: uuidv4(),
        tileId: tile.id,
        name,
        rank: tpl.rank,
        recommendedPower,
        maxPartySize: tpl.maxPartySize,
        bossName,
        rewards: {
          silverCoins: tpl.silverReward,
          rank: tpl.rank,
        },
        status: 'ACTIVE',
        spawnedAt: now,
        expiresAt,
      }).returning();
      if (row) created.push(row);
    }
    return created;
  }

  /** Fast indexed ensure: guarantees global baseline dungeons without loading all 180k tiles. */
  async ensureActiveDungeons(now = new Date()) {
    await this.expireOverdue(now);
    const active = await db.select().from(worldDungeons).where(eq(worldDungeons.status, 'ACTIVE'));
    if (active.length >= TARGET_GLOBAL_DUNGEONS) return active;

    const occupiedTiles = new Set(active.map(row => row.tileId));
    const candidates = await db.select().from(worldTiles)
      .where(and(
        eq(worldTiles.isOuterRim, true),
        notInArray(worldTiles.terrain, ['OCEAN', 'WONDER']),
      ))
      .orderBy(sql`random()`)
      .limit(60);

    const freeTiles = candidates.filter(tile => !occupiedTiles.has(tile.id));
    if (freeTiles.length === 0) return active;

    const needed = Math.min(TARGET_GLOBAL_DUNGEONS - active.length, freeTiles.length);
    const created = await this.spawnOnTiles(freeTiles, needed, now);
    return [...active, ...created];
  }

  /**
   * Localized RTS Dungeon Seeding: ensures at least `minCount` Emerging Dungeons exist on land tiles
   * inside `(cx +/- radius, cy +/- radius)` around a newly spawned player or active viewport chunk.
   */
  async ensureDungeonsNear(cx: number, cy: number, radius = 12, minCount = 5, now = new Date()) {
    await this.expireOverdue(now);

    const minY = clampGridY(cy - radius);
    const maxY = clampGridY(cy + radius);
    const minX = Math.max(0, Math.round(cx - radius));
    const maxX = Math.min(PLANET_GRID_WIDTH - 1, Math.round(cx + radius));

    const localTiles = await db.select().from(worldTiles)
      .where(and(
        between(worldTiles.x, minX, maxX),
        between(worldTiles.y, minY, maxY),
        notInArray(worldTiles.terrain, ['OCEAN', 'WONDER']),
      ));
    if (localTiles.length === 0) return [];

    const tileIds = localTiles.map(t => t.id);
    const [localActive, totalCountRow, localBases] = await Promise.all([
      db.select().from(worldDungeons).where(and(
        eq(worldDungeons.status, 'ACTIVE'),
        inArray(worldDungeons.tileId, tileIds),
      )),
      db.select({ total: sql<number>`count(*)::int` }).from(worldDungeons).where(eq(worldDungeons.status, 'ACTIVE')),
      db.select({ x: masterWorldStatus.baseX, y: masterWorldStatus.baseY })
        .from(masterWorldStatus)
        .where(and(between(masterWorldStatus.baseX, minX, maxX), between(masterWorldStatus.baseY, minY, maxY))),
    ]);

    const totalActive = totalCountRow[0]?.total ?? 0;
    if (localActive.length >= minCount || totalActive >= MAX_GLOBAL_DUNGEONS) {
      return localActive;
    }

    const occupiedIds = new Set(localActive.map(row => row.tileId));
    const baseKeys = new Set(localBases.map(b => `${b.x},${b.y}`));
    const freeTiles = localTiles.filter(t => !occupiedIds.has(t.id) && !baseKeys.has(`${t.x},${t.y}`));
    if (freeTiles.length === 0) return localActive;

    const budget = Math.max(0, MAX_GLOBAL_DUNGEONS - totalActive);
    const needed = Math.min(minCount - localActive.length, freeTiles.length, budget);
    const created = await this.spawnOnTiles(freeTiles, needed, now);
    return [...localActive, ...created];
  }

  async activeByTileIds(tileIds: string[], now = new Date()) {
    await this.expireOverdue(now);
    if (tileIds.length === 0) return [];
    return db.select().from(worldDungeons).where(and(
      eq(worldDungeons.status, 'ACTIVE'),
      inArray(worldDungeons.tileId, tileIds),
    ));
  }
}

export const worldDungeonService = new WorldDungeonService();
