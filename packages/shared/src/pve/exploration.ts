import { mulberry32 } from '../combat/stats.js';
import { pveNeighbors, pveSeed, pveTileId, type PvePoint, type PveTile } from './index.js';

export const PVE_EXPLORATION_VERSION = 3;
export const PVE_ENEMY_STEP_MS = 1500;
export const PVE_SIGHT_RADIUS = 4;
export interface PvePortal extends PvePoint {
  id: string; toAreaId: string; arrival: PvePoint; label: string;
}
export interface PveBuilding {
  id: string; name: string; main: boolean; parentTileId: number; areaId: string;
  door: PvePoint; widthMeters: number; heightMeters: number;
}
export interface PveArea {
  id: string; name: string; level: 'FLOOR' | 'REGION' | 'INTERIOR'; parentAreaId: string | null;
  width: number; height: number; metersPerTile: number; tiles: PveTile[];
  portals: PvePortal[]; discovered: number[]; visited: number[]; collected: number[]; explored: boolean;
}
export interface PveEnemy extends PvePoint {
  battleId?: string;
  id: string; encounterId: number; seed: number; boss: boolean; areaId: string;
  home: PvePoint & { areaId: string }; state: 'IDLE' | 'CHASE' | 'INVESTIGATE' | 'RETURN' | 'DEAD';
  targetSquadId: string | null; lastSeen: (PvePoint & { areaId: string }) | null;
  nextStepAt: number | null; trail: { fromAreaId: string; portalId: string }[];
  disengaged?: { squadId: string; areaId: string; x: number; y: number };
}
export interface PveObjective {
  type: 'DEFEAT_BOSS'; targetId: string; required: number; progress: number; status: 'ACTIVE' | 'COMPLETED';
}
export interface PveExploration {
  version: 2 | 3; seed: string; floor: number; areas: Record<string, PveArea>;
  buildings: PveBuilding[]; enemies: PveEnemy[]; objective: PveObjective;
  sightings: Record<string, Record<string, PvePoint & { id: string; areaId: string; boss: boolean }>>;
}
export interface PveExplorer extends PvePoint { id: string; areaId: string; status: string }

const same = (a: PvePoint, b: PvePoint) => a.x === b.x && a.y === b.y;
export function pveWalkable(area: PveArea, p: PvePoint): boolean {
  return Number.isInteger(p.x) && Number.isInteger(p.y) && p.x >= 0 && p.y >= 0
    && p.x < area.width && p.y < area.height && !['WALL', 'ROCK'].includes(area.tiles[pveTileId(p, area.width)].kind);
}

/** Supercover ray: an exact corner touches both neighboring cells, never peeks through walls. */
export function pveLineOfSight(area: PveArea, from: PvePoint, to: PvePoint, radius = PVE_SIGHT_RADIUS): boolean {
  if ((from.x - to.x) ** 2 + (from.y - to.y) ** 2 > radius ** 2) return false;
  let { x, y } = from;
  const dx = to.x - x, dy = to.y - y, nx = Math.abs(dx), ny = Math.abs(dy);
  const sx = Math.sign(dx), sy = Math.sign(dy);
  let ix = 0, iy = 0;
  while (ix < nx || iy < ny) {
    const decision = (1 + 2 * ix) * ny - (1 + 2 * iy) * nx;
    if (decision === 0) {
      if (!pveWalkable(area, { x: x + sx, y }) || !pveWalkable(area, { x, y: y + sy })) return false;
      x += sx; y += sy; ix++; iy++;
    } else if (decision < 0) { x += sx; ix++; }
    else { y += sy; iy++; }
    if (!pveWalkable(area, { x, y })) return same({ x, y }, to);
  }
  return true;
}

export function pveVisibleEnemies(world: PveExploration, squad: PveExplorer): PveEnemy[] {
  const area = world.areas[squad.areaId];
  return world.enemies.filter(e => e.state !== 'DEAD' && !e.battleId && e.areaId === squad.areaId && pveLineOfSight(area, squad, e));
}

export function pveReveal(area: PveArea, p: PvePoint): void {
  const known = new Set(area.discovered);
  for (const tile of area.tiles) if (pveLineOfSight(area, p, tile)) known.add(tile.id);
  area.discovered = [...known].sort((a, b) => a - b);
  const id = pveTileId(p, area.width);
  if (!area.visited.includes(id)) area.visited.push(id);
}

