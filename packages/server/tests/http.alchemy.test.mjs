import {after,test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {cleanupAccount,createMaster,createHero,grantItems,pool,skipReason,sql,startHarness} from './helpers/harness.mjs';
after(()=>pool.end());
async function fixture(t,mode='MANUAL') {
 const h=await startHarness(),m=await createMaster(h.request,'alchemy');
 t.after(async()=>{await cleanupAccount(m.accountId);await h.close();});
 const request=(p,o={})=>h.request(p,{token:m.token,...o});
 const command=(p,body={},key=randomUUID())=>request(p,{method:'POST',body,headers:{'Idempotency-Key':key}});
 await sql('update masters set level=15,silver_coins=100000 where id=$1',[m.masterId]);
 await grantItems(m.masterId,{ALCHEMY_HERB_1:100,FOOD:1000,MANA_POTION:8,STRENGTH_POTION:4,MEDICINE:4});
 assert.equal((await command('/api/base/buildings',{buildingType:'HALL_OF_MAGIC',plotIndex:1})).status,201);
 const hero=await createHero(m.masterId,{hp:10000,maxHp:10000,attack:100,defense:30});
 await sql('update heroes set mp=0,max_mp=100,current_mp_pct=0 where id=$1',[hero.id]);
 const config={slots:[{itemId:'MANA_POTION',quantity:4},{itemId:'STRENGTH_POTION',quantity:4},null,null,null],autoManaBelow:30,autoStrength:true};
 assert.equal((await command('/api/alchemy/configure',{heroId:hero.id,config})).status,200);
 const party=await command('/api/pve/parties',{name:'Alchemists',heroIds:[hero.id],plan:{battleMode:mode,targetPriority:'FRONTLINE',members:[{heroId:hero.id,slotIndex:0,skillOrder:[]}]}});
 assert.equal(party.status,201);
 return {m,hero,config,request,command,partyId:party.body.partyId};
}

test('Alchemy research and crafting are atomic, branch-gated and idempotent',{skip:skipReason},async t=>{
 const f=await fixture(t);
 assert.equal((await f.command('/api/alchemy/research',{code:'ALCHEMY_MANA'})).status,409);
 assert.equal((await f.command('/api/alchemy/craft',{code:'MANA_POTION',quantity:1})).status,409);
 const body={code:'ALCHEMY_FOUNDATION'},key=randomUUID();
 const pair=await Promise.all([f.command('/api/alchemy/research',body,key),f.command('/api/alchemy/research',body,key)]);
 assert.deepEqual(pair[0].body,pair[1].body);assert.equal(pair[0].status,200);
 assert.equal((await f.command('/api/alchemy/research',{code:'ALCHEMY_MANA'})).status,200);
 const craft={code:'MANA_POTION',quantity:3},k=randomUUID();
 assert.equal((await f.command('/api/alchemy/craft',craft,k)).status,200);
 assert.equal((await f.command('/api/alchemy/craft',craft,k)).status,200);
 assert.equal((await f.command('/api/alchemy/craft',{...craft,quantity:4},k)).status,409);
 const herbs=(await sql("select quantity from master_items where master_id=$1 and item_id='ALCHEMY_HERB_1'",[f.m.masterId])).rows[0].quantity;
 assert.equal(herbs,76);
 assert.equal((await f.command('/api/alchemy/craft',{...craft,quantity:0})).status,400);
 assert.equal((await f.request('/api/alchemy')).body.technologies.filter(t=>t.researched).length,2);
});

async function startBattle(f) {
 const entered=await f.command('/api/pve/enter');assert.equal(entered.status,201);
 const deployed=await f.command(`/api/pve/parties/${f.partyId}/deploy`);assert.equal(deployed.status,201);
 const squadId=deployed.body.squadId,mapId=entered.body.mapId;
 const world=(await sql('select exploration from pve_maps where id=$1',[mapId])).rows[0].exploration;
 const enemy=world.enemies.find(e=>!e.boss);
 Object.assign(enemy,{areaId:'floor',x:1,y:0,state:'IDLE',nextStepAt:null,home:{areaId:'floor',x:1,y:0}});
 world.enemies=[enemy];world.areas.floor.discovered=world.areas.floor.tiles.map(t=>t.id);
 world.areas.floor.tiles[1].kind='EMPTY';delete world.areas.floor.tiles[1].resource;
 await sql('update pve_maps set exploration=$2::jsonb where id=$1',[mapId,JSON.stringify(world)]);
 assert.equal((await f.command(`/api/pve/squads/${squadId}/move`,{areaId:'floor',x:1,y:0})).status,200);
 await sql("update pve_squads set next_step_at=clock_timestamp()-interval '10 milliseconds' where id=$1",[squadId]);
 const state=await f.request('/api/pve/state');assert.equal(state.status,200);
 return {squadId,mapId,battleId:state.body.squads.find(s=>s.id===squadId).lastBattleId};
}
test('Manual PvE consumes distinct items once, keeps turn deadline, accepts actions and settles once',{skip:skipReason},async t=>{
 const f=await fixture(t),b=await startBattle(f);
 let battle=await f.request(`/api/pve/battles/${b.battleId}`);assert.equal(battle.status,200);assert.equal(battle.body.live,true);
 const deadline=battle.body.deadline,key=battle.body.report.pending.key;
 const payload={turnKey:key,itemId:'MANA_POTION'},idem=randomUUID();
 let action=await f.command(`/api/pve/battles/${b.battleId}/action`,payload,idem);assert.equal(action.status,200,JSON.stringify(action.body));
 assert.equal(action.body.deadline,deadline);assert.deepEqual((await f.command(`/api/pve/battles/${b.battleId}/action`,payload,idem)).body,action.body);
 assert.equal((await f.command(`/api/pve/battles/${b.battleId}/action`,payload)).status,400);
 action=await f.command(`/api/pve/battles/${b.battleId}/action`,{turnKey:key,itemId:'STRENGTH_POTION'});assert.equal(action.status,200);
 assert.equal(action.body.report.log.filter(l=>l.actionType==='ITEM').length,2);
 action=await f.command(`/api/pve/battles/${b.battleId}/action`,{turnKey:key,action:'BASIC'});assert.equal(action.status,200);
 assert.equal((await f.command(`/api/pve/battles/${b.battleId}/action`,{watching:false})).status,200);
 battle=await f.request(`/api/pve/battles/${b.battleId}`);assert.equal(battle.body.report.pending,undefined);
 assert.equal((await sql('select count(*)::int n from pve_battles where id=$1',[b.battleId])).rows[0].n,1);
 assert.equal((await f.command(`/api/pve/squads/${b.squadId}/recall`)).status,200);
 const stock=(await sql("select quantity from master_items where master_id=$1 and item_id='STRENGTH_POTION'",[f.m.masterId])).rows[0].quantity;
 assert.equal(stock,3);
});
test('Manual PvE timeout continues AI and reload cannot settle twice',{skip:skipReason},async t=>{
 const f=await fixture(t),b=await startBattle(f);
 await sql("update combat_sessions set combat_state=jsonb_set(combat_state,'{deadline}','0'::jsonb) where id=$1",[b.battleId]);
 const pair=await Promise.all([f.request('/api/pve/state'),f.request('/api/pve/state')]);
 assert.ok(pair.every(r=>r.status===200));
 assert.equal((await sql('select count(*)::int n from pve_battles where id=$1',[b.battleId])).rows[0].n,1);
});

test('Loadout validation and insufficient stock roll back the entire deployment',{skip:skipReason},async t=>{
 const f=await fixture(t);
 assert.equal((await f.command('/api/alchemy/configure',{heroId:f.hero.id,config:{...f.config,slots:[{itemId:'MANA_POTION',quantity:5},null,null,null,null]}})).status,400);
 assert.equal((await f.command('/api/alchemy/configure',{heroId:f.hero.id,config:{...f.config,slots:[{itemId:'MANA_POTION',quantity:4},{itemId:'MANA_POTION',quantity:4},{itemId:'MANA_POTION',quantity:4},null,null]}})).status,200);
 await f.command('/api/pve/enter');
 assert.equal((await f.command(`/api/pve/parties/${f.partyId}/deploy`)).status,409);
 assert.equal((await sql('select count(*)::int n from pve_hero_reservations where master_id=$1',[f.m.masterId])).rows[0].n,0);
 assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='MANA_POTION'",[f.m.masterId])).rows[0].quantity,8);
 assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='FOOD'",[f.m.masterId])).rows[0].quantity,1000);
});

test('Fallen Heroes drop remaining consumables at their position and another squad recovers once',{skip:skipReason},async t=>{
 const f=await fixture(t,'AUTO');
 await sql('update heroes set hp=1,max_hp=1,attack=1,defense=0 where id=$1',[f.hero.id]);
 await f.command('/api/alchemy/configure',{heroId:f.hero.id,config:{...f.config,autoManaBelow:0,autoStrength:false}});
 const b=await startBattle(f);
 assert.equal((await sql('select state from heroes where id=$1',[f.hero.id])).rows[0].state,'DEAD');
 const drops=(await sql('select * from pve_consumable_drops where map_id=$1',[b.mapId])).rows;
 assert.equal(drops.length,1);assert.equal(drops[0].x,1);assert.equal(drops[0].area_id,'floor');
 assert.equal(drops[0].items.reduce((n,s)=>n+s.quantity,0),8);
 const w=(await sql('select exploration from pve_maps where id=$1',[b.mapId])).rows[0].exploration;
 w.enemies=[];await sql('update pve_maps set exploration=$2::jsonb where id=$1',[b.mapId,JSON.stringify(w)]);
 const rescuer=await createHero(f.m.masterId,{name:'Rescuer'});
 const party=await f.command('/api/pve/parties',{name:'Rescuers',heroIds:[rescuer.id]});
 const deployed=await f.command(`/api/pve/parties/${party.body.partyId}/deploy`);assert.equal(deployed.status,201);
 const squad=deployed.body.squadId;
 assert.equal((await f.command(`/api/pve/squads/${squad}/move`,{areaId:'floor',x:1,y:0})).status,200);
 await sql("update pve_squads set next_step_at=clock_timestamp()-interval '10 milliseconds' where id=$1",[squad]);
 await Promise.all([f.request('/api/pve/state'),f.request('/api/pve/state')]);
 assert.equal((await sql('select count(*)::int n from pve_consumable_drops where map_id=$1',[b.mapId])).rows[0].n,0);
 assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='STRENGTH_POTION'",[f.m.masterId])).rows[0].quantity,4);
});

test('Outside battle potions clamp mana, prevent stacking and research survives Hall demolition',{skip:skipReason},async t=>{
 const f=await fixture(t);
 assert.equal((await f.command('/api/alchemy/use',{heroId:f.hero.id,itemId:'MANA_POTION'})).status,200);
 assert.equal((await sql('select mp from heroes where id=$1',[f.hero.id])).rows[0].mp,50);
 assert.equal((await f.command('/api/alchemy/use',{heroId:f.hero.id,itemId:'STRENGTH_POTION'})).status,200);
 assert.equal((await f.command('/api/alchemy/use',{heroId:f.hero.id,itemId:'STRENGTH_POTION'})).status,409);
 assert.equal((await f.command('/api/alchemy/use',{heroId:f.hero.id,itemId:'MEDICINE'})).status,409);
 await f.command('/api/alchemy/research',{code:'ALCHEMY_FOUNDATION'});
 await sql("delete from base_buildings where master_id=$1 and building_type='HALL_OF_MAGIC'",[f.m.masterId]);
 const state=await f.request('/api/alchemy');assert.equal(state.body.technologies[0].researched,true);
 assert.equal((await f.command('/api/alchemy/craft',{code:'MANA_POTION',quantity:1})).status,409);
});

test('A watched manual battle leaves other squads fighting automatically without claiming one enemy twice',{skip:skipReason},async t=>{
 const f=await fixture(t),b=await startBattle(f);
 assert.equal((await f.command(`/api/pve/battles/${b.battleId}/action`,{watching:true})).status,200);
 const second=await createHero(f.m.masterId,{name:'Second Alchemist',hp:10000,maxHp:10000,attack:10000});
 const party=await f.command('/api/pve/parties',{name:'Second Squad',heroIds:[second.id],plan:{battleMode:'MANUAL',targetPriority:'FRONTLINE',members:[{heroId:second.id,slotIndex:0,skillOrder:[]}]}});
 const deployed=await f.command(`/api/pve/parties/${party.body.partyId}/deploy`);assert.equal(deployed.status,201);
 const w=(await sql('select exploration from pve_maps where id=$1',[b.mapId])).rows[0].exploration;
 const e=structuredClone(w.enemies[0]);Object.assign(e,{id:'second-enemy',encounterId:9999,x:2,y:0,nextStepAt:null,state:'IDLE',home:{areaId:'floor',x:2,y:0}});delete e.battleId;
 w.enemies.push(e);w.areas.floor.tiles[2].kind='EMPTY';delete w.areas.floor.tiles[2].resource;
 await sql('update pve_maps set exploration=$2::jsonb where id=$1',[b.mapId,JSON.stringify(w)]);
 await f.command(`/api/pve/squads/${deployed.body.squadId}/move`,{areaId:'floor',x:2,y:0});
 await sql("update pve_squads set next_step_at=clock_timestamp()-interval '1100 milliseconds' where id=$1",[deployed.body.squadId]);
 const state=await f.request('/api/pve/state');assert.equal(state.status,200);
 assert.equal(state.body.squads.find(s=>s.id===b.squadId).status,'FIGHTING');
 assert.notEqual(state.body.squads.find(s=>s.id===deployed.body.squadId).status,'FIGHTING');
 assert.equal((await sql("select count(*)::int n from combat_sessions where master_id=$1 and status='PVE_LIVE'",[f.m.masterId])).rows[0].n,1);
 await f.command(`/api/pve/battles/${b.battleId}/action`,{watching:false});
 assert.equal((await sql('select count(*)::int n from pve_battles where map_id=$1',[b.mapId])).rows[0].n,2);
});

test('Completing the designated objective closes other pending battles and returns surviving bags once',{skip:skipReason},async t=>{
 const f=await fixture(t),b=await startBattle(f);
 const live=(await sql('select combat_state from combat_sessions where id=$1',[b.battleId])).rows[0].combat_state;
 live.deadline=Date.now()+60000;live.heroes[0].stats.atk=100000;
 await sql('update combat_sessions set combat_state=$2::jsonb where id=$1',[b.battleId,JSON.stringify(live)]);
 const second=await createHero(f.m.masterId,{name:'Waiting Alchemist',hp:10000,maxHp:10000,attack:100});
 const party=await f.command('/api/pve/parties',{name:'Waiting Squad',heroIds:[second.id],plan:{battleMode:'MANUAL',targetPriority:'FRONTLINE',members:[{heroId:second.id,slotIndex:0,skillOrder:[]}]}});
 const deployed=await f.command(`/api/pve/parties/${party.body.partyId}/deploy`);
 const w=(await sql('select exploration from pve_maps where id=$1',[b.mapId])).rows[0].exploration;
 w.enemies[0].boss=true;w.objective.targetId=w.enemies[0].id;
 const e=structuredClone(w.enemies[0]);Object.assign(e,{id:'waiting-enemy',boss:false,encounterId:9998,x:2,y:0,nextStepAt:null,state:'IDLE',home:{areaId:'floor',x:2,y:0}});delete e.battleId;
 w.enemies.push(e);w.areas.floor.tiles[2].kind='EMPTY';delete w.areas.floor.tiles[2].resource;
 await sql('update pve_maps set exploration=$2::jsonb where id=$1',[b.mapId,JSON.stringify(w)]);
 await f.command(`/api/pve/squads/${deployed.body.squadId}/move`,{areaId:'floor',x:2,y:0});
 await sql("update pve_squads set next_step_at=clock_timestamp()-interval '1100 milliseconds' where id=$1",[deployed.body.squadId]);
 await f.request('/api/pve/state');
 assert.equal((await sql("select count(*)::int n from combat_sessions where master_id=$1 and status='PVE_LIVE'",[f.m.masterId])).rows[0].n,2);
 const result=await f.command(`/api/pve/battles/${b.battleId}/action`,{watching:false});assert.equal(result.status,200,JSON.stringify(result.body));
 const state=await f.request('/api/pve/state');assert.equal(state.body.map.status,'CLEARED');
 assert.ok(state.body.squads.every(s=>s.status==='WITHDRAWN'));
 assert.equal((await sql("select count(*)::int n from combat_sessions where master_id=$1 and status='PVE_LIVE'",[f.m.masterId])).rows[0].n,0);
 const stock=(await sql("select quantity from master_items where master_id=$1 and item_id='STRENGTH_POTION'",[f.m.masterId])).rows[0].quantity;
 assert.equal(stock,3);
 await f.request('/api/pve/state');
 assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='STRENGTH_POTION'",[f.m.masterId])).rows[0].quantity,stock);
});
