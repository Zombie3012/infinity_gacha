import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { v4 as uuidv4 } from 'uuid';
import { cleanupAccount, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godotmb');
  accountId = m.accountId;

  await sql(
    `insert into mailbox_messages (id, master_id, subject, body, attachments, expires_at, created_at)
     values ($1, $2, 'Quà Thử Nghiệm', 'Chúc mừng Master!', '{"silver":5000}'::jsonb, now() + interval '7 days', now())`,
    [uuidv4(), m.masterId],
  );

  const env = {
    ...process.env,
    MB_TEST_URL: harness.base,
    MB_TEST_TOKEN: m.token,
    MB_TEST_MASTER: m.masterId,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/mailbox_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Mailbox test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('MAILBOX_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
