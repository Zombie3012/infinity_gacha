import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP global world: unlock, exploration and territories', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'world');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await createHero(master.masterId, { attack: 4000, defense: 3000, speed: 500, hp: 50_000 });
  await setSilver(master.masterId, 200_000);

  let base = { x: 0, y: 0 };
  let firstTileId = '';
  let territoryId = '';

  await t.test('an under-levelled Master is refused', async () => {
    const status = await harness.request('/api/world/global', { token: master.token });
    assert.equal(status.status, 200);
    assert.equal(status.body.unlocked, false);
    assert.equal(status.body.eligible.ok, false);

    const unlock = await harness.request('/api/world/global/unlock', { method: 'POST', token: master.token });
    assert.equal(unlock.status, 409);
    assert.equal(unlock.body.error, 'ERR_WORLD_LEVEL_REQUIRED');
  });

  await t.test('eligible Masters unlock with a base, shield and discovered tiles', async () => {
    await sql('update masters set level = 15 where id = $1', [master.masterId]);
    await sql('update worlds set current_floor = 10 where master_id = $1', [master.masterId]);

    const unlock = await harness.request('/api/world/global/unlock', { method: 'POST', token: master.token });
    assert.equal(unlock.status, 201);
    assert.equal(unlock.body.unlocked, true);
    assert.equal(unlock.body.shieldActive, true);
    assert.ok(unlock.body.progress.discovered >= 1);
    base = unlock.body.base;
  });

  await t.test('the map shows discovered and undiscovered tiles', async () => {
    const map = await harness.request('/api/world/global/map', { token: master.token });
    assert.equal(map.status, 200);
    assert.ok(map.body.tiles.length >= 30);
    const discovered = map.body.tiles.filter(tile => tile.discovered);
    assert.ok(discovered.length >= 1);
    assert.ok(map.body.tiles.some(tile => !tile.discovered));
  });

  await t.test('a tile far outside the radius cannot be discovered', async () => {
    const tiles = await sql('select id, x, y from world_tiles order by abs(x - $1) + abs(y - $2) desc limit 1', [base.x, base.y]);
    const far = tiles.rows[0];
    const attempt = await harness.request(`/api/world/global/tiles/${far.id}/discover`, { method: 'POST', token: master.token });
    assert.equal(attempt.status, 409);
    assert.equal(attempt.body.error, 'ERR_WORLD_TILE_OUT_OF_RANGE');
  });

  await t.test('claiming is blocked by the novice shield', async () => {
    const near = await sql('select id from world_tiles order by abs(x - $1) + abs(y - $2) asc limit 1', [base.x, base.y]);
    firstTileId = near.rows[0].id;
    const blocked = await harness.request(`/api/world/global/tiles/${firstTileId}/claim`, { method: 'POST', token: master.token });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_WORLD_SHIELD_ACTIVE');
  });

  await t.test('a discovered, unowned tile can be claimed', async () => {
    await sql('update master_world_status set shield_until = now() - interval \'1 hour\' where master_id = $1', [master.masterId]);
    await harness.request(`/api/world/global/tiles/${firstTileId}/discover`, { method: 'POST', token: master.token });
    // Hero attacks are covered by the expedition suite; simulate the resulting clearance here.
    await sql(`insert into tile_clearances (id, master_id, tile_id, cleared_at)
               values (gen_random_uuid()::text, $1, $2, now())
               on conflict (master_id, tile_id) do update set cleared_at = now()`, [master.masterId, firstTileId]);

    const claimed = await harness.request(`/api/world/global/tiles/${firstTileId}/claim`, { method: 'POST', token: master.token });
    assert.equal(claimed.status, 201);
    assert.equal(claimed.body.territory.status, 'OWNED');
    assert.ok(claimed.body.protectedUntil);
    territoryId = claimed.body.territory.id;

    const duplicate = await harness.request(`/api/world/global/tiles/${firstTileId}/claim`, { method: 'POST', token: master.token });
    assert.equal(duplicate.status, 409);
  });

  await t.test('territories upgrade and report hourly yield', async () => {
    const upgraded = await harness.request(`/api/world/territories/${territoryId}/upgrade`, { method: 'POST', token: master.token });
    assert.equal(upgraded.status, 200);
    assert.equal(upgraded.body.territory.level, 2);
    assert.equal(upgraded.body.silverSpent, 1500);

    const list = await harness.request('/api/world/territories', { token: master.token });
    assert.equal(list.status, 200);
    assert.equal(list.body.owned, 1);
    assert.ok(list.body.hourlyYield > 0);
  });

  await t.test('abandoning releases the tile after the countdown', async () => {
    const abandoned = await harness.request(`/api/world/territories/${territoryId}/abandon`, { method: 'POST', token: master.token });
    assert.equal(abandoned.status, 200);
    assert.equal(abandoned.body.territory.status, 'ABANDONING');

    await sql(`update territories set release_at = now() - interval '1 minute' where id = $1`, [territoryId]);
    const list = await harness.request('/api/world/territories', { token: master.token });
    assert.equal(list.body.owned, 0);

    const history = await harness.request('/api/world/territories/history', { token: master.token });
    assert.ok(history.body.some(row => row.action === 'RELEASED'));
  });

  await t.test('the 10-territory cap is enforced', async () => {
    const tiles = await sql(`select t.id from world_tiles t
                             left join territories te on te.tile_id = t.id
                             where te.id is null order by t.x, t.y limit 11`);
    const rows = tiles.rows;
    for (const tile of rows.slice(0, 10)) {
      await sql(`insert into territories (id, tile_id, master_id, level, status, claimed_at, updated_at)
                 values (gen_random_uuid()::text, $1, $2, 1, 'OWNED', now(), now())`, [tile.id, master.masterId]);
    }
    // Reuse the already-discovered tile so the limit is what blocks the claim.
    const blocked = await harness.request(`/api/world/global/tiles/${firstTileId}/claim`, { method: 'POST', token: master.token });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_TERRITORY_LIMIT_REACHED');
  });
});
