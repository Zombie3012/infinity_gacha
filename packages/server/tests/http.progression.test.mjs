import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

async function insertV2Hero(masterId, origin, overrides = {}) {
  const template = (await sql('select code from hero_templates where default_rarity = $1 order by code limit 1', [overrides.rarity ?? 3])).rows[0];
  const id = (await sql('select gen_random_uuid()::text as id')).rows[0].id;
  await sql(`insert into heroes (
      id, master_id, config_id, name, rarity, category, state, level, exp, hp, max_hp, attack, defense, speed,
      base_str, base_int, base_sta, base_agi, class_code, combat_role, training_stats, origin_stats,
      mp, max_mp, current_hp_pct, current_mp_pct, talent_points, thien_menh, hunger, fatigue, loyalty, created_at, updated_at)
    values ($1,$2,$3,$4,$5,'NORMAL','HEALTHY',20,0,1000,1000,100,50,80,
      $6,$7,$8,$9,$10,'PHYSICAL_DPS','{"str":0,"int":0,"sta":0,"agi":0}'::jsonb,
      $11,0,0,1,1,0,0,0,0,100,now(),now())`,
  [id, masterId, template.code, 'V2 Hero', overrides.rarity ?? 3,
    origin.str, origin.int, origin.sta, origin.agi, overrides.classCode ?? 'WARRIOR', JSON.stringify(origin)]);
  return id;
}

test('HTTP combat v2: training and class change', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'prog');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const agiHeroId = await insertV2Hero(master.masterId, { str: 23, int: 24, sta: 23, agi: 100 });
  const legacyHeroId = (await sql(`insert into heroes (id, master_id, config_id, name, rarity, category, state, level, exp, hp, max_hp, attack, defense, speed)
      values (gen_random_uuid()::text, $1, (select code from hero_templates limit 1), 'Legacy', 1, 'NORMAL', 'HEALTHY', 1, 0, 500, 500, 60, 40, 90)
      returning id`, [master.masterId])).rows[0].id;

  await t.test('training spends points and raises one base stat', async () => {
    const before = await sql('select base_str, training_stats from heroes where id = $1', [agiHeroId]);
    const trained = await harness.request(`/api/heroes/${agiHeroId}/train`, {
      method: 'POST', token: master.token, body: { stat: 'str', points: 5 },
    });
    assert.equal(trained.status, 200);
    assert.equal(trained.body.training.str, 5);
    assert.ok(trained.body.base.str > before.rows[0].base_str);
    assert.equal(trained.body.trainingRemaining, 3 * 19 - 5);

    const invalid = await harness.request(`/api/heroes/${agiHeroId}/train`, {
      method: 'POST', token: master.token, body: { stat: 'luck', points: 1 },
    });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.error, 'ERR_HERO_STAT_INVALID');
  });

  await t.test('legacy heroes cannot use combat v2 progression', async () => {
    const refused = await harness.request(`/api/heroes/${legacyHeroId}/train`, {
      method: 'POST', token: master.token, body: { stat: 'str', points: 1 },
    });
    assert.equal(refused.status, 409);
    assert.equal(refused.body.error, 'ERR_HERO_V2_REQUIRED');
  });

  await t.test('class change charges Silver and one token', async () => {
    await setSilver(master.masterId, 100_000);
    await sql(`insert into master_items (id, master_id, item_id, quantity, updated_at)
               values (gen_random_uuid()::text, $1, 'CLASS_CHANGE_TOKEN', 1, now())
               on conflict (master_id, item_id) do update set quantity = 1`, [master.masterId]);

    const changed = await harness.request(`/api/heroes/${agiHeroId}/class-change`, {
      method: 'POST', token: master.token, body: { targetClass: 'THIEF' },
    });
    assert.equal(changed.status, 200);
    assert.equal(changed.body.classCode, 'THIEF');
    assert.equal(changed.body.combatRole, 'ASSASSIN');
    assert.equal(changed.body.cost.silver, 50_000);

    const balance = await sql('select silver_coins from masters where id = $1', [master.masterId]);
    assert.equal(Number(balance.rows[0].silver_coins), 50_000);
    const token = await sql(`select quantity from master_items where master_id = $1 and item_id = 'CLASS_CHANGE_TOKEN'`, [master.masterId]);
    assert.equal(token.rows[0].quantity, 0);
  });

  await t.test('a second change without a token is refused', async () => {
    const refused = await harness.request(`/api/heroes/${agiHeroId}/class-change`, {
      method: 'POST', token: master.token, body: { targetClass: 'ARCHER' },
    });
    assert.equal(refused.status, 409);
    assert.equal(refused.body.error, 'ERR_CLASS_ITEM_REQUIRED');
  });

  await t.test('changing into Mage rolls an element affinity table', async () => {
    const mageId = await insertV2Hero(master.masterId, { str: 25, int: 140, sta: 30, agi: 25 }, { rarity: 4 });
    await setSilver(master.masterId, 100_000);
    await sql(`insert into master_items (id, master_id, item_id, quantity, updated_at)
               values (gen_random_uuid()::text, $1, 'CLASS_CHANGE_TOKEN', 1, now())
               on conflict (master_id, item_id) do update set quantity = 1`, [master.masterId]);
    const changed = await harness.request(`/api/heroes/${mageId}/class-change`, {
      method: 'POST', token: master.token, body: { targetClass: 'MAGE' },
    });
    assert.equal(changed.status, 200);
    assert.equal(changed.body.classCode, 'MAGE');
    assert.ok(changed.body.affinity);
    const row = await sql('select fire, water, wind, earth, light, dark, lightning from hero_element_affinities where hero_id = $1', [mageId]);
    assert.equal(row.rowCount, 1);
  });
});
