import { and, asc, desc, eq, inArray, isNull, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  heroes, masterWorldStatus, masters, territories, territoryEvents, tileClearances, tileDiscoveries, worldTiles, worlds,
} from '../../database/drizzle-schema.js';
import { topCombatPower } from '../liveops/liveops-rules.js';
import { expeditionService } from './expedition.service.js';
import {
  CLAIM_COST_SILVER, DISCOVERY_RADIUS, MAX_TERRITORIES, MAX_TERRITORY_LEVEL, abandonAt, canClaim,
  canUnlockGlobal, isDiscoverable, protectionUntil, shieldUntil, territoryYield, upgradeCost,
} from './world-rules.js';

export class WorldError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'WorldError';
  }
}

const serialise = (row: typeof territories.$inferSelect, tile: typeof worldTiles.$inferSelect) => ({
  ...row,
  tile,
  hourlyYield: territoryYield(tile.baseYieldPerHour, row.level),
});

export class WorldService {
  private async master(masterId: string) {
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new WorldError('Không tìm thấy Master.', 404);
    return master;
  }

  private async statusRow(masterId: string) {
    const [row] = await db.select().from(masterWorldStatus).where(eq(masterWorldStatus.masterId, masterId)).limit(1);
    return row;
  }

  /** Lazy release of abandoned territories. */
  private async settle(now = new Date()) {
    const due = await db.select().from(territories)
      .where(and(eq(territories.status, 'ABANDONING'), sql`${territories.releaseAt} <= ${now}`));
    for (const row of due) {
      await db.update(territories).set({ status: 'UNOWNED', masterId: null, releaseAt: null, updatedAt: now })
        .where(eq(territories.id, row.id));
      await db.insert(territoryEvents).values({
        id: uuidv4(), tileId: row.tileId, masterId: row.masterId, action: 'RELEASED',
        detail: { releasedAt: now.toISOString() }, createdAt: now,
      });
    }
  }

  private async ownedCount(masterId: string): Promise<number> {
    const [row] = await db.select({ total: sql<number>`count(*)::int` }).from(territories)
      .where(and(eq(territories.masterId, masterId), inArray(territories.status, ['OWNED', 'ABANDONING'])));
    return row?.total ?? 0;
  }

  async status(masterId: string, now = new Date()) {
    await this.settle(now);
    const [master, world, status] = await Promise.all([
      this.master(masterId),
      db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1).then(rows => rows[0]),
      this.statusRow(masterId),
    ]);
    const discovered = status
      ? (await db.select({ total: sql<number>`count(*)::int` }).from(tileDiscoveries).where(eq(tileDiscoveries.masterId, masterId)))[0]?.total ?? 0
      : 0;
    const owned = status ? await this.ownedCount(masterId) : 0;
    const totalTiles = (await db.select({ total: sql<number>`count(*)::int` }).from(worldTiles))[0]?.total ?? 0;