/** BFS with optional fog and danger mask. Unknown cells can only be the final step. */
export function pveAreaPath(area: PveArea, from: PvePoint, to: PvePoint,
  known?: readonly number[], avoid = new Set<number>()): PvePoint[] | null {
  if (!pveWalkable(area, from) || !pveWalkable(area, to)) return null;
  const start = pveTileId(from, area.width), end = pveTileId(to, area.width);
  if (start === end) return [];
  const seen = new Map<number, number>([[start, -1]]), queue = [from], fog = known && new Set(known);
  for (let i = 0; i < queue.length; i++) for (const p of pveNeighbors(queue[i], area.width, area.height)) {
    const id = pveTileId(p, area.width);
    if (seen.has(id) || !pveWalkable(area, p) || avoid.has(id) || (fog && !fog.has(id) && id !== end)) continue;
    seen.set(id, pveTileId(queue[i], area.width)); queue.push(p);
    if (id === end) {
      const ids: number[] = [];
      for (let n = end; n !== start; n = seen.get(n)!) ids.push(n);
      return ids.reverse().map(n => ({ x: n % area.width, y: Math.floor(n / area.width) }));
    }
  }
  return null;
}

function area(id: string, name: string, level: PveArea['level'], parentAreaId: string | null,
  width: number, metersPerTile: number, seed: number): PveArea {
  const random = mulberry32(seed);
  return { id, name, level, parentAreaId, width, height: width, metersPerTile,
    tiles: Array.from({ length: width * width }, (_, n) => ({ id: n, x: n % width,
      y: Math.floor(n / width), kind: 'EMPTY', seed: Math.floor(random() * 0x100000000) })),
    portals: [], discovered: [], visited: [], collected: [], explored: false };
}

/** Obstacles never disconnect a walkable cell; portals/loot/boss therefore remain reachable. */
function obstacles(a: PveArea, seed: number): void {
  const random = mulberry32(seed);
  const reserved = new Set(a.portals.map(p => pveTileId(p, a.width)));
  for (const t of a.tiles) {
    if (t.x < 2 || t.y < 2 || reserved.has(t.id) || random() > 0.15) continue;
    t.kind = random() < 0.5 ? 'WALL' : 'ROCK';
    const open = a.tiles.filter(t => pveWalkable(a, t));
    const seen = new Set<number>([open[0].id]), queue = [open[0]];
    for (let i = 0; i < queue.length; i++) for (const p of pveNeighbors(queue[i], a.width, a.height)) {
      const id = pveTileId(p, a.width);
      if (!seen.has(id) && pveWalkable(a, p)) { seen.add(id); queue.push(a.tiles[id]); }
    }
    if (seen.size !== open.length) t.kind = 'EMPTY';
  }
}

function addEnemy(w: PveExploration, a: PveArea, p: PvePoint, boss = false): void {
  // Independent of which squad opens which building first.
  const encounterId = (a.level === 'FLOOR' ? 1000 : 2000 + Number(a.id.split(':')[1]) * 10)
    + w.enemies.filter(e => e.home.areaId === a.id).length;
  w.enemies.push({ id: boss ? w.objective.targetId : `enemy:${encounterId}`, encounterId,
    seed: pveSeed(`${w.seed}:${w.floor}:${a.id}:${encounterId}`), boss, areaId: a.id, x: p.x, y: p.y,
    home: { areaId: a.id, x: p.x, y: p.y }, state: 'IDLE', targetSquadId: null, lastSeen: null, nextStepAt: null, trail: [] });
}

function populate(w: PveExploration, a: PveArea, resourceCount: number, enemyCount: number, boss = false): void {
  const random = mulberry32(pveSeed(`${w.seed}:${w.floor}:${a.id}:population`));
  const candidates = a.tiles.filter(t => t.x + t.y > 3 && pveWalkable(a, t)
    && (a.level === 'FLOOR' || !a.portals.some(p => same(p, t))));
  for (let i = candidates.length - 1; i > 0; i--) { const j = Math.floor(random() * (i + 1)); [candidates[i], candidates[j]] = [candidates[j], candidates[i]]; }
  candidates.slice(0, resourceCount).forEach((t, i) => {
    t.kind = 'RESOURCE'; t.resource = { itemId: (w.version >= 3 ? ['WOOD', 'STONE', 'FOOD', 'ALCHEMY_HERB_1'] as const : ['WOOD', 'STONE', 'FOOD'] as const)[i % (w.version >= 3 ? 4 : 3)], quantity: 10 + 2 * w.floor };
  });
  candidates.slice(resourceCount, resourceCount + enemyCount).forEach(t => addEnemy(w, a, t));
  if (boss) addEnemy(w, a, candidates[resourceCount + enemyCount], true);
}

