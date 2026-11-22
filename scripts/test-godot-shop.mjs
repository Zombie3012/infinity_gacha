import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { resolve } from 'node:path';
import assert from 'node:assert/strict';
import { buildNow, cleanupAccount, createHero, createMaster, dbReady, pool, sql, startHarness } from '../packages/server/tests/helpers/harness.mjs';

let harness,accountId,proxy;
try{
  if(!dbReady)throw new Error('PostgreSQL is required for shop gameplay checks.');
  harness=await startHarness();
  const master=await createMaster(harness.request,'godotshop');accountId=master.accountId;
  await buildNow(harness.request,master,'SHOP_AIRSHIP',1);
  await sql('update masters set silver_coins=50 where id=$1',[master.masterId]);
  const hero=await createHero(master.masterId,{name:'Airship Fallen',hp:0,maxHp:100});
  const gear=(await sql('select code from equipment_templates order by code limit 1')).rows[0].code;
  let dropped=false;
  proxy=createServer(async(req,res)=>{
    try{
      const chunks=[];for await(const chunk of req)chunks.push(chunk);
      const body=Buffer.concat(chunks);
      const upstream=await fetch(harness.base+req.url,{method:req.method,headers:{'Content-Type':'application/json',Authorization:req.headers.authorization??'',...(req.headers['idempotency-key']?{'Idempotency-Key':req.headers['idempotency-key']}:{})},body:body.length?body:undefined});
      const payload=await upstream.text();
      if(!dropped&&req.method==='POST'&&req.url==='/api/shop/purchase'&&upstream.status===200){dropped=true;res.destroy();return;}
      res.writeHead(upstream.status,{'Content-Type':'application/json'});res.end(payload);
    }catch{if(!res.destroyed){res.writeHead(502);res.end('{}');}}
  });
  await new Promise(resolveListen=>proxy.listen(0,'127.0.0.1',resolveListen));
  const env={...process.env,SHOP_TEST_URL:`http://127.0.0.1:${proxy.address().port}`,SHOP_TEST_TOKEN:master.token,SHOP_TEST_MASTER:master.masterId,SHOP_TEST_HERO:hero.id,SHOP_TEST_GEAR:gear};
  process.exitCode=await new Promise((done,reject)=>{
    const child=spawn(process.env.GODOT_BIN||'godot',['--headless','--path',resolve('client-godot'),'res://tests/airship_shop_network_test.tscn'],{env,windowsHide:true,stdio:['ignore','pipe','pipe']});
    let output='',errors='';
    const timeout=setTimeout(()=>{child.kill();reject(new Error('Airship shop Godot check timed out.'));},60000);
    child.stdout.on('data',data=>{output+=data;process.stdout.write(data);});
    child.stderr.on('data',data=>{errors+=data;process.stderr.write(data);if(/SCRIPT ERROR:/.test(errors))child.kill();});
    child.once('error',error=>{clearTimeout(timeout);reject(error);});
    child.once('exit',code=>{clearTimeout(timeout);done(code===0&&output.includes('AIRSHIP_SHOP_NETWORK_TESTS:')&&!/SCRIPT ERROR:|^ERROR:/m.test(errors)?0:1);});
  });
  assert.equal(dropped,true,'Proxy must exercise response loss after purchase commit.');
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,'44');
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='RESURRECTION_GEM_7'",[master.masterId])).rows[0].quantity,2);
  assert.equal((await sql('select count(*)::int n from shop_purchases where master_id=$1',[master.masterId])).rows[0].n,3);
}catch(error){console.error(error);process.exitCode=1;}
finally{
  if(proxy)await new Promise(done=>proxy.close(done));
  if(accountId)await cleanupAccount(accountId);
  if(harness)await harness.close();
  await pool.end();
}
