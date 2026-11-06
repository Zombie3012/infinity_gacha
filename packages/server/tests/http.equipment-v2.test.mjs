import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP equipment v2: stat aggregation and hero progression integration', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'eqv2');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const hero = await createHero(master.masterId, {
    name: 'V2 Hero', rarity: 5, hp: 1400, maxHp: 1400,
  });

  // Set hero as Combat v2 with 5-star origin stats and WARRIOR class
  const origin = { str: 70, int: 70, sta: 70, agi: 70 };
  await sql(`update heroes set origin_stats = $1, class_code = 'WARRIOR' where id = $2`, [
    JSON.stringify(origin), hero.id,
  ]);

  // Insert two v2 equipment instances into Master inventory:
  // 1. SAMPLE_STEEL_GREATSWORD: MAIN_HAND, bonusStr: 12, bonusSta: 4, v2Stats: { armorPen: 8, critDamage: 10 }
  // 2. SAMPLE_SWIFT_CHARM: ACCESSORY, bonusAgi: 5, bonusHp: 30, v2Stats: { lifesteal: 5, critRate: 3 }
  const swordId = (await sql(`insert into equipment_instances (id, master_id, template_code, location)
                              values (gen_random_uuid()::text, $1, 'SAMPLE_STEEL_GREATSWORD', 'INVENTORY')
                              returning id`, [master.masterId])).rows[0].id;
  const charmId = (await sql(`insert into equipment_instances (id, master_id, template_code, location)
                              values (gen_random_uuid()::text, $1, 'SAMPLE_SWIFT_CHARM', 'INVENTORY')
                              returning id`, [master.masterId])).rows[0].id;

  let baseEffective;
  let baseDerived;

  await t.test('unequipped hero exposes baseline v2 stats in /api/heroes', async () => {
    const list = await harness.request('/api/heroes', { token: master.token });
    assert.equal(list.status, 200);
    const item = list.body.find(h => h.id === hero.id);
    assert.ok(item);
    assert.ok(item.effectiveBaseStats);
    assert.ok(item.v2Stats);
    baseEffective = { ...item.effectiveBaseStats };
    baseDerived = { ...item.derivedStats };
  });

  await t.test('equipping v2 weapon and accessory boosts base and derived stats', async () => {
    const equipSword = await harness.request(`/api/equipment/${swordId}/equip`, {
      method: 'PUT', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(equipSword.status, 200);

    const equipCharm = await harness.request(`/api/equipment/${charmId}/equip`, {
      method: 'PUT', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(equipCharm.status, 200);

    const list = await harness.request('/api/heroes', { token: master.token });
    assert.equal(list.status, 200);
    const item = list.body.find(h => h.id === hero.id);
    assert.ok(item);

    // STR increased by 12, STA increased by 4, AGI increased by 5
    assert.equal(item.effectiveBaseStats.str - baseEffective.str, 12);
    assert.equal(item.effectiveBaseStats.sta - baseEffective.sta, 4);
    assert.equal(item.effectiveBaseStats.agi - baseEffective.agi, 5);

    // STA +4 gives 80 HP, charm flat bonusHp gives 30 HP => maxHp increase = 110
    assert.equal(item.derivedStats.maxHp - baseDerived.maxHp, 110);
    assert.ok(item.derivedStats.attack > baseDerived.attack);
    assert.equal(item.v2Stats.critDamage - 150, 10);
    assert.equal(item.v2Stats.armorPen, 8);
    assert.equal(item.v2Stats.lifesteal, 5);
  });

  await t.test('combat v2 simulation incorporates equipped gear bonuses', async () => {
    const enemyCode = (await sql('select code from enemy_templates where is_active = true order by code limit 1')).rows[0].code;
    const sim = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], seed: 42, maxRounds: 6 },
    });
    assert.equal(sim.status, 200);
    const unit = sim.body.units.find(u => u.id === hero.id);
    assert.ok(unit);
    // Unit stats reflect equipment-boosted maxHp
    assert.equal(unit.maxHp, baseDerived.maxHp + 110);
  });

  await t.test('unequipping removes bonuses and restores original stats', async () => {
    const unequipSword = await harness.request(`/api/equipment/${swordId}/unequip`, {
      method: 'POST', token: master.token,
    });
    assert.equal(unequipSword.status, 200);

    const unequipCharm = await harness.request(`/api/equipment/${charmId}/unequip`, {
      method: 'POST', token: master.token,
    });
    assert.equal(unequipCharm.status, 200);

    const list = await harness.request('/api/heroes', { token: master.token });
    assert.equal(list.status, 200);
    const item = list.body.find(h => h.id === hero.id);
    assert.deepEqual(item.effectiveBaseStats, baseEffective);
    assert.equal(item.derivedStats.maxHp, baseDerived.maxHp);
  });
});
