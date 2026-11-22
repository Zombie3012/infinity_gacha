import { fork } from 'node:child_process';
import { deepStrictEqual } from 'node:assert';
import { createHash, randomUUID } from 'node:crypto';
import { cpSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const argument = (name, fallback) => Number(process.argv.find(value => value.startsWith(`--${name}=`))?.split('=')[1] ?? fallback);
const minutes = argument('minutes', 10);
const players = argument('players', 4);
const restartSeconds = argument('restart-seconds', 90);
if (!(minutes > 0 && minutes <= 240 && Number.isInteger(players) && players >= 1 && players <= 16 && restartSeconds >= 30)) {
  throw new Error('Expected --minutes=(0,240], --players=1..16, --restart-seconds>=30.');
}
if (!process.env.DATABASE_URL || !new URL(process.env.DATABASE_URL).pathname.endsWith('_test')) {
  throw new Error('Use an explicitly configured, disposable DATABASE_URL ending in _test.');
}
process.env.NODE_ENV = 'test';
const { cleanupAccount, createHero, createMaster, grantItems, pool, sql } = await import('../packages/server/tests/helpers/harness.mjs');
mkdirSync('logs', { recursive: true });
const runtime = resolve(`logs/pve-soak-runtime-${Date.now()}`);
mkdirSync(runtime, { recursive: true });
cpSync('packages/server/dist', runtime + '/server', { recursive: true });
cpSync('packages/shared/dist', runtime + '/node_modules/@infiniti-gacha/shared/dist', { recursive: true });
cpSync('packages/shared/package.json', runtime + '/node_modules/@infiniti-gacha/shared/package.json');
process.env.PVE_SOAK_RUNTIME_DIR = runtime + '/server';
const sources = ['modules/pve/pve.service.js', 'modules/combat/combat-v2.engine.js', 'modules/combat/combat-settlement.js',
  'modules/medical/medical.service.js', 'modules/survival/survival.service.js'];
writeFileSync(runtime + '/manifest.json', JSON.stringify(Object.fromEntries(sources.map(path => [path,
  createHash('sha256').update(readFileSync(runtime + '/server/' + path)).digest('hex')])), null, 2));
const metrics = { players, requestedMinutes: minutes, mapsCleared: 0, cohorts: 0, audited: 0, requests: 0,
  acceptedCommands: 0, duplicateReplies: 0, interruptedRequests: 0, restarts: 0, failures: 0, rttMs: [] };
let worker;
let base = '';
let stopping = false;
let restartAt = 0;
let serial = 0;
const active = [];
const startedAt = Date.now();
const deadline = startedAt + minutes * 60_000;
const delay = ms => new Promise(resolveDelay => setTimeout(resolveDelay, ms));
process.on('SIGINT', () => { stopping = true; });
process.on('SIGTERM', () => { stopping = true; });

async function startServer() {
  worker = fork(resolve('scripts/pve-test-server.mjs'), [], { windowsHide: true,
    env: { ...process.env, NODE_ENV: 'test' }, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
  worker.stdout.on('data', chunk => process.stdout.write(chunk));
  worker.stderr.on('data', chunk => process.stderr.write(chunk));
  base = await new Promise((resolveBase, reject) => {
    const timeout = setTimeout(() => reject(new Error('Soak server did not start.')), 10_000);
    worker.once('message', message => { clearTimeout(timeout); resolveBase(`http://127.0.0.1:${message.port}`); });
    worker.once('error', error => { clearTimeout(timeout); reject(error); });
  });
  restartAt = Date.now() + restartSeconds * 1000;
}

async function stopServer(hard = false) {
  const current = worker;
  if (!current || current.exitCode !== null) return;
  await new Promise(resolveStop => {
    const timeout = setTimeout(() => { current.kill(); resolveStop(); }, 3000);
    current.once('exit', () => { clearTimeout(timeout); resolveStop(); });
    if (hard) current.kill(); else current.send('stop');
  });
  worker = null;
}

async function request(path, { token, method = 'GET', body, headers = {} } = {}) {
  metrics.requests++;
  const begin = Date.now();
  try {
    const response = await fetch(base + path, { method, signal: AbortSignal.timeout(8000),
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}), ...headers },
      ...(body ? { body: JSON.stringify(body) } : {}) });
    const result = { status: response.status, body: await response.json() };
    metrics.rttMs.push(Date.now() - begin);
    if (metrics.rttMs.length > 10_000) metrics.rttMs.shift();
    return result;
  } catch {
    metrics.interruptedRequests++;
    return { status: 0, body: { error: 'NETWORK_INTERRUPTED' } };
  }
}

