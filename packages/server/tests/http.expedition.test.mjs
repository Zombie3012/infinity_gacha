import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP hero expeditions: scouting, attacks and recall', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'exp');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const scoutHero = await createHero(master.masterId, { templateIndex: 0, name: 'Scout Hero', attack: 300, defense: 200, speed: 90, hp: 4000 });
  const warrior = await createHero(master.masterId, { templateIndex: 1, name: 'Warrior Hero', attack: 6000, defense: 4000, speed: 300, hp: 80_000 });
  await setSilver(master.masterId, 100_000);
  await sql('update masters set level = 15 where id = $1', [master.masterId]);
  await sql('update worlds set current_floor = 10 where master_id = $1', [master.masterId]);

  let base = { x: 0, y: 0 };
  let targetTileId = '';
  let attackTileId = '';

  await t.test('world unlock and a known tile to explore', async () => {
    const unlock = await harness.request('/api/world/global/unlock', { method: 'POST', token: master.token });
    assert.equal(unlock.status, 201);
    base = unlock.body.base;
    await sql('update master_world_status set shield_until = now() - interval \'1 hour\' where master_id = $1', [master.masterId]);

    const map = await harness.request('/api/world/global/map', { token: master.token });
    const known = map.body.tiles.filter(tile => tile.discovered && !tile.owner);
    assert.ok(known.length >= 2);
    targetTileId = known[0].id;
    attackTileId = known[1].id;
  });

  let scoutExpedition = '';

  await t.test('a scout party travels and then reports', async () => {
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST', token: master.token,
      body: { tileId: targetTileId, mission: 'SCOUT', heroIds: [scoutHero.id] },
    });
    assert.equal(dispatched.status, 201);
    assert.equal(dispatched.body.mission, 'SCOUT');
    assert.ok(dispatched.body.travelSeconds >= 30);
    scoutExpedition = dispatched.body.expeditionId;

    const busy = await harness.request('/api/world/expeditions', {
      method: 'POST', token: master.token,
      body: { tileId: attackTileId, mission: 'SCOUT', heroIds: [scoutHero.id] },
    });
    assert.equal(busy.status, 409);
    assert.equal(busy.body.error, 'ERR_EXPEDITION_HERO_BUSY');

    await sql(`update hero_expeditions set arrive_at = now() - interval '1 minute' where id = $1`, [scoutExpedition]);
    const listed = await harness.request('/api/world/expeditions', { token: master.token });
    const row = listed.body.find(entry => entry.id === scoutExpedition);
    assert.equal(row.phase, 'RETURNING');
    assert.equal(row.result.kind, 'SCOUT_REPORT');
    assert.ok(row.result.guardianPower >= 0);

    await sql(`update hero_expeditions set return_at = now() - interval '1 minute' where id = $1`, [scoutExpedition]);
    const settled = await harness.request('/api/world/expeditions', { token: master.token });
    assert.equal(settled.body.find(entry => entry.id === scoutExpedition).status, 'COMPLETED');
  });

  await t.test('attacking the guardian clears the tile for claiming', async () => {
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST', token: master.token,
      body: { tileId: attackTileId, mission: 'ATTACK', heroIds: [warrior.id] },
    });
    assert.equal(dispatched.status, 201);

    await sql(`update hero_expeditions set arrive_at = now() - interval '1 minute' where id = $1`, [dispatched.body.expeditionId]);
    const listed = await harness.request('/api/world/expeditions', { token: master.token });
    const row = listed.body.find(entry => entry.id === dispatched.body.expeditionId);
    assert.equal(row.result.kind, 'BATTLE_REPORT');
    assert.equal(row.result.won, true);

    const claimed = await harness.request(`/api/world/global/tiles/${attackTileId}/claim`, { method: 'POST', token: master.token });
    assert.equal(claimed.status, 201);
    assert.equal(claimed.body.territory.status, 'OWNED');
  });

  await t.test('an uncleared tile cannot be claimed', async () => {
    const map = await harness.request('/api/world/global/map', { token: master.token });
    const uncleared = map.body.tiles.find(tile => tile.discovered && !tile.owner && tile.id !== attackTileId && tile.id !== targetTileId);
    assert.ok(uncleared, 'expected another discovered tile');
    const blocked = await harness.request(`/api/world/global/tiles/${uncleared.id}/claim`, { method: 'POST', token: master.token });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_TERRITORY_NOT_CLEARED');
  });

  await t.test('a dispatched party can be recalled', async () => {
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST', token: master.token,
      body: { tileId: targetTileId, mission: 'SCOUT', heroIds: [scoutHero.id] },
    });
    assert.equal(dispatched.status, 201);
    const recalled = await harness.request(`/api/world/expeditions/${dispatched.body.expeditionId}/recall`, {
      method: 'POST', token: master.token,
    });
    assert.equal(recalled.status, 200);
    assert.equal(recalled.body.expedition.status, 'RECALLED');
  });
});
