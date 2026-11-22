import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildNow, cleanupAccount, createHero, createMaster, dbReady, grantItems, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP medical: injuries, treatment and Divine Grace', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'med');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const hero = await createHero(master.masterId);
  await sql('update worlds set current_floor = 4 where master_id = $1', [master.masterId]);
  await sql('update masters set silver_coins = 200000 where id = $1', [master.masterId]);
  await buildNow(harness.request, master, 'MEDICAL', 1);

  await t.test('the facility advertises beds and level', async () => {
    const overview = await harness.request('/api/medical', { token: master.token });
    assert.equal(overview.status, 200);
    assert.equal(overview.body.facility.level, 1);
    assert.equal(overview.body.facility.capacity, 2);
  });

  await t.test('an injury is visible with its penalty multiplier', async () => {
    await sql(`insert into hero_injuries (id, hero_id, master_id, severity, penalty_percent, natural_heal_at, started_at)
               values (gen_random_uuid()::text, $1, $2, 'SEVERE', 25, now() + interval '2 hours', now())`, [hero.id, master.masterId]);
    await sql(`update heroes set state = 'INJURED', hp = 10 where id = $1`, [hero.id]);

    const overview = await harness.request('/api/medical', { token: master.token });
    assert.equal(overview.body.injuries.length, 1);
    assert.equal(overview.body.injuries[0].attackMultiplier, 0.75);
  });

  await t.test('admitting a Hero starts a treatment timer', async () => {
    const admitted = await harness.request('/api/medical/treatments', {
      method: 'POST', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(admitted.status, 201);
    assert.ok(admitted.body.seconds >= 60);
    assert.equal(admitted.body.treatment.status, 'ACTIVE');

    const overview = await harness.request('/api/medical', { token: master.token });
    assert.equal(overview.body.facility.bedsUsed, 1);
  });

  await t.test('emergency treatment needs MEDICINE and heals instantly', async () => {
    const blocked = await harness.request('/api/medical/emergency', {
      method: 'POST', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(blocked.status, 409);

    await grantItems(master.masterId, { MEDICINE: 1 });
    const healed = await harness.request('/api/medical/emergency', {
      method: 'POST', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(healed.status, 200);
    assert.equal(healed.body.healed, true);

    const overview = await harness.request('/api/medical', { token: master.token });
    assert.equal(overview.body.injuries.length, 0);
  });

  await t.test('All Heroes can resurrect with one seven-star gem', async () => {
    await sql(`update heroes set state = 'DISABLED', category = 'NORMAL', hp = 0 where id = $1`, [hero.id]);
    await grantItems(master.masterId, { RESURRECTION_GEM_7: 1 });
    const refused = await harness.request('/api/medical/resurrect', {
      method: 'POST', token: master.token, body: { heroId: hero.id },
    });
    assert.equal(refused.status, 200);
    assert.equal(refused.body.gemsUsed, 1);
    assert.equal(refused.body.silverSpent, 0);
  });
});