async function command(actor, endpoint, body, key, method = 'POST') {
  let response = await request(endpoint, { token: actor.token, method, body, headers: { 'Idempotency-Key': key } });
  if (response.status === 401) {
    const login = await request('/api/auth/login', { method: 'POST', body: { username: actor.username, password: 'Password123!' } });
    if (login.status === 200) {
      actor.token = login.body.accessToken;
      response = await request(endpoint, { token: actor.token, method, body, headers: { 'Idempotency-Key': key } });
    }
  }
  return response;
}

async function createActor() {
  const master = await createMaster(request, 'soakpve');
  try {
  const actor = { ...master, pending: new Map(), cursor: 0, lastRevision: 0, retired: false, lastProgressAt: Date.now() };
  await sql('update worlds set difficulty_multiplier=1 where master_id=$1', [master.masterId]);
  await grantItems(master.masterId, { FOOD: 10000, WOOD: 0, STONE: 0 });
  actor.initialSilver = BigInt((await sql('select silver_coins from masters where id=$1', [master.masterId])).rows[0].silver_coins);
  for (let index = 0; index < 3; index++) {
    const hero = await createHero(master.masterId, { name: `Soak Vanguard ${index}`, hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200 });
    const saved = await command(actor, '/api/pve/parties', { name: `Soak Squad ${index}`, heroIds: [hero.id] }, randomUUID());
    if (saved.status !== 201) throw new Error(`Soak party setup failed: ${JSON.stringify(saved.body)}`);
    if (index === 0) {
      const entered = await command(actor, '/api/pve/enter', {}, randomUUID());
      if (entered.status !== 201) throw new Error(`Soak entry failed: ${JSON.stringify(entered.body)}`);
      actor.mapId = entered.body.mapId;
    }
    const deployed = await command(actor, `/api/pve/parties/${saved.body.partyId}/deploy`, {}, randomUUID());
    if (deployed.status !== 201) throw new Error(`Soak deployment failed: ${JSON.stringify(deployed.body)}`);
  }
  metrics.cohorts++;
  return actor;
  } catch (error) {
    await cleanupAccount(master.accountId);
    throw error;
  }
}

async function audit(actor) {
  const connection = await pool.connect();
  try {
    await connection.query('begin transaction isolation level repeatable read read only');
    const map = (await connection.query('select * from pve_maps where id=$1', [actor.mapId])).rows[0];
    const battles = (await connection.query('select settlement,report from pve_battles where map_id=$1', [actor.mapId])).rows;
    const wallet = (await connection.query('select silver_coins from masters where id=$1', [actor.masterId])).rows[0];
    const rewards = battles.reduce((sum, battle) => sum + BigInt(battle.settlement.silverReward), 0n);
    if (BigInt(wallet.silver_coins) !== actor.initialSilver + rewards) throw new Error('Silver differs from committed battle rewards.');
    const transactions = (await connection.query("select reference_id,amount_delta from currency_transactions where master_id=$1 and transaction_type='PVE_MAP_REWARD'", [actor.masterId])).rows;
    if (new Set(transactions.map(row => row.reference_id)).size !== transactions.length) throw new Error('A battle has duplicate currency transactions.');
    if (transactions.reduce((sum, row) => sum + BigInt(row.amount_delta), 0n) !== rewards) throw new Error('Currency ledger and battle reports disagree.');
    if (new Set(map.collected).size !== map.collected.length || new Set(map.cleared).size !== map.cleared.length) throw new Error('Map node rewards were duplicated.');
    const expected = { FOOD: 9970, WOOD: 0, STONE: 0 };
    for (const id of map.collected) {
      const resource = map.layout.tiles[id].resource;
      if (!resource) throw new Error('Collected node lacks its persisted reward.');
      expected[resource.itemId] += resource.quantity;
    }
    const items = (await connection.query("select item_id,quantity from master_items where master_id=$1 and item_id in ('FOOD','WOOD','STONE')", [actor.masterId])).rows;
    for (const [item, quantity] of Object.entries(expected)) if ((items.find(row => row.item_id === item)?.quantity ?? 0) !== quantity) throw new Error(`Resource balance mismatch: ${item}.`);
    const world = (await connection.query('select current_floor from worlds where id=$1', [map.world_id])).rows[0];
    if (world.current_floor !== (map.status === 'CLEARED' ? 2 : 1)) throw new Error('World floor disagrees with the completed boss.');
    if (map.status === 'CLEARED') {
      const reservations = (await connection.query('select hero_id from pve_hero_reservations where map_id=$1', [actor.mapId])).rows;
      if (reservations.length) throw new Error('Completed map retained Hero reservations.');
    }
    await connection.query('commit');
    metrics.audited++;
    return map;
  } catch (error) {
    await connection.query('rollback');
    throw error;
  } finally { connection.release(); }
}

async function retire(actor, cleared) {
  await audit(actor);
  await cleanupAccount(actor.accountId);
  if ((await sql('select id from accounts where id=$1', [actor.accountId])).rowCount) throw new Error('Soak account cleanup failed.');
  actor.retired = true;
  if (cleared) metrics.mapsCleared++;
}

