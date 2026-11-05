import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP combat v2: simulate a battle', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'cv2');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const hero = await createHero(master.masterId, {
    name: 'Vanguard', attack: 8_000, defense: 3_000, speed: 200, hp: 90_000, maxHp: 90_000,
  });
  const enemyCode = (await sql('select code from enemy_templates where is_active = true order by code limit 1')).rows[0].code;

  await t.test('a strong party wins and receives a full battle report', async () => {
    const simulated = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], maxRounds: 10, seed: 42 },
    });
    assert.equal(simulated.status, 200);
    assert.equal(simulated.body.winner, 'HERO');
    assert.ok(simulated.body.rounds >= 1);
    assert.ok(simulated.body.log.length > 0);
    assert.ok(simulated.body.totalDamage > 0);

    const replay = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], maxRounds: 10, seed: 42 },
    });
    assert.equal(replay.status, 200);
    assert.deepEqual(
      replay.body.log.map(entry => entry.damage),
      simulated.body.log.map(entry => entry.damage),
    );
  });

  await t.test('battle reports can be persisted and listed', async () => {
    await sql(`insert into worlds (id, master_id, world_seed, seed_algorithm_version, difficulty_multiplier, current_floor, base_zones, created_at)
               values (gen_random_uuid()::text, $1, gen_random_uuid()::text, 1, 1, 1, 1, now())`, [master.masterId]);
    const persisted = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], seed: 7, persist: true },
    });
    assert.equal(persisted.status, 200);
    assert.ok(persisted.body.sessionId);

    const list = await harness.request('/api/combat/v2/sessions', { token: master.token });
    assert.equal(list.status, 200);
    assert.equal(list.body[0].id, persisted.body.sessionId);
    assert.equal(list.body[0].status, 'COMPLETED');
  });

  await t.test('two-step session resolves and pays Silver', async () => {
    const before = Number((await sql('select silver_coins from masters where id = $1', [master.masterId])).rows[0].silver_coins);
    const started = await harness.request('/api/combat/v2/session/start', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], seed: 11 },
    });
    assert.equal(started.status, 201);
    assert.equal(started.body.status, 'ACTIVE');

    const advanced = await harness.request(`/api/combat/v2/session/${started.body.sessionId}/advance`, {
      method: 'POST', token: master.token,
    });
    assert.equal(advanced.status, 200);
    assert.equal(advanced.body.status, 'COMPLETED');
    assert.equal(advanced.body.report.winner, 'HERO');
    assert.ok(advanced.body.silverReward > 0);

    const after = Number((await sql('select silver_coins from masters where id = $1', [master.masterId])).rows[0].silver_coins);
    assert.ok(after > before);

    const replay = await harness.request(`/api/combat/v2/session/${started.body.sessionId}/advance`, {
      method: 'POST', token: master.token,
    });
    assert.equal(replay.status, 409);
    assert.equal(replay.body.error, 'ERR_COMBAT_V2_SESSION_FINISHED');
  });

  await t.test('concurrent advances pay the reward only once', async () => {
    const started = await harness.request('/api/combat/v2/session/start', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], seed: 21 },
    });
    assert.equal(started.status, 201);
    const before = await sql(`select count(*)::int as total from currency_transactions
                              where master_id = $1 and transaction_type = 'COMBAT_V2_REWARD'`, [master.masterId]);

    const [first, second] = await Promise.all([
      harness.request(`/api/combat/v2/session/${started.body.sessionId}/advance`, { method: 'POST', token: master.token }),
      harness.request(`/api/combat/v2/session/${started.body.sessionId}/advance`, { method: 'POST', token: master.token }),
    ]);
    assert.deepEqual([first.status, second.status].sort((a, b) => a - b), [200, 409]);

    const after = await sql(`select count(*)::int as total from currency_transactions
                             where master_id = $1 and transaction_type = 'COMBAT_V2_REWARD'`, [master.masterId]);
    assert.equal(after.rows[0].total, before.rows[0].total + 1);
  });

  await t.test('unknown Heroes and empty parties are refused', async () => {
    const missing = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: ['00000000-0000-0000-0000-000000000000'], enemyCodes: [enemyCode] },
    });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.error, 'ERR_COMBAT_V2_HERO_NOT_FOUND');

    const empty = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token, body: { heroIds: [] },
    });
    assert.equal(empty.status, 400);
    assert.equal(empty.body.error, 'ERR_COMBAT_V2_NO_HEROES');
  });
});
