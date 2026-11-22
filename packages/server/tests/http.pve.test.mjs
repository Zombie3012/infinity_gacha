import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mulberry32, generatePveLayout } from '@infiniti-gacha/shared';
import { resolveBattleV2 } from '../dist/modules/combat/combat-v2.engine.js';
import { buildNow, cleanupAccount, createHero, createMaster, grantItems, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';

async function party(master, heroIds, name) {
  const id = randomUUID();
  await sql('insert into master_parties (id, master_id, name, is_default) values ($1, $2, $3, false)', [id, master.masterId, name]);
  for (const [slot, heroId] of heroIds.entries()) {
    await sql('insert into combat_party_slots (id, master_id, party_id, hero_id, slot_index) values ($1,$2,$3,$4,$5)', [randomUUID(), master.masterId, id, heroId, slot]);
  }
  return id;
}

async function fixture(t) {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'pve');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    assert.equal((await sql('select count(*)::int as n from accounts where id=$1', [master.accountId])).rows[0].n, 0, 'account cascade cleanup releases deployed Heroes');
    await harness.close();
  });
  const request = (path, options = {}) => harness.request(path, { token: master.token, ...options });
  // This suite deliberately exercises persisted v1 floors; v2 has its own integration suite.
  const legacyMaps = new Set();
  const command = async (path, body = {}, key = randomUUID(), method = 'POST') => {
    const result = await request(path, { method, body, headers: { 'Idempotency-Key': key } });
    if (path === '/api/pve/enter' && result.status === 201 && !legacyMaps.has(result.body.mapId)) {
      legacyMaps.add(result.body.mapId);
      const world = (await sql('select world_seed from worlds where master_id=$1', [master.masterId])).rows[0];
      await sql('update pve_maps set exploration=null, layout=$2::jsonb, discovered=$3::jsonb where id=$1',
        [result.body.mapId, JSON.stringify(generatePveLayout(world.world_seed, result.body.floor, 1)), '[0,1,12]']);
    }
    return result;
  };
  return { master, request, command };
}

async function tile(mapId, index, kind, extra = {}) {
  const map = (await sql('select layout from pve_maps where id = $1', [mapId])).rows[0];
  const node = { ...map.layout.tiles[index], kind, ...extra };
  await sql('update pve_maps set layout = jsonb_set(layout, $2::text[], $3::jsonb) where id = $1', [mapId, ['tiles', String(index)], JSON.stringify(node)]);
}

async function due(squadId, seconds = 6) {
  await sql("update pve_squads set next_step_at = clock_timestamp() - ($2 * interval '1 second') where id = $1", [squadId, seconds]);
}

