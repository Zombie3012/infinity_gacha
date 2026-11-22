import {after,test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {cleanupAccount,createMaster,createHero,grantItems,pool,skipReason,sql,startHarness} from './helpers/harness.mjs';
after(()=>pool.end());
const retired=['LIBRARY','ALCHEMY_WORKSHOP','MAGIC_RESEARCH_LAB'];
async function fixture(t){
 const h=await startHarness(),m=await createMaster(h.request,'magichall');
 t.after(async()=>{await cleanupAccount(m.accountId);await h.close();});
 await sql('update masters set level=15,silver_coins=100000 where id=$1',[m.masterId]);
 const req=(p,body)=>h.request(p,{token:m.token,...(body===undefined?{}:{method:'POST',body})});
 return{m,req};
}
test('Magic Hall replaces child buildings while preserving production, Mage study and immediate upgrades',{skip:skipReason},async t=>{
 const {m,req}=await fixture(t);
 const overview=await req('/api/base/overview');
 assert.ok(overview.body.buildingTypes.some(b=>b.code==='HALL_OF_MAGIC'));
 for(const code of retired){
  assert.ok(!overview.body.buildingTypes.some(b=>b.code===code));
  assert.equal((await req('/api/base/buildings',{buildingType:code,plotIndex:2})).status,404);
 }
 const built=await req('/api/base/buildings',{buildingType:'HALL_OF_MAGIC',plotIndex:1});assert.equal(built.status,201);
 const id=built.body.building.id;
 let hall=(await req('/api/base/overview')).body.buildings.find(b=>b.id===id);
 assert.equal(hall.magicProduction.length,2);assert.equal(hall.maxWorkers,6);
 assert.equal(hall.magicProduction.find(p=>p.wing==='LIBRARY').ratePerHour,0);
 assert.equal(hall.magicProduction.find(p=>p.wing==='ALCHEMY_WORKSHOP').ratePerHour,15);
 const mage=await createHero(m.masterId);await sql("update heroes set class_code='MAGE' where id=$1",[mage.id]);
 await sql("update magic_production_nodes set last_harvest_at=now()-interval '1 hour' where building_id=$1",[id]);
 assert.equal((await req(`/api/base/buildings/${id}/workers`,{heroId:mage.id})).status,201);
 hall=(await req('/api/base/overview')).body.buildings.find(b=>b.id===id);
 assert.ok(hall.magicProduction.find(p=>p.wing==='LIBRARY').stored<1,'No retroactive books before Mage assignment');
 await sql("update magic_production_nodes set last_harvest_at=now()-interval '1 hour' where building_id=$1",[id]);
 const collected=await Promise.all([req(`/api/base/buildings/${id}/collect`,{}),req(`/api/base/buildings/${id}/collect`,{})]);
 assert.ok(collected.every(r=>r.status===200));
 const rewards=collected.flatMap(r=>r.body.resources);
 assert.equal(rewards.filter(r=>r.wing==='LIBRARY').reduce((s,r)=>s+r.collected,0),105);
 assert.equal(rewards.filter(r=>r.wing==='ALCHEMY_WORKSHOP').reduce((s,r)=>s+r.collected,0),30);
 assert.equal((await req(`/api/base/buildings/${id}/mage-study`,{heroId:mage.id,hours:1})).status,200);
 await grantItems(m.masterId,{WOOD:100,STONE:100});
 const upgrade=await req(`/api/base/buildings/${id}/upgrade`,{});assert.equal(upgrade.status,200);
 hall=(await req('/api/base/overview')).body.buildings.find(b=>b.id===id);
 assert.equal(hall.level,2);
 assert.equal(hall.magicProduction.find(p=>p.wing==='LIBRARY').resourceType,'SAMPLE_HERO_EXP_1000');
 assert.equal(hall.magicProduction.find(p=>p.wing==='ALCHEMY_WORKSHOP').baseRatePerHour,30);
});

for(const withHall of [true,false])test(`Legacy magic buildings merge safely ${withHall?'into an existing hall':'without a pre-existing hall'}`,{skip:skipReason},async t=>{
 const {m,req}=await fixture(t);
 // Legacy registry fixture is hidden/rejected by the current API throughout the test.
 for(const code of retired)await sql("insert into building_types(code,name,category,description,max_level,max_workers,required_world_level,build_cost_silver) values($1,$1,'MAGIC_SUB','Legacy fixture',3,2,1,2000) on conflict do nothing",[code]);
 t.after(async()=>{for(const code of retired)await sql('delete from building_types where code=$1',[code]);});
 let hallId;
 if(withHall)hallId=(await req('/api/base/buildings',{buildingType:'HALL_OF_MAGIC',plotIndex:1})).body.building.id;
 const children=[];
 for(let i=0;i<retired.length;i++){
  const id=randomUUID();children.push(id);
  await sql("insert into base_buildings(id,master_id,building_type,plot_index,level,status) values($1,$2,$3,$4,3,'READY')",[id,m.masterId,retired[i],i+2]);
 }
 for(let i=0;i<7;i++){
  const hero=await createHero(m.masterId);
  if(i===0)await sql("update heroes set class_code='MAGE' where id=$1",[hero.id]);
  await sql('insert into building_worker_assignments(id,building_id,hero_instance_id) values($1,$2,$3)',[randomUUID(),children[i%3],hero.id]);
 }
 await sql("insert into base_production_nodes(id,building_id,resource_type,base_rate_per_hour,max_capacity,current_stored) values($1,$2,'SAMPLE_HERO_EXP_10000',15,150,4.25),($3,$4,'ENHANCEMENT_STONE',60,600,2.25)",[randomUUID(),children[0],randomUUID(),children[1]]);
 await sql('select consolidate_magic_buildings($1)',[m.masterId]);
 const state=await req('/api/base/overview');assert.equal(state.status,200);
 assert.ok(!state.body.buildings.some(b=>retired.includes(b.buildingType)));
 const halls=state.body.buildings.filter(b=>b.buildingType==='HALL_OF_MAGIC');assert.equal(halls.length,1);
 if(withHall)assert.equal(halls[0].id,hallId);
 assert.equal(halls[0].level,3);assert.equal(halls[0].magicProduction.length,2);assert.equal(halls[0].workers.length,6);
 assert.equal((await sql('select count(*)::int n from heroes where master_id=$1',[m.masterId])).rows[0].n,7);
 assert.equal((await sql("select count(*)::int n from base_buildings where master_id=$1 and building_type in ('LIBRARY','ALCHEMY_WORKSHOP','MAGIC_RESEARCH_LAB')",[m.masterId])).rows[0].n,0);
 const stock=(await sql('select item_id,quantity from master_items where master_id=$1',[m.masterId])).rows;
 assert.ok(stock.find(r=>r.item_id==='SAMPLE_HERO_EXP_10000').quantity>=5);
 assert.ok(stock.find(r=>r.item_id==='ENHANCEMENT_STONE').quantity>=3);
 assert.equal((await sql('select consolidate_magic_buildings($1) n',[m.masterId])).rows[0].n,0);
});
