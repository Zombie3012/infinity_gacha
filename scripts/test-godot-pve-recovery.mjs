import assert from 'node:assert/strict';
import { fork, spawn } from 'node:child_process';
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { resolve } from 'node:path';

process.env.NODE_ENV = 'test';
const { cleanupAccount, createHero, createMaster, grantItems, pool, sql, startHarness, dbReady } =
  await import('../packages/server/tests/helpers/harness.mjs');
if (!dbReady) throw new Error('PostgreSQL is required for the recovery test.');
const fixtures = [];
let setup;
let worker;
let proxy;
let upstream = '';
let dropEndpoint = '';
let delayState = false;

async function startApi() {
  worker = fork(resolve('scripts/pve-test-server.mjs'), [], { windowsHide: true,
    env: { ...process.env, PVE_TEST_USE_CURRENT_BUILD: '1' }, stdio: ['ignore', 'pipe', 'pipe', 'ipc'] });
  worker.stdout.on('data', data => process.stdout.write(data));
  worker.stderr.on('data', data => process.stderr.write(data));
  upstream = await new Promise((resolvePort, reject) => {
    const timeout = setTimeout(() => reject(new Error('Recovery API did not start.')), 10_000);
    worker.once('message', message => { clearTimeout(timeout); resolvePort(`http://127.0.0.1:${message.port}`); });
    worker.once('error', error => { clearTimeout(timeout); reject(error); });
  });
}

async function stopApi() {
  if (!worker || worker.exitCode !== null) return;
  const current = worker;
  await new Promise(resolveStop => {
    const timeout = setTimeout(() => { current.kill(); resolveStop(); }, 3000);
    current.once('exit', () => { clearTimeout(timeout); resolveStop(); });
    current.send('stop');
  });
  worker = null;
}

function runEngine(phase, environment) {
  return new Promise((resolveRun, reject) => {
    const child = spawn(process.env.GODOT_BIN || 'godot', ['--headless', '--path', resolve('client-godot'),
      'res://tests/pve_recovery_test.tscn'], { windowsHide: true, env: { ...process.env, ...environment, PVE_TEST_PHASE: phase }, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    let errors = '';
    const timeout = setTimeout(() => { child.kill(); reject(new Error(`Godot recovery phase ${phase} timed out.`)); }, 35_000);
    child.stdout.on('data', chunk => { output += chunk.toString(); process.stdout.write(chunk); });
    child.stderr.on('data', chunk => {
      errors += chunk.toString(); process.stderr.write(chunk);
      if (/SCRIPT ERROR: (Parse|Compile) Error|Failed to load script/.test(errors)) child.kill();
    });
    child.once('error', error => { clearTimeout(timeout); reject(error); });
    child.once('exit', code => {
      clearTimeout(timeout);
      if (code === 0 && output.includes(`PVE_RECOVERY_TESTS: ${phase}`) && !/SCRIPT ERROR:|^ERROR:/m.test(errors)) resolveRun();
      else reject(new Error(`Godot recovery phase ${phase} failed.`));
    });
  });
}

try {
  setup = await startHarness();
  const master = await createMaster(setup.request, 'recoverpve'); fixtures.push(master);
  const other = await createMaster(setup.request, 'otherpve'); fixtures.push(other);
  await grantItems(master.masterId, { FOOD: 1000 });
  const hero = await createHero(master.masterId);
  const saved = await setup.request('/api/pve/parties', { method: 'POST', token: master.token,
    headers: { 'Idempotency-Key': randomUUID() }, body: { name: 'Recovery Squad', heroIds: [hero.id] } });
  assert.equal(saved.status, 201);
  assert.equal((await setup.request('/api/pve/enter', { method: 'POST', token: master.token,
    headers: { 'Idempotency-Key': randomUUID() }, body: {} })).status, 201);
  await setup.close(); setup = null;
  await startApi();
  proxy = http.createServer((request, response) => {
    if (request.url.startsWith('/__pve_test/')) {
      let body = '';
      request.on('data', chunk => { body += chunk; });
      request.on('end', () => {
        if (request.url === '/__pve_test/drop-next') dropEndpoint = JSON.parse(body).endpoint;
        if (request.url === '/__pve_test/delay-next-state') delayState = true;
        response.writeHead(200, { 'Content-Type': 'application/json' }); response.end('{}');
      });
      return;
    }
    const drop = request.url === dropEndpoint;
    if (drop) dropEndpoint = '';
    const delayed = delayState && request.url.startsWith('/api/pve/state');
    if (delayed) delayState = false;
    const forwarding = http.request(upstream + request.url, { method: request.method,
      headers: { ...request.headers, host: new URL(upstream).host } }, incoming => {
      const chunks = [];
      incoming.on('data', chunk => chunks.push(chunk));
      incoming.on('end', () => {
        const deliver = () => {
          if (drop) { response.destroy(); return; }
          response.writeHead(incoming.statusCode, incoming.headers); response.end(Buffer.concat(chunks));
        };
        if (delayed) setTimeout(deliver, 400); else deliver();
      });
    });
    forwarding.on('error', () => { response.writeHead(502); response.end('{}'); });
    request.pipe(forwarding);
  });
  await new Promise(resolveListen => proxy.listen(0, '127.0.0.1', resolveListen));
  const environment = { PVE_TEST_API_URL: `http://127.0.0.1:${proxy.address().port}`,
    PVE_TEST_ACCESS_TOKEN: master.token, PVE_TEST_MASTER_ID: master.masterId, PVE_TEST_PARTY_ID: saved.body.partyId,
    PVE_TEST_OTHER_TOKEN: other.token, PVE_TEST_OTHER_MASTER_ID: other.masterId };
  await runEngine('ambiguous', environment);
  assert.equal((await sql('select count(*)::int n from pve_squads where master_id=$1', [master.masterId])).rows[0].n, 1);
  await stopApi(); await startApi();
  await runEngine('resume', environment);
  await stopApi(); await startApi();
  await new Promise(resolveArrival => setTimeout(resolveArrival, 1200));
  await runEngine('offline', environment);
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'", [master.masterId])).rows[0].quantity, 990);
  assert.equal((await sql("select count(*)::int n from pve_commands where master_id=$1 and operation like 'DEPLOY:%'", [master.masterId])).rows[0].n, 1);
  console.log('PVE_RECOVERY_RUNNER: three client processes, two API restarts, PASS');
} catch (error) {
  console.error('[pve-recovery]', error.message); process.exitCode = 1;
} finally {
  if (proxy) await new Promise(resolveClose => { proxy.closeAllConnections(); proxy.close(resolveClose); });
  await stopApi();
  if (setup) await setup.close();
  for (const fixture of fixtures) {
    await cleanupAccount(fixture.accountId);
    assert.equal((await sql('select id from accounts where id=$1', [fixture.accountId])).rowCount, 0);
  }
  await pool.end();
}