test('HTTP private PvE: discovery, three squads, retries, resource collisions and boss progression', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  const roster = [];
  for (let i = 0; i < 4; i++) roster.push(await createHero(master.masterId, { name: `PvE Vanguard ${i}`, attack: 8000, defense: 3000, speed: 200, hp: 90000, maxHp: 90000 }));
  const parties = [];
  for (let i = 0; i < 4; i++) parties.push(await party(master, [roster[i].id], `PvE Squad ${i}`));
  const overlap = await party(master, [roster[0].id], 'PvE Overlap');
  let mapId; const squads = [];

  await t.test('authentication, missing idempotency and input errors are explicit', async () => {
    assert.equal((await request('/api/pve/state', { token: '' })).status, 401);
    assert.equal((await request('/api/pve/enter', { method: 'POST', body: {} })).status, 400);
    assert.equal((await request('/api/pve/state?cursor=-1')).status, 400);
    assert.equal((await request('/api/pve/state')).body.map, null);
  });

  await t.test('concurrent entry with one key creates one deterministic map and masks hidden nodes', async () => {
    const [a, b] = await Promise.all([command('/api/pve/enter', {}, 'enter'), command('/api/pve/enter', {}, 'enter')]);
    assert.equal(a.status, 201); assert.equal(b.status, 201);
    assert.equal(a.body.mapId, b.body.mapId); mapId = a.body.mapId;
    const state = await request('/api/pve/state');
    assert.equal(state.body.map.width, 12); assert.equal(state.body.map.height, 12);
    assert.equal(state.body.map.tiles.length, 144);
    assert.equal(state.body.map.tiles.filter(node => node.kind !== 'UNKNOWN').length, 3);
    assert.equal('seed' in state.body.map.tiles[143], false);
    assert.equal('encounterCatalog' in state.body.map, false);
    assert.equal((await sql('select count(*)::int as n from pve_maps where master_id = $1', [master.masterId])).rows[0].n, 1);
  });

  await t.test('plans support slot eight, reject unavailable skills and are isolated by owner', async () => {
    const plan = { targetPriority: 'HIGHEST_ATK', members: [{ heroId: roster[0].id, slotIndex: 8, skillOrder: [] }] };
    const saved = await command(`/api/pve/parties/${parties[0]}/plan`, plan, 'plan', 'PUT');
    assert.equal(saved.status, 200); assert.equal(saved.body.plan.members[0].slotIndex, 8);
    const bad = await command(`/api/pve/parties/${parties[0]}/plan`, { ...plan, members: [{ ...plan.members[0], skillOrder: ['UNOWNED'] }] }, 'bad-skill', 'PUT');
    assert.equal(bad.status, 400);
    assert.equal((await command(`/api/pve/parties/${randomUUID()}/deploy`)).status, 404);
    const badGrid = await command(`/api/pve/parties/${parties[0]}/plan`, { ...plan, members: [{ ...plan.members[0], slotIndex: 9 }] }, 'bad-grid', 'PUT');
    assert.equal(badGrid.status, 400);
  });

  await t.test('insufficient rations roll back deployment; a successful retry consumes food once', async () => {
    await grantItems(master.masterId, { FOOD: 0 });
    const before = await command(`/api/pve/parties/${parties[0]}/deploy`, {}, 'deploy-0');
    assert.equal(before.status, 409); assert.equal(before.body.error, 'ERR_INSUFFICIENT_RATIONS');
    assert.equal((await sql('select count(*)::int as n from pve_hero_reservations where master_id = $1', [master.masterId])).rows[0].n, 0);
    await grantItems(master.masterId, { FOOD: 500 });
    const [a, b] = await Promise.all([
      command(`/api/pve/parties/${parties[0]}/deploy`, {}, 'deploy-0'), command(`/api/pve/parties/${parties[0]}/deploy`, {}, 'deploy-0'),
    ]);
    assert.equal(a.status, 201); assert.equal(b.status, 201); assert.equal(a.body.squadId, b.body.squadId);
    squads.push(a.body.squadId);
    assert.equal((await sql("select quantity from master_items where master_id = $1 and item_id = 'FOOD'", [master.masterId])).rows[0].quantity, 490);
  });

  await t.test('Hero exclusivity, three-squad cap and frozen pre-battle plans are enforced', async () => {
    const duplicate = await command(`/api/pve/parties/${overlap}/deploy`);
    assert.equal(duplicate.status, 409); assert.equal(duplicate.body.error, 'ERR_PVE_HERO_DEPLOYED');
    for (const id of parties.slice(1, 3)) {
      const deployed = await command(`/api/pve/parties/${id}/deploy`); assert.equal(deployed.status, 201); squads.push(deployed.body.squadId);
    }
    assert.equal((await command(`/api/pve/parties/${parties[3]}/deploy`)).body.error, 'ERR_PVE_SQUAD_LIMIT');
    const frozen = await command(`/api/pve/parties/${parties[0]}/plan`, { targetPriority: 'FRONTLINE', members: [{ heroId: roster[0].id, slotIndex: 0, skillOrder: [] }] }, 'frozen', 'PUT');
    assert.equal(frozen.body.error, 'ERR_PVE_PARTY_DEPLOYED');
    const rosterView = await request('/api/heroes');
    const reserved = rosterView.body.find(hero => hero.id === roster[0].id);
    assert.equal(reserved.pveDeployment.squadId, squads[0]);
    assert.equal(rosterView.body.find(hero => hero.id === roster[3].id).pveDeployment, null);
    const locked = await request(`/api/heroes/${roster[0].id}/lock`, { method: 'PATCH', body: { isLocked: true } });
    assert.equal(locked.status, 409); assert.equal(locked.body.error, 'ERR_PVE_HERO_DEPLOYED');
    await assert.rejects(sql('delete from heroes where id = $1', [roster[0].id]), /ERR_PVE_HERO_DEPLOYED/);
    const membership = await request(`/api/parties/${parties[0]}`, { method: 'PUT', body: { heroIds: [] } });
    assert.equal(membership.status, 409);
  });

  await t.test('movement uses server ETA, fog and stable retry semantics', async () => {
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 11, y: 11 })).status, 409);
    const moving = await command(`/api/pve/squads/${squads[0]}/move`, { x: 1, y: 0 }, 'move-1');
    assert.equal(moving.status, 200);
    assert.equal(moving.body.secondsPerTile, 1);
    assert.ok(new Date(moving.body.nextStepAt).getTime() - Date.now() > 0);
    const instant = (await request('/api/pve/state')).body.squads.find(row => row.id === squads[0]);
    assert.equal(instant.x, 0); assert.equal(instant.status, 'MOVING');
    const replay = await command(`/api/pve/squads/${squads[0]}/move`, { y: 0, x: 1 }, 'move-1');
    assert.deepEqual(replay.body, moving.body);
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 0, y: 1 }, 'move-1')).body.error, 'ERR_PVE_IDEMPOTENCY_CONFLICT');
    await due(squads[0]);
    const states = await Promise.all([request('/api/pve/state'), request('/api/pve/state'), request('/api/pve/state')]);
    for (const state of states) { assert.equal(state.status, 200); assert.equal(state.body.squads.find(row => row.id === squads[0]).x, 1); }
    assert.equal((await sql("select count(*)::int as n from pve_events where map_id = $1 and kind = 'SQUAD_ARRIVED'", [mapId])).rows[0].n, 1);
  });

  await t.test('two arriving squads collect one resource reward exactly once', async () => {
    await tile(mapId, 2, 'RESOURCE', { resource: { itemId: 'WOOD', quantity: 23 } });
    await grantItems(master.masterId, { WOOD: 100 });
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 2, y: 0 })).status, 200);
    assert.equal((await command(`/api/pve/squads/${squads[1]}/move`, { x: 2, y: 0 })).status, 200);
    await due(squads[0], 7); await due(squads[1], 12);
    const states = await Promise.all([request('/api/pve/state'), request('/api/pve/state')]);
    assert.ok(states.every(state => state.status === 200));
    assert.equal((await sql("select quantity from master_items where master_id = $1 and item_id = 'WOOD'", [master.masterId])).rows[0].quantity, 123);
    assert.equal((await sql("select count(*)::int as n from pve_events where map_id = $1 and kind = 'RESOURCE_COLLECTED'", [mapId])).rows[0].n, 1);
  });

  let battleId;
  await t.test('automatic battle stops the route, settles once and leaves other squads usable', async () => {
    await tile(mapId, 3, 'ENEMY');
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 3, y: 0 })).status, 200);
    await due(squads[0]);
    const [a, b] = await Promise.all([request('/api/pve/state'), request('/api/pve/state')]);
    assert.equal(a.status, 200, JSON.stringify(a.body)); assert.equal(b.status, 200);
    const squad = a.body.squads.find(row => row.id === squads[0]);
    assert.equal(squad.status, 'IDLE'); assert.deepEqual(squad.route, []); battleId = squad.lastBattleId;
    const result = await request(`/api/pve/battles/${battleId}`);
    assert.equal(result.status, 200); assert.equal(result.body.report.winner, 'HERO');
    assert.ok(result.body.settlement.silverReward > 0);
    assert.equal(result.body.report.initialUnits.find(unit => unit.side === 'HERO').slotIndex, 8);
    const captured = (await sql('select combat_state from combat_sessions where id=$1', [battleId])).rows[0].combat_state;
    assert.equal(captured.combatAlgorithmVersion, 1);
    assert.equal(captured.heroes[0].formationSlot, 8);
    assert.deepEqual(resolveBattleV2(captured.heroes, captured.enemies, { random: mulberry32(captured.seed),
      maxRounds: captured.maxRounds, timeoutIsDraw: captured.timeoutIsDraw }), result.body.report,
    'persisted server-only inputs reproduce the exact encounter report');
    assert.equal((await sql("select count(*)::int as n from currency_transactions where master_id=$1 and transaction_type='PVE_MAP_REWARD'", [master.masterId])).rows[0].n, 1);
    assert.equal((await command(`/api/pve/squads/${squads[2]}/move`, { x: 0, y: 1 })).status, 200);
    const otherHarness = await startHarness();
    const outsider = await createMaster(otherHarness.request, 'pvex');
    t.after(async () => { await cleanupAccount(outsider.accountId); await otherHarness.close(); });
    // Different owner cannot inspect the report or issue an order to this squad.
    assert.equal((await request(`/api/pve/battles/${battleId}`, { token: outsider.token })).status, 404);
    assert.equal((await request(`/api/pve/squads/${squads[0]}/move`, { token: outsider.token, method: 'POST', body: { x: 4, y: 0 }, headers: { 'Idempotency-Key': 'foreign' } })).status, 404);
  });

  await t.test('boss victory advances once, withdraws squads and opens the next map explicitly', async () => {
    await tile(mapId, 4, 'BOSS');
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 4, y: 0 })).status, 200);
    await due(squads[0]);
    const result = await request('/api/pve/state');
    assert.equal(result.status, 200, JSON.stringify(result.body)); assert.equal(result.body.map.status, 'CLEARED');
    assert.ok(result.body.squads.every(row => !['IDLE', 'MOVING', 'FIGHTING'].includes(row.status)));
    assert.equal((await sql('select count(*)::int as n from pve_hero_reservations where master_id=$1', [master.masterId])).rows[0].n, 0);
    assert.equal((await sql('select current_floor from worlds where id=(select world_id from pve_maps where id=$1)', [mapId])).rows[0].current_floor, 2);
    assert.equal((await command(`/api/pve/squads/${squads[0]}/move`, { x: 5, y: 0 })).status, 409);
    const before = (await sql('select silver_coins from masters where id=$1', [master.masterId])).rows[0].silver_coins;
    await request('/api/pve/state'); await request(`/api/pve/battles/${battleId}`);
    assert.equal((await sql('select silver_coins from masters where id=$1', [master.masterId])).rows[0].silver_coins, before);
    const entered = await command('/api/pve/enter'); assert.equal(entered.status, 201); assert.equal(entered.body.floor, 2);
    assert.notEqual(entered.body.mapId, mapId);
    // Keyset pagination must not lose reports sharing the same logical arrival timestamp.
    await sql("update pve_battles set created_at='2026-11-01T00:00:00Z' where master_id=$1", [master.masterId]);
    const all = await request('/api/pve/battles'); assert.equal(all.status, 200);
    assert.equal(all.body.battles.length, 2);
    assert.ok(all.body.battles.every(row => row.mapId === mapId));
    const page1 = await request('/api/pve/battles?limit=1');
    const page2 = await request('/api/pve/battles?limit=1&before=' + page1.body.nextCursor);
    assert.notEqual(page1.body.battles[0].id, page2.body.battles[0].id);
    const page3 = await request('/api/pve/battles?limit=1&before=' + page2.body.nextCursor);
    assert.deepEqual(page3.body.battles, []);
    assert.equal(page3.body.nextCursor, null);
    assert.equal((await request('/api/pve/battles?limit=0')).status, 400);
    assert.equal((await request('/api/pve/battles?before=' + randomUUID())).status, 404);
    await sql('delete from master_parties where id=$1', [parties[0]]);
    assert.equal((await request(`/api/pve/battles/${battleId}`)).status, 200, 'historical squads/reports survive deleting a withdrawn party');
  });
});

