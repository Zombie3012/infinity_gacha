import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();

  // Ensure ALLIANCE_HALL exists in building_types
  await sql(`
    INSERT INTO building_types (code, name, category, description, max_level, max_workers, required_world_level, build_cost_silver, production)
    VALUES ('ALLIANCE_HALL', 'Đại Sảnh Liên Minh', 'UTILITY', 'Hội quán Liên Minh trong Lâu đài.', 1, 0, 1, 1500, NULL)
    ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name
  `);

  const m = await createMaster(harness.request, 'godotal');
  accountId = m.accountId;
  await sql('update masters set level=30, silver_coins=1000000, gems=5000 where id=$1', [m.masterId]);

  const built = await harness.request('/api/base/buildings', {
    token: m.token,
    method: 'POST',
    body: { buildingType: 'ALLIANCE_HALL', plotIndex: 1 },
  });
  if (built.status !== 201) throw new Error('Failed to build ALLIANCE_HALL: ' + JSON.stringify(built));

  const env = {
    ...process.env,
    AL_TEST_URL: harness.base,
    AL_TEST_TOKEN: m.token,
    AL_TEST_MASTER: m.masterId,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/alliance_building_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Alliance test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('ALLIANCE_BUILDING_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