    return {
      unlocked: Boolean(status),
      eligible: canUnlockGlobal({ masterLevel: master.level, clearedFloor: world?.currentFloor ?? 1 }),
      masterLevel: master.level,
      clearedFloor: world?.currentFloor ?? 1,
      base: status ? { x: status.baseX, y: status.baseY } : null,
      unlockedAt: status?.unlockedAt ?? null,
      shieldUntil: status?.shieldUntil ?? null,
      shieldActive: status ? status.shieldUntil > now : false,
      discoveryRadius: DISCOVERY_RADIUS,
      progress: {
        discovered,
        totalTiles,
        owned,
        maxTerritories: MAX_TERRITORIES,
      },
    };
  }

  /** Scenario P3-01: unlock at level 15 + floor 10, random outer-rim base, 48h shield. */
  async unlock(masterId: string, now = new Date()) {
    const [master, world] = await Promise.all([
      this.master(masterId),
      db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1).then(rows => rows[0]),
    ]);
    const check = canUnlockGlobal({ masterLevel: master.level, clearedFloor: world?.currentFloor ?? 1 });
    if (!check.ok) throw new WorldError(check.reason ?? 'ERR_WORLD_LOCKED', 409);

    const existing = await this.statusRow(masterId);
    if (existing) return this.status(masterId, now);

    const candidates = await db.select().from(worldTiles).where(eq(worldTiles.isOuterRim, true)).orderBy(asc(worldTiles.x), asc(worldTiles.y));
    if (candidates.length === 0) throw new WorldError('Bản đồ thế giới chưa được cấu hình.', 503);
    let hash = 2166136261;
    for (const char of masterId) {
      hash ^= char.charCodeAt(0);
      hash = Math.imul(hash, 16777619);
    }
    const base = candidates[Math.abs(hash) % candidates.length];

    await db.insert(masterWorldStatus).values({
      masterId, unlockedAt: now, baseX: base.x, baseY: base.y, shieldUntil: shieldUntil(now),
    });

    const nearby = candidates.filter(tile => isDiscoverable({ x: tile.x, y: tile.y }, { x: base.x, y: base.y }, []));
    if (nearby.length > 0) {
      await db.insert(tileDiscoveries).values(nearby.map(tile => ({
        id: uuidv4(), masterId, tileId: tile.id, discoveredAt: now,
      }))).onConflictDoNothing();
    }
    await db.insert(territoryEvents).values({
      id: uuidv4(), tileId: base.id, masterId, action: 'BASE_UNLOCKED',
      detail: { x: base.x, y: base.y }, createdAt: now,
    });
    return this.status(masterId, now);
  }

  async map(masterId: string, now = new Date()) {
    await this.settle(now);
    const status = await this.statusRow(masterId);
    if (!status) throw new WorldError('ERR_WORLD_LOCKED', 409);

    const tiles = await db.select().from(worldTiles).orderBy(asc(worldTiles.y), asc(worldTiles.x));
    const territoryRows = await db.select().from(territories);
    const owners = await db.select({ id: masters.id, name: masters.masterName }).from(masters);
    const nameById = new Map(owners.map(row => [row.id, row.name]));
    const territoryByTile = new Map(territoryRows.map(row => [row.tileId, row]));
    const discoveries = await db.select().from(tileDiscoveries).where(eq(tileDiscoveries.masterId, masterId));
    const discovered = new Set(discoveries.map(row => row.tileId));

    return {
      base: { x: status.baseX, y: status.baseY },
      shieldUntil: status.shieldUntil,
      tiles: tiles.map(tile => {
        const territoryRow = territoryByTile.get(tile.id);
        const ownerName = territoryRow?.masterId ? nameById.get(territoryRow.masterId) ?? '—' : null;
        return {
          id: tile.id, x: tile.x, y: tile.y, terrain: tile.terrain, resourceType: tile.resourceType,
          baseYieldPerHour: tile.baseYieldPerHour, requiredPower: tile.requiredPower,
          discovered: discovered.has(tile.id),
          owner: territoryRow?.masterId ? { masterId: territoryRow.masterId, name: ownerName, level: territoryRow.level, status: territoryRow.status } : null,
          mine: territoryRow?.masterId === masterId,
        };
      }),
    };
  }

  async tile(masterId: string, tileId: string, now = new Date()) {
    await this.settle(now);
    const status = await this.statusRow(masterId);
    if (!status) throw new WorldError('ERR_WORLD_LOCKED', 409);
    const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, tileId)).limit(1);
    if (!tile) throw new WorldError('Ô đất không tồn tại.', 404);
    const discoveries = await db.select().from(tileDiscoveries).where(eq(tileDiscoveries.masterId, masterId));
    const discoveredTiles = await db.select().from(worldTiles)
      .where(inArray(worldTiles.id, discoveries.length ? discoveries.map(row => row.tileId) : ['-']));
    const [territoryRow] = await db.select().from(territories).where(eq(territories.tileId, tileId)).limit(1);
    const discovered = discoveries.some(row => row.tileId === tileId);

    return {
      tile,
      discovered,
      owned: territoryRow?.masterId === masterId,
      owner: territoryRow?.masterId ?? null,
      territory: territoryRow ?? null,
      canDiscover: !discovered && isDiscoverable({ x: tile.x, y: tile.y }, { x: status.baseX, y: status.baseY },
        discoveredTiles.map(row => ({ x: row.x, y: row.y }))),
    };
  }

  async discover(masterId: string, tileId: string, now = new Date()) {
    const status = await this.statusRow(masterId);
    if (!status) throw new WorldError('ERR_WORLD_LOCKED', 409);
    const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, tileId)).limit(1);
    if (!tile) throw new WorldError('Ô đất không tồn tại.', 404);
    const existing = await db.select({ id: tileDiscoveries.id }).from(tileDiscoveries)
      .where(and(eq(tileDiscoveries.masterId, masterId), eq(tileDiscoveries.tileId, tileId))).limit(1);
    if (existing.length > 0) return { tileId, discovered: true, alreadyKnown: true };

    const discoveries = await db.select().from(tileDiscoveries).where(eq(tileDiscoveries.masterId, masterId));
    const known = await db.select().from(worldTiles)
      .where(inArray(worldTiles.id, discoveries.length ? discoveries.map(row => row.tileId) : ['-']));
    if (!isDiscoverable({ x: tile.x, y: tile.y }, { x: status.baseX, y: status.baseY }, known.map(row => ({ x: row.x, y: row.y })))) {
      throw new WorldError('ERR_WORLD_TILE_OUT_OF_RANGE', 409);
    }
    await db.insert(tileDiscoveries).values({ id: uuidv4(), masterId, tileId, discoveredAt: now }).onConflictDoNothing();
    return { tileId, discovered: true, alreadyKnown: false };
  }

  async claim(masterId: string, tileId: string, now = new Date()) {
    await expeditionService.settle(masterId, now);
    const status = await this.statusRow(masterId);
    if (!status) throw new WorldError('ERR_WORLD_LOCKED', 409);
    const [tile] = await db.select().from(worldTiles).where(eq(worldTiles.id, tileId)).limit(1);
    if (!tile) throw new WorldError('Ô đất không tồn tại.', 404);

    const [discovery] = await db.select().from(tileDiscoveries)
      .where(and(eq(tileDiscoveries.masterId, masterId), eq(tileDiscoveries.tileId, tileId))).limit(1);
    if (!discovery) throw new WorldError('ERR_WORLD_TILE_NOT_DISCOVERED', 409);

    if (status.shieldUntil > now) {
      throw new WorldError('ERR_WORLD_SHIELD_ACTIVE', 409);
    }

    // Heroes must have won the guardian battle at this tile first (no army abstraction).
    const [clearance] = await db.select().from(tileClearances)
      .where(and(eq(tileClearances.masterId, masterId), eq(tileClearances.tileId, tileId))).limit(1);
    if (!clearance) throw new WorldError('ERR_TERRITORY_NOT_CLEARED', 409);

    const [existing] = await db.select().from(territories).where(eq(territories.tileId, tileId)).limit(1);
    const ownedCount = await this.ownedCount(masterId);
    const check = canClaim(ownedCount, Boolean(existing?.masterId));
    if (!check.ok) throw new WorldError(check.reason ?? 'ERR_TERRITORY_CLAIM_FAILED', 409);

    const master = await this.master(masterId);
    if (Number(master.silverCoins) < CLAIM_COST_SILVER) throw new WorldError('ERR_TERRITORY_INSUFFICIENT_SILVER', 409);

    const protection = protectionUntil(now);
    const territory = await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${CLAIM_COST_SILVER}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      const [row] = existing
        ? await tx.update(territories).set({
          masterId, level: 1, status: 'OWNED', claimedAt: now, protectedUntil: protection, releaseAt: null, updatedAt: now,
        }).where(eq(territories.id, existing.id)).returning()
        : await tx.insert(territories).values({
          id: uuidv4(), tileId, masterId, level: 1, status: 'OWNED', claimedAt: now, protectedUntil: protection, updatedAt: now,
        }).returning();
      await tx.insert(territoryEvents).values({
        id: uuidv4(), tileId, masterId, action: 'CLAIMED',
        detail: { level: 1, silverSpent: CLAIM_COST_SILVER, protectedUntil: protection.toISOString() }, createdAt: now,
      });
      return row;
    });

    return { territory: serialise(territory, tile), silverSpent: CLAIM_COST_SILVER, protectedUntil: protection, owned: ownedCount + 1 };
  }

  async listTerritories(masterId: string, now = new Date()) {
    await this.settle(now);
    const rows = await db.select({ territory: territories, tile: worldTiles })
      .from(territories).innerJoin(worldTiles, eq(worldTiles.id, territories.tileId))
      .where(eq(territories.masterId, masterId)).orderBy(desc(territories.claimedAt));
    const tiles = rows.map(row => serialise(row.territory, row.tile));
    return {
      territories: tiles,
      owned: tiles.filter(row => row.status !== 'UNOWNED').length,
      max: MAX_TERRITORIES,
      hourlyYield: tiles.filter(row => row.status === 'OWNED')
        .reduce((sum, row) => sum + row.hourlyYield, 0),
    };
  }

  async upgrade(masterId: string, territoryId: string, now = new Date()) {
    const [row] = await db.select({ territory: territories, tile: worldTiles })
      .from(territories).innerJoin(worldTiles, eq(worldTiles.id, territories.tileId))
      .where(and(eq(territories.id, territoryId), eq(territories.masterId, masterId))).limit(1);
    if (!row) throw new WorldError('Không tìm thấy lãnh thổ.', 404);
    if (row.territory.status !== 'OWNED') throw new WorldError('Lãnh thổ đang được giải phóng.', 409);
    if (row.territory.level >= MAX_TERRITORY_LEVEL) throw new WorldError('ERR_TERRITORY_MAX_LEVEL', 409);

    const cost = upgradeCost(row.territory.level);
    const master = await this.master(masterId);
    if (Number(master.silverCoins) < cost) throw new WorldError('ERR_TERRITORY_INSUFFICIENT_SILVER', 409);

    const nextLevel = row.territory.level + 1;
    const updated = await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${cost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      const [territoryRow] = await tx.update(territories).set({ level: nextLevel, updatedAt: now })
        .where(eq(territories.id, territoryId)).returning();
      await tx.insert(territoryEvents).values({
        id: uuidv4(), tileId: row.territory.tileId, masterId, action: 'UPGRADED',
        detail: { level: nextLevel, silverSpent: cost }, createdAt: now,
      });
      return territoryRow;
    });

    return { territory: serialise(updated, row.tile), silverSpent: cost };
  }

  async abandon(masterId: string, territoryId: string, now = new Date()) {
    const [row] = await db.select().from(territories)
      .where(and(eq(territories.id, territoryId), eq(territories.masterId, masterId))).limit(1);
    if (!row) throw new WorldError('Không tìm thấy lãnh thổ.', 404);
    if (row.status !== 'OWNED') throw new WorldError('ERR_TERRITORY_ALREADY_ABANDONING', 409);

    const release = abandonAt(now);
    const [updated] = await db.update(territories).set({ status: 'ABANDONING', releaseAt: release, updatedAt: now })
      .where(eq(territories.id, territoryId)).returning();
    await db.insert(territoryEvents).values({
      id: uuidv4(), tileId: row.tileId, masterId, action: 'ABANDON_STARTED',
      detail: { releaseAt: release.toISOString() }, createdAt: now,
    });
    return { territory: updated, releaseAt: release };
  }

  async history(masterId: string) {
    return db.select().from(territoryEvents)
      .where(eq(territoryEvents.masterId, masterId))
      .orderBy(desc(territoryEvents.createdAt)).limit(50);
  }

  /** Global ranking helper used by the world overview page. */
  async leaderboard(limit = 10) {
    const rows = await db.select({
      masterId: territories.masterId,
      name: masters.masterName,
      tiles: sql<number>`count(*)::int`,
      levels: sql<number>`coalesce(sum(${territories.level}), 0)::int`,
    }).from(territories)
      .innerJoin(masters, eq(masters.id, territories.masterId))
      .where(eq(territories.status, 'OWNED'))
      .groupBy(territories.masterId, masters.masterName)
      .orderBy(sql`count(*) desc`)
      .limit(limit);
    return rows;
  }
}

export const worldService = new WorldService();