test('HTTP private PvE: uniform death, gear drops and repair of an emptied party', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  const normal = await createHero(master.masterId, { name: 'Mortal', hp: 1, maxHp: 1, attack: 1, defense: 0, speed: 1 });
  const special = await createHero(master.masterId, { name: 'Immortal', category: 'SPECIAL', hp: 1, maxHp: 1, attack: 1, defense: 0, speed: 1 });
  const partyId = await party(master, [normal.id, special.id], 'Fallen Squad');
  for (const h of [normal,special]) await sql("insert into hero_injuries (id,hero_id,master_id,severity,penalty_percent,natural_heal_at) values (gen_random_uuid()::text,$1,$2,'SEVERE',25,now()+interval '2 hours')",[h.id,master.masterId]);
  const template = (await sql('select code from equipment_templates where bonus_hp=0 order by code limit 1')).rows[0].code;
  const normalGear = randomUUID(); const specialGear = randomUUID();
  for (const [id, hero] of [[normalGear, normal], [specialGear, special]]) {
    await sql("insert into equipment_instances (id,master_id,template_code,equipped_hero_id,location) values ($1,$2,$3,$4,'EQUIPPED')", [id, master.masterId, template, hero.id]);
  }
  await grantItems(master.masterId, { FOOD: 500 });
  const map = await command('/api/pve/enter'); assert.equal(map.status, 201);
  await tile(map.body.mapId, 1, 'ENEMY');
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`); assert.equal(deployed.status, 201);
  const squadId = deployed.body.squadId;
  assert.equal((await command(`/api/pve/squads/${squadId}/move`, { x: 1, y: 0 })).status, 200);
  await due(squadId);
  const state = await request('/api/pve/state'); assert.equal(state.status, 200, JSON.stringify(state.body));
  const squad = state.body.squads.find(row => row.id === squadId);
  assert.equal(squad.status, 'DEFEATED');
  const report = await request(`/api/pve/battles/${squad.lastBattleId}`);
  assert.equal(report.body.report.winner, 'ENEMY');
  assert.equal(report.body.settlement.silverReward, 0);
  const roster = (await sql('select id,state,hp from heroes where id=any($1::varchar[])', [[normal.id, special.id]])).rows;
  assert.equal(roster.find(hero => hero.id === normal.id).state, 'DEAD');
  assert.equal(roster.find(hero => hero.id === special.id).state, 'DEAD');
  assert.equal((await sql('select count(*)::int n from hero_injuries where hero_id=any($1::varchar[]) and healed_at is null',[[normal.id,special.id]])).rows[0].n,0,'death closes old injuries instead of leaving the casualty in healing candidates');
  const gear = (await sql('select id,location,equipped_hero_id,drop_floor from equipment_instances where id=any($1::varchar[])', [[normalGear, specialGear]])).rows;
  assert.equal(gear.find(item => item.id === normalGear).location, 'FLOOR_DROP');
  assert.equal(gear.find(item => item.id === normalGear).drop_floor, 1);
  assert.equal(gear.find(item => item.id === specialGear).location, 'FLOOR_DROP');
  assert.equal(gear.find(item => item.id === specialGear).equipped_hero_id, null);
  assert.equal((await sql('select count(*)::int as n from combat_party_slots where party_id=$1', [partyId])).rows[0].n, 0);
  assert.equal((await sql('select count(*)::int as n from pve_hero_reservations where master_id=$1', [master.masterId])).rows[0].n, 0);
  assert.equal((await sql('select current_floor from worlds where master_id=$1 order by created_at limit 1', [master.masterId])).rows[0].current_floor, 1);
  const replacement = await createHero(master.masterId, { name: 'Replacement' });
  const repaired = await command(`/api/pve/parties/${partyId}`, { name: 'Rebuilt Squad', heroIds: [replacement.id] }, 'repair', 'PUT');
  assert.equal(repaired.status, 200, JSON.stringify(repaired.body));
  assert.equal((await command(`/api/pve/parties/${partyId}/deploy`)).status, 201);
});

test('HTTP private PvE: a failed reward transaction rolls back combat and can be retried', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  const hero = await createHero(master.masterId, { name: 'Rollback Vanguard', attack: 8000, defense: 3000, speed: 200, hp: 90000, maxHp: 90000 });
  const partyId = await party(master, [hero.id], 'Rollback Squad');
  await grantItems(master.masterId, { FOOD: 500 });
  const map = await command('/api/pve/enter'); assert.equal(map.status, 201);
  await tile(map.body.mapId, 1, 'ENEMY');
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`); assert.equal(deployed.status, 201);
  const squadId = deployed.body.squadId;
  await command(`/api/pve/squads/${squadId}/move`, { x: 1, y: 0 });
  await due(squadId);
  const before = (await sql('select silver_coins,exp from masters where id=$1', [master.masterId])).rows[0];
  const heroBefore = (await sql('select exp,hp,level from heroes where id=$1', [hero.id])).rows[0];
  const eventsBefore = (await sql('select revision from pve_maps where id=$1', [map.body.mapId])).rows[0].revision;
  assert.match(master.masterId, /^[0-9a-f-]{36}$/);
  await sql(`create function test_pve_fail_reward() returns trigger language plpgsql as $$ begin raise exception 'TEST_PVE_REWARD_FAILURE'; end; $$`);
  await sql(`create trigger test_pve_reward_failure before insert on currency_transactions for each row when (NEW.master_id = '${master.masterId}' and NEW.transaction_type = 'PVE_MAP_REWARD') execute function test_pve_fail_reward()`);
  const removeFault = () => sql('drop trigger if exists test_pve_reward_failure on currency_transactions; drop function if exists test_pve_fail_reward()');
  t.after(removeFault);
  const failed = await request('/api/pve/state');
  assert.equal(failed.status, 500);
  assert.deepEqual((await sql('select silver_coins,exp from masters where id=$1', [master.masterId])).rows[0], before);
  assert.deepEqual((await sql('select exp,hp,level from heroes where id=$1', [hero.id])).rows[0], heroBefore);
  assert.equal((await sql('select count(*)::int as n from pve_battles where master_id=$1', [master.masterId])).rows[0].n, 0);
  assert.equal((await sql('select revision from pve_maps where id=$1', [map.body.mapId])).rows[0].revision, eventsBefore);
  assert.equal((await sql('select x from pve_squads where id=$1', [squadId])).rows[0].x, 0);
  await removeFault();
  const recovered = await request('/api/pve/state'); assert.equal(recovered.status, 200, JSON.stringify(recovered.body));
  const after = (await sql("select count(*)::int as n from currency_transactions where master_id=$1 and transaction_type='PVE_MAP_REWARD'", [master.masterId])).rows[0].n;
  assert.equal(after, 1);
  await request('/api/pve/state');
  assert.equal((await sql('select count(*)::int as n from pve_battles where master_id=$1', [master.masterId])).rows[0].n, 1);
});

