import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
const testBannerIds = ['TEST_BANNER_NORMAL', 'TEST_BANNER_SPECIAL'];
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godotgacha');
  accountId = m.accountId;
  await sql('update masters set level=10, silver_coins=50000, gems=150 where id=$1', [m.masterId]);

  // Seed temporary active NORMAL and SPECIAL banners for deterministic testing
  await sql(`
    insert into banners (id, name, banner_type, is_active, start_date, end_date)
    values
      ('TEST_BANNER_NORMAL', 'Test Normal Banner', 'NORMAL', true, now() - interval '1 day', now() + interval '7 days'),
      ('TEST_BANNER_SPECIAL', 'Test Special Banner', 'SPECIAL', true, now() - interval '1 day', now() + interval '7 days')
    on conflict (id) do update set is_active = true, start_date = now() - interval '1 day', end_date = now() + interval '7 days'
  `);
  await sql(`
    insert into summon_reward_pool (id, banner_id, reward_type, reward_id, reward_name, pool_group, rarity, weight, is_active)
    values
      ('TEST_POOL_N_H', 'TEST_BANNER_NORMAL', 'HERO', 'PROCEDURAL', 'Hero Thường 2★', 'HERO', 2, 50, true),
      ('TEST_POOL_N_M', 'TEST_BANNER_NORMAL', 'MATERIAL', 'WOOD', 'Gỗ Sồi', 'MATERIAL', 1, 50, true),
      ('TEST_POOL_S_H', 'TEST_BANNER_SPECIAL', 'HERO', 'PROCEDURAL', 'Hero Hiếm 4★', 'HERO', 4, 60, true),
      ('TEST_POOL_S_M', 'TEST_BANNER_SPECIAL', 'MATERIAL', 'ENHANCEMENT_STONE', 'Đá Cường Hóa', 'MATERIAL', 2, 40, true)
    on conflict (id) do nothing
  `);

  const env = {
    ...process.env,
    GACHA_TEST_URL: harness.base,
    GACHA_TEST_TOKEN: m.token,
    GACHA_TEST_MASTER: m.masterId,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/gacha_flow_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Gacha test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('GACHA_FLOW_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
    });
  });
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  if (accountId) await cleanupAccount(accountId);
  await sql('delete from summon_reward_pool where banner_id = any($1)', [testBannerIds]).catch(() => {});
  await sql('delete from banners where id = any($1)', [testBannerIds]).catch(() => {});
  if (harness) await harness.close();
  await pool.end();
}
