import { spawn } from 'node:child_process';
import { resolve } from 'node:path';
import { buildNow, cleanupAccount, createHero, createMaster, dbReady, grantItems, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness, accountId;
try {
  if (!dbReady) throw new Error('PostgreSQL is required for chronicle gameplay checks.');
  harness = await startHarness();
  const master = await createMaster(harness.request, 'godotchronicle'); accountId = master.accountId;
  await sql('update masters set silver_coins=200000 where id=$1',[master.masterId]);
  await buildNow(harness.request,master,'HERO_CHRONICLE',1);
  const hero = await createHero(master.masterId,{name:'Chronicle Fallen',rarity:7,hp:0,maxHp:1000});
  await createHero(master.masterId,{name:'Living Witness'});
  await grantItems(master.masterId,{RESURRECTION_GEM_7:1});
  const before=(await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins;
  const env={...process.env,CHRONICLE_TEST_URL:harness.base,CHRONICLE_TEST_TOKEN:master.token,CHRONICLE_TEST_MASTER:master.masterId,CHRONICLE_TEST_HERO:hero.id};
  process.exitCode=await new Promise((done,reject)=>{
    const child=spawn(process.env.GODOT_BIN||'godot',['--headless','--path',resolve('client-godot'),'res://tests/hero_chronicle_network_test.tscn'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    let output='',errors='';
    const timeout=setTimeout(()=>{child.kill();reject(new Error('Chronicle Godot check timed out.'));},60000);
    child.stdout.on('data',data=>{output+=data;process.stdout.write(data);});
    child.stderr.on('data',data=>{errors+=data;process.stderr.write(data);if(/SCRIPT ERROR:/.test(errors))child.kill();});
    child.once('error',error=>{clearTimeout(timeout);reject(error);});
    child.once('exit',code=>{clearTimeout(timeout);done(code===0&&output.includes('CHRONICLE_NETWORK_TESTS:')&&!/SCRIPT ERROR:|^ERROR:/m.test(errors)?0:1);});
  });
  const after=(await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins;
  if(before!==after)throw new Error('Resurrection unexpectedly charged Silver.');
} catch(error){console.error(error);process.exitCode=1;}
finally{if(accountId)await cleanupAccount(accountId);if(harness)await harness.close();await pool.end();}
