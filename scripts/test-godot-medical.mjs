import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { buildNow, cleanupAccount, createHero, createMaster, dbReady, grantItems, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL is required for medical gameplay checks.');
  harness = await startHarness();
  const master = await createMaster(harness.request, 'godotmedical'); accountId = master.accountId;
  await sql('update worlds set current_floor=4 where master_id=$1', [master.masterId]);
  await sql('update masters set silver_coins=200000 where id=$1', [master.masterId]);
  await buildNow(harness.request, master, 'MEDICAL', 1);
  await grantItems(master.masterId, { MEDICINE: 2 });
  const heroes = [];
  for (let i = 0; i < 3; i++) heroes.push(await createHero(master.masterId, { name: `Patient ${i}`, hp: 30, maxHp: 100 }));
  const env = { ...process.env, MEDICAL_TEST_URL: harness.base, MEDICAL_TEST_TOKEN: master.token,
    MEDICAL_TEST_MASTER: master.masterId, MEDICAL_TEST_HERO_IDS: JSON.stringify(heroes.map(h => h.id)) };
  const code = await new Promise((resolveExit, reject) => {
    const child = spawn(process.env.GODOT_BIN || 'godot', ['--headless', '--path', resolve('client-godot'), 'res://tests/medical_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let output = '', errors = '';
    const timeout = setTimeout(() => { child.kill(); reject(new Error('Medical Godot checks timed out.')); }, 60000);
    child.stdout.on('data', data => { output += data; process.stdout.write(data); });
    child.stderr.on('data', data => { errors += data; process.stderr.write(data); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', error => { clearTimeout(timeout); reject(error); });
    child.once('exit', code => { clearTimeout(timeout); resolveExit(code === 0 && output.includes('MEDICAL_NETWORK_TESTS:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1); });
  });
  process.exitCode = code;
} catch (error) {
  console.error(error); process.exitCode = 1;
} finally {
  if (accountId) await cleanupAccount(accountId);
  if (harness) await harness.close();
  await pool.end();
}
