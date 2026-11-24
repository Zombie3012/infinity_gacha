import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountA, accountB;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();

  const mA = await createMaster(harness.request, 'friendA');
  const mB = await createMaster(harness.request, 'friendB');
  accountA = mA.accountId;
  accountB = mB.accountId;

  const mBRow = await sql('select master_name from masters where id=$1', [mB.masterId]);
  const nameB = mBRow.rows[0]?.master_name || mB.masterId;

  const env = {
    ...process.env,
    FRIENDS_TEST_URL: harness.base,
    FRIENDS_TOKEN_A: mA.token,
    FRIENDS_MASTER_A: mA.masterId,
    FRIENDS_TOKEN_B: mB.token,
    FRIENDS_MASTER_B: mB.masterId,
    FRIENDS_NAME_B: nameB,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/friends_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Friends test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('FRIENDS_NETWORK:') && output.includes('PASS') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
    });
  });
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  if (accountA) await cleanupAccount(accountA);
  if (accountB) await cleanupAccount(accountB);
  if (harness) await harness.close();
  await pool.end();
}
