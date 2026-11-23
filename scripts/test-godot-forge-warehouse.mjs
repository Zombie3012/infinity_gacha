import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createHero, createMaster, dbReady, grantItems, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godotfw');
  accountId = m.accountId;
  await sql('update masters set level=15, silver_coins=500000 where id=$1', [m.masterId]);
  const built = await harness.request('/api/base/buildings', {
    token: m.token,
    method: 'POST',
    body: { buildingType: 'FORGE', plotIndex: 1 },
  });
  if (built.status !== 201) throw new Error(JSON.stringify(built));
  const hero = await createHero(m.masterId, { name: 'Forge Hero', rarity: 3 });
  await grantItems(m.masterId, {
    WOOD: 200,
    STONE: 200,
    IRON: 200,
    IRON_ORE: 200,
    ENHANCEMENT_STONE: 100,
    SAMPLE_TRASH_DULL_SHARD: 20,
  });

  const env = {
    ...process.env,
    FW_TEST_URL: harness.base,
    FW_TEST_TOKEN: m.token,
    FW_TEST_MASTER: m.masterId,
    FW_TEST_FORGE: built.body.building.id,
    FW_TEST_HERO: hero.id,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/forge_warehouse_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Forge/Warehouse test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('FORGE_WAREHOUSE_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
    });
  });
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  if (accountId) await cleanupAccount(accountId);
  if (harness) await harness.close();
  await pool.end();
}
