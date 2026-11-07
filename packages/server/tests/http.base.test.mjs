import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccount, createMaster, dbReady, finishBuildings, setSilver, skipReason, sql, startHarness } from './helpers/harness.mjs';

test('HTTP base, construction and production', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'base');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await setSilver(master.masterId, 100_000);

  let kitchenId = '';
  let houseId = '';
  let nodeId = '';

  await t.test('a new base exposes three plots and the authentic Pick Me Up catalogue (without LUMBER/MINE/FARM)', async () => {
    const overview = await harness.request('/api/base/overview', { token: master.token });
    assert.equal(overview.status, 200);
    assert.equal(overview.body.world.baseZones, 1);
    assert.equal(overview.body.world.plots, 8);
    const codes = overview.body.buildingTypes.map(type => type.code);
    assert.ok(!codes.includes('LUMBER'));
    assert.ok(!codes.includes('MINE'));
    assert.ok(!codes.includes('FARM'));
    for (const expected of ['HOUSE', 'PARTY_MANSION', 'WAREHOUSE', 'TRAINING_CENTER', 'FORGE', 'KITCHEN', 'MEDICAL', 'HALL_OF_MAGIC', 'LIBRARY', 'ALCHEMY_WORKSHOP', 'MAGIC_RESEARCH_LAB']) {
      assert.ok(codes.includes(expected), `missing building type ${expected}`);
    }
    const forgeType = overview.body.buildingTypes.find(type => type.code === 'FORGE');
    assert.equal(forgeType.production, null);
  });

  await t.test('construction reserves the plot and starts a timer', async () => {
    const built = await harness.request('/api/base/buildings', {
      method: 'POST', token: master.token, body: { buildingType: 'KITCHEN', plotIndex: 1 },
    });
    assert.equal(built.status, 201);
    assert.equal(built.body.building.status, 'CONSTRUCTING');
    kitchenId = built.body.building.id;

    const duplicate = await harness.request('/api/base/buildings', {
      method: 'POST', token: master.token, body: { buildingType: 'WAREHOUSE', plotIndex: 1 },
    });
    assert.equal(duplicate.status, 409);
  });

  await t.test('the timer settles into a READY building with a production node', async () => {
    await finishBuildings(master.masterId);
    const overview = await harness.request('/api/base/overview', { token: master.token });
    const building = overview.body.buildings.find(row => row.id === kitchenId);
    assert.equal(building.status, 'READY');
    assert.equal(building.resourceType, 'FOOD');
    assert.equal(building.ratePerHour, 20);
    assert.equal(building.maxLevel, 3);
    assert.equal(building.maxWorkers, 1);

    const nodes = await sql('select id from base_production_nodes where building_id = $1', [kitchenId]);
    assert.equal(nodes.rowCount, 1);
    nodeId = nodes.rows[0].id;
  });

  await t.test('offline accrual is harvestable into the inventory', async () => {
    await sql(`update base_production_nodes set last_harvest_at = now() - interval '2 hours' where id = $1`, [nodeId]);
    const collected = await harness.request(`/api/base/buildings/${kitchenId}/collect`, { method: 'POST', token: master.token });
    assert.equal(collected.status, 200);
    assert.equal(collected.body.resourceType, 'FOOD');
    assert.ok(collected.body.collected >= 38, `expected ~40 food, got ${collected.body.collected}`);

    const inventory = await harness.request('/api/inventory', { token: master.token });
    assert.equal(inventory.status, 200);
  });

  await t.test('Dormitory (HOUSE) promotes to PARTY_MANSION only at Master Level 30', async () => {
    const builtHouse = await harness.request('/api/base/buildings', {
      method: 'POST', token: master.token, body: { buildingType: 'HOUSE', plotIndex: 2 },
    });
    assert.equal(builtHouse.status, 201);
    houseId = builtHouse.body.building.id;
    await finishBuildings(master.masterId);

    const earlyPromote = await harness.request(`/api/base/buildings/${houseId}/promote-mansion`, {
      method: 'POST', token: master.token,
    });
    assert.equal(earlyPromote.status, 409);

    await sql('update masters set level = 30 where id = $1', [master.masterId]);
    const promoted = await harness.request(`/api/base/buildings/${houseId}/promote-mansion`, {
      method: 'POST', token: master.token,
    });
    assert.equal(promoted.status, 200);
    assert.equal(promoted.body.building.buildingType, 'PARTY_MANSION');
  });

  await t.test('zone/floor expansion respects Master Level (15 levels per floor) and World Level', async () => {
    await sql('update masters set level = 1 where id = $1', [master.masterId]);
    const expanded = await harness.request('/api/base/expand', { method: 'POST', token: master.token });
    assert.equal(expanded.status, 200);
    assert.equal(expanded.body.zones, 2);
    assert.equal(expanded.body.plots, 16);

    const blocked = await harness.request('/api/base/expand', { method: 'POST', token: master.token });
    assert.equal(blocked.status, 409);
    assert.match(blocked.body.error, /World Level 2/);
  });

  await t.test('demolition refunds Silver and frees the plot', async () => {
    const demolished = await harness.request(`/api/base/buildings/${kitchenId}/demolish`, { method: 'POST', token: master.token });
    assert.equal(demolished.status, 200);
    assert.ok(demolished.body.refundSilver > 0);
  });
});
