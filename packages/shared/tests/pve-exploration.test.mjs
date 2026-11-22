import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  createPveExploration, materializePveArea, pveAreaPath, pveLineOfSight, pveReveal,
  pveObserve, pveEnemyStep, pveWitnessPortal, pveVisibleEnemies, pveAutoAction, completePveObjective,
} from '../dist/pve/exploration.js';

const squad = (areaId = 'floor', x = 0, y = 0) => ({ id: 'team', areaId, x, y, status: 'IDLE' });
test('Alchemy herbs are deterministic in new floors while lazy legacy interiors retain old resource rules',()=>{
  const current=createPveExploration('herb-version',1);
  assert.equal(current.version,3);
  assert.ok(current.areas.floor.tiles.some(t=>t.resource?.itemId==='ALCHEMY_HERB_1'));
  const legacy=structuredClone(current);legacy.version=2;
  const building=legacy.buildings[0];
  materializePveArea(legacy,`region:${building.parentTileId}`);
  const interior=materializePveArea(legacy,building.areaId);
  assert.ok(interior.tiles.every(t=>t.resource?.itemId!=='ALCHEMY_HERB_1'));
  assert.deepEqual(createPveExploration('herb-version',1),current);
});
function flat(a) { for (const t of a.tiles) { t.kind = 'EMPTY'; delete t.resource; } return a; }

test('three scales, clustered buildings, lazy regions and stable generation order', () => {
  const a = createPveExploration('scale', 2), b = createPveExploration('scale', 2);
  assert.deepEqual(a, b);
  assert.deepEqual(Object.keys(a.areas), ['floor']);
  assert.equal(a.buildings[0].parentTileId, a.buildings[1].parentTileId);
  assert.ok(a.buildings.every(v => v.widthMeters < 100));
  for (const w of [a, b]) for (const building of w === a ? w.buildings : [...w.buildings].reverse()) {
    const region = materializePveArea(w, `region:${building.parentTileId}`);
    assert.equal(region.width, 20); assert.equal(region.metersPerTile, 50);
    const inside = materializePveArea(w, building.areaId);
    assert.equal(inside.width, 8); assert.equal(inside.metersPerTile, 5);
    assert.equal(materializePveArea(w, building.areaId), inside);
  }
  assert.deepEqual([...a.enemies].sort((x,y) => x.id.localeCompare(y.id)), [...b.enemies].sort((x,y) => x.id.localeCompare(y.id)));
  assert.equal(a.enemies.filter(e => !e.boss).length, 18);
  assert.equal(a.enemies.filter(e => e.boss).length, 1);
  assert.equal(Object.values(a.areas).flatMap(a => a.tiles.filter(t => t.resource)).length, 18);
  assert.throws(() => materializePveArea(a, 'interior:99'), /INVALID_PORTAL/);
});

test('generated obstacles preserve access to every door, resource and enemy', () => {
  for (let n = 0; n < 12; n++) {
    const w = createPveExploration(`paths-${n}`, n + 1);
    for (const b of w.buildings) { materializePveArea(w, `region:${b.parentTileId}`); materializePveArea(w, b.areaId); }
    for (const a of Object.values(w.areas)) {
      for (const p of [...a.portals, ...a.tiles.filter(t => t.resource), ...w.enemies.filter(e => e.areaId === a.id)]) {
        assert.notEqual(pveAreaPath(a, { x: 0, y: 0 }, p), null);
      }
    }
  }
});

test('radar is circular, walls block rays and sealed corners cannot be peeked through', () => {
  const a = flat(createPveExploration('los', 1).areas.floor);
  assert.equal(pveLineOfSight(a, { x: 0,y: 0 }, { x: 4,y: 0 }), true);
  assert.equal(pveLineOfSight(a, { x: 0,y: 0 }, { x: 4,y: 1 }), false);
  a.tiles[1].kind = 'WALL';
  assert.equal(pveLineOfSight(a, { x: 0,y: 0 }, { x: 2,y: 0 }), false);
  assert.equal(pveLineOfSight(a, { x: 0,y: 0 }, { x: 1,y: 1 }), false);
  a.discovered = []; pveReveal(a, { x: 0,y: 0 });
  assert.ok(!a.discovered.includes(2));
  assert.equal(pveAreaPath(a, { x: 0,y: 0 }, { x: 1,y: 0 }), null);
});

