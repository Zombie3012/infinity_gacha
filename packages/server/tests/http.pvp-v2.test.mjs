import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP PvP v2: Combat v2 engine resolution, turns log and territory capture', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const attacker = await createMaster(harness.request, 'pvpv2A');
  const defender = await createMaster(harness.request, 'pvpv2B');
  t.after(async () => {
    await cleanupAccount(attacker.accountId);
    await cleanupAccount(defender.accountId);
    await harness.close();
  });

  // Create v2 heroes with originStats for attacker and defender
  const attackerHero = await createHero(attacker.masterId, {
    templateIndex: 0,
    name: 'V2 Raider',
    attack: 500,
    defense: 300,
    speed: 150,
    hp: 4000,
  });
  // Update with originStats and class
  await sql(`update heroes set origin_stats = $1, rarity = 4, level = 25, class_code = 'WARRIOR' where id = $2`, [
    JSON.stringify({ str: 60, int: 20, sta: 50, agi: 40 }),
    attackerHero.id,
  ]);

  const defenderHero = await createHero(defender.masterId, {
    templateIndex: 0,
    name: 'V2 Guard',
    attack: 80,
    defense: 50,
    speed: 30,
    hp: 500,
  });
  await sql(`update heroes set origin_stats = $1, rarity = 2, level = 5, class_code = 'WARRIOR' where id = $2`, [
    JSON.stringify({ str: 15, int: 10, sta: 20, agi: 10 }),
    defenderHero.id,
  ]);

  await setSilver(attacker.masterId, 100_000);
  await sql('update masters set level = 20 where id = $1', [attacker.masterId]);
  await sql('update worlds set current_floor = 15 where master_id = $1', [attacker.masterId]);

  let contestedTileId = '';
  let defenderTerritoryId = '';
  let attackExpeditionId = '';

  await t.test('setup world, base and contested territory', async () => {
    const unlock = await harness.request('/api/world/global/unlock', { method: 'POST', token: attacker.token });
    assert.equal(unlock.status, 201);
    const base = unlock.body.base;
    await sql('update master_world_status set shield_until = now() - interval \'1 hour\' where master_id = $1', [attacker.masterId]);

    const near = await sql(`select t.id, t.x, t.y from world_tiles t
                            left join territories te on te.tile_id = t.id
                            where te.id is null
                            order by abs(t.x - $1) + abs(t.y - $2) asc limit 2`, [base.x, base.y]);
    contestedTileId = near.rows[1].id;

    await sql(`insert into master_world_status (master_id, unlocked_at, base_x, base_y, shield_until)
               values ($1, now() - interval '10 days', $2, $3, now() - interval '5 days')
               on conflict (master_id) do update set shield_until = now() - interval '5 days'`,
      [defender.masterId, base.x, base.y]);

    await sql(`insert into territories (id, tile_id, master_id, level, status, claimed_at, protected_until, updated_at)
               values (gen_random_uuid()::text, $1, $2, 2, 'OWNED', now() - interval '2 days', NULL, now())
               returning id`, [contestedTileId, defender.masterId]);
    const territory = await sql('select id from territories where tile_id = $1', [contestedTileId]);
    defenderTerritoryId = territory.rows[0].id;

    const discovery = await sql('select id from tile_discoveries where master_id = $1 and tile_id = $2', [attacker.masterId, contestedTileId]);
    if (discovery.rowCount === 0) {
      await sql(`insert into tile_discoveries (id, master_id, tile_id, discovered_at)
                 values (gen_random_uuid()::text, $1, $2, now())`, [attacker.masterId, contestedTileId]);
    }
  });

  await t.test('defense estimate reflects Combat Power v2 formula', async () => {
    const defense = await harness.request(`/api/world/tiles/${contestedTileId}/defense`, { token: attacker.token });
    assert.equal(defense.status, 200);
    assert.equal(defense.body.owned, true);
    assert.equal(defense.body.ownerMasterId, defender.masterId);
    assert.ok(defense.body.defensePower > 0, 'defensePower should be calculated with v2 stats');
  });

  await t.test('dispatch attack and verify Combat v2 battle log in report', async () => {
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST',
      token: attacker.token,
      body: { tileId: contestedTileId, mission: 'ATTACK', heroIds: [attackerHero.id] },
    });
    assert.equal(dispatched.status, 201);
    attackExpeditionId = dispatched.body.expeditionId;

    // Fast-forward arrival
    await sql(`update hero_expeditions set arrive_at = now() - interval '1 minute' where id = $1`, [attackExpeditionId]);

    const listed = await harness.request('/api/world/expeditions', { token: attacker.token });
    assert.equal(listed.status, 200);
    const row = listed.body.find(e => e.id === attackExpeditionId);
    assert.ok(row, 'expedition found in list');

    assert.equal(row.result.kind, 'PVP_REPORT');
    assert.equal(row.result.winner, 'ATTACKER');
    assert.ok(row.result.rounds >= 1);
    assert.ok(row.result.partyPower > 0, 'partyPower is populated');
    assert.ok(row.result.defenderPower > 0, 'defenderPower is populated');

    // Verify Combat v2 battleLog and battleSummary
    assert.ok(Array.isArray(row.result.battleLog), 'battleLog is an array');
    assert.ok(row.result.battleLog.length > 0, 'battleLog contains turn actions');
    assert.ok(row.result.battleSummary, 'battleSummary exists');
    assert.ok(row.result.battleSummary.totalDamage > 0, 'totalDamage > 0');

    // Territory transfer verified
    const owner = await sql('select master_id from territories where id = $1', [defenderTerritoryId]);
    assert.equal(owner.rows[0].master_id, attacker.masterId);
  });

  await t.test('pvp battles log stores full v2 report', async () => {
    const battles = await harness.request('/api/world/pvp/battles', { token: attacker.token });
    assert.equal(battles.status, 200);
    assert.ok(battles.body.length > 0);
    const battle = battles.body[0];
    assert.equal(battle.winner, 'ATTACKER');
    assert.equal(battle.defenderMasterId, defender.masterId);
    assert.ok(battle.report.battleLog.length > 0, 'battleLog stored in DB');
  });
});
