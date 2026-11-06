import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createMaster, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

async function insertDistinctTestHero(masterId, overrides = {}) {
  const rarity = overrides.rarity ?? 1;
  const ownedCodes = (await sql('select config_id from heroes where master_id = $1', [masterId])).rows.map(r => r.config_id);
  const template = (await sql(
    'select code from hero_templates where default_rarity = $1 and not (code = any($2)) order by code limit 1',
    [rarity, ownedCodes],
  )).rows[0];

  assert.ok(template, `Must have a free ${rarity}★ template for master`);
  const id = (await sql('select gen_random_uuid()::text as id')).rows[0].id;
  const origin = overrides.origin ?? (rarity === 1 ? { str: 40, int: 20, sta: 25, agi: 15 } : { str: 50, int: 30, sta: 30, agi: 20 });
  const level = overrides.level ?? 1;
  await sql(`insert into heroes (
      id, master_id, config_id, name, rarity, category, state, level, exp, hp, max_hp, attack, defense, speed,
      base_str, base_int, base_sta, base_agi, class_code, combat_role, training_stats, origin_stats,
      mp, max_mp, current_hp_pct, current_mp_pct, talent_points, thien_menh, hunger, fatigue, loyalty, is_locked, created_at, updated_at)
    values ($1,$2,$3,$4,$5,'NORMAL','HEALTHY',$6,0,1000,1000,100,50,80,
      $7,$8,$9,$10,'WARRIOR','PHYSICAL_DPS','{"str":0,"int":0,"sta":0,"agi":0}'::jsonb,
      $11,0,0,1,1,0,0,0,0,100,$12,now(),now())`,
  [id, masterId, template.code, overrides.name ?? 'Promotion Test Hero', rarity, level,
    origin.str, origin.int, origin.sta, origin.agi, JSON.stringify(origin), Boolean(overrides.isLocked)]);
  return id;
}

test('HTTP Hero Star Promotion (Pick Me Up style)', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'promotestar');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  await setSilver(master.masterId, 200_000);

  await t.test('preview returns eligibility, required level, cost and available fodders', async () => {
    const hero1 = await insertDistinctTestHero(master.masterId, { rarity: 1, level: 9, name: 'Hero Under Level' });
    const fodder1 = await insertDistinctTestHero(master.masterId, { rarity: 1, level: 1, name: 'Fodder 1' });

    const previewUnder = await harness.request(`/api/heroes/${hero1}/promote-star/preview`, {
      method: 'GET', token: master.token,
    });
    assert.equal(previewUnder.status, 200);
    assert.equal(previewUnder.body.eligible, false);
    assert.equal(previewUnder.body.reason, 'ERR_HERO_LEVEL_NOT_MAX');
    assert.equal(previewUnder.body.requirements.requiredLevel, 10);
    assert.equal(previewUnder.body.requirements.requiredFodderCount, 1);
    assert.equal(previewUnder.body.requirements.silverCost, 10_000);
    assert.ok(previewUnder.body.availableFodders.some(f => f.id === fodder1));

    // Update hero to level 10 (max level for 1★)
    await sql('update heroes set level = 10 where id = $1', [hero1]);

    const previewReady = await harness.request(`/api/heroes/${hero1}/promote-star/preview`, {
      method: 'GET', token: master.token,
    });
    assert.equal(previewReady.status, 200);
    assert.equal(previewReady.body.eligible, true);
    assert.equal(previewReady.body.hero.currentLevel, 10);
    assert.equal(previewReady.body.hero.nextMaxLevel, 20);
    assert.ok(previewReady.body.projectedStats);
  });

  await t.test('promoting 1-star hero to 2-star consumes 1 fodder and raises stats', async () => {
    const target1 = await insertDistinctTestHero(master.masterId, { rarity: 1, level: 10, name: 'Hero To 2Star' });
    const fodder1 = await insertDistinctTestHero(master.masterId, { rarity: 1, level: 1, name: 'Sacrifice Fodder' });

    // Equipping fodder with sample equipment to verify it safely returns to inventory
    const eqTemplate = (await sql('select code from equipment_templates limit 1')).rows[0]?.code;
    let equippedItemId;
    if (eqTemplate) {
      equippedItemId = (await sql(`insert into equipment_instances (id, master_id, template_code, equipped_hero_id, location, created_at)
        values (gen_random_uuid()::text, $1, $2, $3, 'EQUIPPED', now()) returning id`,
      [master.masterId, eqTemplate, fodder1])).rows[0].id;
    }

    const res = await harness.request(`/api/heroes/${target1}/promote-star`, {
      method: 'POST', token: master.token, body: { fodderHeroIds: [fodder1] },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.previousStar, 1);
    assert.equal(res.body.newStar, 2);
    assert.equal(res.body.level, 10);
    assert.equal(res.body.maxLevel, 20);
    assert.equal(res.body.silverCost, 10_000);
    assert.deepEqual(res.body.consumedFodderIds, [fodder1]);

    // Check stats upgraded to 130 budget (origin was 100)
    const totalOrigin = res.body.stats.baseStr + res.body.stats.baseInt + res.body.stats.baseSta + res.body.stats.baseAgi;
    assert.ok(totalOrigin >= 130);

    // Verify fodder is deleted
    const fodderCheck = await sql('select id from heroes where id = $1', [fodder1]);
    assert.equal(fodderCheck.rows.length, 0);

    // Verify equipment safely unequipped to inventory
    if (equippedItemId) {
      const eqCheck = await sql('select location, equipped_hero_id from equipment_instances where id = $1', [equippedItemId]);
      assert.equal(eqCheck.rows[0].location, 'INVENTORY');
      assert.equal(eqCheck.rows[0].equipped_hero_id, null);
    }
  });

  await t.test('promoting 2-star hero to 3-star requires 2 fodders and unlocks 2nd imprint slot', async () => {
    const target2 = await insertDistinctTestHero(master.masterId, {
      rarity: 2, level: 20, name: 'Hero To 3Star', origin: { str: 40, int: 30, sta: 35, agi: 25 },
    });
    const fodderA = await insertDistinctTestHero(master.masterId, { rarity: 2, level: 5 });
    const fodderB = await insertDistinctTestHero(master.masterId, { rarity: 2, level: 1 });

    // Refuse when only 1 fodder is provided
    const refuseNotEnough = await harness.request(`/api/heroes/${target2}/promote-star`, {
      method: 'POST', token: master.token, body: { fodderHeroIds: [fodderA] },
    });
    assert.equal(refuseNotEnough.status, 400);

    // Refuse when self is in fodder list
    const refuseSelf = await harness.request(`/api/heroes/${target2}/promote-star`, {
      method: 'POST', token: master.token, body: { fodderHeroIds: [target2, fodderA] },
    });
    assert.equal(refuseSelf.status, 400);

    // Succeed with 2 valid 2-star fodders
    const res = await harness.request(`/api/heroes/${target2}/promote-star`, {
      method: 'POST', token: master.token, body: { fodderHeroIds: [fodderA, fodderB] },
    });

    assert.equal(res.status, 200);
    assert.equal(res.body.previousStar, 2);
    assert.equal(res.body.newStar, 3);
    assert.equal(res.body.maxLevel, 30);
    assert.equal(res.body.imprintSlots, 2); // 3-star has 2 imprint slots!
    assert.equal(res.body.silverCost, 25_000);
  });
});
