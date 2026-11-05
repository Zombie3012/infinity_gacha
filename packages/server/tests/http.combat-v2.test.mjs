import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP combat v2: simulate a battle', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const master = await createMaster(harness.request, 'cv2');
  t.after(async () => {
    await cleanupAccount(master.accountId);
    await harness.close();
  });

  const hero = await createHero(master.masterId, {
    name: 'Vanguard', attack: 8_000, defense: 3_000, speed: 200, hp: 90_000, maxHp: 90_000,
  });
  const enemyCode = (await sql('select code from enemy_templates where is_active = true order by code limit 1')).rows[0].code;

  await t.test('a strong party wins and receives a full battle report', async () => {
    const simulated = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], maxRounds: 10, seed: 42 },
    });
    assert.equal(simulated.status, 200);
    assert.equal(simulated.body.winner, 'HERO');
    assert.ok(simulated.body.rounds >= 1);
    assert.ok(simulated.body.log.length > 0);
    assert.ok(simulated.body.totalDamage > 0);

    const replay = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: [hero.id], enemyCodes: [enemyCode], maxRounds: 10, seed: 42 },
    });
    assert.equal(replay.status, 200);
    assert.deepEqual(
      replay.body.log.map(entry => entry.damage),
      simulated.body.log.map(entry => entry.damage),
    );
  });

  await t.test('unknown Heroes and empty parties are refused', async () => {
    const missing = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token,
      body: { heroIds: ['00000000-0000-0000-0000-000000000000'], enemyCodes: [enemyCode] },
    });
    assert.equal(missing.status, 404);
    assert.equal(missing.body.error, 'ERR_COMBAT_V2_HERO_NOT_FOUND');

    const empty = await harness.request('/api/combat/v2/simulate', {
      method: 'POST', token: master.token, body: { heroIds: [] },
    });
    assert.equal(empty.status, 400);
    assert.equal(empty.body.error, 'ERR_COMBAT_V2_NO_HEROES');
  });
});
