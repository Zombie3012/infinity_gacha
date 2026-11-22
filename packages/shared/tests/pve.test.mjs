import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  defaultPvePlan, findPvePath, generatePveLayout, pveNeighbors, pveTileId,
  revealPveTiles, validatePvePlan,
} from '../dist/pve/index.js';

test('PvE generation is reproducible, versioned and independent per floor', () => {
  const first = generatePveLayout('world-a', 1);
  assert.deepEqual(generatePveLayout('world-a', 1), first);
  assert.notDeepEqual(generatePveLayout('world-a', 2), first);
  assert.notDeepEqual(generatePveLayout('world-b', 1), first);
  assert.throws(() => generatePveLayout('world-a', 1, 2), /ALGORITHM_UNSUPPORTED/);
  assert.throws(() => generatePveLayout('world-a', 0), /INVALID_SEED/);
});

test('PvE maps have reachable bosses/resources and a safe starting area across many seeds', () => {
  for (let index = 0; index < 100; index++) {
    const layout = generatePveLayout(`seed-${index}`, 1 + index % 10);
    assert.equal(layout.tiles.length, 144);
    assert.equal(layout.tiles.filter(t => t.kind === 'CAMP').length, 1);
    assert.equal(layout.tiles.filter(t => t.kind === 'BOSS').length, 1);
    assert.ok(layout.tiles.filter(t => t.kind === 'RESOURCE').length > 0);
    const known = layout.tiles.map(t => t.id);
    for (const tile of layout.tiles) {
      const path = findPvePath(layout, known, { x: 0, y: 0 }, tile);
      assert.equal(path.length, tile.x + tile.y);
      if (tile.x + tile.y <= 2) assert.ok(['CAMP', 'EMPTY'].includes(tile.kind));
    }
  }
});

test('PvE fog permits a single unknown frontier destination, never an unknown intermediate cell', () => {
  const layout = generatePveLayout('fog', 1);
  const camp = { x: 0, y: 0 };
  const known = revealPveTiles(layout, [], camp);
  assert.deepEqual(known, [0, 1, 12]);
  assert.deepEqual(findPvePath(layout, known, camp, { x: 2, y: 0 }), [{ x: 1, y: 0 }, { x: 2, y: 0 }]);
  assert.throws(() => findPvePath(layout, known, camp, { x: 3, y: 0 }), /UNDISCOVERED/);
  assert.throws(() => findPvePath(layout, known, camp, { x: -1, y: 0 }), /INVALID_DESTINATION/);
  assert.throws(() => findPvePath(layout, known, camp, { x: 1.5, y: 0 }), /INVALID_DESTINATION/);
  assert.equal(pveNeighbors(camp, 12, 12).length, 2);
  assert.equal(pveNeighbors({ x: 6, y: 6 }, 12, 12).length, 4);
  assert.equal(pveTileId({ x: 11, y: 11 }), 143);
});

test('PvE plans keep five members on distinct cells in a nine-cell formation', () => {
  const heroes = ['a', 'b', 'c', 'd', 'e'];
  const plan = defaultPvePlan(heroes);
  assert.equal(plan.members.length, 5);
  assert.equal(new Set(plan.members.map(m => m.slotIndex)).size, 5);
  assert.ok(plan.members.some(m => m.slotIndex === 8));
  const reject = altered => assert.throws(() => validatePvePlan(altered, heroes), /INVALID_PLAN/);
  reject({ ...plan, targetPriority: 'MANUAL' });
  reject({ ...plan, members: plan.members.slice(1) });
  reject({ ...plan, members: plan.members.map((m, i) => i === 1 ? { ...m, heroId: 'foreign' } : m) });
  reject({ ...plan, members: plan.members.map(m => ({ ...m, slotIndex: 0 })) });
  reject({ ...plan, members: plan.members.map(m => ({ ...m, slotIndex: 9 })) });
  reject({ ...plan, members: plan.members.map(m => ({ ...m, skillOrder: ['skill', 'skill'] })) });
  assert.throws(() => defaultPvePlan([]), /INVALID_PARTY/);
  assert.throws(() => defaultPvePlan([...heroes, 'f']), /INVALID_PARTY/);
  const normalized = validatePvePlan(plan, heroes);
  normalized.members[0].skillOrder.push('NEW');
  assert.deepEqual(plan.members[0].skillOrder, []);
});
