import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildNow, cleanupAccount, createHero, createMaster, grantItems, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';
import { medicalService } from '../dist/modules/medical/medical.service.js';

after(async()=>{await pool.end();});

test('HTTP lifecycle: retained combat finalizes zero-HP casualties and does not convert them into injuries',{skip:skipReason},async t=>{
  const h=await startHarness(),master=await createMaster(h.request,'oldlife');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  const normal=await createHero(master.masterId),special=await createHero(master.masterId,{category:'SPECIAL'});
  await grantItems(master.masterId,{FOOD:1000});
  const party=await h.request('/api/combat/party',{method:'PUT',token:master.token,body:{heroIds:[normal.id,special.id]}});assert.equal(party.status,200);
  const start=await h.request('/api/combat/session/start',{method:'POST',token:master.token,body:{}});assert.equal(start.status,201);
  const session=(await sql("select id,combat_state from combat_sessions where master_id=$1 and status='ACTIVE'",[master.masterId])).rows[0];
  for(const unit of session.combat_state.heroes) {unit.hp=0;if(unit.id===normal.id)delete unit.origin;}
  await sql('update combat_sessions set combat_state=$2::jsonb where id=$1',[session.id,JSON.stringify(session.combat_state)]);
  const {CombatSessionService}=await import('../dist/modules/combat/combat-session.service.js');
  await assert.rejects(()=>new CombatSessionService().retreat(master.masterId,session.id),/tử trận/);
  const finished=await h.request(`/api/combat/session/${session.id}/advance`,{method:'POST',token:master.token});assert.equal(finished.status,200);
  const rows=(await sql('select id,state,hp,current_hp_pct from heroes where id=any($1::varchar[])',[[normal.id,special.id]])).rows;
  assert.equal(rows.find(r=>r.id===normal.id).state,'DEAD');assert.equal(rows.find(r=>r.id===special.id).state,'DEAD');
  assert.ok(rows.every(r=>r.hp===0&&r.current_hp_pct===0));
  const again=await h.request(`/api/combat/session/${session.id}/advance`,{method:'POST',token:master.token});assert.equal(again.status,200);
  assert.equal((await sql('select count(*)::int n from hero_death_records where master_id=$1',[master.masterId])).rows[0].n,2);
});
test('HTTP lifecycle: casualties are not injuries, cannot perform activities, and stale care never revives them', {skip:skipReason},async t=>{
  const h=await startHarness(),master=await createMaster(h.request,'lifecycle');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  const request=(p,o={})=>h.request(p,{token:master.token,...o});
  const post=(p,body)=>request(p,{method:'POST',body});
  await sql('update worlds set current_floor=4 where master_id=$1',[master.masterId]);
  await sql('update masters set silver_coins=100000 where id=$1',[master.masterId]);
  const facility=await buildNow(h.request,master,'MEDICAL',1);
  await grantItems(master.masterId,{MEDICINE:4,FOOD:100,RESURRECTION_GEM_7:5});
  const normal=await createHero(master.masterId,{hp:0,maxHp:100}),special=await createHero(master.masterId,{category:'SPECIAL',hp:0,maxHp:100});
  await sql("update heroes set state=case when category='NORMAL' then 'DEAD' else 'DISABLED' end,current_hp_pct=0 where id=any($1::varchar[])",[[normal.id,special.id]]);
  assert.equal((await medicalService.recordBattleInjuries(master.masterId,[{id:normal.id,hp:5,maxHp:100},{id:special.id,hp:5,maxHp:100}])).injured,0);
  for(const hero of [normal,special]) {
    const injury=(await sql("insert into hero_injuries (id,hero_id,master_id,severity,penalty_percent,natural_heal_at) values (gen_random_uuid()::text,$1,$2,'SEVERE',25,now()+interval '2 hours') returning id",[hero.id,master.masterId])).rows[0];
    await sql("insert into hero_treatments (id,master_id,hero_id,building_id,injury_id,treatment_type,status,finishes_at) values (gen_random_uuid()::text,$1,$2,$3,$4,'INJURY','ACTIVE',now()-interval '1 minute')",[master.masterId,hero.id,facility.id,injury.id]);
  }
  const overview=await request('/api/medical');assert.equal(overview.status,200);
  assert.equal(overview.body.activeTreatments.length,0);assert.equal(overview.body.candidates.length,0);assert.equal(overview.body.injuries.length,0);
  assert.ok((await sql('select status from hero_treatments where master_id=$1',[master.masterId])).rows.every(r=>r.status==='CANCELLED'));
  for(const hero of [normal,special]) {
    for(const [path,body] of [
      ['/api/medical/treatments',{heroId:hero.id}],['/api/medical/emergency',{heroId:hero.id}],
      [`/api/survival/heroes/${hero.id}/feed`,{quantity:1}],[`/api/survival/heroes/${hero.id}/rest`,{}],
      [`/api/base/buildings/${facility.id}/workers`,{heroId:hero.id}],
    ]) assert.equal((await post(path,body)).status,409,path);
  }
  assert.ok((await sql('select hp,state from heroes where id=any($1::varchar[])',[[normal.id,special.id]])).rows.every(r=>r.hp===0&&['DEAD','DISABLED'].includes(r.state)));
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='MEDICINE'",[master.masterId])).rows[0].quantity,4);
  assert.equal((await request('/api/survival')).body.heroes.length,0);
  assert.equal((await post('/api/medical/resurrect',{heroId:normal.id})).status,200);
  assert.equal((await post('/api/medical/resurrect',{heroId:special.id})).status,200);
  const restored=(await sql('select state,hp,current_hp_pct from heroes where id=$1',[special.id])).rows[0];
  assert.equal(restored.state,'HEALTHY');assert.ok(restored.hp>0);assert.ok(restored.current_hp_pct>0);
  assert.equal((await sql('select healed_by from hero_injuries where hero_id=$1',[special.id])).rows[0].healed_by,'RESURRECTION');
  // Living nonterminal states must not be accepted by the resurrection endpoint.
  await sql("update heroes set state='RESTING' where id=$1",[special.id]);
  assert.equal((await post('/api/medical/resurrect',{heroId:special.id})).status,409);
});

test('HTTP lifecycle: simultaneous Quick Heal requests charge one medicine for one restored Hero',{skip:skipReason},async t=>{
  const h=await startHarness(),master=await createMaster(h.request,'healrace');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  const hero=await createHero(master.masterId,{hp:20,maxHp:100});
  await grantItems(master.masterId,{MEDICINE:2});
  const results=await Promise.all([0,1].map(()=>h.request('/api/medical/emergency',{method:'POST',token:master.token,body:{heroId:hero.id}})));
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='MEDICINE'",[master.masterId])).rows[0].quantity,1);
});
