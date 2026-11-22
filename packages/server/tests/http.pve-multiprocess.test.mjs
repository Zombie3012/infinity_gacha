import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fork } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { cleanupAccount, createHero, createMaster, grantItems, skipReason, sql } from './helpers/harness.mjs';

async function startWorker() {
  const child = fork(fileURLToPath(new URL('../../../scripts/pve-test-server.mjs', import.meta.url)), [], {
    execArgv: [], windowsHide: true, env: { ...process.env, NODE_ENV: 'test', PVE_TEST_USE_CURRENT_BUILD: '1' },
    stdio: ['ignore', 'ignore', 'pipe', 'ipc'],
  });
  let diagnostics = '';
  child.stderr.on('data', data => { diagnostics += data; });
  const base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => { child.kill(); reject(new Error('PvE API worker startup timed out.')); }, 10_000);
    child.once('message', message => { clearTimeout(timeout); resolve(`http://127.0.0.1:${message.port}`); });
    child.once('exit', code => { clearTimeout(timeout); reject(new Error(`PvE worker exited ${code}: ${diagnostics}`)); });
    child.once('error', error => { clearTimeout(timeout); reject(error); });
  });
  return { base, async close() {
    if (child.exitCode !== null) return;
    await new Promise(resolve => {
      const timeout = setTimeout(() => { child.kill(); resolve(); }, 3000);
      child.once('exit', () => { clearTimeout(timeout); resolve(); }); child.send('stop');
    });
  } };
}

test('HTTP PvE across two API processes: reservations, arrival collisions and boss settlement', { skip: skipReason }, async t => {
  const workers = [];
  let master;
  t.after(async () => {
    for (const worker of workers) await worker.close();
    if (master) {
      await cleanupAccount(master.accountId);
      assert.equal((await sql('select id from accounts where id=$1', [master.accountId])).rowCount, 0);
    }
  });
  workers.push(await startWorker()); workers.push(await startWorker());
  const requestTo = async (index, path, { token = master?.token, method = 'GET', body, headers = {} } = {}) => {
    const response = await fetch(workers[index].base + path, { method, signal: AbortSignal.timeout(20_000),
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers },
      body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, body: await response.json() };
  };
  master = await createMaster((path, options) => requestTo(0, path, options), 'pveprocess');
  await grantItems(master.masterId, { FOOD: 1000, WOOD: 0 });
  const command = (index, path, body = {}, key = randomUUID()) => requestTo(index, path,
    { method: 'POST', body, headers: { 'Idempotency-Key': key } });
  const entries = await Promise.all(workers.map((_, index) => command(index, '/api/pve/enter', {}, 'shared-enter')));
  assert.ok(entries.every(entry => entry.status === 201));
  assert.equal(entries[0].body.mapId, entries[1].body.mapId);
  const mapId = entries[0].body.mapId;
  const layout = (await sql('select layout from pve_maps where id=$1', [mapId])).rows[0].layout;
  layout.tiles[1] = { ...layout.tiles[1], kind: 'RESOURCE', resource: { itemId: 'WOOD', quantity: 29 } };
  layout.tiles[2].kind = 'ENEMY'; layout.tiles[3].kind = 'BOSS';
  await sql('update pve_maps set layout=$2::jsonb where id=$1', [mapId, JSON.stringify(layout)]);
  const squads = [];
  for (let index = 0; index < 3; index++) {
    const hero = await createHero(master.masterId, { hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
    const party = await command(index % 2, '/api/pve/parties', { name: `Process Squad ${index}`, heroIds: [hero.id] });
    assert.equal(party.status, 201);
    const deployed = await Promise.all(workers.map((_, worker) => command(worker, `/api/pve/parties/${party.body.partyId}/deploy`, {}, `deploy-${index}`)));
    assert.ok(deployed.every(row => row.status === 201), JSON.stringify(deployed));
    assert.deepEqual(deployed[0].body, deployed[1].body);
    squads.push(deployed[0].body.squadId);
  }
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, 970);
  for (const destination of [1, 2, 3]) {
    const ordered = await Promise.all(squads.map((squad, index) => command(index % 2, `/api/pve/squads/${squad}/move`, { x: destination, y: 0 })));
    assert.ok(ordered.every(row => row.status === 200), JSON.stringify(ordered));
    await sql("update pve_squads set next_step_at=now()-interval '6 seconds' where id=any($1::varchar[])", [squads]);
    const settled = await Promise.all(Array.from({ length: 20 }, (_, index) => requestTo(index % 2, '/api/pve/state')));
    assert.ok(settled.every(row => row.status === 200), JSON.stringify(settled.map(row => [row.status, row.body.error])));
    const battles = (await sql('select count(*)::int n from pve_battles where map_id=$1', [mapId])).rows[0].n;
    assert.equal(battles, destination - 1);
    assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='WOOD'", [master.masterId])).rows[0].quantity, 29);
    if (destination === 3) {
      assert.ok(settled.every(row => row.body.map.status === 'CLEARED'));
      assert.equal((await sql('select current_floor from worlds where master_id=$1', [master.masterId])).rows[0].current_floor, 2);
      assert.equal((await sql('select count(*)::int n from pve_hero_reservations where master_id=$1', [master.masterId])).rows[0].n, 0);
    }
  }
  const rewards = (await sql("select count(*)::int n from currency_transactions where master_id=$1 and transaction_type='PVE_MAP_REWARD'", [master.masterId])).rows[0].n;
  assert.equal(rewards, 2);
});
