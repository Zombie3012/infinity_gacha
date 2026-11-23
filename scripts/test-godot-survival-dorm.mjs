import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { cleanupAccount, createHero, createMaster, dbReady, grantItems, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL required');
  harness = await startHarness();
  const m = await createMaster(harness.request, 'godotsd');
  accountId = m.accountId;
  await sql('update masters set level=10, silver_coins=100000 where id=$1', [m.masterId]);
  await grantItems(m.masterId, { WOOD: 200, STONE: 200, FOOD_RAW: 20, FOOD: 20, MOON_CAKE: 5 });

  const kitchen = await harness.request('/api/base/buildings', {
    token: m.token, method: 'POST', body: { buildingType: 'KITCHEN', plotIndex: 1 },
  });
  const dorm = await harness.request('/api/base/buildings', {
    token: m.token, method: 'POST', body: { buildingType: 'HOUSE', plotIndex: 2 },
  });
  if (kitchen.status !== 201 || dorm.status !== 201) throw new Error('Failed to build kitchen/dorm: ' + JSON.stringify({ kitchen, dorm }));

  const tired = await createHero(m.masterId, { name: 'Tired Hero', rarity: 3 });
  const fresh = await createHero(m.masterId, { name: 'Fresh Hero', rarity: 3 });
  const persInit = await harness.request('/api/personality', { token: m.token });
  const persList = Array.isArray(persInit.body) ? persInit.body : (persInit.body?.profiles || persInit.body?.heroes || persInit.body?.items || []);
  const tiredPers = persList.find((h) => h.heroId === tired.id || h.id === tired.id);
  const favMeal = tiredPers?.favoriteMeal || tiredPers?.favoriteMealCode || tiredPers?.personality?.favoriteMeal;
  if (favMeal) {
    await grantItems(m.masterId, { [favMeal]: 5 });
  } else {
    await grantItems(m.masterId, { MOON_CAKE: 5, ROAST_CHICKEN: 5, SPICED_STEW: 5, HERBAL_SOUP: 5, GRILLED_FISH: 5 });
  }
  await sql(`
    insert into hero_survival_states (hero_instance_id, fatigue_score, hunger_score)
    values ($1, 65, 70), ($2, 0, 10)
    on conflict (hero_instance_id) do update set fatigue_score = excluded.fatigue_score, hunger_score = excluded.hunger_score
  `, [tired.id, fresh.id]);

  const env = {
    ...process.env,
    SD_TEST_URL: harness.base,
    SD_TEST_TOKEN: m.token,
    SD_TEST_MASTER: m.masterId,
    SD_KITCHEN_ID: kitchen.body.building.id,
    SD_DORM_ID: dorm.body.building.id,
    SD_HERO_TIRED: tired.id,
    SD_HERO_FRESH: fresh.id,
  };

  process.exitCode = await new Promise((done, reject) => {
    const child = spawn(
      process.env.GODOT_BIN || 'godot',
      ['--headless', '--path', resolve('client-godot'), 'res://tests/survival_dorm_network_test.tscn'],
      { env, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let output = '', errors = '';
    const timer = setTimeout(() => { child.kill(); reject(new Error('Survival/Dorm test timed out')); }, 60000);
    child.stdout.on('data', (d) => { output += d; process.stdout.write(d); });
    child.stderr.on('data', (d) => { errors += d; process.stderr.write(d); if (/SCRIPT ERROR:/.test(errors)) child.kill(); });
    child.once('error', (e) => { clearTimeout(timer); reject(e); });
    child.once('exit', (code) => {
      clearTimeout(timer);
      done(code === 0 && output.includes('SURVIVAL_DORM_NETWORK:') && !/SCRIPT ERROR:|^ERROR:/m.test(errors) ? 0 : 1);
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
