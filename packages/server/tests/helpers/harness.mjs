/**
 * Shared harness for HTTP-level integration tests.
 *
 * Each test file boots the real Express app in-process, registers its own
 * account (so files never fight over fixtures) and removes it afterwards.
 * When PostgreSQL is unreachable every suite skips instead of failing, so the
 * unit tests stay usable on a bare machine.
 */
process.env.NODE_ENV = 'test';

const { pool } = await import('../../dist/database/db.js');
const { createApp } = await import('../../dist/server.js');

export const dbReady = await pool
  .query('select 1')
  .then(() => true)
  .catch(() => false);

if (!dbReady) await pool.end().catch(() => {});

export const skipReason = dbReady ? false : 'PostgreSQL is not reachable';

export async function startHarness() {
  const app = createApp();
  const server = app.listen(0);
  await new Promise(resolve => server.once('listening', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const adminKey = process.env.ADMIN_API_KEY ?? '';

  const request = async (path, options = {}) => {
    const { method = 'GET', token, admin = false, body, headers = {} } = options;
    const response = await fetch(`${base}${path}`, {
      method,
      headers: {
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(admin ? { 'x-admin-api-key': adminKey, 'x-operator-id': 'ACT-04' } : {}),
        ...headers,
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    const payload = await response.json().catch(() => ({}));
    return { status: response.status, body: payload };
  };

  const close = async () => {
    await new Promise(resolve => server.close(resolve));
  };

  return { base, request, close, adminKey };
}

let counter = 0;

export async function createMaster(request, prefix = 'it') {
  counter += 1;
  const username = `${prefix}${Date.now().toString(36)}${counter}${Math.floor(Math.random() * 90 + 10)}`.slice(0, 32).toLowerCase();
  const registered = await request('/api/auth/register', { method: 'POST', body: { username, password: 'Password123!' } });
  if (registered.status !== 201) throw new Error(`register failed: ${registered.status} ${JSON.stringify(registered.body)}`);
  const token = registered.body.accessToken;
  const master = await request('/api/master/init', { method: 'POST', token, body: { masterName: 'Integration Master' } });
  if (master.status !== 201) throw new Error(`master init failed: ${master.status} ${JSON.stringify(master.body)}`);
  return { username, token, accountId: registered.body.accountId, masterId: master.body.id };
}

export async function cleanupAccount(accountId) {
  if (!accountId) return;
  await pool.query('delete from accounts where id = $1', [accountId]).catch(() => {});
}

export async function sql(query, params = []) {
  return pool.query(query, params);
}

/** Fast-forward a building timer so the next read settles it. */
export async function finishBuildings(masterId) {
  await sql(`update base_buildings set upgrade_finishes_at = now() - interval '1 minute'
             where master_id = $1 and status in ('CONSTRUCTING', 'UPGRADING')`, [masterId]);
}

export async function grantItems(masterId, entries) {
  for (const [itemId, quantity] of Object.entries(entries)) {
    await sql(`insert into master_items (id, master_id, item_id, quantity, updated_at)
               values (gen_random_uuid()::text, $1, $2, $3, now())
               on conflict (master_id, item_id) do update set quantity = $3, updated_at = now()`,
      [masterId, itemId, quantity]);
  }
}

export async function setSilver(masterId, amount) {
  await sql('update masters set silver_coins = $2, gems = 0, gem_debt = 0 where id = $1', [masterId, amount]);
}

export { pool };

/** Insert a bare Hero row (tests that need a body but not the gacha flow). */
export async function createHero(masterId, overrides = {}) {
  const template = await pool.query('select code from hero_templates order by code limit 1');
  const code = template.rows[0]?.code;
  if (!code) throw new Error('no hero templates seeded');
  const id = (await pool.query('select gen_random_uuid()::text as id')).rows[0].id;
  const hero = {
    name: 'IT Hero', rarity: 3, category: 'NORMAL', hp: 500, maxHp: 500,
    attack: 60, defense: 40, speed: 25, ...overrides,
  };
  await pool.query(
    `insert into heroes (id, master_id, config_id, name, rarity, category, state, level, exp, hp, max_hp,
       attack, defense, speed, talent_points, thien_menh, hunger, fatigue, loyalty, created_at, updated_at)
     values ($1,$2,$3,$4,$5,$6,'HEALTHY',1,0,$7,$8,$9,$10,$11,0,0,0,0,100,now(),now())`,
    [id, masterId, code, hero.name, hero.rarity, hero.category, hero.hp, hero.maxHp, hero.attack, hero.defense, hero.speed],
  );
  return { id, ...hero, configId: code };
}

/** Build and instantly finish a production/utility building. */
export async function buildNow(request, master, buildingType, plotIndex = 1) {
  const built = await request('/api/base/buildings', {
    method: 'POST', token: master.token, body: { buildingType, plotIndex },
  });
  if (built.status !== 201) throw new Error(`build ${buildingType} failed: ${built.status} ${JSON.stringify(built.body)}`);
  await finishBuildings(master.masterId);
  return built.body.building;
}
