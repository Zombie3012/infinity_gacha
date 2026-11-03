/**
 * HTTP-level smoke test for the P0 API surface.
 *
 * It boots the real Express app in-process and exercises the main player loop
 * plus the DM-14 admin plane. When PostgreSQL is not reachable the whole suite
 * is skipped instead of failing, so unit tests stay usable on a bare machine.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

process.env.NODE_ENV = 'test';

const { pool } = await import('../dist/database/db.js');

const databaseReachable = await pool
  .query('select 1')
  .then(() => true)
  .catch(() => false);

if (!databaseReachable) await pool.end().catch(() => {});

let server;
let base = '';

async function request(path, options = {}) {
  const response = await fetch(`${base}${path}`, options);
  const body = await response.json().catch(() => ({}));
  return { status: response.status, body };
}

test('P0 API smoke', { skip: databaseReachable ? false : 'PostgreSQL is not reachable' }, async t => {
  const { createApp } = await import('../dist/server.js');
  const app = createApp();
  server = app.listen(0);
  await new Promise(resolve => server.once('listening', resolve));
  base = `http://127.0.0.1:${server.address().port}`;

  const username = `smoke${Date.now().toString().slice(-9)}`;
  let accountId = null;
  let createdConfigId = null;

  t.after(async () => {
    if (createdConfigId) {
      await pool.query('delete from system_configs where id = $1', [createdConfigId]).catch(() => {});
    }
    if (accountId) {
      await pool.query('delete from accounts where id = $1', [accountId]).catch(() => {});
    }
    await new Promise(resolve => server.close(resolve));
    await pool.end().catch(() => {});
  });

  await t.test('health reports a connected database', async () => {
    const health = await request('/health');
    assert.equal(health.status, 200);
    assert.equal(health.body.status, 'ok');
    assert.equal(health.body.database, 'connected');
  });

  let token = '';
  await t.test('register, initialize Master and inspect profile', async () => {
    const register = await request('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password: 'Password123!' }),
    });
    assert.equal(register.status, 201);
    accountId = register.body.accountId;
    token = register.body.accessToken;
    assert.ok(token);

    const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };
    const master = await request('/api/master/init', {
      method: 'POST', headers, body: JSON.stringify({ masterName: 'Smoke Master' }),
    });
    assert.equal(master.status, 201);
    assert.equal(master.body.masterName, 'Smoke Master');

    const me = await request('/api/me', { headers });
    assert.equal(me.status, 200);
    assert.equal(me.body.account.username, username);
    assert.ok(me.body.world?.worldSeed);
  });

  await t.test('exchange currency and summon from the seeded banner', async () => {
    const headers = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'Idempotency-Key': `smoke-${Date.now()}`,
    };

    const banners = await request('/api/gacha/banners', { headers });
    assert.equal(banners.status, 200);
    assert.ok(banners.body.length > 0, 'expected at least one active banner seed');
    const bannerId = banners.body[0].id;

    const exchange = await request('/api/economy/exchange-scrolls', {
      method: 'POST', headers, body: JSON.stringify({ amount: 1 }),
    });
    assert.equal(exchange.status, 200);
    assert.equal(exchange.body.silverSpent, '10000');

    const summon = await request('/api/gacha/summon', {
      method: 'POST', headers, body: JSON.stringify({ bannerId, rollCount: 1 }),
    });
    assert.equal(summon.status, 200);
    assert.equal(summon.body.results.length, 1);
    assert.equal(summon.body.scrollsConsumed, 1);

    const replay = await fetch(`${base}/api/gacha/summon`, {
      method: 'POST', headers, body: JSON.stringify({ bannerId, rollCount: 1 }),
    });
    assert.equal(replay.status, 200, 'idempotent replay must not consume another scroll');
  });

  await t.test('admin plane reports health and versions configuration', async adminT => {
    const adminKey = process.env.ADMIN_API_KEY ?? '';
    if (!adminKey) {
      adminT.skip('ADMIN_API_KEY is not configured');
      return;
    }
    const adminHeaders = { 'Content-Type': 'application/json', 'x-admin-api-key': adminKey, 'x-operator-id': 'ACT-06' };

    const monitoring = await request('/api/admin/monitoring', { headers: adminHeaders });
    assert.equal(monitoring.status, 200);
    assert.equal(monitoring.body.status, 'ok');
    assert.ok(monitoring.body.counts.accounts >= 1);

    const created = await request('/api/admin/configs', {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({ configKey: 'SEED_ALGORITHM', configValue: { algorithmVersion: 1 }, updatedBy: 'ACT-06', activate: false }),
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.version, 1);
    createdConfigId = created.body.id;

    const audit = await request('/api/admin/audit-logs?action=CONFIG_VERSION_CREATED&limit=5', { headers: adminHeaders });
    assert.equal(audit.status, 200);
    assert.ok(audit.body.some(row => row.entityId === created.body.id));

    const rejected = await request('/api/admin/configs', {
      method: 'POST',
      headers: adminHeaders,
      body: JSON.stringify({ configKey: 'NOT_A_RULE', configValue: {}, updatedBy: 'ACT-06' }),
    });
    assert.equal(rejected.status, 400);
  });
});
