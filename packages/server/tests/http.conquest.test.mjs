import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cleanupAccount, createHero, createMaster, dbReady, setSilver, skipReason, sql, startHarness,
} from './helpers/harness.mjs';

test('HTTP conquest: alliance war, Wonder siege and season settlement', { skip: skipReason }, async t => {
  const harness = await startHarness();
  const alpha = await createMaster(harness.request, 'warA');
  const beta = await createMaster(harness.request, 'warB');
  t.after(async () => {
    await cleanupAccount(alpha.accountId);
    await cleanupAccount(beta.accountId);
    await harness.close();
  });

  let alphaAllianceId = '';
  let betaAllianceId = '';
  let warId = '';
  let activeSeasonId = '';

  await t.test('two level-20 Masters found rival alliances', async () => {
    for (const master of [alpha, beta]) {
      await sql('update masters set level = 20 where id = $1', [master.masterId]);
      await setSilver(master.masterId, 600_000);
    }
    const first = await harness.request('/api/alliance', {
      method: 'POST', token: alpha.token, body: { name: 'Alpha Legion', tag: 'AL1' },
    });
    assert.equal(first.status, 201);
    alphaAllianceId = first.body.alliance.id;

    const second = await harness.request('/api/alliance', {
      method: 'POST', token: beta.token, body: { name: 'Beta Legion', tag: 'BL1' },
    });
    assert.equal(second.status, 201);
    betaAllianceId = second.body.alliance.id;

    await createHero(alpha.masterId, { attack: 10_000, defense: 8_000, speed: 400, hp: 120_000 });
    await createHero(beta.masterId, { attack: 10, defense: 5, speed: 5, hp: 100 });

    const overview = await harness.request('/api/world/conquest', { token: alpha.token });
    assert.equal(overview.status, 200);
    assert.equal(overview.body.season.status, 'ACTIVE');
    assert.equal(overview.body.myAlliance.canDeclareWar, true);
    activeSeasonId = overview.body.season.id;
  });

  await t.test('the leader declares a 24-hour war', async () => {
    const declared = await harness.request('/api/alliance/wars', {
      method: 'POST', token: alpha.token, body: { targetAllianceId: betaAllianceId },
    });
    assert.equal(declared.status, 201);
    warId = declared.body.id;
    assert.equal(declared.body.declaringAllianceId, alphaAllianceId);
    assert.equal(declared.body.targetAllianceId, betaAllianceId);
    assert.ok(declared.body.secondsRemaining > 86_000);

    const busy = await harness.request('/api/alliance/wars', {
      method: 'POST', token: beta.token, body: { targetAllianceId: alphaAllianceId },
    });
    assert.equal(busy.status, 409);
    assert.equal(busy.body.error, 'ERR_ALLIANCE_WAR_BUSY');

    const list = await harness.request('/api/alliance/wars', { token: beta.token });
    assert.equal(list.status, 200);
    assert.equal(list.body.wars.length, 1);
    assert.equal(list.body.wars[0].opponent.tag, 'AL1');
    assert.equal(list.body.wars[0].viewerSide, 'TARGET');
  });

  await t.test('a won hero raid on an enemy territory scores war points', async () => {
    // Place both Masters on the same spot, give Beta an owned tile, then raid it.
    const tiles = (await sql(`select t.id, t.x, t.y from world_tiles t
                              left join territories te on te.tile_id = t.id
                              where te.id is null and t.terrain <> 'WONDER'
                              order by t.x limit 2`)).rows;
    const [home, target] = tiles;

    for (const master of [alpha, beta]) {
      await sql(`insert into master_world_status (master_id, unlocked_at, base_x, base_y, shield_until)
                 values ($1, now() - interval '10 days', $2, $3, now() - interval '5 days')
                 on conflict (master_id) do update set base_x = $2, base_y = $3, shield_until = now() - interval '5 days'`,
        [master.masterId, home.x, home.y]);
    }
    await sql(`insert into tile_discoveries (id, master_id, tile_id, discovered_at)
               values (gen_random_uuid()::text, $1, $2, now())
               on conflict (master_id, tile_id) do nothing`, [alpha.masterId, target.id]);
    await sql(`insert into territories (id, tile_id, master_id, level, status, claimed_at, protected_until, updated_at)
               values (gen_random_uuid()::text, $1, $2, 1, 'OWNED', now() - interval '2 days', null, now())`,
      [target.id, beta.masterId]);

    const heroId = (await sql('select id from heroes where master_id = $1 limit 1', [alpha.masterId])).rows[0].id;
    const dispatched = await harness.request('/api/world/expeditions', {
      method: 'POST', token: alpha.token,
      body: { tileId: target.id, mission: 'ATTACK', heroIds: [heroId] },
    });
    assert.equal(dispatched.status, 201);
    await sql(`update hero_expeditions set arrive_at = now() - interval '1 minute' where id = $1`,
      [dispatched.body.expeditionId]);

    const settled = await harness.request('/api/world/expeditions', { token: alpha.token });
    const trip = settled.body.find(row => row.id === dispatched.body.expeditionId);
    assert.equal(trip.result.kind, 'PVP_REPORT');
    assert.equal(trip.result.won, true);

    const war = await harness.request('/api/alliance/wars', { token: alpha.token });
    const row = war.body.wars.find(entry => entry.id === warId);
    assert.equal(row.declaringPoints, 100);

    const ranking = await harness.request('/api/world/conquest/ranking', { token: alpha.token });
    assert.equal(ranking.body.entries[0].points, 100);
  });

  await t.test('the war resolves on points and pays both sides through the mailbox', async () => {
    await sql(`update alliance_wars set declaring_points = 300, target_points = 100,
               ends_at = now() - interval '1 minute' where id = $1`, [warId]);

    const resolved = await harness.request('/api/alliance/wars', { token: alpha.token });
    const war = resolved.body.wars.find(row => row.id === warId);
    assert.equal(war.status, 'RESOLVED');
    assert.equal(war.winnerAllianceId, alphaAllianceId);

    const mail = await harness.request('/api/mailbox', { token: alpha.token });
    assert.equal(mail.status, 200);
    assert.ok(mail.body.unclaimed.some(message => message.subject.includes('Chiến thắng')));

    const betaMail = await harness.request('/api/mailbox', { token: beta.token });
    assert.ok(betaMail.body.unclaimed.some(message => message.subject.includes('Kết thúc')));

    const ranking = await harness.request('/api/world/conquest/ranking', { token: alpha.token });
    assert.equal(ranking.body.entries[0].allianceId, alphaAllianceId);
    // 100 from the won raid + 300 victory points; the 300 war points were seeded directly.
    assert.equal(ranking.body.entries[0].points, 400);
  });

  await t.test('the Wonder opens only in the final three days', async () => {
    const closed = await harness.request('/api/world/conquest/wonder/siege', { method: 'POST', token: alpha.token });
    assert.equal(closed.status, 409);
    assert.equal(closed.body.error, 'ERR_WONDER_NOT_CONTESTED');

    await sql(`update world_conquest_seasons
               set start_time = now() - interval '28 days', end_time = now() + interval '2 days'
               where id = $1`, [activeSeasonId]);
    const open = await harness.request('/api/world/conquest', { token: alpha.token });
    assert.equal(open.body.wonder.contestOpen, true);
    assert.equal(open.body.wonder.holder, null);
  });

  await t.test('a strong alliance seizes the Wonder and cannot re-seize it', async () => {
    const siege = await harness.request('/api/world/conquest/wonder/siege', { method: 'POST', token: alpha.token });
    assert.equal(siege.status, 200);
    assert.equal(siege.body.won, true);
    assert.equal(siege.body.holderAllianceId, alphaAllianceId);

    const again = await harness.request('/api/world/conquest/wonder/siege', { method: 'POST', token: alpha.token });
    assert.equal(again.status, 409);
    assert.equal(again.body.error, 'ERR_WONDER_ALREADY_HELD');

    const weak = await harness.request('/api/world/conquest/wonder/siege', { method: 'POST', token: beta.token });
    assert.equal(weak.status, 200);
    assert.equal(weak.body.won, false);

    const state = await harness.request('/api/world/conquest', { token: beta.token });
    assert.equal(state.body.wonder.holder.tag, 'AL1');
    assert.ok(state.body.wonder.percent >= 0);
  });

  await t.test('an 8-hour hold conquers the season and pays the crown', async () => {
    await sql(`update wonder_holdings set accumulated_seconds = 28800, last_settled_at = now()
               where alliance_id = $1`, [alphaAllianceId]);

    const [before] = (await sql(`select quantity from master_summon_inventory
                                 where master_id = $1 and scroll_type = 'SPECIAL'`, [alpha.masterId])).rows;
    const holder = await harness.request('/api/world/conquest', { token: alpha.token });
    assert.equal(holder.status, 200);
    assert.equal(holder.body.season.status, 'CONCLUDED');
    assert.equal(holder.body.season.conqueringAllianceId, alphaAllianceId);

    const [after] = (await sql(`select quantity from master_summon_inventory
                                where master_id = $1 and scroll_type = 'SPECIAL'`, [alpha.masterId])).rows;
    assert.equal(Number(after.quantity) - Number(before?.quantity ?? 0), 10);

    const seasons = await harness.request('/api/world/conquest/seasons', { token: alpha.token });
    const concluded = seasons.body.find(row => row.id === activeSeasonId);
    assert.equal(concluded.status, 'CONCLUDED');
    assert.equal(concluded.conqueringAllianceId, alphaAllianceId);

    const oldRanking = await harness.request(`/api/world/conquest/ranking?seasonId=${activeSeasonId}`, { token: alpha.token });
    assert.equal(oldRanking.body.entries[0].finalRank, 1);
  });

  await t.test('a fresh season starts with an unclaimed Wonder', async () => {
    const fresh = await harness.request('/api/world/conquest', { token: alpha.token });
    assert.equal(fresh.status, 200);
    assert.equal(fresh.body.season.status, 'ACTIVE');
    assert.equal(fresh.body.wonder.holder, null);
    assert.notEqual(fresh.body.season.id, activeSeasonId);

    const seasons = await harness.request('/api/world/conquest/seasons', { token: alpha.token });
    assert.ok(seasons.body.length >= 2);
    assert.equal(seasons.body[0].status, 'ACTIVE');
  });
});