test('HTTP private PvE: deployed Heroes reject legacy combat without consuming rations', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  const hero = await createHero(master.masterId);
  const partyId = await party(master, [hero.id], 'Reserved Squad');
  await grantItems(master.masterId, { FOOD: 100 });
  assert.equal((await command('/api/pve/enter')).status, 201);
  assert.equal((await command(`/api/pve/parties/${partyId}/deploy`)).status, 201);
  const before = (await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity;
  for (const endpoint of ['/api/combat/v2/session/start', '/api/combat/session/start']) {
    const response = await request(endpoint, { method: 'POST', body: { heroIds: [hero.id], partyId } });
    assert.equal(response.status, 409, JSON.stringify(response.body));
    assert.equal(response.body.error, 'ERR_PVE_MAP_ACTIVE');
  }
  const oldDungeon = await request('/api/dungeon/floor/1/enter', { method: 'POST', body: { templateCode: 'QUIET_FOREST' } });
  assert.equal(oldDungeon.status, 409, JSON.stringify(oldDungeon.body));
  assert.equal(oldDungeon.body.error, 'ERR_PVE_MAP_ACTIVE');
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, before);
});

test('HTTP private PvE: concurrent expedition assignment and deployment cannot reserve the same Hero', { skip: skipReason }, async t => {
  const { master, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 1000 });
  assert.equal((await command('/api/pve/enter')).status, 201);
  const tileId = (await sql('select id from world_tiles order by id limit 1')).rows[0].id;
  for (let iteration = 0; iteration < 8; iteration++) {
    const hero = await createHero(master.masterId, { name: `Racing Hero ${iteration}` });
    const partyId = await party(master, [hero.id], `Race Squad ${iteration}`);
    const expeditionId = randomUUID();
    await sql(`insert into hero_expeditions (id,master_id,tile_id,mission,status,depart_at,arrive_at)
      values ($1,$2,$3,'SCOUT','TRAVELING',now(),now()+interval '1 hour')`, [expeditionId, master.masterId, tileId]);
    const results = await Promise.allSettled([
      command(`/api/pve/parties/${partyId}/deploy`),
      sql('insert into expedition_members (id,expedition_id,hero_id,slot_index) values ($1,$2,$3,0)', [randomUUID(), expeditionId, hero.id]),
    ]);
    assert.equal(results[0].status, 'fulfilled');
    const deployed = results[0].value;
    const expeditionSucceeded = results[1].status === 'fulfilled';
    assert.notEqual(deployed.status === 201, expeditionSucceeded, 'exactly one activity may claim the Hero');
    if (deployed.status === 201) {
      assert.match(String(results[1].reason), /ERR_PVE_HERO_DEPLOYED/);
      assert.equal((await command(`/api/pve/squads/${deployed.body.squadId}/recall`)).status, 200);
    } else {
      assert.equal(deployed.status, 409, JSON.stringify(deployed.body));
      assert.equal(deployed.body.error, 'ERR_PVE_HERO_BUSY');
    }
  }
});

