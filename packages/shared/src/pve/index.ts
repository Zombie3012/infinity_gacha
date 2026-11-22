import { GAME_CONSTANTS } from '../constants/index.js';
import { mulberry32 } from '../combat/stats.js';

export type PveTargetPriority = 'FRONTLINE' | 'LOWEST_HP' | 'HIGHEST_ATK';
export const PVE_TELEPORT_STONE = 'TELEPORT_STONE';
export type PveRecallPolicy = 'FREE' | 'UNTIL_COMPLETE';
export function defaultPveRecallPolicy(floor: number): PveRecallPolicy {
  return floor % 5 === 0 ? 'UNTIL_COMPLETE' : 'FREE';
}
export type PveTileKind = 'CAMP' | 'EMPTY' | 'RESOURCE' | 'ENEMY' | 'BOSS' | 'WALL' | 'ROCK';
export type PveSquadStatus = 'IDLE' | 'MOVING' | 'FIGHTING' | 'WITHDRAWN' | 'DEFEATED';
export interface PvePoint { x: number; y: number }
export interface PveFormationMember {
  heroId: string;
  slotIndex: number;
  skillOrder: string[];
}
export interface PvePlan {
  battleMode?: 'AUTO' | 'MANUAL';
  targetPriority: PveTargetPriority;
  members: PveFormationMember[];
}
export interface PveTile extends PvePoint {
  id: number;
  kind: PveTileKind;
  seed: number;
  resource?: { itemId: 'WOOD' | 'STONE' | 'FOOD' | 'ALCHEMY_HERB_1'; quantity: number };
}
export interface PveLayout {
  algorithmVersion: number;
  width: number;
  height: number;
  tiles: PveTile[];
}

export class PveRuleError extends Error {
  constructor(readonly code: string) { super(code); this.name = 'PveRuleError'; }
}

export function pveSeed(value: string): number {
  // Explicit namespace/version keeps the existing World Seed algorithms intact.
  let hash = 2166136261;
  for (const char of value) hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  return hash >>> 0;
}

export function pveTileId(point: PvePoint, width: number = GAME_CONSTANTS.PVE.MAP_WIDTH): number {
  return point.y * width + point.x;
}

export function pveNeighbors(point: PvePoint, width: number, height: number): PvePoint[] {
  return [{ x: point.x, y: point.y - 1 }, { x: point.x + 1, y: point.y },
    { x: point.x, y: point.y + 1 }, { x: point.x - 1, y: point.y }]
    .filter(p => p.x >= 0 && p.y >= 0 && p.x < width && p.y < height);
}

export function generatePveLayout(worldSeed: string, floor: number, version: number = GAME_CONSTANTS.PVE.ALGORITHM_VERSION): PveLayout {
  if (!worldSeed || !Number.isSafeInteger(floor) || floor < 1) throw new PveRuleError('ERR_PVE_INVALID_SEED');
  if (version !== 1) throw new PveRuleError('ERR_PVE_ALGORITHM_UNSUPPORTED');
  const { MAP_WIDTH: width, MAP_HEIGHT: height } = GAME_CONSTANTS.PVE;
  const random = mulberry32(pveSeed(`pve:v${version}:${worldSeed}:${floor}`));
  const tiles: PveTile[] = Array.from({ length: width * height }, (_, id) => ({
    id, x: id % width, y: Math.floor(id / width), kind: 'EMPTY', seed: Math.floor(random() * 0x100000000),
  }));
  tiles[0].kind = 'CAMP';
  tiles[tiles.length - 1].kind = 'BOSS';
  // No impassable terrain in v1: every node is reachable. Keep the camp's first two steps safe.
  const candidates = tiles.filter(t => t.x + t.y > 2 && t.kind === 'EMPTY');
  for (let i = candidates.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [candidates[i], candidates[j]] = [candidates[j], candidates[i]];
  }
  const items = ['WOOD', 'STONE', 'FOOD'] as const;
  candidates.slice(0, 18).forEach((tile, index) => {
    tile.kind = 'RESOURCE';
    tile.resource = { itemId: items[index % items.length], quantity: 10 + 2 * floor };
  });
  candidates.slice(18, 36).forEach(tile => { tile.kind = 'ENEMY'; });
  return { algorithmVersion: version, width, height, tiles };
}

