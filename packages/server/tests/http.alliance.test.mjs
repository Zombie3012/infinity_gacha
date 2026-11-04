import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP alliance: founding, joining, managing, chatting and leaving', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const leader = await createMaster(harness.request, 'allA');
  const officer = await createMaster(harness.request, 'allB');
  const recruit = await createMaster(harness.request, 'allC');
  t.after(async () => {
    await cleanupAccount(leader.accountId);
    await cleanupAccount(officer.accountId);
    await cleanupAccount(recruit.accountId);
    await harness.close();
  });

  let allianceId = '';
  let requestId = '';

  await t.test('a Master below level 20 cannot found an alliance', async () => {
    await setSilver(leader.masterId, 600_000);
    const refused = await harness.request('/api/alliance', {
      method: 'POST', token: leader.token, body: { name: 'Bình Minh', tag: 'BM1' },
    });
    assert.equal(refused.status, 409);
    assert.equal(refused.body.error, 'ERR_ALLIANCE_LEVEL_REQUIRED');

    const poor = await setSilver(officer.masterId, 0);
    assert.equal(poor, undefined);
    await sql('update masters set level = 20 where id = $1', [officer.masterId]);
    const broke = await harness.request('/api/alliance', {
      method: 'POST', token: officer.token, body: { name: 'Nghèo', tag: 'NG1' },
    });
    assert.equal(broke.status, 409);
    assert.equal(broke.body.error, 'ERR_ALLIANCE_INSUFFICIENT_FUNDS');
  });

  await t.test('a level-20 Master pays Silver and becomes the Leader', async () => {
    await sql('update masters set level = 20 where id = $1', [leader.masterId]);
    const created = await harness.request('/api/alliance', {
      method: 'POST', token: leader.token,
      body: { name: 'Bình Minh', tag: 'bm1', motto: 'Cùng tiến', emblemIcon: '☀' },
    });
    assert.equal(created.status, 201);
    assert.equal(created.body.inAlliance, true);
    assert.equal(created.body.currencySpent, 'SILVER');
    assert.equal(created.body.alliance.tag, 'BM1');
    assert.equal(created.body.membership.role, 'LEADER');
    assert.equal(created.body.alliance.maxMembers, 30);
    allianceId = created.body.alliance.id;

    const balance = await sql('select silver_coins from masters where id = $1', [leader.masterId]);
    assert.equal(Number(balance.rows[0].silver_coins), 100_000);
  });

  await t.test('the alliance is searchable and the name is unique', async () => {
    const search = await harness.request('/api/alliance/search?query=bình', { token: officer.token });
    assert.equal(search.status, 200);
    assert.equal(search.body.alliances.length, 1);
    assert.equal(search.body.alliances[0].pending, false);

    await setSilver(officer.masterId, 600_000);
    const duplicate = await harness.request('/api/alliance', {
      method: 'POST', token: officer.token, body: { name: 'Bình Minh', tag: 'KH2' },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(duplicate.body.error, 'ERR_ALLIANCE_NAME_TAKEN');
  });

  await t.test('a request is created once and shows up for officers', async () => {
    const joined = await harness.request('/api/alliance/join', {
      method: 'POST', token: officer.token, body: { allianceId, message: 'Cho mình vào bang' },
    });
    assert.equal(joined.status, 201);
    requestId = joined.body.request.id;

    const duplicate = await harness.request('/api/alliance/join', {
      method: 'POST', token: officer.token, body: { allianceId },
    });
    assert.equal(duplicate.status, 409);
    assert.equal(duplicate.body.error, 'ERR_ALLIANCE_REQUEST_PENDING');

    const mine = await harness.request('/api/alliance', { token: officer.token });
    assert.equal(mine.body.inAlliance, false);
    assert.equal(mine.body.pendingRequest.allianceName, 'Bình Minh');

    const board = await harness.request('/api/alliance', { token: leader.token });
    assert.equal(board.body.requests.length, 1);
    assert.equal(board.body.requests[0].name, 'Integration Master');
  });

  await t.test('the leader approves, then promotes the new member', async () => {
    const approved = await harness.request(`/api/alliance/requests/${requestId}/approve`, {
      method: 'POST', token: leader.token,
    });
    assert.equal(approved.status, 200);
    assert.equal(approved.body.status, 'APPROVED');

    const memberView = await harness.request('/api/alliance', { token: officer.token });
    assert.equal(memberView.body.inAlliance, true);
    assert.equal(memberView.body.membership.role, 'MEMBER');
    assert.equal(memberView.body.alliance.memberCount, 2);
    assert.equal(memberView.body.permissions.canManage, false);

    const promoted = await harness.request(`/api/alliance/members/${officer.masterId}/manage`, {
      method: 'POST', token: leader.token, body: { action: 'PROMOTE' },
    });
    assert.equal(promoted.status, 200);
    assert.equal(promoted.body.role, 'OFFICER');

    const officerView = await harness.request('/api/alliance', { token: officer.token });
    assert.equal(officerView.body.permissions.canManage, true);
    assert.equal(officerView.body.permissions.canUpgradeTech, false);
  });

  await t.test('an officer approves recruits, edits the notice and cannot upgrade tech', async () => {
    const joined = await harness.request('/api/alliance/join', {
      method: 'POST', token: recruit.token, body: { allianceId },
    });
    assert.equal(joined.status, 201);
    const approved = await harness.request(`/api/alliance/requests/${joined.body.request.id}/approve`, {
      method: 'POST', token: officer.token,
    });
    assert.equal(approved.status, 200);

    const notice = await harness.request('/api/alliance/notice', {
      method: 'PATCH', token: officer.token, body: { noticeBoard: 'Tập trung tại (500, 500)' },
    });
    assert.equal(notice.status, 200);
    assert.equal(notice.body.noticeBoard, 'Tập trung tại (500, 500)');

    const tech = await harness.request('/api/alliance/tech/upgrade', { method: 'POST', token: officer.token });
    assert.equal(tech.status, 403);
    assert.equal(tech.body.error, 'ERR_ALLIANCE_LEADER_ONLY');

    const upgraded = await harness.request('/api/alliance/tech/upgrade', { method: 'POST', token: leader.token });
    assert.equal(upgraded.status, 200);
    assert.equal(upgraded.body.maxMembers, 40);
    assert.equal(upgraded.body.allianceLevel, 2);
  });

  await t.test('the guild chat carries text and coordinate pings', async () => {
    const text = await harness.request('/api/alliance/chat', {
      method: 'POST', token: leader.token, body: { body: 'Chào cả nhà' },
    });
    assert.equal(text.status, 201);
    assert.equal(text.body.messageType, 'TEXT');

    const ping = await harness.request('/api/alliance/chat', {
      method: 'POST', token: officer.token, body: { coordinates: { x: 500, y: 500 } },
    });
    assert.equal(ping.status, 201);
    assert.equal(ping.body.messageType, 'PING');
    assert.equal(ping.body.coordinates.x, 500);

    const bad = await harness.request('/api/alliance/chat', {
      method: 'POST', token: officer.token, body: { coordinates: { x: 2000, y: 0 } },
    });
    assert.equal(bad.status, 400);
    assert.equal(bad.body.error, 'ERR_ALLIANCE_PING_INVALID');

    const history = await harness.request('/api/alliance/chat', { token: recruit.token });
    assert.equal(history.status, 200);
    assert.equal(history.body.length, 2);
    assert.equal(history.body[0].body, 'Chào cả nhà');
  });

  await t.test('a member leaves and receives a 24-hour cooldown', async () => {
    const left = await harness.request('/api/alliance/leave', { method: 'POST', token: recruit.token });
    assert.equal(left.status, 200);
    assert.equal(left.body.cooldownUntil !== null, true);

    const view = await harness.request('/api/alliance', { token: recruit.token });
    assert.equal(view.body.inAlliance, false);
    assert.equal(view.body.cooldown.reason, 'LEFT');

    const retry = await harness.request('/api/alliance/join', {
      method: 'POST', token: recruit.token, body: { allianceId },
    });
    assert.equal(retry.status, 409);
    assert.equal(retry.body.error, 'ERR_ALLIANCE_COOLDOWN');
  });

  await t.test('the leader transfers, then leaves and the cooldown applies to them too', async () => {
    const blocked = await harness.request('/api/alliance/leave', { method: 'POST', token: leader.token });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_ALLIANCE_LEADER_MUST_TRANSFER');

    const transferred = await harness.request(`/api/alliance/members/${officer.masterId}/manage`, {
      method: 'POST', token: leader.token, body: { action: 'TRANSFER' },
    });
    assert.equal(transferred.status, 200);

    const oldLeader = await harness.request('/api/alliance', { token: leader.token });
    assert.equal(oldLeader.body.membership.role, 'OFFICER');

    const left = await harness.request('/api/alliance/leave', { method: 'POST', token: leader.token });
    assert.equal(left.status, 200);
    assert.equal(left.body.disbanded, false);

    const newLeader = await harness.request('/api/alliance', { token: officer.token });
    assert.equal(newLeader.body.membership.role, 'LEADER');
    assert.equal(newLeader.body.alliance.memberCount, 1);
  });

  await t.test('the last leader leaving disbands the alliance', async () => {
    const left = await harness.request('/api/alliance/leave', { method: 'POST', token: officer.token });
    assert.equal(left.status, 200);
    assert.equal(left.body.disbanded, true);

    const search = await harness.request('/api/alliance/search', { token: recruit.token });
    assert.equal(search.body.alliances.length, 0);
  });
});