test('HTTP private PvE: simultaneous arrivals cannot pay the same enemy twice', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 1000 });
  const map = await command('/api/pve/enter'); assert.equal(map.status, 201);
  await tile(map.body.mapId, 1, 'ENEMY');
  const squads = [];
  for (let index = 0; index < 2; index++) {
    const hero = await createHero(master.masterId, { name: `Collision Hero ${index}`, hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
    const partyId = await party(master, [hero.id], `Collision Squad ${index}`);
    const deployed = await command(`/api/pve/parties/${partyId}/deploy`); assert.equal(deployed.status, 201);
    squads.push(deployed.body.squadId);
    await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 });
  }
  await sql("update pve_squads set next_step_at=now()-interval '6 seconds' where id=any($1::varchar[])", [squads]);
  const responses = await Promise.all(Array.from({ length: 6 }, () => request('/api/pve/state')));
  assert.ok(responses.every(response => response.status === 200));
  assert.equal((await sql('select count(*)::int as n from pve_battles where map_id=$1', [map.body.mapId])).rows[0].n, 1);
  assert.equal((await sql("select count(*)::int as n from currency_transactions where master_id=$1 and transaction_type='PVE_MAP_REWARD'", [master.masterId])).rows[0].n, 1);
  const final = responses.at(-1).body;
  assert.ok(final.squads.every(squad => squad.x === 1 && squad.status === 'IDLE'));
});

test('HTTP private PvE: base survival reads preserve battle fatigue and reserved Heroes cannot rest or feed', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 1000 });
  const hero = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
  const partyId = await party(master, [hero.id], 'Survival Squad');
  const entered = await command('/api/pve/enter');
  await tile(entered.body.mapId, 1, 'ENEMY');
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`);
  assert.equal(deployed.status, 201);
  for (const action of ['rest', 'feed']) {
    const response = await request(`/api/survival/heroes/${hero.id}/${action}`, { method: 'POST', body: { quantity: 1 } });
    assert.equal(response.status, 409, JSON.stringify(response.body));
    assert.equal(response.body.error, 'ERR_PVE_HERO_DEPLOYED');
  }
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, 990);
  await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 });
  await due(deployed.body.squadId);
  const reads = await Promise.all(Array.from({ length: 16 }, (_, index) => request(index % 2 ? '/api/survival' : '/api/pve/state')));
  assert.ok(reads.every(response => response.status === 200));
  const state = (await sql('select hunger_score,fatigue_score,is_resting from hero_survival_states where hero_instance_id=$1', [hero.id])).rows[0];
  assert.ok(state.hunger_score >= 8 && state.hunger_score < 9, JSON.stringify(state));
  assert.ok(state.fatigue_score >= 12 && state.fatigue_score < 13, JSON.stringify(state));
  assert.equal(state.is_resting, false);
  assert.equal((await command(`/api/pve/squads/${deployed.body.squadId}/recall`)).status, 200);
  assert.equal((await request(`/api/survival/heroes/${hero.id}/rest`, { method: 'POST' })).status, 200);
  assert.equal((await request('/api/heroes')).body.find(row => row.id === hero.id).pveDeployment, null);
});

test('HTTP private PvE: event pages retain all revisions and reset a cursor from another map', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  const entered = await command('/api/pve/enter');
  const mapId = entered.body.mapId;
  // A long offline backlog: verify the public bounded cursor contract independently of movement.
  await sql(`insert into pve_events (id,master_id,map_id,revision,kind,data,occurred_at)
    select gen_random_uuid()::text,$1,$2,n,'TEST_BACKLOG','{}',now() from generate_series(2,251) n`, [master.masterId, mapId]);
  await sql('update pve_maps set revision=251 where id=$1', [mapId]);
  const revisions = [];
  let cursor = 0;
  for (let index = 0; index < 3; index++) {
    const page = await request(`/api/pve/state?mapId=${mapId}&cursor=${cursor}`);
    assert.equal(page.status, 200);
    revisions.push(...page.body.events.map(event => event.revision));
    cursor = page.body.cursor;
  }
  assert.deepEqual(revisions, Array.from({ length: 251 }, (_, index) => index + 1));
  const empty = await request(`/api/pve/state?mapId=${mapId}&cursor=${cursor}`);
  assert.equal(empty.body.cursor, 251); assert.deepEqual(empty.body.events, []);
  const reset = await request(`/api/pve/state?mapId=${randomUUID()}&cursor=251`);
  assert.equal(reset.body.events[0].revision, 1); assert.equal(reset.body.cursor, 100);
});

test('HTTP private PvE: a timed-out boss is a draw, can be retried, and never advances the floor', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 1000 });
  const hero = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 1, defense: 100000, speed: 200 });
  const partyId = await party(master, [hero.id], 'Draw Squad');
  const entered = await command('/api/pve/enter');
  await tile(entered.body.mapId, 1, 'BOSS');
  const catalog = (await sql('select encounter_catalog from pve_maps where id=$1', [entered.body.mapId])).rows[0].encounter_catalog;
  for (const foe of catalog) { foe.hp = 1000000; foe.attack = 1; foe.defense = 100000; foe.agi = 1; }
  await sql('update pve_maps set encounter_catalog=$2::jsonb where id=$1', [entered.body.mapId, JSON.stringify(catalog)]);
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`);
  assert.equal(deployed.status, 201);
  await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 });
  await due(deployed.body.squadId);
  const state = await request('/api/pve/state');
  assert.equal(state.status, 200, JSON.stringify(state.body));
  assert.equal(state.body.map.status, 'ACTIVE');
  const report = await request('/api/pve/battles/' + state.body.squads[0].lastBattleId);
  assert.equal(report.body.report.winner, 'DRAW');
  assert.equal(report.body.report.rounds, 30);
  assert.equal(report.body.settlement.silverReward, 0);
  assert.equal(report.body.settlement.bossCleared, false);
  assert.equal((await sql('select current_floor from worlds where master_id=$1', [master.masterId])).rows[0].current_floor, 1);
  const retry = await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 }, 'retry-draw');
  assert.equal(retry.status, 200);
  assert.notEqual(retry.body.battleId, report.body.id);
  assert.deepEqual((await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 }, 'retry-draw')).body, retry.body);
  assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1', [entered.body.mapId])).rows[0].n, 2);
});