test('chase loses sight, investigates the last known cell and returns home without tracking a hidden team', () => {
  const w = createPveExploration('ai', 1), a = flat(w.areas.floor), e = w.enemies[0];
  w.enemies = [e]; Object.assign(e, { x: 3, y: 0, home: { areaId: 'floor', x: 3,y: 0 } });
  const s = squad(); pveObserve(w, [s], 1000);
  assert.equal(e.state, 'CHASE'); assert.equal(e.nextStepAt, 2500);
  pveEnemyStep(w, e, 2500); assert.equal(e.x, 2);
  s.x = 10; pveObserve(w, [s], 2500);
  assert.equal(e.state, 'INVESTIGATE'); assert.equal(e.lastSeen.x, 0);
  for (let at = 4000; e.state !== 'IDLE' && at < 30000; at += 1500) pveEnemyStep(w, e, at);
  assert.equal(e.state, 'IDLE'); assert.equal(e.x, 3); assert.equal(e.nextStepAt, null);
});

test('boss follows an observed door crossing and physically returns through the same doorway', () => {
  const w = createPveExploration('door', 1), root = flat(w.areas.floor);
  const p = root.portals[1], target = flat(materializePveArea(w, p.toAreaId));
  const e = w.enemies[0]; w.enemies = [e];
  Object.assign(e, { boss: true, areaId: 'floor', x: 1,y: 0, home: { areaId: 'floor', x: 1,y: 0 } });
  const s = squad('floor',1,0); pveWitnessPortal(w,s,p,1000);
  pveEnemyStep(w,e,2500);
  assert.equal(e.areaId,target.id); assert.equal(e.x,0);
  pveObserve(w,[],2500);
  for (let at=4000;e.state!=='IDLE' && at<30000;at+=1500) pveEnemyStep(w,e,at);
  assert.equal(e.areaId,'floor'); assert.equal(e.x,1); assert.equal(e.state,'IDLE');
});

test('an unseen corner contact can be ambush, while an already visible enemy cannot', () => {
  const w=createPveExploration('ambush',1), a=flat(w.areas.floor), e=w.enemies[0];
  w.enemies=[e]; Object.assign(e,{x:1,y:1}); a.tiles[1].kind='WALL';
  const s=squad();
  const before=new Set(pveVisibleEnemies(w,s).map(e=>e.id));
  assert.equal(before.has(e.id),false);
  Object.assign(s,{x:1,y:1}); assert.equal(pveVisibleEnemies(w,s).length,1);
  assert.equal(before.has(e.id),false,'contact reveal cannot retroactively cancel surprise');
});

test('auto ignores concealed enemy coordinates and objective completion requires the designated ID', () => {
  const w=createPveExploration('auto',1), a=flat(w.areas.floor), s=squad();
  pveReveal(a,s); w.enemies=[];
  const action=pveAutoAction(w,s), hidden=structuredClone(w);
  hidden.enemies.push({id:'hidden',areaId:'floor',x:11,y:11,state:'IDLE',boss:false});
  assert.deepEqual(pveAutoAction(hidden,s),action);
  assert.equal(completePveObjective(w,'some-other-boss'),false);
  assert.equal(completePveObjective(w,w.objective.targetId),true);
  assert.equal(w.objective.progress,1);
  assert.equal(completePveObjective(w,w.objective.targetId),false);
});

test('auto completes optional buildings before finding the objective, retaining a boss sighting around walls', () => {
  for (let n=0;n<10;n++) {
    const w=createPveExploration(`auto-e2e-${n}`,1), s=squad(); w.enemies=[];
    let reached=false;
    for (let steps=0;steps<2500;steps++) {
      const a=w.areas[s.areaId], action=pveAutoAction(w,s);
      assert.notEqual(action.type,'STOP',`seed ${n}: ${action.reason}`);
      if(action.type==='PORTAL') {
        const p=a.portals.find(p=>p.id===action.portalId);materializePveArea(w,p.toAreaId);
        Object.assign(s,{areaId:p.toAreaId,...p.arrival});
        // Isolate navigation from the independent pursuit/combat tests.
        w.enemies=w.enemies.filter(e=>e.boss);
      } else Object.assign(s,action.path[0]);
      const here=w.areas[s.areaId];pveReveal(here,s);
      const tile=here.tiles[s.y*here.width+s.x];if(tile.resource&&!here.collected.includes(tile.id))here.collected.push(tile.id);
      if(w.enemies.some(e=>e.boss&&e.areaId===s.areaId&&e.x===s.x&&e.y===s.y)){reached=true;break;}
    }
    assert.ok(reached,`seed ${n} reaches the designated boss`);
    assert.ok(w.buildings.filter(b=>!b.main).every(b=>w.areas[b.areaId]?.explored));
  }
});
