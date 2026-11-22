import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { startHarness, createMaster, createHero, cleanupAccount, grantItems, buildNow, sql, pool, skipReason } from './helpers/harness.mjs';

after(() => pool.end());

test('Hero progression: promote through 6-7 stars, unlock Lv.60/70 and archive fodders', {skip:skipReason}, async t=>{
  const h=await startHarness(), master=await createMaster(h.request,'chronstar');
  t.after(async()=>{await cleanupAccount(master.accountId);await h.close();});
  const request=(path,options={})=>h.request(path,{token:master.token,...options});
  await sql('update masters set silver_coins=2000000 where id=$1',[master.masterId]);
  await grantItems(master.masterId,{SAMPLE_HERO_PROMOTION_SEAL:100});
  const hero=await createHero(master.masterId,{rarity:5});
  await sql(`update heroes set level=50,promotion_rank=4,origin_stats='{"str":90,"int":40,"sta":90,"agi":60}' where id=$1`,[hero.id]);
  for(const fromStar of [5,6]){
    const fodders=[];
    for(let i=0;i<fromStar;i++)fodders.push((await createHero(master.masterId,{rarity:fromStar})).id);
    const preview=await request(`/api/heroes/${hero.id}/promote-star/preview`);
    assert.equal(preview.status,200);assert.equal(preview.body.eligible,true);assert.ok(preview.body.projectedStats);
    const promoted=await request(`/api/heroes/${hero.id}/promote-star`,{method:'POST',body:{fodderHeroIds:fodders}});
    assert.equal(promoted.status,200,JSON.stringify(promoted.body));assert.equal(promoted.body.newStar,fromStar+1);
    const breakthrough=await request(`/api/heroes/${hero.id}/breakthrough/preview`);
    assert.equal(breakthrough.status,200);assert.equal(breakthrough.body.hero.isMax,false);
    const unlocked=await request(`/api/heroes/${hero.id}/breakthrough`,{method:'POST',body:{}});
    assert.equal(unlocked.status,200,JSON.stringify(unlocked.body));assert.equal(unlocked.body.maxLevel,(fromStar+1)*10);
    await sql('update heroes set level=$2 where id=$1',[hero.id,(fromStar+1)*10]);
    const consumed=(await sql('select status,hero_id from hero_chronicles where id=any($1::varchar[])',[fodders])).rows;
    assert.equal(consumed.length,fromStar);assert.ok(consumed.every(r=>r.status==='SACRIFICED'&&r.hero_id===null));
  }
  const max=await request(`/api/heroes/${hero.id}/promote-star/preview`);
  assert.equal(max.body.reason,'ERR_HERO_MAX_STAR');
  const record=(await request(`/api/chronicles/heroes/${hero.id}`)).body;
  assert.equal(record.rarity,7);assert.equal(record.events.filter(e=>e.type==='STAR_PROMOTED').length,2);
  const levels=(await sql('select count(*)::int n from hero_level_configs where level between 51 and 70')).rows[0].n;
  assert.equal(levels,20);
});