test('HTTP private PvE: recovered v2 Heroes enter encounters with their restored HP percentage', { skip: skipReason }, async t => {
  for (const mode of ['emergency', 'treatment', 'resurrection']) await t.test(mode, async child => {
    const { master, request, command } = await fixture(child);
    const hero = await createHero(master.masterId, { category: mode === 'resurrection' ? 'SPECIAL' : 'NORMAL' });
    await sql(`update heroes set origin_stats='{"str":30,"int":20,"sta":30,"agi":20}',
      hp=100,current_hp_pct=0.2,mp=35,max_mp=100,current_mp_pct=0.35 where id=$1`, [hero.id]);
    await sql('update masters set silver_coins=200000 where id=$1', [master.masterId]);
    await grantItems(master.masterId, { FOOD: 1000, MEDICINE: 1, RESURRECTION_GEM_7: 5 });
    let expectedHpPct = 1;
    if (mode === 'emergency') {
      const healed = await request('/api/medical/emergency', { method: 'POST', body: { heroId: hero.id } });
      assert.equal(healed.status, 200, JSON.stringify(healed.body));
    } else if (mode === 'treatment') {
      await sql('update worlds set current_floor=4 where master_id=$1', [master.masterId]);
      await buildNow(request, master, 'MEDICAL', 1);
      const admitted = await request('/api/medical/treatments', { method: 'POST', body: { heroId: hero.id } });
      assert.equal(admitted.status, 201, JSON.stringify(admitted.body));
      await sql("update hero_treatments set finishes_at=now()-interval '1 minute' where hero_id=$1", [hero.id]);
      assert.equal((await request('/api/medical')).status, 200);
    } else {
      await sql("update heroes set state='DISABLED',hp=0,current_hp_pct=0 where id=$1", [hero.id]);
      const revived = await Promise.all(Array.from({ length: 3 }, () => request('/api/medical/resurrect', { method: 'POST', body: { heroId: hero.id } })));
      assert.equal(revived.filter(row => row.status === 200).length, 1, JSON.stringify(revived));
      assert.equal(revived.filter(row => row.status === 409).length, 2);
      assert.equal((await sql('select resurrection_count from hero_resurrection_cycles where hero_id=$1', [hero.id])).rows[0].resurrection_count, 1);
      assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='RESURRECTION_GEM_7'", [master.masterId])).rows[0].quantity, 4);
      expectedHpPct = 1;
    }
    const healed = (await sql('select hp,max_hp,current_hp_pct,current_mp_pct from heroes where id=$1', [hero.id])).rows[0];
    assert.equal(healed.current_hp_pct, expectedHpPct);
    assert.equal(healed.current_mp_pct, 0.35, 'HP recovery does not refill MP');
    const partyId = await party(master, [hero.id], 'Recovered Squad');
    const entered = await command('/api/pve/enter');
    await tile(entered.body.mapId, 1, 'ENEMY');
    const catalog = (await sql('select encounter_catalog from pve_maps where id=$1', [entered.body.mapId])).rows[0].encounter_catalog;
    for (const foe of catalog) { foe.hp = 1; foe.attack = 1; foe.defense = 0; foe.agi = 1; }
    await sql('update pve_maps set encounter_catalog=$2::jsonb where id=$1', [entered.body.mapId, JSON.stringify(catalog)]);
    const deployed = await command(`/api/pve/parties/${partyId}/deploy`);
    assert.equal(deployed.status, 201, JSON.stringify(deployed.body));
    await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 });
    await due(deployed.body.squadId);
    const state = await request('/api/pve/state');
    const battle = await request('/api/pve/battles/' + state.body.squads[0].lastBattleId);
    assert.equal(battle.status, 200, JSON.stringify(battle.body));
    const initial = battle.body.report.initialUnits.find(unit => unit.id === hero.id);
    assert.equal(initial.hp, Math.max(1, Math.round(initial.maxHp * expectedHpPct)));
    assert.equal(initial.mp, Math.round(initial.maxMp * 0.35));
  });
});

