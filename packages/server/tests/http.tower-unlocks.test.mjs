import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccount, createMaster, pool, sql, startHarness } from './helpers/harness.mjs';

test('tower milestones govern buildings and legacy activities', async t => {
  const harness = await startHarness();
  let master;
  t.after(async () => {
    if (master) await cleanupAccount(master.accountId);
    await harness.close();
    await pool.end();
  });
  master = await createMaster(harness.request, 'towergate');
  const request = (path, options = {}) => harness.request(path, { token: master.token, ...options });
  const initial = await request('/api/base/overview');
  assert.equal(initial.status, 200);
  assert.equal(initial.body.world.currentFloor, 1);
  assert.equal(initial.body.world.unlockedLobbyFloors, 2);
  assert.equal(initial.body.world.plots, 16);
  assert.equal(initial.body.expansion.canExpand, false);

  const type = (overview, code) => overview.body.buildingTypes.find(row => row.code === code);
  for (const code of ['HOUSE', 'PARTY_MANSION', 'HERO_CHRONICLE', 'WAREHOUSE', 'TRAINING_CENTER', 'FORGE', 'KITCHEN', 'MEDICAL']) {
    assert.equal(type(initial, code)?.unlocked, true, code);
  }
  for (const code of ['SHOP_AIRSHIP', 'HALL_OF_MAGIC', 'ALLIANCE_HALL', 'AIRSHIP_PORT']) {
    assert.equal(type(initial, code)?.unlocked, false, code);
  }
  const me = await request('/api/me');
  assert.equal(Object.hasOwn(me.body.master, 'exp'), false);
  assert.equal(Object.hasOwn(me.body.master, 'level'), false);
  const beforeGift = await sql('select exp, level from masters where id=$1', [master.masterId]);
  const gift = await request('/api/giftcodes/redeem', { method: 'POST', body: { code: 'VIP999' } });
  assert.equal(gift.status, 200);
  assert.equal(Object.hasOwn(gift.body.rewards, 'exp'), false);
  assert.deepEqual((await sql('select exp, level from masters where id=$1', [master.masterId])).rows, beforeGift.rows);
  assert.equal((await request('/api/dungeon/floor/1/enter', { method: 'POST', body: {} })).status, 403);
  assert.equal((await request('/api/shop')).status, 403);
  assert.equal((await request('/api/alliance')).status, 403);
  assert.equal((await request('/api/world/global/map')).status, 403);
  assert.equal((await request('/api/world/expeditions')).status, 403);
  const lockedBuild = await request('/api/base/buildings', { method: 'POST', body: { buildingType: 'HALL_OF_MAGIC', plotIndex: 1 } });
  assert.equal(lockedBuild.status, 409);
  const home = await request('/api/base/buildings', { method: 'POST', body: { buildingType: 'HOUSE', plotIndex: 1 } });
  const villa = await request('/api/base/buildings', { method: 'POST', body: { buildingType: 'PARTY_MANSION', plotIndex: 2 } });
  assert.equal(home.status, 201);
  assert.equal(villa.status, 201);

  for (const [currentFloor, shop, hall, training, alliance] of [
    [5, false, false, 1, false], [6, true, false, 1, false],
    [10, true, false, 1, false], [11, true, true, 2, false],
    [20, true, true, 2, false], [21, true, true, 3, false],
    [25, true, true, 3, false], [26, true, true, 3, true],
  ]) {
    await sql('update worlds set current_floor=$2 where master_id=$1', [master.masterId, currentFloor]);
    const overview = await request('/api/base/overview');
    assert.equal(type(overview, 'SHOP_AIRSHIP').unlocked, shop, `shop ${currentFloor}`);
    assert.equal(type(overview, 'HALL_OF_MAGIC').unlocked, hall, `hall ${currentFloor}`);
    assert.equal(type(overview, 'TRAINING_CENTER').maxAllowedCount, training, `training ${currentFloor}`);
    assert.equal(type(overview, 'ALLIANCE_HALL').unlocked, alliance, `alliance hall ${currentFloor}`);
    assert.equal(type(overview, 'AIRSHIP_PORT').unlocked, alliance, `port ${currentFloor}`);
    const snapshot = await request('/api/world/rts/snapshot');
    assert.equal(snapshot.body.clearedFloor, currentFloor - 1);
    const guild = await request('/api/alliance');
    assert.equal(guild.status, alliance ? 200 : 403, `alliance ${currentFloor}`);
    if (currentFloor === 25 || currentFloor === 26) {
      const unlocked = await request('/api/world/global/unlock', { method: 'POST', body: {} });
      assert.equal(unlocked.status, currentFloor === 25 ? 409 : 201);
    }
    if (currentFloor >= 6) {
      assert.equal((await request('/api/dungeon/floor/1/enter', { method: 'POST', body: {} })).status, 503);
      assert.equal((await request('/api/shop')).status, 200);
    }
  }
  const builtHall = await request('/api/base/buildings', { method: 'POST', body: { buildingType: 'HALL_OF_MAGIC', plotIndex: 3 } });
  assert.equal(builtHall.status, 201);
  await sql('update worlds set current_floor=1 where master_id=$1', [master.masterId]);
  const blockedHall = await request(`/api/base/buildings/${builtHall.body.building.id}/upgrade`, { method: 'POST', body: {} });
  assert.equal(blockedHall.status, 403);
  assert.equal((await request('/api/alchemy')).status, 403);
  await sql('update worlds set current_floor=26 where master_id=$1', [master.masterId]);
  assert.equal((await request('/api/base/buildings/missing/promote-mansion', { method: 'POST', body: {} })).status, 404);
  const replay = await request('/api/pve/enter', { method: 'POST', body: { floor: 1 }, headers: { 'Idempotency-Key': 'replay-old-floor' } });
  assert.equal(replay.status, 201);
  assert.equal(replay.body.floor, 1);
  assert.equal((await sql('select current_floor from worlds where master_id=$1', [master.masterId])).rows[0].current_floor, 26);
});
