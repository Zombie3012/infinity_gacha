import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountA, accountB;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();

  const mA = await createMaster(harness.request, 'chatA');
  const mB = await createMaster(harness.request, 'chatB');
  accountA = mA.accountId;
  accountB = mB.accountId;

  await sql('update masters set level=30, silver_coins=1000000, gems=5000 where id=$1', [mA.masterId]);
  const alRes = await harness.request('/api/alliance', {
    token: mA.token,
    method: 'POST',
    body: { name: 'Chat Test Guild', tag: 'CTG' },
  });
  if (alRes.status !== 201) throw new Error('Failed to create alliance for chat test: ' + JSON.stringify(alRes));

  const mBRow = await sql('select master_name from masters where id=$1', [mB.masterId]);
  const peerName = mBRow.rows[0]?.master_name || mB.masterId;

  const env = {
    ...process.env,
    CHAT_TEST_URL: harness.base,
    CHAT_TEST_TOKEN: mA.token,
    CHAT_TEST_MASTER: mA.masterId,
    CHAT_PEER_NAME: peerName,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/chat_channels_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Chat test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('CHAT_CHANNELS_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
