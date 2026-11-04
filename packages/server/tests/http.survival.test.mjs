import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, grantItems, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP survival: food, feeding and resting', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'surv');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const hero = await createHero(master.masterId);
  await grantItems(master.masterId, { FOOD_RAW: 10, FOOD: 20 });

  await t.test('the kitchen converts raw food into meals', async () => {
    const cooked = await harness.request('/api/survival/kitchen/cook', {
      method: 'POST', token: master.token, body: { quantity: 5 },
    });
    assert.equal(cooked.status, 200);
    assert.equal(cooked.body.meals, 5);
    assert.equal(cooked.body.rawUsed, 10);
    assert.equal(cooked.body.stock, 25);
  });

  await t.test('feeding consumes one meal and reduces hunger', async () => {
    await sql(`update hero_survival_states set hunger_score = 60, last_tick_at = now() where hero_instance_id = $1`, [hero.id]);
    const fed = await harness.request(`/api/survival/heroes/${hero.id}/feed`, {
      method: 'POST', token: master.token, body: { quantity: 1 },
    });
    assert.equal(fed.status, 200);
    assert.equal(fed.body.foodUsed, 1);
    assert.equal(fed.body.hungerScore, 40);
    assert.equal(fed.body.hungerState, 'HUNGRY');
  });

  await t.test('resting drains fatigue over time', async () => {
    await sql(`update hero_survival_states set fatigue_score = 80, is_resting = false, last_tick_at = now() where hero_instance_id = $1`, [hero.id]);
    const resting = await harness.request(`/api/survival/heroes/${hero.id}/rest`, { method: 'POST', token: master.token });
    assert.equal(resting.status, 200);
    assert.equal(resting.body.isResting, true);

    await sql(`update hero_survival_states set last_tick_at = now() - interval '4 hours' where hero_instance_id = $1`, [hero.id]);
    const overview = await harness.request('/api/survival', { token: master.token });
    const row = overview.body.heroes.find(entry => entry.heroId === hero.id);
    assert.ok(row.fatigueScore <= 21, `expected ~20 fatigue, got ${row.fatigueScore}`);
    assert.equal(row.isResting, true);
  });

  await t.test('ration quotes follow context and hero count', async () => {
    await grantItems(master.masterId, { FOOD: 60 });
    const dungeon = await harness.request('/api/survival/rations/quote', {
      method: 'POST', token: master.token, body: { context: 'DUNGEON', heroCount: 4 },
    });
    assert.equal(dungeon.status, 200);
    assert.equal(dungeon.body.required, 40);
    assert.equal(dungeon.body.affordable, true);

    const war = await harness.request('/api/survival/rations/quote', {
      method: 'POST', token: master.token, body: { context: 'WAR', heroCount: 2 },
    });
    assert.equal(war.body.required, 30);
  });

  await t.test('base upkeep quotes meals for healthy Heroes', async () => {
    const upkeep = await harness.request('/api/survival/upkeep?hours=24', { token: master.token });
    assert.equal(upkeep.status, 200);
    assert.equal(upkeep.body.heroCount, 1);
    assert.equal(upkeep.body.required, 2);
  });
});
