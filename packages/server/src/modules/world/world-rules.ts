/**
 * Domain 13 (P3) global-world rules.
 *
 * Sample tuning (prototype):
 * - Global World unlocks at Master level 15 and dungeon floor 10 cleared
 * - a new Master is placed on a random Outer Rim tile with a 48h Novice Shield
 *   and a 5-tile discovery radius around the base
 * - a tile can be discovered if it is inside the base radius or adjacent (1 tile)
 *   to an already discovered tile
 * - a Master may own at most 10 territories
 * - claiming protects the tile for 30 minutes; abandoning takes 10 minutes
 * - territory yield grows 50% per level
 */

export const UNLOCK_MASTER_LEVEL = 15;
export const UNLOCK_CLEARED_FLOOR = 10;
export const NOVICE_SHIELD_HOURS = 48;
export const DISCOVERY_RADIUS = 5;
export const MAX_TERRITORIES = 10;
export const CLAIM_PROTECTION_MINUTES = 30;
export const ABANDON_MINUTES = 10;
export const CLAIM_COST_SILVER = 2000;
export const UPGRADE_BASE_COST_SILVER = 1500;
export const MAX_TERRITORY_LEVEL = 5;

export interface UnlockState {
  masterLevel: number;
  clearedFloor: number;
}

export function canUnlockGlobal(state: UnlockState): { ok: boolean; reason?: 'ERR_WORLD_LEVEL_REQUIRED' | 'ERR_WORLD_FLOOR_REQUIRED' } {
  if (state.masterLevel < UNLOCK_MASTER_LEVEL) return { ok: false, reason: 'ERR_WORLD_LEVEL_REQUIRED' };
  if (state.clearedFloor < UNLOCK_CLEARED_FLOOR) return { ok: false, reason: 'ERR_WORLD_FLOOR_REQUIRED' };
  return { ok: true };
}

export function tileDistance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
}

export function isDiscoverable(
  tile: { x: number; y: number },
  base: { x: number; y: number },
  discovered: readonly { x: number; y: number }[],
  radius = DISCOVERY_RADIUS,
): boolean {
  if (tileDistance(tile, base) <= radius) return true;
  return discovered.some(point => tileDistance(tile, point) <= 1);
}

export function territoryYield(baseYield: number, level: number): number {
  return Math.round(baseYield * (1 + 0.5 * (Math.max(1, Math.floor(level)) - 1)) * 100) / 100;
}

export function upgradeCost(currentLevel: number): number {
  return UPGRADE_BASE_COST_SILVER * Math.max(1, Math.floor(currentLevel));
}

export function canClaim(ownedCount: number, alreadyOwned: boolean): { ok: boolean; reason?: string } {
  if (alreadyOwned) return { ok: false, reason: 'ERR_TERRITORY_ALREADY_OWNED' };
  if (ownedCount >= MAX_TERRITORIES) return { ok: false, reason: 'ERR_TERRITORY_LIMIT_REACHED' };
  return { ok: true };
}

export function protectionUntil(now: Date, minutes = CLAIM_PROTECTION_MINUTES): Date {
  return new Date(now.getTime() + minutes * 60_000);
}

export function abandonAt(now: Date, minutes = ABANDON_MINUTES): Date {
  return new Date(now.getTime() + minutes * 60_000);
}

export function shieldUntil(now: Date): Date {
  return new Date(now.getTime() + NOVICE_SHIELD_HOURS * 3_600_000);
}