export function revealPveTiles(layout: PveLayout, discovered: readonly number[], position: PvePoint): number[] {
  return [...new Set([...discovered, pveTileId(position, layout.width),
    ...pveNeighbors(position, layout.width, layout.height).map(p => pveTileId(p, layout.width))])].sort((a, b) => a - b);
}

/** A shortest four-way path. Unknown tiles may be the destination, never intermediate steps. */
export function findPvePath(layout: PveLayout, discovered: readonly number[], from: PvePoint, to: PvePoint): PvePoint[] {
  if (![to.x, to.y, from.x, from.y].every(Number.isSafeInteger)
    || [from, to].some(p => p.x < 0 || p.y < 0 || p.x >= layout.width || p.y >= layout.height)) {
    throw new PveRuleError('ERR_PVE_INVALID_DESTINATION');
  }
  const start = pveTileId(from, layout.width);
  const end = pveTileId(to, layout.width);
  if (start === end) return [];
  const known = new Set(discovered);
  const previous = new Map<number, number>([[start, -1]]);
  const queue: PvePoint[] = [from];
  for (let index = 0; index < queue.length; index++) {
    const here = queue[index];
    for (const next of pveNeighbors(here, layout.width, layout.height)) {
      const id = pveTileId(next, layout.width);
      if (previous.has(id) || (!known.has(id) && id !== end)) continue;
      previous.set(id, pveTileId(here, layout.width));
      if (id === end) {
        const ids: number[] = [];
        for (let cursor = end; cursor !== start; cursor = previous.get(cursor)!) ids.push(cursor);
        return ids.reverse().map(tileId => ({ x: tileId % layout.width, y: Math.floor(tileId / layout.width) }));
      }
      queue.push(next);
    }
  }
  throw new PveRuleError('ERR_PVE_DESTINATION_UNDISCOVERED');
}

export function defaultPvePlan(heroIds: readonly string[]): PvePlan {
  return validatePvePlan({ targetPriority: 'FRONTLINE', members: heroIds.map((heroId, index) => ({
    heroId, slotIndex: [0, 2, 4, 6, 8][index], skillOrder: [],
  })) }, heroIds);
}

/** Reject partial/duplicate layouts rather than silently rearranging a player's formation. */
export function validatePvePlan(value: unknown, heroIds: readonly string[]): PvePlan {
  if (heroIds.length < 1 || heroIds.length > 5 || new Set(heroIds).size !== heroIds.length) {
    throw new PveRuleError('ERR_PVE_INVALID_PARTY');
  }
  const plan = value as Partial<PvePlan> | null;
  if (!plan || (plan.battleMode !== undefined && !['AUTO','MANUAL'].includes(plan.battleMode)) || !['FRONTLINE', 'LOWEST_HP', 'HIGHEST_ATK'].includes(plan.targetPriority ?? '')
    || !Array.isArray(plan.members) || plan.members.length !== heroIds.length) {
    throw new PveRuleError('ERR_PVE_INVALID_PLAN');
  }
  const ids = new Set<string>(); const slots = new Set<number>();
  for (const member of plan.members) {
    if (!member || typeof member.heroId !== 'string' || !heroIds.includes(member.heroId) || ids.has(member.heroId)
      || !Number.isSafeInteger(member.slotIndex) || member.slotIndex < 0 || member.slotIndex > 8 || slots.has(member.slotIndex)
      || !Array.isArray(member.skillOrder) || member.skillOrder.length > 20 || new Set(member.skillOrder).size !== member.skillOrder.length
      || member.skillOrder.some(code => typeof code !== 'string' || code.length < 1 || code.length > 60)) {
      throw new PveRuleError('ERR_PVE_INVALID_PLAN');
    }
    ids.add(member.heroId); slots.add(member.slotIndex);
  }
  return { battleMode: plan.battleMode ?? 'AUTO', targetPriority: plan.targetPriority!, members: plan.members.map(member => ({
    heroId: member.heroId, slotIndex: member.slotIndex, skillOrder: [...member.skillOrder],
  })) };
}
