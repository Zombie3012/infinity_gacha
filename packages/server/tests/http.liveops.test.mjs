import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP liveops: quests, events and leaderboards', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'ops');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await setSilver(master.masterId, 100_000);

  await t.test('quest board instantiates daily and weekly cycles', async () => {
    const quests = await harness.request('/api/quests', { token: master.token });
    assert.equal(quests.status, 200);
    assert.equal(quests.body.daily.length, 5);
    assert.equal(quests.body.weekly.length, 3);
    assert.ok(quests.body.main.length >= 1);
    assert.ok(quests.body.achievements.length >= 5);
  });

  await t.test('shop spending advances the daily spend quest and pays out', async () => {
    await harness.request('/api/shop/purchase', {
      method: 'POST', token: master.token, body: { itemCode: 'STAMINA_POTION', quantity: 2 },
    });
    const quests = await harness.request('/api/quests', { token: master.token });
    const spendQuest = quests.body.daily.find(row => row.code === 'DAILY_SPEND_1000');
    assert.ok(spendQuest, 'daily spend quest should be active today');
    assert.equal(spendQuest.status, 'COMPLETED');

    const before = await harness.request('/api/me', { token: master.token });
    const claim = await harness.request(`/api/quests/${spendQuest.code}/claim`, { method: 'POST', token: master.token });
    assert.equal(claim.status, 200);
    assert.equal(claim.body.reward.silver, 200);

    const after = await harness.request('/api/me', { token: master.token });
    assert.equal(Number(after.body.master.silverCoins), Number(before.body.master.silverCoins) + 200);
  });

  await t.test('the seeded event exposes missions and a phase', async () => {
    const events = await harness.request('/api/events', { token: master.token });
    assert.equal(events.status, 200);
    assert.ok(events.body.length >= 1);
    assert.ok(['ACTIVE', 'GRACE'].includes(events.body[0].phase));
    assert.equal(events.body[0].missions.length, 3);
  });

  await t.test('leaderboards rank the master and closing a season mails rewards', async () => {
    const board = await harness.request('/api/leaderboards?board=DUNGEON_PROGRESS', { token: master.token });
    assert.equal(board.status, 200);
    assert.ok(board.body.entries.length >= 1);
    assert.ok(board.body.viewer, 'the caller should have a rank');

    await sql(`delete from leaderboard_seasons where board = 'DUNGEON_PROGRESS' and status = 'CLOSED'`);

    const closed = await harness.request('/api/admin/leaderboards/DUNGEON_PROGRESS/close', { method: 'POST', admin: true });
    assert.equal(closed.status, 200);
    assert.ok(closed.body.rewarded >= 1);

    const mailbox = await harness.request('/api/mailbox', { token: master.token });
    const rewardMail = mailbox.body.unclaimed.find(row => row.subject.includes('Thưởng xếp hạng'));
    assert.ok(rewardMail, 'season reward should arrive by mail');
  });
});
