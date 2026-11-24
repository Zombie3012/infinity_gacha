/**
 * Full-Planet 600x300 RTS Grid Rules (180,000 tiles: 5 Continents + Great Ocean + Imperial Wonder).
 *
 * Locked 1:1 coordinate mapping shared identically with Godot `PlanetCoordinates`:
 * - x in [0 .. PLANET_GRID_WIDTH - 1]  -> longitude in [-180 deg, +180 deg] (West -> East)
 * - y in [0 .. PLANET_GRID_HEIGHT - 1] -> latitude  in [+90 deg,  -90 deg] (North -> South)
 * - Angular step = 0.60 deg per tile
 */

export const PLANET_GRID_WIDTH = 600;
export const PLANET_GRID_HEIGHT = 300;
export const TILE_DEG_SIZE = 360 / PLANET_GRID_WIDTH; // 0.60 deg

export const MIN_SPAWN_SPACING_TILES = 10;
export const DEFAULT_CHUNK_RADIUS = 12;
export const MAX_CHUNK_RADIUS = 16;
export const MIN_CHUNK_RADIUS = 6;

export const PLAYABLE_CONTINENTS = [
  'emerald_reach',
  'crystal_wastes',
  'frostspire_crown',
  'skyshard_isles',
  'ashen_rift',
] as const;

export type PlanetContinentId = (typeof PLAYABLE_CONTINENTS)[number] | 'great_ocean' | 'imperial_wonder';

export const SPAWNABLE_TERRAINS = ['PLAINS', 'FOREST', 'HILLS'] as const;

export function gridToLatLon(gx: number, gy: number): { lat: number; lon: number } {
  const u = (gx + 0.5) / PLANET_GRID_WIDTH;
  const v = (gy + 0.5) / PLANET_GRID_HEIGHT;
  return {
    lat: (0.5 - v) * 180,
    lon: (u - 0.5) * 360,
  };
}

export function latLonToGrid(latDeg: number, lonDeg: number): { x: number; y: number } {
  const wrappedLon = ((((lonDeg + 180) % 360) + 360) % 360) - 180;
  const clampedLat = Math.max(-90, Math.min(90, latDeg));
  const u = (wrappedLon / 360) + 0.5;
  const v = 0.5 - (clampedLat / 180);
  return {
    x: Math.max(0, Math.min(PLANET_GRID_WIDTH - 1, Math.floor(u * PLANET_GRID_WIDTH))),
    y: Math.max(0, Math.min(PLANET_GRID_HEIGHT - 1, Math.floor(v * PLANET_GRID_HEIGHT))),
  };
}

export function clampChunkRadius(raw: unknown): number {
  const n = Number(raw);
  if (!Number.isFinite(n)) return DEFAULT_CHUNK_RADIUS;
  return Math.max(MIN_CHUNK_RADIUS, Math.min(MAX_CHUNK_RADIUS, Math.round(n)));
}

export function wrapGridX(x: number): number {
  const m = Math.round(x) % PLANET_GRID_WIDTH;
  return m < 0 ? m + PLANET_GRID_WIDTH : m;
}

export function clampGridY(y: number): number {
  return Math.max(0, Math.min(PLANET_GRID_HEIGHT - 1, Math.round(y)));
}

/** Shortest horizontal distance on a cylindrical 360-deg world (Chebyshev metric with horizontal wrap). */
export function planetTileDistance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  const rawDx = Math.abs(a.x - b.x);
  const dx = Math.min(rawDx, PLANET_GRID_WIDTH - rawDx);
  const dy = Math.abs(a.y - b.y);
  return Math.max(dx, dy);
}
