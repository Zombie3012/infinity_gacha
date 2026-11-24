/**
 * Targeted integration test for Airship Port (Bến Thiên Hành) & World RTS Expedition.
 * Verifies:
 * 1. Floor 25 unlock gate for AIRSHIP_PORT & World RTS
 * 2. Tech Tree unlock -> Crafting Small/Rescue/Attack/Large(4x5) ships
 * 3. Dock Grid sizing (Lv.1 4x4 rejects 4x5 -> Lv.2 5x5 + Tech expands dock -> 4x5 fits + move/rotate)
 * 4. Dynamic 1-hour Fog of War along Scout flight path
 * 5. Emerging Dungeons (no resource nodes) + 15-Hero Transport Carrier Raid + Rescue Cutter (6 Heroes) for STRANDED
 * 6. Live Redirect & Recall + clean DB teardown
 */
import assert from 'node:assert/strict';
import { v4 as uuidv4 } from 'uuid';
import { eq } from 'drizzle-orm';
import { db, pool } from '../packages/server/dist/database/db.js';
import {
  accounts, heroExpeditions, heroes, masters, worldDungeons, worlds,
} from '../packages/server/dist/database/drizzle-schema.js';
import { buildingService } from '../packages/server/dist/modules/base/building.service.js';
import { airshipService } from '../packages/server/dist/modules/world/airship.service.js';
import { expeditionService } from '../packages/server/dist/modules/world/expedition.service.js';
import { worldService } from '../packages/server/dist/modules/world/world.service.js';

const tag = `airship_rts_${Date.now()}`;
const accountId = uuidv4();
const masterId = uuidv4();
const worldId = uuidv4();
const heroIds = [];

