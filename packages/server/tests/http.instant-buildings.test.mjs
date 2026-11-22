import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { cleanupAccount, createMaster, grantItems, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';
after(()=>pool.end());

async function fixture(t){
  const h=await startHarness(),m=await createMaster(h.request,'instantbase');
  t.after(async()=>{await cleanupAccount(m.accountId);await h.close();});
  await sql('update masters set silver_coins=100000 where id=$1',[m.masterId]);
  const req=(path,body)=>h.request(path,{token:m.token,...(body===undefined?{}:{method:'POST',body})});
  return {m,req};
}

test('Instant building: create/upgrade production immediately and preserve production earned at the old rate',{skip:skipReason},async t=>{
  const {m,req}=await fixture(t);
  const built=await req('/api/base/buildings',{buildingType:'KITCHEN',plotIndex:1});
  assert.equal(built.status,201);const id=built.body.building.id;
  assert.equal(built.body.building.status,'READY');assert.equal(built.body.building.upgradeFinishesAt,null);
  assert.equal((await sql('select base_rate_per_hour from base_production_nodes where building_id=$1',[id])).rows[0].base_rate_per_hour,20);
  const blocked=await req(`/api/base/buildings/${id}/upgrade`,{});assert.equal(blocked.status,409);
  assert.equal((await sql('select level from base_buildings where id=$1',[id])).rows[0].level,1);
  await grantItems(m.masterId,{WOOD:100,STONE:100});
  await sql("update base_production_nodes set current_stored=5,last_harvest_at=now()-interval '1 hour' where building_id=$1",[id]);
  const upgraded=await req(`/api/base/buildings/${id}/upgrade`,{});
  assert.equal(upgraded.status,200);assert.equal(upgraded.body.building.level,2);
  assert.equal(upgraded.body.building.status,'READY');assert.equal(upgraded.body.building.upgradeFinishesAt,null);
  const node=(await sql('select current_stored,base_rate_per_hour from base_production_nodes where building_id=$1',[id])).rows[0];
  assert.equal(node.base_rate_per_hour,40);assert.ok(node.current_stored>=25&&node.current_stored<25.2);
  const overview=await req('/api/base/overview');assert.equal(overview.body.buildings.find(b=>b.id===id).ratePerHour,40);
});

test('Instant building: legacy pending jobs finish before future deadlines exactly once, without another charge',{skip:skipReason},async t=>{
  const {m,req}=await fixture(t);
  const built=await req('/api/base/buildings',{buildingType:'KITCHEN',plotIndex:1});const id=built.body.building.id;
  await sql("update base_buildings set status='UPGRADING',upgrade_finishes_at=now()+interval '30 days' where id=$1",[id]);
  const before=(await sql('select silver_coins from masters where id=$1',[m.masterId])).rows[0].silver_coins;
  const reads=await Promise.all([req('/api/base/overview'),req('/api/base/overview')]);
  assert.ok(reads.every(r=>r.status===200&&r.body.buildings.find(b=>b.id===id).level===2));
  assert.equal((await sql('select level,upgrade_finishes_at from base_buildings where id=$1',[id])).rows[0].upgrade_finishes_at,null);
  assert.equal((await sql('select silver_coins from masters where id=$1',[m.masterId])).rows[0].silver_coins,before);
  await sql("update base_buildings set status='CONSTRUCTING',upgrade_finishes_at=now()+interval '30 days' where id=$1",[id]);
  await sql('delete from base_production_nodes where building_id=$1',[id]);
  await req('/api/base/overview');
  assert.equal((await sql('select count(*)::int n from base_production_nodes where building_id=$1',[id])).rows[0].n,1);
  assert.equal((await sql('select level from base_buildings where id=$1',[id])).rows[0].level,2);
});

test('Instant building: concurrent construction and upgrades cannot overspend or exceed the plot limit',{skip:skipReason},async t=>{
  const {m,req}=await fixture(t);
  const builds=await Promise.all(Array.from({length:12},()=>req('/api/base/buildings',{buildingType:'KITCHEN',plotIndex:1})));
  assert.equal(builds.filter(r=>r.status===201).length,1);
  assert.equal(builds.filter(r=>r.status===409).length,11);
  const id=builds.find(r=>r.status===201).body.building.id;
  await sql('update masters set silver_coins=2400 where id=$1',[m.masterId]);
  await grantItems(m.masterId,{WOOD:100,STONE:100});
  const upgrades=await Promise.all([req(`/api/base/buildings/${id}/upgrade`,{}),req(`/api/base/buildings/${id}/upgrade`,{})]);
  assert.deepEqual(upgrades.map(r=>r.status).sort(),[200,409]);
  assert.equal((await sql('select silver_coins from masters where id=$1',[m.masterId])).rows[0].silver_coins,'0');
  assert.equal((await sql('select level from base_buildings where id=$1',[id])).rows[0].level,2);
});