async function tick(actor) {
  const state = await request(`/api/pve/state?mapId=${actor.mapId}&cursor=${actor.cursor}`, { token: actor.token });
  if (state.status === 0) return;
  if (state.status !== 200) throw new Error(`State failed: ${JSON.stringify(state.body)}`);
  if (state.body.map.revision < actor.lastRevision) throw new Error('Map revision went backwards after a restart.');
  if (state.body.map.revision !== actor.lastRevision) actor.lastProgressAt = Date.now();
  actor.lastRevision = state.body.map.revision;
  actor.cursor = state.body.cursor;
  if (state.body.map.status === 'CLEARED') return retire(actor, true);
  if (Date.now() - actor.lastProgressAt > 90_000) throw new Error('A squad remained stalled without an authoritative update.');
  for (const [index, squad] of state.body.squads.filter(row => ['IDLE', 'MOVING', 'FIGHTING'].includes(row.status)).entries()) {
    let pending = actor.pending.get(squad.id);
    if (!pending && squad.status !== 'IDLE') continue;
    if (!pending) {
      // Three routes share some cells on purpose, exercising resource/enemy collisions.
      const destination = index === 1
        ? squad.y < 11 ? { x: squad.x, y: squad.y + 1 } : { x: squad.x + 1, y: squad.y }
        : index === 2 && squad.y < squad.x ? { x: squad.x, y: squad.y + 1 }
          : squad.x < 11 ? { x: squad.x + 1, y: squad.y } : { x: squad.x, y: squad.y + 1 };
      if (destination.x > 11 || destination.y > 11) continue;
      pending = { key: randomUUID(), destination };
      actor.pending.set(squad.id, pending);
    }
    const endpoint = `/api/pve/squads/${squad.id}/move`;
    const first = command(actor, endpoint, pending.destination, pending.key);
    const responses = ++serial % 4 === 0
      ? await Promise.all([first, command(actor, endpoint, pending.destination, pending.key)]) : [await first];
    const success = responses.find(response => response.status === 200);
    if (success) {
      if (responses.every(response => response.status === 200) && responses.length === 2) {
        deepStrictEqual(responses[0].body, responses[1].body, 'Duplicate command replies differ.');
        metrics.duplicateReplies++;
      }
      actor.pending.delete(squad.id); metrics.acceptedCommands++;
    } else if (responses.some(response => response.status >= 400 && response.status < 500)) {
      const response = responses.find(value => value.status >= 400 && value.status < 500);
      if (!['ERR_PVE_SQUAD_WITHDRAWN', 'ERR_PVE_MAP_CLEARED', 'ERR_PVE_ALREADY_AT_DESTINATION'].includes(response.body.error)) {
        throw new Error(`Movement rejected: ${JSON.stringify(response.body)}`);
      }
      actor.pending.delete(squad.id);
    }
  }
}

function report() {
  const samples = [...metrics.rttMs].sort((a, b) => a - b);
  const result = { ...metrics, rttMs: undefined, elapsedSeconds: Math.round((Date.now() - startedAt) / 1000),
    p95Ms: samples[Math.floor(samples.length * 0.95)] ?? null, livePlayers: active.filter(actor => !actor.retired).length };
  writeFileSync('logs/pve-soak-summary.json', JSON.stringify(result, null, 2));
  console.log('[pve-soak]', JSON.stringify(result));
}

try {
  await startServer();
  for (let index = 0; index < players; index++) active.push(await createActor());
  let nextReport = Date.now();
  while (!stopping && Date.now() < deadline) {
    if (Date.now() >= restartAt) {
      // Kill a real API process while existing, persisted routes are in flight.
      await stopServer(true); await startServer(); metrics.restarts++;
    }
    await Promise.all(active.filter(actor => !actor.retired).map(async actor => {
      try { await tick(actor); }
      catch (error) {
        const debug = (await sql('select layout,discovered,collected,cleared,status from pve_maps where id=$1', [actor.mapId])).rows;
        writeFileSync(`logs/pve-soak-failure-${actor.masterId}.json`, JSON.stringify({ error: error.message, mapId: actor.mapId, debug }, null, 2));
        throw error;
      }
    }));
    for (let index = 0; index < active.length; index++) if (active[index].retired && Date.now() < deadline && !stopping) active[index] = await createActor();
    if (Date.now() >= nextReport) { report(); nextReport = Date.now() + 30_000; }
    await delay(2000);
  }
} catch (error) {
  metrics.failures++;
  console.error('[pve-soak]', error.message);
  process.exitCode = 1;
} finally {
  await stopServer();
  for (const actor of active.filter(value => !value.retired)) {
    try { await retire(actor, false); }
    catch (error) { metrics.failures++; process.exitCode = 1; console.error('[pve-soak audit]', error.message); }
  }
  report();
  await pool.end();
}
