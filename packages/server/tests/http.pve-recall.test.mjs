import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { materializePveArea } from '@infiniti-gacha/shared';
import { cleanupAccount, createHero, createMaster, grantItems, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';

after(async()=>{await pool.end();});
async function fixture(t,floor=5) {
  const h=await startHarness(), master=await createMaster(h.request,'recall');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  await sql('update worlds set current_floor=$2 where master_id=$1',[master.masterId,floor]);
  await grantItems(master.masterId,{FOOD:1000,TELEPORT_STONE:2});
  const request=(p,o={})=>h.request(p,{token:master.token,...o});
  const command=(p,body={},key=randomUUID())=>request(p,{method:'POST',body,headers:{'Idempotency-Key':key}});
  const entered=await command('/api/pve/enter');assert.equal(entered.status,201);
  const squads=[];
  for(let i=0;i<2;i++) {
    const hero=await createHero(master.masterId,{hp:90000,maxHp:90000,attack:8000,defense:3000,speed:200});
    const saved=await command('/api/pve/parties',{name:`Recall ${i}`,heroIds:[hero.id]});assert.equal(saved.status,201);
    const deployed=await command(`/api/pve/parties/${saved.body.partyId}/deploy`);assert.equal(deployed.status,201);squads.push(deployed.body.squadId);
  }
  return {master,request,command,squads,mapId:entered.body.mapId};
}
const body={areaId:'floor',x:0,y:0};

test('HTTP recall: shared stone point, atomic retries, position validation and escape from pursuit', {skip:skipReason},async t=>{
  const f=await fixture(t,1),[one,two]=f.squads;
  const initial=(await sql('select exploration from pve_maps where id=$1',[f.mapId])).rows[0].exploration;
  Object.assign(initial.enemies[0],{targetSquadId:one,state:'CHASE',nextStepAt:Date.now()+60000});
  await sql('update pve_maps set exploration=$2::jsonb where id=$1',[f.mapId,JSON.stringify(initial)]);
  let state=(await f.request('/api/pve/state')).body;
  assert.equal(state.map.recallPolicy,'FREE');assert.equal(state.squads.find(s=>s.id===one).canRecall,false);
  assert.equal((await f.command(`/api/pve/squads/${one}/recall`)).body.error,'ERR_PVE_SQUAD_PURSUED');
  assert.equal((await f.command(`/api/pve/squads/${one}/recall-point`,{...body,x:1})).status,400);
  const placed=await Promise.all([f.command(`/api/pve/squads/${one}/recall-point`,body,'stone'),f.command(`/api/pve/squads/${one}/recall-point`,body,'stone')]);
  assert.ok(placed.every(r=>r.status===200));assert.deepEqual(placed[0].body,placed[1].body);
  state=(await f.request('/api/pve/state')).body;
  assert.equal(state.teleportStones,1);assert.equal(state.map.recallPoints.length,1);assert.ok(state.squads.every(s=>s.canRecall));
  await sql("update pve_squads set status='FIGHTING' where id=$1",[one]);
  assert.equal((await f.command(`/api/pve/squads/${one}/recall`)).body.error,'ERR_PVE_SQUAD_FIGHTING');
  await sql("update pve_squads set status='IDLE' where id=$1",[one]);
  assert.equal((await f.command(`/api/pve/squads/${two}/recall-point`,body)).body.error,'ERR_PVE_RECALL_POINT_EXISTS');
  // Same coordinates in a different area are not the same recall point.
  const world=(await sql('select exploration from pve_maps where id=$1',[f.mapId])).rows[0].exploration;
  world.areas.other={...structuredClone(world.areas.floor),id:'other'};
  Object.assign(world.enemies[0],{targetSquadId:two,state:'INVESTIGATE',nextStepAt:Date.now()+60000});
  await sql('update pve_maps set exploration=$2::jsonb where id=$1',[f.mapId,JSON.stringify(world)]);
  await sql("update pve_squads set area_id='other' where id=$1",[two]);
  assert.equal((await f.command(`/api/pve/squads/${two}/recall`)).body.error,'ERR_PVE_SQUAD_PURSUED');
  await sql("update pve_squads set area_id='floor' where id=$1",[two]);
  assert.equal((await f.command(`/api/pve/squads/${two}/recall`)).body.status,'WITHDRAWN');
  const after=(await sql('select exploration from pve_maps where id=$1',[f.mapId])).rows[0].exploration;
  assert.equal(after.enemies[0].state,'RETURN');assert.equal(after.enemies[0].targetSquadId,null);
  assert.equal((await f.command(`/api/pve/squads/${one}/recall`)).body.status,'WITHDRAWN');
  assert.equal((await f.request('/api/pve/state')).body.teleportStones,1);
});

test('HTTP recall: every fifth floor rejects recall and stones even at an existing point', {skip:skipReason},async t=>{
  const f=await fixture(t),id=f.squads[0];
  let state=(await f.request('/api/pve/state')).body;
  assert.equal(state.map.recallPolicy,'UNTIL_COMPLETE');
  assert.equal((await f.command(`/api/pve/squads/${id}/recall`)).body.error,'ERR_PVE_RECALL_LOCKED');
  assert.equal((await f.command(`/api/pve/squads/${id}/recall-point`,body)).body.error,'ERR_PVE_RECALL_LOCKED');
  await sql('update pve_maps set recall_points=$2::jsonb where id=$1',[f.mapId,JSON.stringify([{...body,createdBy:id}])]);
  state=(await f.request('/api/pve/state')).body;
  assert.equal(state.squads.find(s=>s.id===id).canRecall,false);
  assert.equal(state.teleportStones,2);
  assert.equal((await f.command(`/api/pve/squads/${id}/recall`)).body.error,'ERR_PVE_RECALL_LOCKED');
  const w=(await sql('select exploration from pve_maps where id=$1',[f.mapId])).rows[0].exploration;
  const main=w.buildings.find(b=>b.main);materializePveArea(w,`region:${main.parentTileId}`);materializePveArea(w,main.areaId);
  const boss=w.enemies.find(e=>e.id===w.objective.targetId);Object.assign(boss,{areaId:'floor',x:1,y:0});w.enemies=[boss];
  await sql('update pve_maps set exploration=$2::jsonb where id=$1',[f.mapId,JSON.stringify(w)]);
  assert.equal((await f.command(`/api/pve/squads/${id}/move`,{areaId:'floor',x:1,y:0})).status,200);
  await sql("update pve_squads set next_step_at=clock_timestamp()-interval '20 milliseconds' where id=$1",[id]);
  const cleared=(await f.request('/api/pve/state')).body;assert.equal(cleared.map.status,'CLEARED');
  assert.ok(cleared.squads.every(s=>s.status==='WITHDRAWN'),'completing the objective still withdraws squads on a locked floor');
  assert.equal((await f.command('/api/pve/enter')).body.floor,6);
});

test('HTTP recall: ordinary floor remains free and insufficient stones change nothing', {skip:skipReason},async t=>{
  const f=await fixture(t,1),[one,two]=f.squads;
  await grantItems(f.master.masterId,{TELEPORT_STONE:0});
  assert.equal((await f.command(`/api/pve/squads/${one}/recall-point`,body)).body.error,'ERR_PVE_TELEPORT_STONE_REQUIRED');
  assert.equal((await f.request('/api/pve/state')).body.map.recallPoints.length,0);
  assert.equal((await f.command(`/api/pve/squads/${one}/recall`)).body.status,'WITHDRAWN');
  assert.equal((await f.command(`/api/pve/squads/${two}/recall`)).body.status,'WITHDRAWN');
});

test('HTTP recall: explicit floor rule overrides the interval default and stone metadata is available', {skip:skipReason},async t=>{
  const floor=123455;
  const previous=(await sql('select recall_policy from pve_floor_rules where floor=$1',[floor])).rows[0];
  await sql("insert into pve_floor_rules (floor,recall_policy) values ($1,'FREE') on conflict(floor) do update set recall_policy='FREE'",[floor]);
  t.after(async()=>{
    if(previous) await sql('update pve_floor_rules set recall_policy=$2 where floor=$1',[floor,previous.recall_policy]);
    else await sql('delete from pve_floor_rules where floor=$1',[floor]);
  });
  const f=await fixture(t,floor);
  assert.equal((await f.request('/api/pve/state')).body.map.recallPolicy,'FREE');
  assert.equal((await f.command(`/api/pve/squads/${f.squads[0]}/recall`)).body.status,'WITHDRAWN');
  const inventory=(await f.request('/api/inventory')).body;
  const stone=inventory.items.find(i=>i.itemId==='TELEPORT_STONE');assert.equal(stone.name,'Đá dịch chuyển');assert.equal(stone.canUse,false);
  const bought=await f.command('/api/shop/purchase',{itemCode:'TELEPORT_STONE',quantity:1});assert.equal(bought.status,200);
  assert.equal((await f.request('/api/pve/state')).body.teleportStones,3);
});

test('HTTP developer reset: archive, withdraw, replay floor one and keep unrelated progress', {skip:skipReason},async t=>{
  const f=await fixture(t,1),[one]=f.squads;
  await f.command(`/api/pve/squads/${one}/recall-point`,body);
  await sql('update worlds set current_floor=15 where master_id=$1',[f.master.masterId]);
  const wallet=(await sql('select silver_coins from masters where id=$1',[f.master.masterId])).rows[0];
  assert.equal((await f.command('/api/pve/dev/reset-tower',{})).status,400);
  const reset=await Promise.all([f.command('/api/pve/dev/reset-tower',{confirm:true},'reset'),f.command('/api/pve/dev/reset-tower',{confirm:true},'reset')]);
  assert.ok(reset.every(r=>r.status===200));assert.deepEqual(reset[0].body,reset[1].body);assert.equal(reset[0].body.run,1);
  const state=(await f.request('/api/pve/state')).body;assert.equal(state.map,null);assert.equal(state.currentFloor,1);assert.equal(state.run,1);
  assert.equal((await sql('select status from pve_maps where id=$1',[f.mapId])).rows[0].status,'ABANDONED');
  assert.equal((await sql('select count(*)::int n from pve_hero_reservations where master_id=$1',[f.master.masterId])).rows[0].n,0);
  assert.ok((await sql('select status from pve_squads where map_id=$1',[f.mapId])).rows.every(s=>s.status==='WITHDRAWN'));
  assert.deepEqual((await sql('select silver_coins from masters where id=$1',[f.master.masterId])).rows[0],wallet);
  const entered=await f.command('/api/pve/enter');assert.equal(entered.status,201);assert.equal(entered.body.floor,1);assert.notEqual(entered.body.mapId,f.mapId);
  assert.equal((await f.request('/api/pve/state')).body.map.recallPoints.length,0);
  const {pveService}=await import('../dist/modules/pve/pve.service.js');
  const original=process.env.NODE_ENV;process.env.NODE_ENV='production';
  try {await assert.rejects(()=>pveService.resetTower(f.master.masterId,{confirm:true},'prod-reset'),/DEV_ONLY/);}
  finally {process.env.NODE_ENV=original;}
  assert.equal((await f.request('/api/pve/state')).body.run,1);
});