test('Chronicle: ownership, death, full-HP revival exactly once, preserved biography and consumed instances', { skip: skipReason }, async t => {
  const h = await startHarness(), master = await createMaster(h.request, 'chronicle'), other = await createMaster(h.request, 'outsider');
  t.after(async () => { await cleanupAccount(master.accountId); await cleanupAccount(other.accountId); await h.close(); });
  const request = (path, options = {}) => h.request(path, { token: master.token, ...options });
  await sql('update masters set silver_coins=100000 where id=$1', [master.masterId]);
  await buildNow(h.request, master, 'HERO_CHRONICLE', 1);
  const heroes = [];
  for (const category of ['NORMAL','SPECIAL','LIMITED']) heroes.push(await createHero(master.masterId, { name: category, category, rarity: 7 }));
  const before = await request('/api/chronicles/heroes');
  assert.equal(before.status, 200); assert.equal(before.body.total, 3);
  assert.ok(before.body.records.every(r => r.status === 'ALIVE' && r.biography.length > 80 && r.events[0].type === 'SUMMONED'));
  const hero = heroes[0], original = before.body.records.find(r => r.id === hero.id);
  const hidden = await h.request(`/api/chronicles/heroes/${hero.id}`, { token: other.token }); assert.equal(hidden.status, 404);
  assert.equal((await h.request(`/api/chronicles/heroes/${hero.id}/resurrect`, {token: other.token, method:'POST', body:{}})).status,404);
  // Normalize every origin and zero HP to the same terminal state.
  await sql("update heroes set hp=0,state='INJURED' where master_id=$1", [master.masterId]);
  const deceased = (await sql('select state,category,hp from heroes where master_id=$1',[master.masterId])).rows;
  assert.ok(deceased.every(r => r.state === 'DEAD' && r.category === 'HERO' && r.hp === 0));
  assert.equal((await request('/api/chronicles/heroes?status=DEAD')).body.total, 3);
  const path = `/api/chronicles/heroes/${hero.id}/resurrect`;
  assert.equal((await request(path,{method:'POST',body:{}})).status,409);
  await grantItems(master.masterId, { RESURRECTION_GEM_7: 2 });
  const silver = (await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins;
  const responses = await Promise.all(Array.from({length:3},()=>request(path,{method:'POST',body:{}})));
  assert.deepEqual(responses.map(r=>r.status).sort(),[200,409,409]);
  const restored = (await sql('select hp,max_hp,current_hp_pct,state from heroes where id=$1',[hero.id])).rows[0];
  assert.equal(restored.hp,restored.max_hp); assert.equal(restored.current_hp_pct,1); assert.equal(restored.state,'HEALTHY');
  assert.equal((await sql('select silver_coins from masters where id=$1',[master.masterId])).rows[0].silver_coins,silver);
  let record = (await request(`/api/chronicles/heroes/${hero.id}`)).body;
  assert.equal(record.biography,original.biography);
  assert.deepEqual(record.events.map(e=>e.type),['SUMMONED','DIED','RESURRECTED']);
  assert.equal((await request(path,{method:'POST',body:{}})).status,409);
  // A second death costs the same single gem, regardless of the legacy cycle count.
  await sql("update heroes set hp=0 where id=$1",[hero.id]);
  assert.equal((await request(path,{method:'POST',body:{}})).status,200);
  assert.equal((await sql("select quantity from master_items where master_id=$1 and item_id='RESURRECTION_GEM_7'",[master.masterId])).rows[0].quantity,0);
  // Chronicle writes roll back with the Hero change.
  const connection = await pool.connect();
  try { await connection.query('begin'); await connection.query('update heroes set hp=0 where id=$1',[hero.id]); await connection.query('rollback'); }
  finally { connection.release(); }
  record = (await request(`/api/chronicles/heroes/${hero.id}`)).body;
  assert.equal(record.events.filter(e=>e.type==='DIED').length,2); assert.equal(record.status,'ALIVE');
  await sql('delete from heroes where id=$1',[hero.id]);
  record = (await request(`/api/chronicles/heroes/${hero.id}`)).body;
  assert.equal(record.status,'SACRIFICED'); assert.equal(record.heroId,null); assert.equal(record.biography,original.biography);
  assert.equal((await request(path,{method:'POST',body:{}})).status,409);
  await sql('delete from heroes where id=$1',[heroes[1].id]);
  record = (await request(`/api/chronicles/heroes/${heroes[1].id}`)).body;
  assert.equal(record.status,'DEAD'); assert.equal(record.heroId,null);
});

test('Summons: fixed Hero duplicates become distinct chronicled instances; material rarity uses the 1-7 star catalogue', { skip: skipReason }, async t => {
  const h=await startHarness(), master=await createMaster(h.request,'chronroll');
  const bannerId=randomUUID();
  t.after(async()=>{await cleanupAccount(master.accountId);await sql('delete from banners where id=$1',[bannerId]);await h.close();});
  const template=(await sql("select code,default_rarity from hero_templates where code not like 'PROCEDURAL_%' order by default_rarity desc limit 1")).rows[0];
  assert.ok(template);
  await sql("insert into banners(id,name,banner_type) values($1,'Chronicle test','SPECIAL')",[bannerId]);
  await sql("insert into summon_reward_pool(id,banner_id,reward_id,reward_name,reward_type,pool_group,hero_template_code,rarity,weight) values($1,$2,'CHRONICLE_TEST','Fixed Hero','HERO','OTHER_HERO',$3,$4,1000000000)",[randomUUID(),bannerId,template.code,template.default_rarity]);
  await sql("insert into summon_reward_pool(id,banner_id,reward_id,reward_name,reward_type,pool_group,rarity,weight) values($1,$2,'RESURRECTION_GEM_7','Gem','MATERIAL','MATERIAL',null,1)",[randomUUID(),bannerId]);
  await sql('update masters set gems=1000 where id=$1',[master.masterId]);
  const summon=key=>h.request('/api/gacha/summon',{method:'POST',token:master.token,headers:{'Idempotency-Key':key},body:{bannerId,rollCount:1}});
  assert.equal((await summon('one')).status,200); assert.equal((await summon('two')).status,200);
  const instances=(await sql('select id,category,thien_menh from heroes where master_id=$1',[master.masterId])).rows;
  assert.equal(instances.length,2); assert.notEqual(instances[0].id,instances[1].id); assert.ok(instances.every(r=>r.category==='HERO'&&r.thien_menh===0));
  assert.equal((await sql('select count(*)::int n from hero_chronicles where master_id=$1',[master.masterId])).rows[0].n,2);
  assert.equal((await summon('two')).status,200);
  assert.equal((await sql('select count(*)::int n from heroes where master_id=$1',[master.masterId])).rows[0].n,2);
  await sql("update summon_reward_pool set weight=case when reward_type='HERO' then 1 else 1000000000 end where banner_id=$1",[bannerId]);
  const gem=await summon('gem'); assert.equal(gem.status,200); assert.equal(gem.body.results[0].rarity,7);
  const inventory=await h.request('/api/inventory',{token:master.token});
  assert.equal(inventory.status,200);
  assert.equal(inventory.body.items.find(i=>i.itemId==='RESURRECTION_GEM_7').rarity,7);
});