export function createPveExploration(seed: string, floor: number): PveExploration {
  const root = area('floor', `Tầng ${floor}`, 'FLOOR', null, 12, 1000, pveSeed(`${seed}:${floor}:floor`));
  const random = mulberry32(pveSeed(`${seed}:${floor}:buildings`));
  const cluster = 26 + Math.floor(random() * 80);
  const mainTile = 130 + Math.floor(random() * 14);
  const buildings: PveBuilding[] = [false, false, true].map((main, i) => ({
    id: `building:${i}`, name: main ? 'Thành trì mục tiêu' : `Công trình phụ ${i + 1}`, main,
    parentTileId: main ? mainTile : cluster, areaId: `interior:${i}`,
    door: [{ x: 6, y: 5 }, { x: 14, y: 13 }, { x: 10, y: 10 }][i], widthMeters: 40, heightMeters: 40,
  }));
  root.tiles[0].kind = 'CAMP';
  for (let id = 0; id < 144; id++) root.portals.push({ id: `region:${id}`, x: id % 12,
    y: Math.floor(id / 12), toAreaId: `region:${id}`, arrival: { x: 0, y: 0 }, label: 'Khám phá khu vực' });
  const w: PveExploration = { version: PVE_EXPLORATION_VERSION, seed, floor, areas: { floor: root }, buildings, enemies: [],
    objective: { type: 'DEFEAT_BOSS', targetId: 'objective:boss', required: 1, progress: 0, status: 'ACTIVE' }, sightings: {} };
  populate(w, root, 6, 6); pveReveal(root, { x: 0, y: 0 });
  return w;
}

/** Stable identity, lazy materialization; only a portal in an existing area can request this. */
export function materializePveArea(w: PveExploration, id: string): PveArea {
  if (w.areas[id]) return w.areas[id];
  const parentPortal = Object.values(w.areas).flatMap(a => a.portals.map(p => ({ a, p }))).find(v => v.p.toAreaId === id);
  if (!parentPortal) throw new Error('ERR_PVE_INVALID_PORTAL');
  const building = w.buildings.find(b => b.areaId === id);
  const a = building ? area(id, building.name, 'INTERIOR', parentPortal.a.id, 8, 5, pveSeed(`${w.seed}:${w.floor}:${id}`))
    : area(id, `Khu vực ${id.split(':')[1]}`, 'REGION', 'floor', 20, 50, pveSeed(`${w.seed}:${w.floor}:${id}`));
  a.portals.push({ id: `${id}:exit`, x: 0, y: 0, toAreaId: parentPortal.a.id,
    arrival: { x: parentPortal.p.x, y: parentPortal.p.y }, label: 'Ra ngoài' });
  if (!building) for (const b of w.buildings.filter(b => b.parentTileId === Number(id.split(':')[1]))) {
    a.portals.push({ id: `${b.id}:enter`, ...b.door, toAreaId: b.areaId, arrival: { x: 0, y: 0 }, label: b.name });
  }
  obstacles(a, pveSeed(`${w.seed}:${w.floor}:${id}:walls`));
  w.areas[id] = a;
  // Fixed floor budget: 6 outside, 4 in each of the three buildings. Detail regions add no economy.
  if (building) populate(w, a, 4, 4, building.main);
  pveReveal(a, { x: 0, y: 0 });
  return a;
}

