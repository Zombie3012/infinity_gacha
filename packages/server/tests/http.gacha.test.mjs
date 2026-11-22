import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccount, createMaster, skipReason, sql, startHarness } from './helpers/harness.mjs';

test('HTTP gacha: flat rates, Gem costs and idempotent payment', { skip: skipReason }, async t => {
  const harness = await startHarness();
  t.after(() => harness.close());
  const master = await createMaster(harness.request, 'gacha');
  t.after(() => cleanupAccount(master.accountId));
  const token = master.token;

  await t.test('seeded banners expose flat pool rates without a pity contract', async () => {
    const normal = await harness.request('/api/gacha/banners/banner-001', { token });
    const special = await harness.request('/api/gacha/banners/banner-002', { token });
    assert.equal(normal.status, 200);
    assert.equal(special.status, 200);
    assert.equal(normal.body.banner.costType, 'SCROLL');
    assert.equal(normal.body.banner.costPerRoll, 1);
    assert.equal(normal.body.rates.fiveStarHeroPercent, 0);
    assert.equal(special.body.banner.costType, 'GEMS');
    assert.equal(special.body.banner.costPerRoll, 100);
    assert.equal(special.body.rates.fiveStarHeroPercent, 0.4);
    for (const { body } of [normal, special]) {
      assert.equal(body.rates.heroTotalPercent, 50);
      assert.equal(body.rates.materialPercent, 50);
      assert.equal('pity' in body, false);
    }
  });

  await sql('update masters set gems = 1000 where id = $1', [master.masterId]);
  await sql(`insert into master_summon_inventory (id, master_id, scroll_type, quantity)
    values (gen_random_uuid()::text, $1, 'NORMAL', 10)
    on conflict (master_id, scroll_type) do update set quantity = 10`, [master.masterId]);

  const summon = (bannerId, rollCount, key) => harness.request('/api/gacha/summon', {
    token, method: 'POST', body: { bannerId, rollCount }, headers: { 'Idempotency-Key': key },
  });

  await t.test('ten Special rolls consume 1000 Gems once, including a retry at zero balance', async () => {
    const first = await summon('banner-002', 10, 'special-ten');
    assert.equal(first.status, 200);
    assert.equal(first.body.currencyType, 'GEMS');
    assert.equal(first.body.currencyConsumed, 1000);
    assert.equal(first.body.scrollsConsumed, 0);
    assert.equal(first.body.remainingGems, '0');
    assert.equal(first.body.results.length, 10);
    const replay = await summon('banner-002', 10, 'special-ten');
    assert.equal(replay.status, 200);
    assert.equal(replay.body.sessionId, first.body.sessionId);
    const wallet = await sql('select gems from masters where id = $1', [master.masterId]);
    assert.equal(Number(wallet.rows[0].gems), 0);
    const history = await sql('select count(*)::int as total from summon_history where master_id = $1', [master.masterId]);
    assert.equal(history.rows[0].total, 10);
  });

  await t.test('insufficient Gems reject a fresh summon without recording another roll', async () => {
    const rejected = await summon('banner-002', 1, 'special-empty');
    assert.equal(rejected.status, 409);
    const sessions = await sql('select count(*)::int as total from summon_sessions where master_id = $1', [master.masterId]);
    assert.equal(sessions.rows[0].total, 1);
  });

  await t.test('Normal rolls consume scrolls and leave historical pity fields at zero', async () => {
    const result = await summon('banner-001', 1, 'normal-one');
    assert.equal(result.status, 200);
    assert.equal(result.body.currencyType, 'SCROLL');
    assert.equal(result.body.scrollsConsumed, 1);
    const inventory = await sql("select quantity from master_summon_inventory where master_id = $1 and scroll_type = 'NORMAL'", [master.masterId]);
    assert.equal(inventory.rows[0].quantity, 9);
    const sessions = await sql('select pity_before, pity_after from summon_sessions where master_id = $1', [master.masterId]);
    assert.ok(sessions.rows.every(row => row.pity_before === 0 && row.pity_after === 0));
    const history = await sql('select pity_number from summon_history where master_id = $1', [master.masterId]);
    assert.ok(history.rows.every(row => row.pity_number === 0));
  });
});
