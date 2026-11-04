import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP PvP: hero attacks, protection and territory transfer', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const attacker = await createMaster(harness.request, 'pvpA');
  const defender = await createMaster(harness.request, 'pvpb');
  t.after(async () => {
    await cleanupAccount(attacker.accountId);
    await cleanupAccount(defender.accountId);
    await harness.close();
  });

  const attackerHero = await createHero(attacker.masterId, { templateIndex: 0, name: 'Raider', attack: 8000, defense: 6000, speed: 400, hp: 90_000 });
  await createHero(defender.masterId, { templateIndex: 0, name: 'Sentry', attack: 20, defense: 10, speed: 10, hp: 100 });

  await setSilver(attacker.masterId, 100_000);
  await sql('update masters set level = 15 where id = $1', [attacker.masterId]);
  await sql('update worlds set current_floor = 10 where master_id = $1', [attacker.masterId]);

  let contestedTileId = '';
  let defenderTerritoryId = '';
  let attackExpedition = '';

  await t.test('prepare a defended tile owned by the second Master', async () => {
    const unlock = await harness.request('/api/world/global/unlock', { method: 'POST', token: attacker.token });
    assert.equal(unlock.status, 201);
    const base = unlock.body.base;
    await sql('update master_world_status set shield_until = now() - interval \'1 hour\' where master_id = $1', [attacker.masterId]);

    const near = await sql(`select t.id, t.x, t.y from world_tiles t
                            left join territories te on te.tile_id = t.id
                            where te.id is null
                            order by abs(t.x - $1) + abs(t.y - $2) asc limit 2`, [base.x, base.y]);
    contestedTileId = near.rows[1].id;

    // Give the defender a world presence and an owned, unprotected territory.
    await sql(`insert into master_world_status (master_id, unlocked_at, base_x, base_y, shield_until)
               values ($1, now() - interval '10 days', $2, $3, now() - interval '5 days')
               on conflict (master_id) do update set shield_until = now() - interval '5 days'`,
      [defender.masterId, base.x, base.y]);
    await sql(`insert into territories (id, tile_id, master_id, level, status, claimed_at, protected_until, updated_at)
               values (gen_random_uuid()::text, $1, $2, 2, 'OWNED', now() - interval '2 days', NULL, now())
               returning id`, [contestedTileId, defender.masterId]);
    const territory = await sql('select id from territories where tile_id = $1', [contestedTileId]);
    defenderTerritoryId = territory.rows[0].id;

    // The attacker already discovered the tile earlier (radius 5 covers it).
    const discovery = await sql('select id from tile_discoveries where master_id = $1 and tile_id = $2', [attacker.masterId, contestedTileId]);
    if (discovery.rowCount === 0) {
      await sql(`insert into tile_discoveries (id, master_id, tile_id, discovered_at)
                 values (gen_random_uuid()::text, $1, $2, now())`, [attacker.masterId, contestedTileId]);
    }
  });

  await t.test('defense estimate exposes the garrison power', async () => {
    const defense = await harness.request(`/api/world/tiles/${contestedTileId}/defense`, { token: attacker.token });
    assert.equal(defense.status, 200);
    assert.equal(defense.body.owned, true);
    assert.ok(defense.body.defensePower > 0);
    assert.equal(defense.body.protected, false);
  });

  await t.test('a protected territory cannot be attacked', async () => {
    await sql('update territories set protected_until = now() + interval \'30 minutes\' where id = $1', [defenderTerritoryId]);
    const blocked = await harness.request('/api/world/expeditions', {
      method: 'POST', token: attacker.token,
      body: { tileId: contestedTileId, mission: 'ATTACK', heroIds: [attackerHero.id] },
    });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_TERRITORY_PROTECTED');

    await sql('update territories set protected_until = null where id = $1', [defenderTerritoryId]);
  });

  await t.test('the hero raid resolves as PvP and transfers the territory', async () => {
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST', token: attacker.token,
      body: { tileId: contestedTileId, mission: 'ATTACK', heroIds: [attackerHero.id] },
    });
    assert.equal(dispatched.status, 201);
    attackExpedition = dispatched.body.expeditionId;

    await sql(`update hero_expeditions set arrive_at = now() - interval '1 minute' where id = $1`, [attackExpedition]);
    const listed = await harness.request('/api/world/expeditions', { token: attacker.token });
    const row = listed.body.find(entry => entry.id === attackExpedition);
    assert.equal(row.result.kind, 'PVP_REPORT');
    assert.equal(row.result.winner, 'ATTACKER');
    assert.ok(row.result.rounds >= 3);

    const owner = await sql('select master_id from territories where id = $1', [defenderTerritoryId]);
    assert.equal(owner.rows[0].master_id, attacker.masterId);

    const battles = await harness.request('/api/world/pvp/battles', { token: attacker.token });
    assert.equal(battles.status, 200);
    assert.equal(battles.body[0].winner, 'ATTACKER');
    assert.equal(battles.body[0].defenderMasterId, defender.masterId);
  });

  await t.test('the defender sees the loss in their own battle log', async () => {
    const battles = await harness.request('/api/world/pvp/battles', { token: defender.token });
    assert.equal(battles.status, 200);
    assert.equal(battles.body[0].winner, 'ATTACKER');
    assert.equal(battles.body[0].attackerMasterId, attacker.masterId);
  });
});
