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
      done(code === 0 && output.includes('CHAT_CHANNELS_NETWORK:') && output.includes('PASS') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
    });
  });

  if (process.exitCode === 0) {
    // Verify WORLD channel was NOT persisted to PostgreSQL, while PRIVATE was persisted
    const worldDb = await sql("select count(*)::int as cnt from chat_messages where channel = 'WORLD' and sender_master_id = $1", [mA.masterId]);
    if ((worldDb.rows[0]?.cnt ?? 0) !== 0) {
      throw new Error('WORLD chat must not persist to PostgreSQL');
    }
    const privDb = await sql("select count(*)::int as cnt from chat_messages where channel = 'PRIVATE' and sender_master_id = $1", [mA.masterId]);
    if ((privDb.rows[0]?.cnt ?? 0) < 1) {
      throw new Error('PRIVATE chat must persist to PostgreSQL');
    }
    // Verify GET /api/chat/stream SSE endpoint delivers real-time event
    const ac = new AbortController();
    const sseRes = await fetch(`${harness.base}/api/chat/stream`, {
      headers: { Authorization: `Bearer ${mB.token}` },
      signal: ac.signal,
    });
    if (!sseRes.ok || !sseRes.headers.get('content-type')?.includes('text/event-stream')) {
      throw new Error('SSE stream endpoint failed');
    }
    const reader = sseRes.body.getReader();
    const dec = new TextDecoder();
    await harness.request('/api/chat/private', {
      token: mA.token,
      method: 'POST',
      body: { recipientMasterId: mB.masterId, body: 'SSE Live Ping' },
    });
    let sseText = '';
    for (let i = 0; i < 6; i++) {
      const { value, done } = await reader.read();
      if (done) break;
      sseText += dec.decode(value, { stream: true });
      if (sseText.includes('SSE Live Ping')) break;
    }
    ac.abort();
    if (!sseText.includes('SSE Live Ping')) {
      throw new Error('SSE stream did not receive real-time message');
    }
    console.log('CHAT_SSE_AND_STORAGE_POLICY: PASS');
  }
} catch (e) {
  console.error(e);
  process.exitCode = 1;
} finally {
  if (accountA) await cleanupAccount(accountA);
  if (accountB) await cleanupAccount(accountB);
  if (harness) await harness.close();
  await pool.end();
}
