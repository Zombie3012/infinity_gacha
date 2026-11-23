import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createHero, createMaster, dbReady, grantItems, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godothd');
  accountId = m.accountId;
  await sql('update masters set level=15, silver_coins=200000 where id=$1', [m.masterId]);
  const hero = await createHero(m.masterId, { name: 'Dev Hero', rarity: 3 });
  await grantItems(m.masterId, { SAMPLE_HERO_EXP_100: 5, SAMPLE_HERO_PROMOTION_SEAL: 5 });

  const env = {
    ...process.env,
    HD_TEST_URL: harness.base,
    HD_TEST_TOKEN: m.token,
    HD_TEST_MASTER: m.masterId,
    HD_HERO_ID: hero.id,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/hero_dev_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Hero dev test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('HERO_DEV_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
