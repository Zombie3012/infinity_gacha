import { after, test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { buildNow, cleanupAccount, createHero, createMaster, pool, skipReason, sql, startHarness } from './helpers/harness.mjs';

after(()=>pool.end());

async function fixture(t){
  const h=await startHarness(), master=await createMaster(h.request,'airship');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  const request=(path,options={})=>h.request(path,{token:master.token,...options});
  const buy=(itemCode,quantity=1,key=randomUUID())=>request('/api/shop/purchase',{method:'POST',headers:{'Idempotency-Key':key},body:{itemCode,quantity}});
  return{h,master,request,buy};
}

test('Airship catalogue: buildable shop, all usable items/equipment, stars and temporary one-Silver prices',{skip:skipReason},async t=>{
  const {h,master,request}=await fixture(t);
  const building=await buildNow(h.request,master,'SHOP_AIRSHIP',1);
  assert.equal(building.buildingType,'SHOP_AIRSHIP');
  const response=await request('/api/shop');assert.equal(response.status,200);
  const items=response.body.items;
  // Admin-configured fixture SKUs may coexist with the default catalogue.
  const defaults=items.filter(i=>i.code===i.itemId||i.code==='SHOP_SCROLL_NORMAL');
  assert.ok(defaults.length>20);assert.ok(defaults.every(i=>i.priceSilver==='1'&&i.dailyLimit===0&&i.remainingToday===null));
  assert.ok(items.every(i=>i.rarity>=1&&i.rarity<=7));
  for(const code of ['RESURRECTION_GEM_7','TELEPORT_STONE','MEDICINE','FOOD','FOOD_RAW','CLASS_CHANGE_TOKEN','SAMPLE_HERO_EXP_100','SAMPLE_HERO_EXP_1000','SAMPLE_HERO_EXP_10000','SAMPLE_HERO_PROMOTION_SEAL','SAMPLE_HERO_AWAKENING_CORE','SAMPLE_HERO_SKILL_BOOK','SHOP_SCROLL_NORMAL'])assert.ok(items.some(i=>i.code===code),code);
  assert.equal(items.find(i=>i.code==='RESURRECTION_GEM_7').rarity,7);
  assert.ok(!items.some(i=>['DIVINE_TEAR','STAMINA_POTION'].includes(i.itemId)||i.itemId.startsWith('SAMPLE_TRASH_')));
  const gear=(await sql('select code,rarity from equipment_templates')).rows;
  for(const row of gear)assert.ok(items.some(i=>i.category==='EQUIPMENT'&&i.itemId===row.code&&i.rarity===row.rarity));
  assert.equal((await request('/api/shop/items/RESURRECTION_GEM_7')).body.priceSilver,'1');
});

test('Airship purchase: gem works for full-HP revival and retries pay once',{skip:skipReason},async t=>{
  const {master,request,buy}=await fixture(t);
  await sql('update masters set silver_coins=10 where id=$1',[master.masterId]);
  const key=randomUUID();
  const purchases=await Promise.all(Array.from({length:3},()=>buy('RESURRECTION_GEM_7',2,key)));
  assert.ok(purchases.every(r=>r.status===200),JSON.stringify(purchases));
  assert.equal(new Set(purchases.map(r=>r.body.purchaseId)).size,1);
  assert.equal(purchases.filter(r=>!r.body.replayed).length,1);
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,'8');
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='RESURRECTION_GEM_7'",[master.masterId])).rows[0].quantity,2);
  assert.equal((await sql("select count(*)::int n from currency_transactions where master_id=$1 and transaction_type='SHOP_PURCHASE'",[master.masterId])).rows[0].n,1);
  assert.equal((await buy('MEDICINE',2,key)).status,409);
  const hero=await createHero(master.masterId,{hp:0,maxHp:100});
  const revived=await request(`/api/chronicles/heroes/${hero.id}/resurrect`,{method:'POST',body:{}});
  assert.equal(revived.status,200);assert.equal(revived.body.hp,100);assert.equal(revived.body.silverSpent,0);
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,'8');
});

test('Airship purchase: simultaneous distinct orders cannot overdraw the wallet',{skip:skipReason},async t=>{
  const {master,buy}=await fixture(t);
  await sql('update masters set silver_coins=1 where id=$1',[master.masterId]);
  const responses=await Promise.all([buy('MEDICINE'),buy('TELEPORT_STONE')]);
  assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,'0');
  assert.equal((await sql("select sum(quantity)::int n from master_items where master_id=$1 and item_id in ('MEDICINE','TELEPORT_STONE')",[master.masterId])).rows[0].n,1);
});

test('Airship purchase: equipment and scrolls reach their actual inventories; failed delivery rolls back',{skip:skipReason},async t=>{
  const {master,buy}=await fixture(t);
  await sql('update masters set silver_coins=100 where id=$1',[master.masterId]);
  const gear=(await sql('select code from equipment_templates order by code limit 1')).rows[0].code;
  const bought=await buy(gear,2);assert.equal(bought.status,200);
  assert.equal(bought.body.equipmentInstanceIds.length,2);
  const instances=(await sql('select location,equipped_hero_id,template_code from equipment_instances where id=any($1::varchar[])',[bought.body.equipmentInstanceIds])).rows;
  assert.ok(instances.length===2&&instances.every(r=>r.location==='INVENTORY'&&r.equipped_hero_id===null&&r.template_code===gear));
  assert.equal((await sql('select count(*)::int n from master_items where master_id=$1 and item_id=$2',[master.masterId,gear])).rows[0].n,0);
  const before=(await sql("select coalesce(sum(quantity),0)::int n from master_summon_inventory where master_id=$1 and scroll_type='NORMAL'",[master.masterId])).rows[0].n;
  assert.equal((await buy('SHOP_SCROLL_NORMAL',3)).status,200);
  assert.equal((await sql("select quantity from master_summon_inventory where master_id=$1 and scroll_type='NORMAL'",[master.masterId])).rows[0].quantity,before+3);
  const code='BAD_'+randomUUID().replaceAll('-','').toUpperCase();
  await sql("insert into shop_items(code,name,description,item_id,category,price_silver) values($1,'Bad delivery','Test','MISSING_EQUIPMENT','EQUIPMENT',1)",[code]);
  t.after(()=>sql('delete from shop_items where code=$1',[code]));
  const failed=await buy(code);assert.equal(failed.status,409);
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,'95');
  assert.equal((await sql('select count(*)::int n from shop_purchases where master_id=$1 and item_code=$2',[master.masterId,code])).rows[0].n,0);
  assert.equal((await buy('MEDICINE',0)).status,400);
  assert.equal((await buy('MEDICINE',1.5)).status,400);
  assert.equal((await buy('MEDICINE',100)).status,400);
  assert.equal((await buy('DIVINE_TEAR')).status,404);
});