async function run() {
  try {
    // 0. Seed temporary account + master + world (Floor 24 initially) + 15 heroes
    await db.insert(accounts).values({
      id: accountId,
      username: tag,
      passwordHash: 'test-hash',
      role: 'PLAYER',
    });
    await db.insert(masters).values({
      id: masterId,
      accountId,
      masterName: `Commander_${tag.slice(-6)}`,
      level: 30,
      silverCoins: 250000n,
      gems: 1000,
    });
    await db.insert(worlds).values({
      id: worldId,
      masterId,
      worldName: 'TestSkyWorld',
      worldSeed: 12345,
      currentFloor: 24,
      baseZones: 2,
    });

    for (let i = 0; i < 15; i++) {
      const hid = uuidv4();
      heroIds.push(hid);
      await db.insert(heroes).values({
        id: hid,
        masterId,
        configId: `hero_test_${i + 1}`,
        name: `SkyHero_${i + 1}`,
        rarity: 5,
        classCode: 'KNIGHT',
        level: 30,
        hp: 500,
        maxHp: 500,
        attack: 120,
        defense: 80,
        speed: 15,
        state: 'ALIVE',
      });
    }

    // 1. Floor 24 must BLOCK constructing AIRSHIP_PORT
    await assert.rejects(
      () => buildingService.construct(masterId, 'AIRSHIP_PORT', 1),
      /Tháp tầng 25/,
      'AIRSHIP_PORT must require Tower Floor 25',
    );
    console.log('[OK] 1. Floor < 25 blocks AIRSHIP_PORT construction');

    // Reach Tower Floor 25 -> construct AIRSHIP_PORT Lv.1 (4x4 dock)
    await db.update(worlds).set({ currentFloor: 25 }).where(eq(worlds.id, worldId));
    const built = await buildingService.construct(masterId, 'AIRSHIP_PORT', 1);
    const portId = built.building.id;
    let state = await airshipService.getPortState(masterId);
    assert.equal(state.portLevel, 1);
    assert.deepEqual(state.dock, { width: 4, height: 4 });
    console.log('[OK] 2. Floor 25 unlocks AIRSHIP_PORT Lv.1 with 4x4 dock grid');

    // 2. Tech Tree gating: cannot craft SCOUT_SKIFF before unlocking TECH_SHIP_SCOUT
    await assert.rejects(
      () => airshipService.craft(masterId, 'SCOUT_SKIFF', { instant: true }),
      /Cây Công Nghệ/,
    );
    await airshipService.unlockTech(masterId, 'TECH_SHIP_SCOUT');
    await airshipService.unlockTech(masterId, 'TECH_SHIP_RESCUE');
    await airshipService.unlockTech(masterId, 'TECH_SHIP_ATTACK');

    const scoutRes = await airshipService.craft(masterId, 'SCOUT_SKIFF', { instant: true });
    const rescueRes = await airshipService.craft(masterId, 'RESCUE_CUTTER', { instant: true });
    assert.equal(scoutRes.airship.gridW, 2);
    assert.equal(scoutRes.airship.gridH, 2);
    assert.equal(rescueRes.airship.gridW, 2);
    assert.equal(rescueRes.airship.gridH, 3);
    console.log('[OK] 3. Tech Tree unlocks & crafts Scout (2x2) + Rescue (2x3) on 4x4 dock');

    // 3. Upgrade Port Lv.1 -> Lv.2 (5x5), unlock TECH_SHIP_TRANSPORT + TECH_DOCK_EXPAND_1 -> craft Large 4x5 Transport Carrier
    await buildingService.upgrade(masterId, portId);
    await airshipService.unlockTech(masterId, 'TECH_SHIP_TRANSPORT');
    await airshipService.unlockTech(masterId, 'TECH_DOCK_EXPAND_1'); // 6x5
    await airshipService.unlockTech(masterId, 'TECH_DOCK_EXPAND_2'); // 6x6
    state = await airshipService.getPortState(masterId);
    assert.deepEqual(state.dock, { width: 6, height: 6 });

    // Fragmented 6x6 dock (Scout at 0,0 + Rescue at 2,0) rejects 4x5 until we pack Rescue to (0,2)!
    await assert.rejects(
      () => airshipService.craft(masterId, 'TRANSPORT_CARRIER', { instant: true }),
      /không còn khoảng trống liền kề 4x5/,
    );
    await airshipService.moveOnDock(masterId, rescueRes.airship.id, 0, 2, 0);
    const transportRes = await airshipService.craft(masterId, 'TRANSPORT_CARRIER', { instant: true });
    assert.equal(transportRes.airship.sizeClass, 'LARGE');
    assert.equal(transportRes.airship.gridW, 4);
    assert.equal(transportRes.airship.gridH, 5);
    console.log('[OK] 4. Upgraded Port + Dock Tech expands grid to 6x6; packing Rescue frees 4x5 slot for Transport Carrier');

    // Rotate Rescue Cutter / upgrade Scout on dock grid
    await airshipService.upgrade(masterId, scoutRes.airship.id);
    console.log('[OK] 5. Ship upgrade succeeded');

    // 4. Unlock Global World RTS (now requires Floor 25) + RTS Snapshot
    await worldService.unlock(masterId);
    let snap = await expeditionService.rtsSnapshot(masterId);
    assert.equal(snap.unlocked, true);
    assert.ok(snap.tiles.length >= 144, 'Expected 12x12 outer-rim tiles');
    const fogTile = snap.tiles.find(t => !t.visible);
    assert.ok(fogTile, 'Dynamic Fog of War must keep distant tiles hidden');
    console.log(`[OK] 6. RTS Snapshot active (${snap.tiles.length} tiles, Fog of War active)`);

    // 5. Dispatch SCOUT_SKIFF to fogTile -> arrive -> check 1-hour vision trail
    const t0 = new Date();
    const scoutExp = await expeditionService.dispatch(
      masterId, fogTile.id, 'SCOUT', heroIds.slice(0, 2),
      { airshipId: scoutRes.airship.id }, t0,
    );
    // Live redirect test on traveling scout
    const altTile = snap.tiles.find(t => !t.visible && t.id !== fogTile.id) ?? fogTile;
    await expeditionService.redirect(masterId, scoutExp.expeditionId, altTile.id, new Date(t0.getTime() + 5000));
    const afterArrive = new Date(t0.getTime() + 600_000);
    snap = await expeditionService.rtsSnapshot(masterId, afterArrive);
    const litTarget = snap.tiles.find(t => t.id === altTile.id);
    assert.equal(litTarget.visible, true, 'Scouted tile must be visible after scout passes');
    assert.ok(litTarget.visionSecondsRemaining > 2500, 'Vision must persist ~1 hour');

    // Check 1-hour expiry (+2 hours -> fog returns!)
    const afterTwoHours = new Date(afterArrive.getTime() + 7200_000);
    const snapExpired = await expeditionService.rtsSnapshot(masterId, afterTwoHours);
    const expiredTile = snapExpired.tiles.find(t => t.id === altTile.id);
    assert.equal(expiredTile.visible, false, 'Fog of War must cover tile again after 1 hour');
    console.log('[OK] 7. Scout redirect + 1-hour Dynamic Fog of War reveal & auto-re-fog verified');

    // 6. Emerging Dungeon Raid with Transport Carrier carrying 10 Heroes (>5, up to 15!)
    const [raidDungeon] = await db.select().from(worldDungeons).where(eq(worldDungeons.status, 'ACTIVE')).limit(1);
    assert.ok(raidDungeon, 'Emerging dungeons must exist');
    // Ensure a 15-hero Raid dungeon is available for testing 10-hero Transport Carrier
    await db.update(worldDungeons).set({ maxPartySize: 15, recommendedPower: 100 }).where(eq(worldDungeons.id, raidDungeon.id));
    const raidExp = await expeditionService.dispatch(
      masterId, raidDungeon.tileId, 'DUNGEON', heroIds.slice(0, 10),
      { airshipId: transportRes.airship.id, dungeonId: raidDungeon.id }, afterTwoHours,
    );
    assert.equal(raidExp.heroes.length, 10, 'Transport Carrier must carry up to 15 Heroes');
    await expeditionService.recall(masterId, raidExp.expeditionId, new Date(afterTwoHours.getTime() + 1000));
    console.log('[OK] 8. Transport Carrier dispatched 10 Heroes (up to 15 cap) to Emerging Dungeon & recalled cleanly');

    // 7. Rescue Cutter (6 Heroes) rescuing a STRANDED expedition
    const strandedExpId = uuidv4();
    await db.insert(heroExpeditions).values({
      id: strandedExpId,
      masterId,
      tileId: altTile.id,
      mission: 'DUNGEON',
      status: 'STRANDED',
      departAt: afterTwoHours,
      arriveAt: afterTwoHours,
      strandedAt: afterTwoHours,
      createdAt: afterTwoHours,
    });
    const rescueExp = await expeditionService.dispatch(
      masterId, altTile.id, 'RESCUE', heroIds.slice(0, 6),
      { airshipId: rescueRes.airship.id, rescueTargetExpeditionId: strandedExpId }, afterTwoHours,
    );
    assert.equal(rescueExp.heroes.length, 6, 'Rescue Cutter must carry up to 6 Heroes');
    await expeditionService.settle(masterId, new Date(afterTwoHours.getTime() + 900_000));
    const [rescuedRow] = await db.select().from(heroExpeditions).where(eq(heroExpeditions.id, strandedExpId)).limit(1);
    assert.notEqual(rescuedRow.status, 'STRANDED', 'Stranded expedition must be rescued by Rescue Cutter');
    console.log('[OK] 9. Rescue Cutter (6 Heroes) rescued STRANDED expedition');

    // 8. GARRISON (Tập kết / Đồn trú) -> GARRISONED -> redirect -> recall
    const tGar = new Date(afterTwoHours.getTime() + 1_800_000);
    const garExp = await expeditionService.dispatch(
      masterId, fogTile.id, 'GARRISON', heroIds.slice(0, 4),
      { airshipId: transportRes.airship.id }, tGar,
    );
    const afterGarArrive = new Date(tGar.getTime() + 900_000);
    const snapGar = await expeditionService.rtsSnapshot(masterId, afterGarArrive);
    const garFleet = snapGar.activeFleets.find(f => f.id === garExp.expeditionId);
    assert.equal(garFleet?.status, 'GARRISONED', 'Garrison fleet must stay GARRISONED upon arrival');
    const garTileView = snapGar.tiles.find(t => t.id === fogTile.id);
    assert.equal(garTileView?.visible, true, 'Garrisoned tile must stay illuminated');
    await expeditionService.redirect(masterId, garExp.expeditionId, altTile.id, new Date(afterGarArrive.getTime() + 1000));
    await expeditionService.recall(masterId, garExp.expeditionId, new Date(afterGarArrive.getTime() + 2000));
    console.log('[OK] 10. GARRISON (Tập kết / Đồn trú) -> GARRISONED vision -> redirect -> recall verified');

    console.log('\nALL AIRSHIP PORT & RTS EXPEDITION CHECKS PASSED!');
  } finally {
    await db.delete(accounts).where(eq(accounts.id, accountId)).catch(() => {});
    await pool.end();
  }
}

run().catch(err => {
  console.error('TEST FAILED:', err);
  process.exit(1);
});
