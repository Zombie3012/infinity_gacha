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

  let lumberMillId = '';
  let nodeId = '';

  await t.test('a new base exposes three plots and the catalogue', async () => {
    const overview = await harness.request('/api/base/overview', { token: master.token });
    assert.equal(overview.status, 200);
    assert.equal(overview.body.world.baseZones, 1);
    assert.equal(overview.body.world.plots, 3);
    assert.ok(overview.body.buildingTypes.some(type => type.code === 'LUMBER' && type.unlocked));
  });

  await t.test('construction reserves the plot and starts a timer', async () => {
    const built = await harness.request('/api/base/buildings', {
      method: 'POST', token: master.token, body: { buildingType: 'LUMBER', plotIndex: 1 },
    });
    assert.equal(built.status, 201);
    assert.equal(built.body.building.status, 'CONSTRUCTING');
    lumberMillId = built.body.building.id;

    const duplicate = await harness.request('/api/base/buildings', {
      method: 'POST', token: master.token, body: { buildingType: 'FARM', plotIndex: 1 },
    });
    assert.equal(duplicate.status, 409);
  });

  await t.test('the timer settles into a READY building with a production node', async () => {
    await finishBuildings(master.masterId);
    const overview = await harness.request('/api/base/overview', { token: master.token });
    const building = overview.body.buildings.find(row => row.id === lumberMillId);
    assert.equal(building.status, 'READY');
    assert.equal(building.resourceType, 'WOOD');
    assert.equal(building.ratePerHour, 80);

    const nodes = await sql('select id from base_production_nodes where building_id = $1', [lumberMillId]);
    assert.equal(nodes.rowCount, 1);
    nodeId = nodes.rows[0].id;
  });

  await t.test('offline accrual is harvestable into the inventory', async () => {
    await sql(`update base_production_nodes set last_harvest_at = now() - interval '2 hours' where id = $1`, [nodeId]);
    const collected = await harness.request(`/api/base/buildings/${lumberMillId}/collect`, { method: 'POST', token: master.token });
    assert.equal(collected.status, 200);
    assert.equal(collected.body.resourceType, 'WOOD');
    assert.ok(collected.body.collected >= 150, `expected ~160 wood, got ${collected.body.collected}`);

    const inventory = await harness.request('/api/inventory', { token: master.token });
    assert.equal(inventory.status, 200);
  });

  await t.test('zone 2 expands but zone 3 is gated by world level', async () => {
    const expanded = await harness.request('/api/base/expand', { method: 'POST', token: master.token });
    assert.equal(expanded.status, 200);
    assert.equal(expanded.body.zones, 2);
    assert.equal(expanded.body.plots, 6);

    const blocked = await harness.request('/api/base/expand', { method: 'POST', token: master.token });
    assert.equal(blocked.status, 409);
    assert.match(blocked.body.error, /World Level 2/);
  });

  await t.test('demolition refunds Silver and frees the plot', async () => {
    const demolished = await harness.request(`/api/base/buildings/${lumberMillId}/demolish`, { method: 'POST', token: master.token });
    assert.equal(demolished.status, 200);
    assert.ok(demolished.body.refundSilver > 0);

    const overview = await harness.request('/api/base/overview', { token: master.token });
    assert.equal(overview.body.buildings.length, 0);
  });
});
