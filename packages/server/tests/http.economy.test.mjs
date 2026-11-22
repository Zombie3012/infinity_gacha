import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import {
  cleanupAccount, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

const sign = (secret, store, transactionId) =>
  createHmac('sha256', secret).update(`${store}:${transactionId}`).digest('hex');

test('HTTP economy: shop limits, mailbox and IAP', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'econ');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await setSilver(master.masterId, 100_000);
  const limitedSku = 'TEST_LIMIT_' + master.masterId.replaceAll('-','').toUpperCase();
  await sql("insert into shop_items(code,name,description,item_id,category,price_silver,daily_limit) values($1,'Test limit','Isolated limit fixture','FOOD','CONSUMABLE',500,5)",[limitedSku]);
  t.after(()=>sql('delete from shop_items where code=$1',[limitedSku]));

  await t.test('daily purchase limits sell the remainder and warn', async () => {
    const first = await harness.request('/api/shop/purchase', {
      method: 'POST', token: master.token, body: { itemCode: limitedSku, quantity: 4 },
    });
    assert.equal(first.status, 200);
    assert.equal(first.body.purchased, 4);
    assert.equal(first.body.remainingToday, 1);

    const second = await harness.request('/api/shop/purchase', {
      method: 'POST', token: master.token, body: { itemCode: limitedSku, quantity: 2 },
    });
    assert.equal(second.status, 200);
    assert.equal(second.body.purchased, 1);
    assert.equal(second.body.warning, 'ERR_SHOP_DAILY_LIMIT_EXCEEDED');

    const blocked = await harness.request('/api/shop/purchase', {
      method: 'POST', token: master.token, body: { itemCode: limitedSku, quantity: 1 },
    });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.body.error, 'ERR_SHOP_DAILY_LIMIT_EXCEEDED');
  });

  let mailId = '';

  await t.test('operator mail is claimable exactly once', async () => {
    const sent = await harness.request('/api/admin/mailbox/send', {
      method: 'POST', admin: true,
      body: { username: master.username, subject: 'IT mail', body: 'compensation', attachments: { silver: 5000, items: [{ itemId: 'FOOD', quantity: 2 }] } },
    });
    assert.equal(sent.status, 201);
    mailId = sent.body.id;

    const before = await harness.request('/api/me', { token: master.token });
    const claimed = await harness.request(`/api/mailbox/${mailId}/claim`, { method: 'POST', token: master.token });
    assert.equal(claimed.status, 200);
    assert.equal(claimed.body.silver, 5000);

    const after = await harness.request('/api/me', { token: master.token });
    assert.equal(Number(after.body.master.silverCoins), Number(before.body.master.silverCoins) + 5000);

    const again = await harness.request(`/api/mailbox/${mailId}/claim`, { method: 'POST', token: master.token });
    assert.equal(again.status, 409);
  });

  await t.test('IAP checkout, receipt validation and replay protection', async () => {
    const secret = process.env.PAYMENT_GATEWAY_SECRET ?? '';
    const checkout = await harness.request('/api/iap/checkout', {
      method: 'POST', token: master.token, body: { productCode: 'PKG_GEMS_TIER_1', store: 'APPLE' },
    });
    assert.equal(checkout.status, 201);

    const bad = await harness.request('/api/iap/receipt', {
      method: 'POST', token: master.token,
      body: { transactionId: checkout.body.transactionId, storeTransactionId: 'IT_TX_1', receiptToken: 'deadbeef' },
    });
    assert.equal(bad.status, 401);

    const good = await harness.request('/api/iap/receipt', {
      method: 'POST', token: master.token,
      body: { transactionId: checkout.body.transactionId, storeTransactionId: 'IT_TX_1', receiptToken: sign(secret, 'APPLE', 'IT_TX_1') },
    });
    assert.equal(good.status, 200);
    assert.equal(good.body.gemsGranted, 1000);

    const second = await harness.request('/api/iap/checkout', {
      method: 'POST', token: master.token, body: { productCode: 'PKG_GEMS_TIER_1', store: 'APPLE' },
    });
    const replay = await harness.request('/api/iap/receipt', {
      method: 'POST', token: master.token,
      body: { transactionId: second.body.transactionId, storeTransactionId: 'IT_TX_1', receiptToken: sign(secret, 'APPLE', 'IT_TX_1') },
    });
    assert.equal(replay.status, 409);
    assert.equal(replay.body.error, 'ERR_IAP_DUPLICATE_RECEIPT');
  });

  await t.test('refund after spending books Gem debt', async () => {
    const [transaction] = (await sql(
      `select id from payment_transactions where master_id = $1 and status = 'COMPLETED' order by created_at desc limit 1`,
      [master.masterId],
    )).rows;
    await sql('update masters set gems = 200 where id = $1', [master.masterId]);

    const refund = await harness.request('/api/admin/iap/refund', {
      method: 'POST', admin: true, body: { transactionId: transaction.id, reason: 'IT refund' },
    });
    assert.equal(refund.status, 200);
    assert.equal(refund.body.gemsClawedBack, 200);
    assert.equal(refund.body.gemDebtAdded, 800);

    const me = await harness.request('/api/me', { token: master.token });
    assert.equal(String(me.body.master.gemDebt), '800');
    assert.equal(String(me.body.master.gems), '0');
  });
});
