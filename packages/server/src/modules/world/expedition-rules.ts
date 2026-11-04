/**
 * Domain 13 (P3) hero expeditions — there is no army entity. Heroes themselves
 * travel, scout and fight on the global map.
 *
 * Sample tuning:
 * - an expedition carries 1–5 owned, alive, idle Heroes
 * - travel time is 30s per map tile of Chebyshev distance (minimum 30s)
 * - scouting returns a report (owner, defender power, yields) and consumes no resources
 * - attacking resolves the tile guardian against the party's combat power; winning
 *   clears the tile for that Master, which is the prerequisite for claiming it
 * - recalled expeditions return immediately and cannot claim or scout anything
 */

export const MAX_EXPEDITION_HEROES = 5;
export const SECONDS_PER_TILE = 30;
export const MIN_TRAVEL_SECONDS = 30;
export const GUARDIAN_TOLERANCE = 0.95;

export type ExpeditionMission = 'SCOUT' | 'ATTACK';
export type ExpeditionStatus = 'TRAVELING' | 'RETURNING' | 'COMPLETED' | 'RECALLED';

export function travelSeconds(distance: number): number {
  return Math.max(MIN_TRAVEL_SECONDS, Math.floor(Math.max(0, distance)) * SECONDS_PER_TILE);
}

export function validateParty(heroIds: readonly string[]): { ok: boolean; reason?: string } {
  if (heroIds.length < 1) return { ok: false, reason: 'ERR_EXPEDITION_EMPTY' };
  if (heroIds.length > MAX_EXPEDITION_HEROES) return { ok: false, reason: 'ERR_EXPEDITION_TOO_MANY_HEROES' };
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
  phase: 'TRAVELING' | 'RETURNING' | 'DONE';
  secondsRemaining: number;
} {
  if (status === 'COMPLETED' || status === 'RECALLED') {
    return { status, phase: 'DONE', secondsRemaining: 0 };
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