export function pveObserve(w: PveExploration, squads: PveExplorer[], at: number): void {
  const active = squads.filter(s => ['IDLE', 'MOVING'].includes(s.status));
  for (const s of active) rememberEnemies(w, s);
  for (const e of w.enemies.filter(e => e.state !== 'DEAD' && !e.battleId)) {
    const visible = active.filter(s => !(e.disengaged?.squadId === s.id && e.disengaged.areaId === s.areaId && same(e.disengaged, s))
      && s.areaId === e.areaId && pveLineOfSight(w.areas[e.areaId], e, s))
      .sort((a, b) => ((a.x - e.x) ** 2 + (a.y - e.y) ** 2) - ((b.x - e.x) ** 2 + (b.y - e.y) ** 2) || a.id.localeCompare(b.id));
    const target = visible.find(s => s.id === e.targetSquadId) ?? visible[0];
    if (target) {
      e.state = 'CHASE'; e.targetSquadId = target.id;
      e.lastSeen = { areaId: target.areaId, x: target.x, y: target.y };
      e.nextStepAt ??= at + PVE_ENEMY_STEP_MS;
    } else if (e.state === 'CHASE') {
      e.state = 'INVESTIGATE'; e.nextStepAt ??= at + PVE_ENEMY_STEP_MS;
    }
  }
}

/** Called before moving a squad through a door, while its old position can still be observed. */
export function pveWitnessPortal(w: PveExploration, squad: PveExplorer, portal: PvePortal, at: number): void {
  for (const e of w.enemies) if (e.state !== 'DEAD' && !e.battleId && e.areaId === squad.areaId
    && pveLineOfSight(w.areas[e.areaId], e, squad)) {
    e.targetSquadId = squad.id; e.state = 'CHASE';
    e.lastSeen = { areaId: portal.toAreaId, ...portal.arrival };
    // Each observed crossing is recorded so returning enemies traverse real doors.
    e.trail.push({ fromAreaId: squad.areaId, portalId: portal.id });
    e.nextStepAt ??= at + PVE_ENEMY_STEP_MS;
  }
}

export function pveEnemyStep(w: PveExploration, e: PveEnemy, at: number): void {
  if (e.state === 'IDLE' || e.state === 'DEAD') { e.nextStepAt = null; return; }
  const a = w.areas[e.areaId];
  let destination = e.state === 'RETURN' ? e.home : e.lastSeen;
  let portal: PvePortal | undefined;
  if (!destination) { e.state = 'RETURN'; e.targetSquadId = null; destination = e.home; }
  if (destination.areaId !== e.areaId) {
    if (e.state === 'RETURN') {
      const back = [...e.trail].reverse().find(t => w.areas[t.fromAreaId]?.portals.find(p => p.id === t.portalId)?.toAreaId === e.areaId);
      portal = back && a.portals.find(p => p.toAreaId === back.fromAreaId);
    } else {
      const forward = e.trail.find(t => t.fromAreaId === e.areaId);
      portal = forward && a.portals.find(p => p.id === forward.portalId);
    }
    if (!portal) { e.state = 'RETURN'; e.targetSquadId = null; e.nextStepAt = at + PVE_ENEMY_STEP_MS; return; }
    destination = { areaId: e.areaId, x: portal.x, y: portal.y };
  }
  if (same(e, destination)) {
    if (portal) {
      materializePveArea(w, portal.toAreaId);
      if (e.state === 'RETURN') {
        const i = e.trail.map(t => t.fromAreaId).lastIndexOf(portal.toAreaId);
        if (i >= 0) e.trail.splice(i);
      }
      e.areaId = portal.toAreaId; e.x = portal.arrival.x; e.y = portal.arrival.y;
    } else if (e.state === 'RETURN') {
      e.state = 'IDLE'; e.targetSquadId = null; e.lastSeen = null; e.trail = []; e.nextStepAt = null; return;
    } else { e.state = 'RETURN'; e.targetSquadId = null; }
  } else {
    const path = pveAreaPath(a, e, destination);
    if (path?.length) { e.x = path[0].x; e.y = path[0].y; }
    else { e.state = 'RETURN'; e.targetSquadId = null; }
  }
  e.nextStepAt = at + PVE_ENEMY_STEP_MS;
}

export function completePveObjective(w: PveExploration, defeatedEnemyId: string): boolean {
  if (w.objective.status !== 'ACTIVE' || w.objective.targetId !== defeatedEnemyId) return false;
  w.objective.progress = w.objective.required; w.objective.status = 'COMPLETED';
  for (const enemy of w.enemies) { enemy.nextStepAt = null; enemy.targetSquadId = null; if (enemy.state !== 'DEAD') enemy.state = 'IDLE'; }
  return true;
}

