import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildNow, cleanupAccount, createMaster, dbReady, grantItems, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP crafting, enhancement and fusion', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'craft');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await setSilver(master.masterId, 200_000);
  await grantItems(master.masterId, { IRON: 40, WOOD: 20, ENHANCEMENT_STONE: 10 });
  await sql('update worlds set current_floor = 4 where master_id = $1', [master.masterId]);
  await buildNow(harness.request, master, 'FORGE', 1);

  let firstSword = '';

  await t.test('recipes report their material state', async () => {
    const overview = await harness.request('/api/crafting', { token: master.token });
    assert.equal(overview.status, 200);
    assert.equal(overview.body.forgeLevel, 1);
    const recipe = overview.body.recipes.find(row => row.code === 'RECIPE_IRON_SWORD');
    assert.equal(recipe.validation.ok, true);
  });

  await t.test('crafting consumes materials and rolls an instance', async () => {
    const crafted = await harness.request('/api/crafting/craft', {
      method: 'POST', token: master.token, body: { recipeCode: 'RECIPE_IRON_SWORD' },
    });
    assert.equal(crafted.status, 201);
    firstSword = crafted.body.instanceId;

    const overview = await harness.request('/api/crafting', { token: master.token });
    assert.equal(overview.body.materials.IRON, 30);
    assert.equal(overview.body.materials.WOOD, 15);
    const instance = overview.body.equipment.find(row => row.id === firstSword);
    assert.equal(instance.starLevel, 1);
    assert.ok(instance.stats.attack >= 1);
  });

  await t.test('enhancement spends stones and compounds the multiplier', async () => {
    const enhanced = await harness.request(`/api/crafting/equipment/${firstSword}/enhance`, { method: 'POST', token: master.token });
    assert.equal(enhanced.status, 200);
    assert.equal(enhanced.body.enhanceLevel, 1);
    assert.equal(enhanced.body.statMultiplier, 1.1);
    assert.equal(enhanced.body.stonesSpent, 1);
  });

  await t.test('three identical items fuse into the next star', async () => {
    for (let index = 0; index < 2; index += 1) {
      const crafted = await harness.request('/api/crafting/craft', {
        method: 'POST', token: master.token, body: { recipeCode: 'RECIPE_IRON_SWORD' },
      });
      assert.equal(crafted.status, 201);
    }
    const fused = await harness.request('/api/crafting/fuse', {
      method: 'POST', token: master.token, body: { templateCode: 'SAMPLE_IRON_SWORD', starLevel: 1 },
    });
    assert.equal(fused.status, 200);
    assert.equal(fused.body.starLevel, 2);
    assert.equal(fused.body.statMultiplier, 1.3);
    assert.equal(fused.body.consumed.length, 3);

    const overview = await harness.request('/api/crafting', { token: master.token });
    const swords = overview.body.equipment.filter(row => row.templateCode === 'SAMPLE_IRON_SWORD');
    // 3 swords crafted + the 1 seeded starter sword, minus the 3 consumed, plus the fused one.
    assert.equal(swords.length, 2);
    assert.equal(swords.filter(row => row.starLevel === 2).length, 1);
  });

  await t.test('a missing-material craft is refused with the reason code', async () => {
    const failed = await harness.request('/api/crafting/craft', {
      method: 'POST', token: master.token, body: { recipeCode: 'RECIPE_SWIFT_CHARM' },
    });
    assert.equal(failed.status, 409);
    assert.equal(failed.body.error, 'ERR_CRAFT_MISSING_MATERIALS');
  });
});
