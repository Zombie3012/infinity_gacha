import {spawn} from 'node:child_process';
import {resolve} from 'node:path';
import {randomUUID} from 'node:crypto';
import {cleanupAccount,createHero,createMaster,grantItems,pool,sql,startHarness} from '../packages/server/tests/helpers/harness.mjs';
let h,accountId;
try {
 h=await startHarness();const m=await createMaster(h.request,'godotpotions');accountId=m.accountId;
 const command=(p,body={})=>h.request(p,{token:m.token,method:'POST',body,headers:{'Idempotency-Key':randomUUID()}});
 await grantItems(m.masterId,{FOOD:100,MANA_POTION:4,STRENGTH_POTION:4});
 const hero=await createHero(m.masterId,{name:'Potion Captain',hp:10000,maxHp:10000,attack:100,defense:30});
 await sql("update heroes set max_mp=100,mp=0,current_mp_pct=0,class_code='WARRIOR',level=3 where id=$1",[hero.id]);
 await sql("insert into hero_skill_instances(id,hero_id,skill_code,is_unlocked) values($1,$2,'SAMPLE_SKILL_WARRIOR_HEAVY_STRIKE',true)",[randomUUID(),hero.id]);
 const config={slots:[{itemId:'MANA_POTION',quantity:4},{itemId:'STRENGTH_POTION',quantity:4},null,null,null],autoHpBelow:0,autoManaBelow:30,autoStrength:true};
 await command('/api/alchemy/configure',{heroId:hero.id,config});
 const party=await command('/api/pve/parties',{name:'Potion Team',heroIds:[hero.id],plan:{battleMode:'MANUAL',targetPriority:'FRONTLINE',members:[{heroId:hero.id,slotIndex:0,skillOrder:[]}]}});
 const entry=await command('/api/pve/enter'),deployed=await command(`/api/pve/parties/${party.body.partyId}/deploy`);
 if(deployed.status!==201)throw new Error(JSON.stringify(deployed));
 const world=(await sql('select exploration from pve_maps where id=$1',[entry.body.mapId])).rows[0].exploration;
 const enemy=world.enemies.find(e=>!e.boss);Object.assign(enemy,{areaId:'floor',x:1,y:0,state:'IDLE',nextStepAt:null,home:{areaId:'floor',x:1,y:0}});
 world.enemies=[enemy];world.areas.floor.discovered=world.areas.floor.tiles.map(t=>t.id);world.areas.floor.tiles[1].kind='EMPTY';delete world.areas.floor.tiles[1].resource;
 await sql('update pve_maps set exploration=$2::jsonb where id=$1',[entry.body.mapId,JSON.stringify(world)]);
 await command(`/api/pve/squads/${deployed.body.squadId}/move`,{areaId:'floor',x:1,y:0});
 await sql("update pve_squads set next_step_at=clock_timestamp()-interval '10 milliseconds' where id=$1",[deployed.body.squadId]);
 const state=await h.request('/api/pve/state',{token:m.token});const battle=state.body.squads.find(s=>s.id===deployed.body.squadId).lastBattleId;
 const env={...process.env,POTION_TEST_URL:h.base,POTION_TEST_TOKEN:m.token,POTION_TEST_MASTER:m.masterId,POTION_TEST_BATTLE:battle};
 process.exitCode=await new Promise((done,reject)=>{
  const child=spawn(process.env.GODOT_BIN||'godot',['--headless','--path',resolve('client-godot'),'res://tests/pve_consumables_network_test.tscn'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let output='',errors='';const timer=setTimeout(()=>{child.kill();reject(new Error('PvE consumable UI timed out'));},60000);
  child.stdout.on('data',d=>{output+=d;process.stdout.write(d);});child.stderr.on('data',d=>{errors+=d;process.stderr.write(d);if(/SCRIPT ERROR:/.test(errors))child.kill();});
  child.once('error',e=>{clearTimeout(timer);reject(e);});child.once('exit',code=>{clearTimeout(timer);done(code===0&&output.includes('PVE_CONSUMABLE_NETWORK:')&&!/SCRIPT ERROR:|^ERROR:/m.test(errors)?0:1);});
 });
}catch(e){console.error(e);process.exitCode=1;}
finally{if(accountId)await cleanupAccount(accountId);if(h)await h.close();await pool.end();}
