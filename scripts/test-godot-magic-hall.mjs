import {spawn} from 'node:child_process';
import {resolve} from 'node:path';
import {cleanupAccount,createHero,createMaster,dbReady,grantItems,pool,sql,startHarness} from '../packages/server/tests/helpers/harness.mjs';
let harness, accountId;
try {
 if(!dbReady) throw new Error('PostgreSQL required');
 harness=await startHarness();
 const m=await createMaster(harness.request,'godotmagic'); accountId=m.accountId;
 await sql('update masters set level=15,silver_coins=200000 where id=$1',[m.masterId]);
 const built=await harness.request('/api/base/buildings',{token:m.token,method:'POST',body:{buildingType:'HALL_OF_MAGIC',plotIndex:1}});
 if(built.status!==201)throw new Error(JSON.stringify(built));
 const hero=await createHero(m.masterId,{name:'Hall Mage',rarity:4,hp:300,maxHp:1000});
 await sql("update heroes set class_code='MAGE' where id=$1",[hero.id]);
 await createHero(m.masterId,{name:'Fallen Mage',hp:0,maxHp:1000});
 const recruit=await createHero(m.masterId,{name:'Class Candidate',rarity:4});
 await sql(`update heroes set level=20,class_code='WARRIOR',base_str=60,base_int=100,base_sta=20,base_agi=20,origin_stats='{"str":60,"int":100,"sta":20,"agi":20}'::jsonb where id=$1`,[recruit.id]);
 await grantItems(m.masterId,{ALCHEMY_HERB_1:100,SAMPLE_HERO_EXP_100:1,MEDICINE:1,SAMPLE_HERO_AWAKENING_CORE:10,CLASS_CHANGE_TOKEN:1,SAMPLE_HERO_SKILL_BOOK:1});
 await sql("update magic_production_nodes set current_stored=5 where building_id=$1 and wing='ALCHEMY_WORKSHOP'",[built.body.building.id]);
 const env={...process.env,MAGIC_TEST_URL:harness.base,MAGIC_TEST_TOKEN:m.token,MAGIC_TEST_MASTER:m.masterId,MAGIC_TEST_HALL:built.body.building.id,MAGIC_TEST_HERO:hero.id,MAGIC_TEST_RECRUIT:recruit.id};
 process.exitCode=await new Promise((done,reject)=>{
  const child=spawn(process.env.GODOT_BIN||'godot',['--headless','--path',resolve('client-godot'),'res://tests/magic_hall_network_test.tscn'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let output='',errors='';
  const timer=setTimeout(()=>{child.kill();reject(new Error('Magic Hall check timed out'));},60000);
  child.stdout.on('data',d=>{output+=d;process.stdout.write(d);});
  child.stderr.on('data',d=>{errors+=d;process.stderr.write(d);if(/SCRIPT ERROR:/.test(errors))child.kill();});
  child.once('error',e=>{clearTimeout(timer);reject(e);});
  child.once('exit',code=>{clearTimeout(timer);done(code===0&&output.includes('MAGIC_HALL_NETWORK:')&&!/SCRIPT ERROR:|^ERROR:/m.test(errors)?0:1);});
 });
}catch(e){console.error(e);process.exitCode=1;}
finally{if(accountId)await cleanupAccount(accountId);if(harness)await harness.close();await pool.end();}
