import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  effectiveMultiplier,
  enhanceCost,
  enhanceMultiplier,
  fusionMultiplierForStar,
  fusionRequirement,
  rollSubstats,
  scaledBonus,
  validateCraft,
} from '../dist/modules/crafting/crafting-rules.js';

const recipe = {
  requiredMaterials: [{ itemId: 'IRON', quantity: 10 }, { itemId: 'WOOD', quantity: 5 }],
  requiredSilver: 1000,
  requiredForgeLevel: 1,
};

test('DM-10 Crafting - material requirement', async (t) => {
  await t.test('scenario 12.1: enough ore, wood, silver and forge level passes', () => {
    const result = validateCraft({ ...recipe, owned: { IRON: 10, WOOD: 5 }, silver: 1000, forgeLevel: 1 });
    assert.equal(result.ok, true);
  });

  await t.test('missing materials are reported with the shortfall', () => {
    const result = validateCraft({ ...recipe, owned: { IRON: 4, WOOD: 5 }, silver: 5000, forgeLevel: 2 });
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'ERR_CRAFT_MISSING_MATERIALS');
    assert.deepEqual(result.missingMaterials, [{ itemId: 'IRON', quantity: 6 }]);
  });

  await t.test('missing Silver is reported separately', () => {
    const result = validateCraft({ ...recipe, owned: { IRON: 10, WOOD: 5 }, silver: 400, forgeLevel: 1 });
    assert.equal(result.reason, 'ERR_CRAFT_MISSING_SILVER');
    assert.equal(result.missingSilver, 600);
  });

  await t.test('forge level gates high tier recipes', () => {
    const result = validateCraft({ ...recipe, requiredForgeLevel: 3, owned: { IRON: 10, WOOD: 5 }, silver: 1000, forgeLevel: 1 });
    assert.equal(result.reason, 'ERR_CRAFT_FORGE_LEVEL');
    assert.equal(result.forgeLevelShort, 2);
  });
});

test('DM-10 Crafting - enhancement and fusion', async (t) => {
  await t.test('enhancement cost grows with the current level', () => {
    assert.deepEqual(enhanceCost(0), { stones: 1, silver: 500 });
    assert.deepEqual(enhanceCost(3), { stones: 4, silver: 2000 });
  });

  await t.test('each enhancement adds 10% of the base stats', () => {
    assert.equal(enhanceMultiplier(0), 1);
    assert.equal(enhanceMultiplier(5), 1.5);
  });

  await t.test('scenario 12.2: fusion needs three items and raises stats by 30%', () => {
    assert.equal(fusionRequirement(), 3);
    assert.equal(fusionMultiplierForStar(2), 1.3);
    assert.equal(fusionMultiplierForStar(3), 1.69);
  });

  await t.test('crafted substats are deterministic per instance seed', () => {
    const first = rollSubstats('instance-abc', 3);
    assert.deepEqual(first, rollSubstats('instance-abc', 3));
    assert.ok(first.hp > 0 && first.attack > 0);
  });

  await t.test('scaled bonuses combine template, multiplier and substats', () => {
    assert.equal(scaledBonus(100, 1.3, 4), 134);
    assert.equal(scaledBonus(50, 1, 0), 50);
  });
});

test('DM-10 Crafting - star and enhancement stack', async (t) => {
  await t.test('enhancing a fused item multiplies instead of replacing its star bonus', () => {
    assert.equal(effectiveMultiplier(1, 0), 1);
    assert.equal(effectiveMultiplier(2, 0), 1.3);
    assert.equal(effectiveMultiplier(2, 1), 1.43);
    assert.equal(effectiveMultiplier(3, 2), 2.03);
  });

  await t.test('enhancement on a base item still behaves as before', () => {
    assert.equal(effectiveMultiplier(1, 5), 1.5);
    assert.equal(enhanceMultiplier(5), 1.5);
  });
});
