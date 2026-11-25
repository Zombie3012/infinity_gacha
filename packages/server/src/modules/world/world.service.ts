import { and, asc, between, desc, eq, inArray, isNull, or, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  heroes, masterWorldStatus, masters, territories, territoryEvents, tileClearances, tileDiscoveries,
  worldDungeons, worldTiles, worlds,
} from '../../database/drizzle-schema.js';
import { topCombatPower } from '../liveops/liveops-rules.js';
import { expeditionService } from './expedition.service.js';
import { worldDungeonService } from './world-dungeon.service.js';
import {
  clampChunkRadius, clampGridY, DEFAULT_CHUNK_RADIUS, MIN_SPAWN_SPACING_TILES, PLANET_GRID_HEIGHT,
  PLANET_GRID_WIDTH, PLAYABLE_CONTINENTS, planetTileDistance, SPAWNABLE_TERRAINS, wrapGridX,
} from './planet-grid-rules.js';
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
      unlocked: Boolean(status) && (world?.currentFloor ?? 1) > 25,
      eligible: canUnlockGlobal({ currentFloor: world?.currentFloor ?? 1 }),
      clearedFloor: Math.max(0, (world?.currentFloor ?? 1) - 1),
      base: status ? { x: status.baseX, y: status.baseY, continentId: status.continentId } : null,
      worldGrid: { width: PLANET_GRID_WIDTH, height: PLANET_GRID_HEIGHT },
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

  /**
   * RTS Smart Random Spawn:
   * - Balances new players across all 5 playable continents (or honors optional `continentId`).
   * - Picks an unoccupied Outer Rim land tile (`PLAINS` / `FOREST` / `HILLS`, never `OCEAN` or `WONDER`)
   *   maintaining >= MIN_SPAWN_SPACING_TILES (10) distance from all existing player bases (soft fallback 6->3->1).
   * - Auto-discovers nearby land tiles and seeds local Emerging Dungeons around the new base.
   */
  private async pickRandomSpawnTile(preferredContinentId?: string | null) {
    const validPreferred = preferredContinentId && (PLAYABLE_CONTINENTS as readonly string[]).includes(preferredContinentId)
      ? preferredContinentId
      : null;

    // Count active bases per continent to balance population across all 5 continents
    const popRows = await db.select({
      continentId: masterWorldStatus.continentId,
      total: sql<number>`count(*)::int`,
    }).from(masterWorldStatus).groupBy(masterWorldStatus.continentId);
    const popByContinent = new Map(popRows.map(r => [r.continentId, r.total]));

    let continentOrder: string[];
    if (validPreferred) {
      continentOrder = [validPreferred, ...PLAYABLE_CONTINENTS.filter(c => c !== validPreferred)];
    } else {
      // Sort continents by lowest population, randomizing ties so consecutive new players spread naturally
      const shuffled = [...PLAYABLE_CONTINENTS].sort(() => Math.random() - 0.5);
      continentOrder = shuffled.sort((a, b) => (popByContinent.get(a) ?? 0) - (popByContinent.get(b) ?? 0));
    }

    const allBases = await db.select({
      x: masterWorldStatus.baseX,
      y: masterWorldStatus.baseY,
      continentId: masterWorldStatus.continentId,
    }).from(masterWorldStatus);
    const occupiedBaseKeys = new Set(allBases.map(b => `${b.x},${b.y}`));

    for (const cid of continentOrder) {
      const candidates = await db.select().from(worldTiles)
        .where(and(
          eq(worldTiles.isOuterRim, true),
          eq(worldTiles.continentId, cid),
          inArray(worldTiles.terrain, [...SPAWNABLE_TERRAINS]),
        ))
        .orderBy(sql`random()`)
        .limit(120);
      if (candidates.length === 0) continue;

      const candIds = candidates.map(c => c.id);
      const [ownedTerrs, activeDungs] = await Promise.all([
        db.select({ tileId: territories.tileId }).from(territories)
          .where(and(inArray(territories.tileId, candIds), sql`${territories.masterId} IS NOT NULL`)),
        db.select({ tileId: worldDungeons.tileId }).from(worldDungeons)
          .where(and(inArray(worldDungeons.tileId, candIds), eq(worldDungeons.status, 'ACTIVE'))),
      ]);
      const blockedIds = new Set([...ownedTerrs.map(r => r.tileId), ...activeDungs.map(r => r.tileId)]);
      const free = candidates.filter(c => !occupiedBaseKeys.has(`${c.x},${c.y}`) && !blockedIds.has(c.id));
      if (free.length === 0) continue;

      const contBases = allBases.filter(b => b.continentId === cid);
      for (const minSpacing of [MIN_SPAWN_SPACING_TILES, 6, 3, 1]) {
        const spaced = free.find(tile => contBases.every(b => planetTileDistance(tile, b) >= minSpacing));
        if (spaced) return spaced;
      }
      return free[0];
    }

    // Ultimate fallback (e.g., tiny custom test DB without continent metadata)
    const [fallback] = await db.select().from(worldTiles)
      .where(and(eq(worldTiles.isOuterRim, true), sql`${worldTiles.terrain} <> 'OCEAN'`))
      .orderBy(sql`random()`)
      .limit(1);
    return fallback ?? null;
  }

  /** Unlock Global World with RTS Random Spawn, 48h Novice Shield, and local dungeons. */
  async unlock(masterId: string, optionsOrNow: { continentId?: string | null } | Date = {}, maybeNow?: Date) {
    const now = optionsOrNow instanceof Date ? optionsOrNow : (maybeNow ?? new Date());
    const preferredContinent = optionsOrNow instanceof Date ? null : (optionsOrNow?.continentId ?? null);

    const [master, world] = await Promise.all([
      this.master(masterId),
      db.select().from(worlds).where(eq(worlds.masterId, masterId)).limit(1).then(rows => rows[0]),
    ]);
    const check = canUnlockGlobal({ currentFloor: world?.currentFloor ?? 1 });
    if (!check.ok) throw new WorldError(check.reason ?? 'ERR_WORLD_LOCKED', 409);

    const existing = await this.statusRow(masterId);
    if (existing) return this.status(masterId, now);

    const base = await this.pickRandomSpawnTile(preferredContinent);
    if (!base) throw new WorldError('Bản đồ thế giới chưa được cấu hình.', 503);

    await db.insert(masterWorldStatus).values({
      masterId,
      unlockedAt: now,
      baseX: base.x,
      baseY: base.y,
      continentId: base.continentId ?? 'emerald_reach',
      shieldUntil: shieldUntil(now),
    });

    // Discover nearby LAND tiles inside DISCOVERY_RADIUS using fast indexed bounding box
    const minX = Math.max(0, base.x - DISCOVERY_RADIUS);
    const maxX = Math.min(PLANET_GRID_WIDTH - 1, base.x + DISCOVERY_RADIUS);
    const minY = clampGridY(base.y - DISCOVERY_RADIUS);
    const maxY = clampGridY(base.y + DISCOVERY_RADIUS);
    const nearby = await db.select().from(worldTiles).where(and(
      between(worldTiles.x, minX, maxX),
      between(worldTiles.y, minY, maxY),
      sql`${worldTiles.terrain} NOT IN ('OCEAN', 'WONDER')`,
    ));
    if (nearby.length > 0) {
      await db.insert(tileDiscoveries).values(nearby.map(tile => ({
        id: uuidv4(), masterId, tileId: tile.id, discoveredAt: now,
      }))).onConflictDoNothing();
    }

    await db.insert(territoryEvents).values({
      id: uuidv4(), tileId: base.id, masterId, action: 'BASE_UNLOCKED',
      detail: { x: base.x, y: base.y, continentId: base.continentId }, createdAt: now,
    });

    // Seed at least 1 starter dungeon inside home vision (radius 2) + 4 more across the surrounding chunk (radius 12)
    await worldDungeonService.ensureDungeonsNear(base.x, base.y, 2, 1, now)
      .then(() => worldDungeonService.ensureDungeonsNear(base.x, base.y, DEFAULT_CHUNK_RADIUS, 5, now))
      .catch(err => console.error('[world.unlock] ensureDungeonsNear failed', err));

    return this.status(masterId, now);
  }

  async map(masterId: string, optionsOrNow: { cx?: unknown; cy?: unknown; radius?: unknown } | Date = {}, maybeNow?: Date) {
    const now = optionsOrNow instanceof Date ? optionsOrNow : (maybeNow ?? new Date());
    const opts = optionsOrNow instanceof Date ? {} : (optionsOrNow ?? {});

    await this.settle(now);
    const status = await this.statusRow(masterId);
    if (!status) throw new WorldError('ERR_WORLD_LOCKED', 409);

    const cx = opts.cx !== undefined ? wrapGridX(Number(opts.cx)) : status.baseX;
    const cy = opts.cy !== undefined ? clampGridY(Number(opts.cy)) : status.baseY;
    const radius = clampChunkRadius(opts.radius ?? DEFAULT_CHUNK_RADIUS);
    const minX = Math.max(0, cx - radius);
    const maxX = Math.min(PLANET_GRID_WIDTH - 1, cx + radius);
    const minY = clampGridY(cy - radius);
    const maxY = clampGridY(cy + radius);

    const [discoveries, ownedRows] = await Promise.all([
      db.select().from(tileDiscoveries).where(eq(tileDiscoveries.masterId, masterId)),
      db.select({ tileId: territories.tileId }).from(territories).where(eq(territories.masterId, masterId)),
    ]);
    const discovered = new Set(discoveries.map(row => row.tileId));
    const pinnedIds = Array.from(new Set([...discovered, ...ownedRows.map(r => r.tileId)]));

    const tiles = await db.select().from(worldTiles)
      .where(pinnedIds.length > 0
        ? or(
            and(between(worldTiles.x, minX, maxX), between(worldTiles.y, minY, maxY)),
            inArray(worldTiles.id, pinnedIds),
          )
        : and(between(worldTiles.x, minX, maxX), between(worldTiles.y, minY, maxY)))
      .orderBy(asc(worldTiles.y), asc(worldTiles.x));

    const tileIds = tiles.map(t => t.id);
    const territoryRows = tileIds.length > 0
      ? await db.select().from(territories).where(inArray(territories.tileId, tileIds))
      : [];
    const ownerIds = Array.from(new Set(territoryRows.map(r => r.masterId).filter((id): id is string => Boolean(id))));
    const owners = ownerIds.length > 0
      ? await db.select({ id: masters.id, name: masters.masterName }).from(masters).where(inArray(masters.id, ownerIds))
      : [];
    const nameById = new Map(owners.map(row => [row.id, row.name]));
    const territoryByTile = new Map(territoryRows.map(row => [row.tileId, row]));

    return {
      base: { x: status.baseX, y: status.baseY, continentId: status.continentId },
      worldGrid: { width: PLANET_GRID_WIDTH, height: PLANET_GRID_HEIGHT },
      chunkCenter: { x: cx, y: cy, radius },
      shieldUntil: status.shieldUntil,
      tiles: tiles.map(tile => {
        const territoryRow = territoryByTile.get(tile.id);
        const ownerName = territoryRow?.masterId ? nameById.get(territoryRow.masterId) ?? '—' : null;
        return {
          id: tile.id, x: tile.x, y: tile.y, terrain: tile.terrain, resourceType: tile.resourceType,
          continentId: tile.continentId, regionId: tile.regionId, zoneTier: tile.zoneTier,
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
    if (tile.terrain === 'OCEAN') throw new WorldError('ERR_OCEAN_UNCLAIMABLE', 409);

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
