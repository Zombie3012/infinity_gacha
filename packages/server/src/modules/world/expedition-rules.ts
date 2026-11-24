/**
 * Domain 13 (P3) hero expeditions + Airship RTS rules.
 *
 * - Default party size without airship: 1–5 Heroes (backwards compatible)
 * - With an airship: capped by ship maxHeroes (Scout 3, Attack 5, Rescue 6, Transport 15)
 * - Travel time is scaled by airship speedMult (base 30s per Chebyshev tile, min 15s with fast ship)
 * - Missions:
 *   - SCOUT: scans flight path and leaves 1-hour dynamic vision (Fog of War)
 *   - DUNGEON: raids an Emerging World Dungeon (up to 15 Heroes with Transport Carrier)
 *   - RESCUE: dispatches Rescue Cutter (up to 6 Heroes) to recover a STRANDED expedition
 *   - ATTACK: legacy/PvP tile attack
 */

export const MAX_EXPEDITION_HEROES = 5;
export const MAX_TRANSPORT_HEROES = 15;
export const SECONDS_PER_TILE = 30;
export const MIN_TRAVEL_SECONDS = 15;
export const GUARDIAN_TOLERANCE = 0.95;

export type ExpeditionMission = 'SCOUT' | 'ATTACK' | 'DUNGEON' | 'RESCUE' | 'GARRISON';
export type ExpeditionStatus = 'TRAVELING' | 'RETURNING' | 'GARRISONED' | 'STRANDED' | 'COMPLETED' | 'RECALLED';

export function travelSeconds(distance: number, speedMult = 1): number {
  const safeSpeed = Math.max(0.5, speedMult);
  const raw = Math.floor(Math.max(0, distance)) * SECONDS_PER_TILE;
  return Math.max(MIN_TRAVEL_SECONDS, Math.round(raw / safeSpeed));
}

export function validateParty(heroIds: readonly string[], maxHeroes = MAX_EXPEDITION_HEROES): { ok: boolean; reason?: string } {
  if (heroIds.length < 1) return { ok: false, reason: 'ERR_EXPEDITION_EMPTY' };
  if (heroIds.length > maxHeroes) return { ok: false, reason: 'ERR_EXPEDITION_TOO_MANY_HEROES' };
  if (new Set(heroIds).size !== heroIds.length) return { ok: false, reason: 'ERR_EXPEDITION_DUPLICATE_HERO' };
  return { ok: true };
}

/** Attacking needs real strength; scouting can be done by anyone. */
export function resolveGuardianBattle(partyPower: number, guardianPower: number): { won: boolean; ratio: number } {
  const ratio = guardianPower <= 0 ? 99 : Math.round((partyPower / guardianPower) * 100) / 100;
  return { won: partyPower >= guardianPower * GUARDIAN_TOLERANCE, ratio };
}

export function canClaimCleared(cleared: boolean): { ok: boolean; reason?: string } {
  return cleared ? { ok: true } : { ok: false, reason: 'ERR_TERRITORY_NOT_CLEARED' };
}

export function expeditionProgress(status: ExpeditionStatus, arriveAt: Date, returnAt: Date | null, now: Date): {
  status: ExpeditionStatus;
  phase: 'TRAVELING' | 'RETURNING' | 'GARRISONED' | 'STRANDED' | 'DONE';
  secondsRemaining: number;
} {
  if (status === 'COMPLETED' || status === 'RECALLED') {
    return { status, phase: 'DONE', secondsRemaining: 0 };
  }
  if (status === 'GARRISONED') {
    return { status, phase: 'GARRISONED', secondsRemaining: 0 };
  }
  if (status === 'STRANDED') {
    return { status, phase: 'STRANDED', secondsRemaining: 0 };
  }
  if (status === 'RETURNING') {
    const target = returnAt ?? now;
    return { status, phase: 'RETURNING', secondsRemaining: Math.max(0, Math.ceil((target.getTime() - now.getTime()) / 1000)) };
  }
  return {
    status,
    phase: 'TRAVELING',
    secondsRemaining: Math.max(0, Math.ceil((arriveAt.getTime() - now.getTime()) / 1000)),
  };
}
