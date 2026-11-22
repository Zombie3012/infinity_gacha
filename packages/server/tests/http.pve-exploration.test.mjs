import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createPveExploration, materializePveArea } from '@infiniti-gacha/shared';
import { cleanupAccount, createHero, createMaster, grantItems, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';

after(async () => { await pool.end(); });
async function fixture(t, teams = 1) {
  const h = await startHarness(), master = await createMaster(h.request, 'areas');
  t.after(async () => { await cleanupAccount(master.accountId); await h.close(); });
  const request = (p, o={}) => h.request(p,{token:master.token,...o});
  const command = (p,body={},key=randomUUID()) => request(p,{method:'POST',body,headers:{'Idempotency-Key':key}});
  await grantItems(master.masterId,{FOOD:10000});
  const entry=await command('/api/pve/enter'); assert.equal(entry.status,201);
  const squads=[];
  for(let i=0;i<teams;i++) {
    const hero=await createHero(master.masterId,{name:`Explorer ${i}`,attack:8000,defense:3000,speed:200,hp:90000,maxHp:90000});
    const party=await command('/api/pve/parties',{name:`Explorers ${i}`,heroIds:[hero.id]}); assert.equal(party.status,201);
    const deployed=await command(`/api/pve/parties/${party.body.partyId}/deploy`); assert.equal(deployed.status,201);
    squads.push(deployed.body.squadId);
  }
  const mapId=entry.body.mapId;
  const load=async()=> (await sql('select exploration from pve_maps where id=$1',[mapId])).rows[0].exploration;
  const save=async w=>sql('update pve_maps set exploration=$2::jsonb where id=$1',[mapId,JSON.stringify(w)]);
  const due=async id=>sql("update pve_squads set next_step_at=clock_timestamp()-interval '20 milliseconds' where id=$1",[id]);
  return {master,request,command,squads,mapId,load,save,due};
}
const flatten=a=>{for(const t of a.tiles){t.kind='EMPTY';delete t.resource;}a.discovered=a.tiles.map(t=>t.id);};

test('HTTP exploration: area context, timed/idempotent portals, independent teams and resource collision', {skip:skipReason},async t=>{
  const f=await fixture(t,3), [one,two,three]=f.squads;
  let state=await f.request('/api/pve/state');
  assert.equal(state.body.map.algorithmVersion,3);assert.equal(state.body.areas.length,1);
  assert.equal(state.body.objective.type,'DEFEAT_BOSS');
  let w=await f.load(); w.enemies=[]; flatten(w.areas.floor); await f.save(w);
  assert.equal((await f.command(`/api/pve/squads/${one}/move`,{x:1,y:0})).status,400);
  assert.equal((await f.command(`/api/pve/squads/${one}/portal`,{areaId:'floor',portalId:'region:1'})).status,400);
  const payload={areaId:'floor',portalId:'region:0'};
  const a=await f.command(`/api/pve/squads/${one}/portal`,payload,'door'); assert.equal(a.status,200);
  assert.ok(Date.parse(a.body.nextStepAt)-Date.now()>700);
  assert.deepEqual((await f.command(`/api/pve/squads/${one}/portal`,payload,'door')).body,a.body);
  await f.due(one); state=await f.request('/api/pve/state');
  assert.equal(state.body.squads.find(s=>s.id===one).areaId,'region:0');
  assert.equal(state.body.squads.find(s=>s.id===two).areaId,'floor');
  assert.equal(state.body.areas.find(a=>a.id==='region:0').width,20);
  assert.deepEqual((await f.request('/api/pve/state')).body.areas,state.body.areas,'reload keeps materialized terrain');
  w=await f.load(); flatten(w.areas['region:0']);
  w.areas['region:0'].tiles[1].kind='RESOURCE';w.areas['region:0'].tiles[1].resource={itemId:'WOOD',quantity:37};await f.save(w);
  await sql("update pve_squads set area_id='region:0' where id=$1",[two]);
  const before=(await sql("select quantity from master_items where master_id=$1 and item_id='WOOD'",[f.master.masterId])).rows[0]?.quantity??0;
  for(const id of [one,two]) assert.equal((await f.command(`/api/pve/squads/${id}/move`,{areaId:'region:0',x:1,y:0})).status,200);
  await sql("update pve_squads set next_step_at=clock_timestamp()-interval '20 milliseconds' where id=any($1::varchar[])",[[one,two]]);
  const parallel=await Promise.all([f.request('/api/pve/state'),f.request('/api/pve/state')]);
  assert.ok(parallel.every(r=>r.status===200));
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='WOOD'",[f.master.masterId])).rows[0].quantity,before+37);
  assert.equal((await f.request('/api/pve/state')).body.squads.find(s=>s.id===three).areaId,'floor');
  assert.equal((await f.command(`/api/pve/squads/${one}/move`,{areaId:'floor',x:2,y:0})).status,400);
  w=await f.load();const enemy=createPveExploration('collision',1).enemies[0];
  Object.assign(enemy,{areaId:'region:0',x:2,y:0,home:{areaId:'region:0',x:2,y:0}});w.enemies=[enemy];await f.save(w);
  for(const id of [one,two]) assert.equal((await f.command(`/api/pve/squads/${id}/move`,{areaId:'region:0',x:2,y:0})).status,200);
  await sql("update pve_squads set next_step_at=clock_timestamp()-interval '20 milliseconds' where id=any($1::varchar[])",[[one,two]]);
  await Promise.all([f.request('/api/pve/state'),f.request('/api/pve/state')]);
  assert.equal((await f.request('/api/pve/battles')).body.battles.length,1,'two squads cannot settle one mobile enemy twice');
  assert.equal((await f.load()).enemies[0].state,'DEAD');
});

test('HTTP pursuit: recall locked, 1500ms enemy steps, observed portal crossing and lost target', {skip:skipReason},async t=>{
  const f=await fixture(t), id=f.squads[0];let w=await f.load();flatten(w.areas.floor);
  const enemy=w.enemies[0];w.enemies=[enemy];Object.assign(enemy,{x:3,y:0,home:{areaId:'floor',x:3,y:0}});await f.save(w);
  await f.command(`/api/pve/squads/${id}/move`,{areaId:'floor',x:1,y:0});await f.due(id);
  let state=await f.request('/api/pve/state');assert.equal(state.body.squads[0].pursued,true);
  w=await f.load();assert.equal(w.enemies[0].state,'CHASE');
  const arrived=(await sql("select occurred_at from pve_events where map_id=$1 and kind='SQUAD_ARRIVED' order by revision desc limit 1",[f.mapId])).rows[0];
  assert.equal(w.enemies[0].nextStepAt-new Date(arrived.occurred_at).getTime(),1500);
  assert.equal((await f.command(`/api/pve/squads/${id}/recall`)).body.error,'ERR_PVE_SQUAD_PURSUED');
  const p={areaId:'floor',portalId:'region:1'};
  assert.equal((await f.command(`/api/pve/squads/${id}/portal`,p)).status,200);await f.due(id);await f.request('/api/pve/state');
  w=await f.load();assert.equal(w.enemies[0].lastSeen.areaId,'region:1');
  await sql('update pve_squads set x=3,y=0 where id=$1',[id]);
  // Move the follower to the already observed door, then make its next step due.
  Object.assign(w.enemies[0],{x:1,y:0,nextStepAt:Date.now()-20});await f.save(w);
  state=await f.request('/api/pve/state');w=await f.load();assert.equal(w.enemies[0].areaId,'region:1');
  // Player disappears behind cover/into another area; no remote position tracking.
  await sql("update pve_squads set area_id='floor',x=11,y=11 where id=$1",[id]);
  w.enemies[0].nextStepAt=Date.now()-20;await f.save(w);await f.request('/api/pve/state');w=await f.load();
  assert.ok(['INVESTIGATE','RETURN'].includes(w.enemies[0].state));
});

test('HTTP ambush: unseen doorway contact, one settlement, objective boss killed outside its building', {skip:skipReason},async t=>{
  const f=await fixture(t,2),[one,two]=f.squads;let w=await f.load();
  const building=w.buildings.find(b=>b.main);const region=materializePveArea(w,`region:${building.parentTileId}`);
  const inside=materializePveArea(w,building.areaId);flatten(region);flatten(inside);flatten(w.areas.floor);
  const boss=w.enemies.find(e=>e.id===w.objective.targetId);w.enemies=[boss];
  const exit=region.portals[0];Object.assign(boss,{areaId:'floor',x:exit.arrival.x,y:exit.arrival.y,nextStepAt:null,state:'IDLE'});
  await f.save(w);await sql('update pve_squads set area_id=$2,x=0,y=0 where id=$1',[one,region.id]);
  const body={areaId:region.id,portalId:exit.id};
  const ordered=await f.command(`/api/pve/squads/${one}/portal`,body,'boss-exit');assert.equal(ordered.status,200);
  await f.due(one);const states=await Promise.all([f.request('/api/pve/state'),f.request('/api/pve/state')]);
  assert.ok(states.every(s=>s.status===200));const state=states[0].body;
  assert.equal(state.map.status,'CLEARED');assert.equal(state.objective.status,'COMPLETED');assert.equal(state.objective.progress,1);
  assert.ok(state.squads.every(s=>s.status==='WITHDRAWN'));
  assert.equal(state.squads.find(s=>s.id===two).nextStepAt,null);
  const battles=(await f.request('/api/pve/battles')).body.battles;assert.equal(battles.length,1);
  const battle=(await f.request(`/api/pve/battles/${battles[0].id}`)).body;
  assert.equal(battle.settlement.areaId,'floor');assert.equal(battle.settlement.enemyId,w.objective.targetId);
  assert.equal(battle.report.ambush,true);assert.equal(battle.report.log.filter(e=>e.round===0).length,3);
  assert.ok(battle.report.log.filter(e=>e.round===0).every(e=>e.actorId.includes(':')));
  const replay=await f.command(`/api/pve/squads/${one}/portal`,body,'boss-exit');assert.deepEqual(replay.body,ordered.body);
  assert.equal((await f.request('/api/pve/battles')).body.battles.length,1);
  assert.equal((await sql('select count(*)::int n from pve_hero_reservations where map_id=$1',[f.mapId])).rows[0].n,0);
  assert.equal((await f.command('/api/pve/enter')).body.floor,2);
});

test('HTTP v2 failure rolls back objective, enemy, route, rewards and combat before retry', {skip:skipReason},async t=>{
  const f=await fixture(t), id=f.squads[0];let w=await f.load();flatten(w.areas.floor);
  const main=w.buildings.find(b=>b.main);materializePveArea(w,`region:${main.parentTileId}`);materializePveArea(w,main.areaId);
  const boss=w.enemies.find(e=>e.id===w.objective.targetId);Object.assign(boss,{areaId:'floor',x:1,y:0});w.enemies=[boss];await f.save(w);
  await f.command(`/api/pve/squads/${id}/move`,{areaId:'floor',x:1,y:0});await f.due(id);
  const before=(await sql('select silver_coins from masters where id=$1',[f.master.masterId])).rows[0].silver_coins;
  const tag='pve_fault_'+randomUUID().replaceAll('-','');
  await sql(`create function ${tag}() returns trigger language plpgsql as $$ begin if NEW.map_id='${f.mapId}' then raise exception 'EXPECTED_PVE_V2_ROLLBACK'; end if; return NEW; end $$`);
  await sql(`create trigger ${tag} before insert on pve_battles for each row execute function ${tag}()`);
  const drop=async()=>{await sql(`drop trigger if exists ${tag} on pve_battles`);await sql(`drop function if exists ${tag}()`);};t.after(drop);
  assert.equal((await f.request('/api/pve/state')).status,500);
  const rolled=await f.load();assert.equal(rolled.objective.status,'ACTIVE');assert.notEqual(rolled.enemies[0].state,'DEAD');
  assert.equal((await sql('select x from pve_squads where id=$1',[id])).rows[0].x,0);
  assert.equal((await sql('select silver_coins from masters where id=$1',[f.master.masterId])).rows[0].silver_coins,before);
  assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1',[f.mapId])).rows[0].n,0);
  await drop();
  const state=await f.request('/api/pve/state');assert.equal(state.body.objective.status,'COMPLETED');
  await f.request('/api/pve/state');assert.equal((await f.request('/api/pve/battles')).body.battles.length,1);
});

test('HTTP long offline catch-up commits bounded progress and cannot be overtaken by a new order', {skip:skipReason},async t=>{
  const f=await fixture(t),id=f.squads[0],w=await f.load();w.enemies=[];flatten(w.areas.floor);await f.save(w);
  const route=Array.from({length:1100},(_,i)=>({x:(i+1)%2,y:0}));
  await sql("update pve_squads set route=$2::jsonb,status='MOVING',next_step_at=clock_timestamp()-interval '2000 seconds' where id=$1",[id,JSON.stringify(route)]);
  const path=`/api/pve/squads/${id}/recall`;
  assert.equal((await f.command(path,{},'offline-recall')).body.error,'ERR_PVE_CATCHUP_PENDING');
  assert.equal((await sql("select count(*)::int n from pve_commands where master_id=$1 and key='offline-recall'",[f.master.masterId])).rows[0].n,0);
  assert.equal((await sql('select route from pve_squads where id=$1',[id])).rows[0].route.length,588);
  const next=await f.request('/api/pve/state');assert.equal(next.body.catchupPending,true);
  const done=await f.request('/api/pve/state');assert.equal(done.body.catchupPending,false);
  assert.equal((await f.command(path,{},'offline-recall')).body.status,'WITHDRAWN');
});
