/**
 * Targeted integration test for Whole-Planet Seeding (600x300 = 180,000 tiles),
 * RTS Smart Random Spawn, Ocean unclaimable guard, and Viewport Chunk Streaming.
 */
import assert from 'node:assert/strict';
import { v4 as uuidv4 } from 'uuid';
import { and, eq, inArray, sql } from 'drizzle-orm';
import { db, pool } from '../packages/server/dist/database/db.js';
import {
  accounts, masterWorldStatus, masters, worldTiles, worlds,
} from '../packages/server/dist/database/drizzle-schema.js';
import { worldService } from '../packages/server/dist/modules/world/world.service.js';
import { expeditionService } from '../packages/server/dist/modules/world/expedition.service.js';
import { planetTileDistance } from '../packages/server/dist/modules/world/planet-grid-rules.js';

const tag = `planet_spawn_${Date.now()}`;
const createdAccountIds = [];
const createdMasterIds = [];

async function run() {
  try {
    // 1. Verify full 600x300 planet grid + OCEAN + Land in DB
    const [counts] = await db.execute(sql`
      SELECT
        count(*) FILTER (WHERE x BETWEEN 0 AND 599 AND y BETWEEN 0 AND 299)::int AS planet_total,
        count(*) FILTER (WHERE x BETWEEN 0 AND 599 AND y BETWEEN 0 AND 299 AND terrain = 'OCEAN')::int AS ocean_total,
        count(*) FILTER (WHERE x BETWEEN 0 AND 599 AND y BETWEEN 0 AND 299 AND terrain NOT IN ('OCEAN', 'WONDER'))::int AS land_total,
        count(*) FILTER (WHERE x BETWEEN 0 AND 599 AND y BETWEEN 0 AND 299 AND is_outer_rim = true AND terrain IN ('PLAINS','FOREST','HILLS'))::int AS spawnable_total
      FROM world_tiles
    `).then(r => r.rows);

    assert.equal(counts.planet_total, 180000, 'Expected 180,000 planet tiles (600x300)');
    assert.ok(counts.ocean_total > 100000, `Expected >100k ocean tiles, got ${counts.ocean_total}`);
    assert.ok(counts.land_total > 50000, `Expected >50k land tiles, got ${counts.land_total}`);
    assert.ok(counts.spawnable_total > 10000, `Expected >10k outer-rim spawnable tiles, got ${counts.spawnable_total}`);
    console.log(`[OK] 1. Planet DB verified: total=${counts.planet_total}, land=${counts.land_total}, ocean=${counts.ocean_total}, spawnable=${counts.spawnable_total}`);

    // 2. Spawn 6 new players via worldService.unlock() -> RTS Smart Random Spawn
    const spawns = [];
    for (let i = 0; i < 6; i++) {
      const accountId = uuidv4();
      const masterId = uuidv4();
      const worldId = uuidv4();
      createdAccountIds.push(accountId);
      createdMasterIds.push(masterId);

      await db.insert(accounts).values({
        id: accountId,
        username: `${tag}_p${i}`,
        passwordHash: 'test-hash',
        role: 'PLAYER',
      });
      await db.insert(masters).values({
        id: masterId,
        accountId,
        masterName: `RtsLord_${i}_${tag.slice(-4)}`,
        level: 20,
        silverCoins: 100000n,
        gems: 500,
      });
      await db.insert(worlds).values({
        id: worldId,
        masterId,
        worldName: `World_${i}`,
        worldSeed: 1000 + i,
        currentFloor: 25,
        baseZones: 2,
      });

      const unlocked = await worldService.unlock(masterId);
      assert.ok(unlocked.unlocked, 'Player should unlock Global World');
      assert.ok(unlocked.base, 'Player should receive a base coordinate');

      const [baseTile] = await db.select().from(worldTiles)
        .where(and(eq(worldTiles.x, unlocked.base.x), eq(worldTiles.y, unlocked.base.y))).limit(1);
      assert.ok(baseTile, `Spawn tile (${unlocked.base.x},${unlocked.base.y}) must exist`);
      assert.ok(['PLAINS', 'FOREST', 'HILLS'].includes(baseTile.terrain),
        `Spawn must be PLAINS/FOREST/HILLS, got ${baseTile.terrain}`);
      assert.notEqual(baseTile.terrain, 'OCEAN', 'Player must NEVER spawn on OCEAN');
      assert.notEqual(baseTile.terrain, 'WONDER', 'Player must NEVER spawn on WONDER');
      assert.equal(baseTile.isOuterRim, true, 'Player should spawn on Outer Rim');

      spawns.push({
        masterId,
        x: unlocked.base.x,
        y: unlocked.base.y,
        continentId: baseTile.continentId,
        terrain: baseTile.terrain,
      });
    }

    // Verify no duplicate coords & >= 10 tile spacing on same continent & multi-continent distribution
    const coordKeys = new Set(spawns.map(s => `${s.x},${s.y}`));
    assert.equal(coordKeys.size, spawns.length, 'Every player must have a unique base coordinate');
    const continents = new Set(spawns.map(s => s.continentId));
    assert.ok(continents.size >= 3, `Expected players spread across >= 3 continents, got ${Array.from(continents).join(', ')}`);

    for (let i = 0; i < spawns.length; i++) {
      for (let j = i + 1; j < spawns.length; j++) {
        if (spawns[i].continentId === spawns[j].continentId) {
          const dist = planetTileDistance(spawns[i], spawns[j]);
          assert.ok(dist >= 10, `Same-continent players must be >= 10 tiles apart, got ${dist}`);
        }
      }
    }
    console.log(`[OK] 2. 6 new players spawned cleanly across ${continents.size} continents: ${spawns.map(s => `${s.continentId}(${s.x},${s.y}:${s.terrain})`).join(', ')}`);

    // 3. Verify Viewport Chunk Streaming (fast, bounded, includes OCEAN + worldGrid + local dungeons)
    const p0 = spawns[0];
    const t0 = Date.now();
    const snap = await expeditionService.rtsSnapshot(p0.masterId, { cx: p0.x, cy: p0.y, radius: 12 });
    const elapsedMs = Date.now() - t0;
    assert.deepEqual(snap.worldGrid, { width: 600, height: 300 });
    assert.deepEqual(snap.chunkCenter, { x: p0.x, y: p0.y, radius: 12 });
    assert.ok(snap.tiles.length >= 600 && snap.tiles.length <= 750,
      `Expected ~25x25 chunk (~625 tiles), got ${snap.tiles.length}`);
    const chunkDungeons = snap.tiles.filter(t => t.dungeon);
    assert.ok(chunkDungeons.length >= 1, `Expected >= 1 visible starter dungeon near new spawn, got ${chunkDungeons.length}`);
    assert.ok(Array.isArray(snap.nearbyPlayers), 'Snapshot must include nearbyPlayers array');
    console.log(`[OK] 3. Viewport chunk around (${p0.x},${p0.y}) returned ${snap.tiles.length} tiles & ${chunkDungeons.length} visible starter dungeon(s) in ${elapsedMs}ms`);

    // 4. Pan to Great Ocean (cx=100, cy=250) -> verify OCEAN tiles streamed cleanly
    const oceanSnap = await expeditionService.rtsSnapshot(p0.masterId, { cx: 100, cy: 250, radius: 6 });
    const oceanTiles = oceanSnap.tiles.filter(t => t.terrain === 'OCEAN');
    assert.ok(oceanTiles.length > 50, `Expected OCEAN tiles in Great Ocean chunk, got ${oceanTiles.length}`);
    console.log(`[OK] 4. Great Ocean chunk returned ${oceanTiles.length} OCEAN tiles`);

    // 5. Verify OCEAN tile is UNCLAIMABLE (ERR_OCEAN_UNCLAIMABLE)
    const sampleOcean = oceanTiles[0];
    await assert.rejects(
      () => worldService.claim(p0.masterId, sampleOcean.id),
      /ERR_OCEAN_UNCLAIMABLE/,
      'Claiming an OCEAN tile must fail with ERR_OCEAN_UNCLAIMABLE',
    );
    console.log(`[OK] 5. Claiming OCEAN tile ${sampleOcean.id} properly rejected with ERR_OCEAN_UNCLAIMABLE`);

    // 6. Pan near Player 1 -> verify Player 1 shows up in Player 0's nearbyPlayers!
    const p1 = spawns[1];
    const p1Snap = await expeditionService.rtsSnapshot(p0.masterId, { cx: p1.x, cy: p1.y, radius: 10 });
    const foundP1 = p1Snap.nearbyPlayers.find(np => np.masterId === p1.masterId);
    assert.ok(foundP1, 'Other player base inside streamed viewport chunk must appear in nearbyPlayers');
    assert.equal(foundP1.x, p1.x);
    assert.equal(foundP1.y, p1.y);
    console.log(`[OK] 6. Viewport pan to (${p1.x},${p1.y}) detected nearbyPlayer ${foundP1.masterName} (visible=${foundP1.visible})`);

    console.log('PLANET_SPAWN_AND_CHUNKS_TEST_PASS');
  } finally {
    if (createdMasterIds.length > 0) {
      await db.delete(masterWorldStatus).where(inArray(masterWorldStatus.masterId, createdMasterIds)).catch(() => {});
    }
    if (createdAccountIds.length > 0) {
      await db.delete(accounts).where(inArray(accounts.id, createdAccountIds)).catch(() => {});
    }
    await pool.end();
  }
}

run().catch(err => {
  console.error('PLANET_SPAWN_AND_CHUNKS_TEST_FAIL:', err);
  process.exit(1);
});
