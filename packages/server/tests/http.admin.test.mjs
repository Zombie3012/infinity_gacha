import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccount, createMaster, dbReady, skipReason, sql, startHarness } from './helpers/harness.mjs';

test('HTTP admin: players, content, analytics and support', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'adm');
  let ticketId = '';

  t.after(async () => {
    await sql(`delete from item_templates where code like 'IT_%'`).catch(() => {});
    await sql(`delete from hero_templates where code like 'IT_%'`).catch(() => {});
    await sql(`delete from enemy_templates where code like 'IT_%'`).catch(() => {});
    await sql(`delete from system_configs where config_key = 'IT_CONFIG'`).catch(() => {});
    await sql(`delete from leaderboard_seasons where board = 'COMBAT_POWER'`).catch(() => {});
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await t.test('player search finds the new account', async () => {
    const search = await harness.request(`/api/admin/players?query=${master.username}`, { admin: true });
    assert.equal(search.status, 200);
    assert.equal(search.body.length, 1);
    assert.equal(search.body[0].username, master.username);
  });

  await t.test('restriction blocks login and restore re-enables it', async () => {
    const restricted = await harness.request(`/api/admin/players/${master.accountId}/restrict`, {
      method: 'POST', admin: true, body: { status: 'SUSPENDED', reason: 'IT' },
    });
    assert.equal(restricted.status, 200);
    assert.equal(restricted.body.status, 'SUSPENDED');

    const blocked = await harness.request('/api/auth/login', {
      method: 'POST', body: { username: master.username, password: 'Password123!' },
    });
    assert.equal(blocked.status, 403);

    const restored = await harness.request(`/api/admin/players/${master.accountId}/restore`, { method: 'POST', admin: true });
    assert.equal(restored.status, 200);

    const login = await harness.request('/api/auth/login', {
      method: 'POST', body: { username: master.username, password: 'Password123!' },
    });
    assert.equal(login.status, 200);
    // Restriction revoked every live session, so subsequent tests must use the new token.
    master.token = login.body.accessToken;
  });

  await t.test('compensation mails Silver and credits Gems', async () => {
    const before = await harness.request('/api/me', { token: master.token });
    const compensation = await harness.request(`/api/admin/players/${master.accountId}/compensation`, {
      method: 'POST', admin: true, body: { silver: 3000, gems: 7, subject: 'IT compensation' },
    });
    assert.equal(compensation.status, 201);

    const after = await harness.request('/api/me', { token: master.token });
    assert.equal(Number(after.body.master.gems), Number(before.body.master.gems) + 7);

    const mailbox = await harness.request('/api/mailbox', { token: master.token });
    assert.ok(mailbox.body.unclaimed.some(row => row.subject === 'IT compensation'));
  });

  await t.test('content configuration upserts items, heroes and bosses', async () => {
    const item = await harness.request('/api/admin/content/items', {
      method: 'POST', admin: true, body: { code: 'IT_ITEM', name: 'IT Item', category: 'MATERIAL', rarity: 2 },
    });
    assert.equal(item.status, 201);
    assert.equal(item.body.code, 'IT_ITEM');

    const hero = await harness.request('/api/admin/content/heroes', {
      method: 'POST', admin: true,
      body: { code: 'IT_HERO', name: 'IT Hero', rarity: 3, heroClass: 'MAGE', element: 'FIRE', baseHp: 900, baseAttack: 100, baseDefense: 50, baseSpeed: 60 },
    });
    assert.equal(hero.status, 201);
    assert.equal(hero.body.baseHp, 900);

    const stats = await harness.request('/api/admin/content/heroes/IT_HERO/stats', {
      method: 'POST', admin: true, body: { baseHp: 1200 },
    });
    assert.equal(stats.status, 200);
    assert.equal(stats.body.baseHp, 1200);

    const boss = await harness.request('/api/admin/content/enemies', {
      method: 'POST', admin: true,
      body: { code: 'IT_BOSS', name: 'IT Boss', baseHp: 9000, baseAttack: 300, baseDefense: 200, baseSpeed: 80, baseExpReward: 100, baseSilverReward: 500, isBoss: true },
    });
    assert.equal(boss.status, 201);
    assert.equal(boss.body.isBoss, true);

    const bosses = await harness.request('/api/admin/content/enemies?boss=true', { admin: true });
    assert.ok(bosses.body.some(row => row.code === 'IT_BOSS'));
  });

  await t.test('analytics aggregates the running dataset', async () => {
    const summary = await harness.request('/api/admin/analytics', { admin: true });
    assert.equal(summary.status, 200);
    assert.ok(summary.body.players.accounts >= 1);
    assert.ok(typeof summary.body.gacha.totalRolls === 'number');
    assert.ok(typeof summary.body.battle.winRate.rate === 'number');
    assert.ok(typeof summary.body.retention.activeThisWeek === 'number');
  });

  await t.test('support ticket lifecycle is guarded', async () => {
    const created = await harness.request('/api/support/tickets', {
      method: 'POST', token: master.token,
      body: { subject: 'IT ticket', body: 'Something went wrong during the integration test.' },
    });
    assert.equal(created.status, 201);
    ticketId = created.body.id;

    const reply = await harness.request(`/api/admin/support/tickets/${ticketId}/reply`, {
      method: 'POST', admin: true, body: { body: 'We are looking into it.' },
    });
    assert.equal(reply.status, 200);
    assert.equal(reply.body.status, 'IN_PROGRESS');

    const resolved = await harness.request(`/api/admin/support/tickets/${ticketId}/status`, {
      method: 'POST', admin: true, body: { status: 'RESOLVED' },
    });
    assert.equal(resolved.status, 200);

    const closed = await harness.request(`/api/admin/support/tickets/${ticketId}/status`, {
      method: 'POST', admin: true, body: { status: 'CLOSED' },
    });
    assert.equal(closed.status, 200);

    const reopen = await harness.request(`/api/admin/support/tickets/${ticketId}/status`, {
      method: 'POST', admin: true, body: { status: 'OPEN' },
    });
    assert.equal(reopen.status, 409);
    assert.equal(reopen.body.error, 'ERR_SUPPORT_INVALID_TRANSITION');

    const detail = await harness.request(`/api/admin/support/tickets/${ticketId}`, { admin: true });
    assert.equal(detail.body.messages.length, 2);
  });
});