test('HTTP private PvE: work/treatment conflicts and frozen equipment/skills preserve costs', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await sql('update masters set silver_coins=200000,level=10 where id=$1', [master.masterId]);
  await grantItems(master.masterId, { FOOD: 1000, MEDICINE: 1 });
  const kitchen = await buildNow(request, master, 'KITCHEN', 1);
  await buildNow(request, master, 'MEDICAL', 2);
  const hero = await createHero(master.masterId, { hp: 400, maxHp: 500 });
  const partyId = await party(master, [hero.id], 'Busy Squad');
  const gearId = randomUUID();
  const template = (await sql('select code from equipment_templates order by code limit 1')).rows[0].code;
  await sql("insert into equipment_instances (id,master_id,template_code,equipped_hero_id,location) values ($1,$2,$3,$4,'EQUIPPED')", [gearId, master.masterId, template, hero.id]);
  const skillCode = (await sql('select code from hero_skill_templates order by code limit 1')).rows[0].code;
  await sql('insert into hero_skill_instances (id,hero_id,skill_code,is_unlocked) values ($1,$2,$3,true)', [randomUUID(), hero.id, skillCode]);
  assert.equal((await command('/api/pve/enter')).status, 201);
  assert.equal((await request(`/api/base/buildings/${kitchen.id}/workers`, { method: 'POST', body: { heroId: hero.id } })).status, 201);
  assert.equal((await command(`/api/pve/parties/${partyId}/deploy`, {}, 'busy-retry')).body.error, 'ERR_PVE_HERO_BUSY');
  assert.equal((await request(`/api/base/buildings/${kitchen.id}/workers/${hero.id}`, { method: 'DELETE' })).status, 200);
  assert.equal((await request('/api/medical/treatments', { method: 'POST', body: { heroId: hero.id } })).status, 201);
  assert.equal((await command(`/api/pve/parties/${partyId}/deploy`, {}, 'busy-retry')).body.error, 'ERR_PVE_HERO_BUSY');
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, 1000);
  assert.equal((await request(`/api/medical/treatments/${hero.id}`, { method: 'DELETE' })).status, 200);
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`, {}, 'busy-retry');
  assert.equal(deployed.status, 201, JSON.stringify(deployed.body));
  for (const [path, body] of [[`/api/equipment/${gearId}/unequip`, {}],
    ['/api/medical/treatments', { heroId: hero.id }], ['/api/medical/emergency', { heroId: hero.id }],
    [`/api/base/buildings/${kitchen.id}/workers`, { heroId: hero.id }]]) {
    const blocked = await request(path, { method: 'POST', body });
    assert.equal(blocked.status, 409, JSON.stringify(blocked.body));
    assert.equal(blocked.body.error, 'ERR_PVE_HERO_DEPLOYED');
  }
  await assert.rejects(sql('update hero_skill_instances set skill_level=2 where hero_id=$1', [hero.id]), /ERR_PVE_HERO_DEPLOYED/);
  assert.equal((await sql('select skill_level from hero_skill_instances where hero_id=$1', [hero.id])).rows[0].skill_level, 1);
  assert.equal((await sql('select equipped_hero_id from equipment_instances where id=$1', [gearId])).rows[0].equipped_hero_id, hero.id);
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='MEDICINE'", [master.masterId])).rows[0].quantity, 1);
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, 990);
  assert.equal((await command(`/api/pve/squads/${deployed.body.squadId}/recall`)).status, 200);
  assert.equal((await request(`/api/equipment/${gearId}/unequip`, { method: 'POST', body: {} })).status, 200);
});

test('HTTP private PvE: an idle Hero breakthrough cannot overwrite concurrent battle Silver', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await sql('update masters set silver_coins=200000 where id=$1', [master.masterId]);
  const config = (await sql("select * from hero_development_configs where action='PROMOTION' and rank=1")).rows[0];
  await grantItems(master.masterId, { FOOD: 1000, [config.material_item_id]: config.material_quantity });
  const fighter = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
  const idle = await createHero(master.masterId, { rarity: 2 });
  await sql('update heroes set level=$2 where id=$1', [idle.id, config.required_hero_level]);
  const partyId = await party(master, [fighter.id], 'Concurrent Reward Squad');
  const entered = await command('/api/pve/enter');
  await tile(entered.body.mapId, 1, 'ENEMY');
  const deployed = await command(`/api/pve/parties/${partyId}/deploy`);
  await command(`/api/pve/squads/${deployed.body.squadId}/move`, { x: 1, y: 0 });
  await due(deployed.body.squadId);
  const gate = await pool.connect();
  let battleRequest;
  let breakthroughRequest;
  try {
    await gate.query('begin');
    const gatePid = (await gate.query('select pg_backend_pid() pid')).rows[0].pid;
    await gate.query('select id from masters where id=$1 for update', [master.masterId]);
    const waitForBlocked = async minimum => {
      const deadline = Date.now() + 5000;
      while (Date.now() < deadline) {
        const waiting = (await sql('select pid,pg_blocking_pids(pid) blockers from pg_stat_activity where cardinality(pg_blocking_pids(pid))>0')).rows;
        const chained = new Set([gatePid]);
        for (let pass = 0; pass < waiting.length; pass++) {
          for (const row of waiting) if (row.blockers.some(pid => chained.has(pid))) chained.add(row.pid);
        }
        if (chained.size - 1 >= minimum) return;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.fail('Concurrent requests did not reach the controlled Master lock.');
    };
    battleRequest = request('/api/pve/state');
    await waitForBlocked(1);
    breakthroughRequest = request(`/api/heroes/${idle.id}/breakthrough`, { method: 'POST', body: {} });
    await waitForBlocked(2);
    await gate.query('commit');
  } finally {
    await gate.query('rollback'); gate.release();
  }
  const [battle, breakthrough] = await Promise.all([battleRequest, breakthroughRequest]);
  assert.equal(battle.status, 200, JSON.stringify(battle.body));
  assert.equal(breakthrough.status, 200, JSON.stringify(breakthrough.body));
  const reward = (await sql('select settlement from pve_battles where map_id=$1', [entered.body.mapId])).rows[0].settlement.silverReward;
  assert.ok(reward > 0);
  const expected = 200000n + BigInt(reward) - BigInt(breakthrough.body.silverCost);
  assert.equal((await sql('select silver_coins from masters where id=$1', [master.masterId])).rows[0].silver_coins, expected.toString());
  assert.equal(breakthrough.body.remainingSilver, expected.toString());
});

test('HTTP PvE auto exploration persists, collects, fights a boss and stops safely', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 100, WOOD: 0 });
  const hero = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
  const partyId = await party(master, [hero.id], 'Auto Squad');
  const map = await command('/api/pve/enter');
  await tile(map.body.mapId, 1, 'RESOURCE', { resource: { itemId: 'WOOD', quantity: 21 } });
  await tile(map.body.mapId, 2, 'BOSS');
  await sql('update pve_maps set discovered=$2::jsonb where id=$1', [map.body.mapId, JSON.stringify([0, 1, 2, 12])]);
  const squad = (await command(`/api/pve/parties/${partyId}/deploy`)).body.squadId;
  const started = await command(`/api/pve/squads/${squad}/auto`, { enabled: true }, 'start-auto');
  assert.equal(started.status, 200); assert.equal(started.body.enabled, true);
  assert.deepEqual((await command(`/api/pve/squads/${squad}/auto`, { enabled: true }, 'start-auto')).body, started.body);
  const state = await request('/api/pve/state');
  assert.equal(state.body.squads[0].leaderHeroId, hero.id);
  assert.equal(state.body.squads[0].autoExplore, true);
  assert.equal(state.body.secondsPerTile, 1);
  await due(squad, 10);
  const cleared = await request('/api/pve/state');
  assert.equal(cleared.status, 200, JSON.stringify(cleared.body));
  assert.equal(cleared.body.map.status, 'CLEARED');
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='WOOD'", [master.masterId])).rows[0].quantity, 21);
  assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1', [map.body.mapId])).rows[0].n, 1);
  await request('/api/pve/state');
  assert.equal((await sql('select current_floor from worlds where master_id=$1', [master.masterId])).rows[0].current_floor, 2);
});

test('HTTP PvE auto can be stopped, and a loss never retries itself', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 100 });
  const hero = await createHero(master.masterId, { hp: 1, maxHp: 1, attack: 1, defense: 0, speed: 1 });
  const partyId = await party(master, [hero.id], 'Auto Loss');
  const map = await command('/api/pve/enter');
  await tile(map.body.mapId, 1, 'ENEMY');
  const squad = (await command(`/api/pve/parties/${partyId}/deploy`)).body.squadId;
  assert.equal((await command(`/api/pve/squads/${squad}/auto`, { enabled: true })).status, 200);
  const stopped = await command(`/api/pve/squads/${squad}/auto`, { enabled: false });
  assert.equal(stopped.body.status, 'IDLE');
  assert.equal((await request('/api/pve/state')).body.squads[0].route.length, 0);
  assert.equal((await command(`/api/pve/squads/${squad}/auto`, { enabled: true })).status, 200);
  await due(squad);
  const result = await request('/api/pve/state');
  assert.equal(result.body.squads[0].status, 'DEFEATED');
  assert.equal(result.body.squads[0].autoExplore, false);
  await request('/api/pve/state');
  assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1', [map.body.mapId])).rows[0].n, 1);
  const reinforcement = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
  const secondParty = await party(master, [reinforcement.id], 'Reinforcement');
  const second = (await command(`/api/pve/parties/${secondParty}/deploy`)).body.squadId;
  assert.equal((await command(`/api/pve/squads/${second}/auto`, { enabled: true })).status, 200);
  // Settle only this first encounter; a random second enemy can otherwise be reached in six seconds.
  await due(second, 0.02);
  const reinforced = await request('/api/pve/state');
  assert.equal(reinforced.status, 200, JSON.stringify(reinforced.body));
  assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1', [map.body.mapId])).rows[0].n, 2, 'another auto squad can attack an enemy previously visited by a defeated squad');
});

test('HTTP PvE squad avatar follows the first surviving party member', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 100 });
  const leader = await createHero(master.masterId, { hp: 1, maxHp: 1, defense: 0, speed: 1 });
  const survivor = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 2 });
  const partyId = await party(master, [leader.id, survivor.id], 'Leaders');
  const map = await command('/api/pve/enter');
  await tile(map.body.mapId, 1, 'ENEMY');
  const catalog = (await sql('select encounter_catalog from pve_maps where id=$1', [map.body.mapId])).rows[0].encounter_catalog;
  for (const foe of catalog) { foe.agi = 100; foe.attack = 1000; foe.hp = 20; }
  await sql('update pve_maps set encounter_catalog=$2::jsonb where id=$1', [map.body.mapId, JSON.stringify(catalog)]);
  const squad = (await command(`/api/pve/parties/${partyId}/deploy`)).body.squadId;
  assert.equal((await request('/api/pve/state')).body.squads[0].leaderHeroId, leader.id);
  await command(`/api/pve/squads/${squad}/move`, { x: 1, y: 0 });
  await due(squad);
  const after = (await request('/api/pve/state')).body;
  assert.equal(after.squads[0].status, 'IDLE');
  assert.equal(after.squads[0].leaderHeroId, survivor.id);
  assert.equal((await sql('select state from heroes where id=$1', [leader.id])).rows[0].state, 'DEAD');
});

test('HTTP PvE movement advances on the server one-second clock', { skip: skipReason }, async t => {
  const { master, request, command } = await fixture(t);
  await grantItems(master.masterId, { FOOD: 100 });
  const hero = await createHero(master.masterId);
  const partyId = await party(master, [hero.id], 'Clock');
  assert.equal((await command('/api/pve/enter')).status, 201);
  const squad = (await command(`/api/pve/parties/${partyId}/deploy`)).body.squadId;
  const ordered = await command(`/api/pve/squads/${squad}/move`, { x: 1, y: 0 });
  assert.equal(ordered.body.secondsPerTile, 1);
  const before = await request('/api/pve/state');
  assert.equal(before.body.squads[0].x, 0);
  const eta = Date.parse(ordered.body.nextStepAt);
  await new Promise(resolve => setTimeout(resolve, Math.max(0, eta - Date.now() + 100)));
  const after = await request('/api/pve/state');
  assert.equal(after.body.squads[0].x, 1);
  assert.equal(after.body.squads[0].status, 'IDLE');
});
