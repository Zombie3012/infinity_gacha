import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

const binary = process.env.GODOT_BIN || 'godot';
const project = resolve('client-godot');
const integration = process.argv.includes('--integration');
const scene = integration ? 'res://tests/pve_network_test.tscn' : 'res://tests/pve_ui_test.tscn';
const environment = { ...process.env };
let cleanup = async () => {};
let inspectFailure = async () => {};

try {
  if (integration) {
    const { cleanupAccount, createHero, createMaster, grantItems, pool, sql, startHarness, dbReady } =
      await import('../packages/server/tests/helpers/harness.mjs');
    if (!dbReady) throw new Error('PostgreSQL is required for the Godot integration test.');
    const harness = await startHarness();
    let accountId;
    cleanup = async () => {
      if (accountId) {
        await cleanupAccount(accountId);
        const remains = await sql('select id from accounts where id=$1', [accountId]);
        if (remains.rows.length) throw new Error('Godot test account cleanup failed.');
      }
      await harness.close();
      await pool.end();
    };
    const master = await createMaster(harness.request, 'godotpve');
    accountId = master.accountId;
    inspectFailure = async () => {
      const squads = await sql('select name, status, x, y, route, next_step_at, last_battle_id from pve_squads where master_id=$1', [master.masterId]);
      const commands = await sql('select operation, result from pve_commands where master_id=$1 order by created_at', [master.masterId]);
      console.error('[pve-godot] failure state:', JSON.stringify({ squads: squads.rows, commands: commands.rows }));
    };
    await sql('update worlds set difficulty_multiplier=1 where master_id=$1', [master.masterId]);
    await grantItems(master.masterId, { FOOD: 1000, WOOD: 0 });
    const heroes = [];
    for (let index = 0; index < 2; index++) heroes.push(await createHero(master.masterId, {
      name: `Engine Vanguard ${index}`, hp: 90000, maxHp: 90000, attack: 8000, defense: 3000, speed: 200,
    }));
    const entered = await harness.request('/api/pve/enter', { method: 'POST', token: master.token, headers: { 'Idempotency-Key': 'godot-map-fixture' }, body: {} });
    if (entered.status !== 201) throw new Error(`Could not prepare map: ${JSON.stringify(entered.body)}`);
    const mapId = entered.body.mapId;
    const map = (await sql('select layout from pve_maps where id=$1', [mapId])).rows[0];
    for (const [index, kind] of [[1, 'RESOURCE'], [2, 'ENEMY'], [3, 'BOSS']]) {
      map.layout.tiles[index].kind = kind;
      if (index === 1) map.layout.tiles[index].resource = { itemId: 'WOOD', quantity: 23 };
    }
    await sql('update pve_maps set layout=$2::jsonb where id=$1', [mapId, JSON.stringify(map.layout)]);
    Object.assign(environment, {
      PVE_TEST_API_URL: harness.base,
      PVE_TEST_ACCESS_TOKEN: master.token,
      PVE_TEST_MASTER_ID: master.masterId,
      PVE_TEST_HERO_IDS: JSON.stringify(heroes.map(hero => hero.id)),
    });
  }

  if ((binary.includes('/') || binary.includes('\\')) && !existsSync(binary)) throw new Error('GODOT_BIN does not point to an executable.');
  const exitCode = await new Promise((resolveExit, reject) => {
    const child = spawn(binary, ['--headless', '--path', project, scene], { env: environment, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '';
    let errorOutput = '';
    const timeout = setTimeout(() => { child.kill(); reject(new Error('Godot PvE checks timed out.')); }, integration ? 120_000 : 35_000);
    child.stdout.on('data', chunk => { output += chunk.toString(); process.stdout.write(chunk); });
    child.stderr.on('data', chunk => {
      errorOutput += chunk.toString(); process.stderr.write(chunk);
      if (/SCRIPT ERROR: (Parse|Compile) Error|Failed to load script/.test(errorOutput)) child.kill();
    });
    child.on('error', error => { clearTimeout(timeout); reject(new Error(`Cannot start Godot. Set GODOT_BIN to Godot 4.7.2 or compatible: ${error.message}`)); });
    child.on('exit', code => {
      clearTimeout(timeout);
      // Some Godot script errors leave a zero process exit; require the test's completion marker too.
      const marker = integration ? 'PVE_NETWORK_TESTS:' : 'PVE_UI_TESTS:';
      resolveExit(code === 0 && output.includes(marker) && !/SCRIPT ERROR:|^ERROR:/m.test(errorOutput) ? 0 : 1);
    });
  });
  process.exitCode = exitCode;
  if (exitCode !== 0) await inspectFailure();
} catch (error) {
  console.error(`[pve-godot] ${error.message}`);
  process.exitCode = 1;
} finally {
  await cleanup();
}