export type PveAutoAction = { type: 'MOVE'; path: PvePoint[] } | { type: 'PORTAL'; portalId: string } | { type: 'STOP'; reason: string };
function rememberEnemies(w: PveExploration, s: PveExplorer): void {
  w.sightings ??= {};
  const memory = w.sightings[s.id] ??= {};
  for (const e of pveVisibleEnemies(w, s)) memory[e.id] = { id: e.id, areaId: e.areaId, x: e.x, y: e.y, boss: e.boss };
}
/** Knowledge-limited auto: only the squad's visible enemies can affect its path. */
export function pveAutoAction(w: PveExploration, s: PveExplorer): PveAutoAction {
  rememberEnemies(w, s);
  const a = w.areas[s.areaId], visible = pveVisibleEnemies(w, s), known = new Set(a.discovered);
  const danger = new Set<number>();
  for (const t of a.tiles) if (visible.some(e => !e.boss && pveLineOfSight(a, e, t))) danger.add(t.id);
  const pursued = visible.filter(e => !e.boss && e.targetSquadId === s.id && ['CHASE', 'INVESTIGATE'].includes(e.state));
  if (pursued.length) {
    const covers = a.tiles.filter(t => known.has(t.id) && pveWalkable(a, t) && !danger.has(t.id))
      .map(t => pveAreaPath(a, s, t, a.discovered)).filter((p): p is PvePoint[] => !!p?.length)
      .sort((x, y) => x.length - y.length);
    if (covers.length) return { type: 'MOVE', path: covers[0].slice(0, 1) };
    return { type: 'STOP', reason: 'NO_SAFE_PATH' };
  }
  const route = (p: PvePoint) => pveAreaPath(a, s, p, a.discovered, danger);
  const atPortal = (p: PvePortal): PveAutoAction | null => {
    if (same(s, p)) return { type: 'PORTAL', portalId: p.id };
    const path = route(p); return path?.length ? { type: 'MOVE', path: path.slice(0, 1) } : null;
  };
  // Optional buildings before the main objective; no server knowledge of hidden enemy positions.
  const pending = w.buildings.filter(b => !w.areas[b.areaId]?.explored);
  const desired = pending.some(b => !b.main) ? pending.filter(b => !b.main) : pending;
  if (a.level === 'FLOOR') {
    for (const b of desired) {
      const p = a.portals.find(p => p.toAreaId === `region:${b.parentTileId}`)!;
      if (known.has(pveTileId(p, a.width))) { const action = atPortal(p); if (action) return action; }
    }
  } else if (a.level === 'REGION') {
    for (const b of desired.filter(b => a.id === `region:${b.parentTileId}`)) {
      const p = a.portals.find(p => p.toAreaId === b.areaId)!;
      if (known.has(pveTileId(p, a.width))) { const action = atPortal(p); if (action) return action; }
    }
    if (!desired.some(b => a.id === `region:${b.parentTileId}`)) {
      const action = atPortal(a.portals[0]); if (action) return action;
    }
  } else {
    const boss = visible.find(e => e.id === w.objective.targetId) ?? w.sightings[s.id]?.[w.objective.targetId];
    if (boss?.areaId === s.areaId) { const path = route(boss); if (path?.length) return { type: 'MOVE', path: path.slice(0, 1) }; }
  }
  const candidates = a.tiles.filter(t => known.has(t.id) && pveWalkable(a, t) && !same(t, s)
    && ((!a.visited.includes(t.id)) || (t.kind === 'RESOURCE' && !a.collected.includes(t.id))))
    .map(t => ({ t, path: route(t) })).filter((v): v is { t: PveTile; path: PvePoint[] } => !!v.path?.length)
    .sort((x, y) => Number(y.t.kind === 'RESOURCE' && !a.collected.includes(y.t.id)) - Number(x.t.kind === 'RESOURCE' && !a.collected.includes(x.t.id))
      || x.path.length - y.path.length || x.t.id - y.t.id);
  if (candidates.length) return { type: 'MOVE', path: candidates[0].path.slice(0, 1) };
  if (a.level !== 'FLOOR') {
    // A main interior is never considered finished while its objective remains alive.
    if (w.buildings.some(b => b.areaId === a.id && b.main) && w.objective.status === 'ACTIVE') return { type: 'STOP', reason: 'NO_SAFE_PATH' };
    a.explored = true; const action = atPortal(a.portals[0]); if (action) return action;
  }
  return { type: 'STOP', reason: danger.size ? 'NO_SAFE_PATH' : 'EXPLORED' };
}
