import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createHero, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godotex');
  accountId = m.accountId;
  await sql('update masters set level=15, silver_coins=50000 where id=$1', [m.masterId]);
  await sql('update worlds set current_floor=26 where master_id=$1', [m.masterId]);
  const hero = await createHero(m.masterId, { name: 'Scout Hero', rarity: 3 });
  const unlockRes = await harness.request('/api/world/global/unlock', { token: m.token, method: 'POST', body: {} });
  if (unlockRes.status >= 400) throw new Error('World unlock failed: ' + JSON.stringify(unlockRes));

  const env = {
    ...process.env,
    EX_TEST_URL: harness.base,
    EX_TEST_TOKEN: m.token,
    EX_TEST_MASTER: m.masterId,
    EX_HERO_ID: hero.id,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/world_expedition_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Expedition test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('WORLD_EXPEDITION_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
