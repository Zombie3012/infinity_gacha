/**
 * Domain 13 / MOD-13-07 (P3) world-war and conquest rules.
 *
 * Sample tuning (prototype):
 * - a World Conquest season lasts 30 days
 * - the Central Imperial Wonder at (500, 500) opens for contest in the last
 *   3 days of the season; an alliance that holds it for 8 continuous hours
 *   becomes the Conqueror Alliance
 * - an alliance war lasts 24 hours; each side scores points from won hero
 *   battles (territory captures), repelled defences and wonder sieges
 * - the alliance with more points wins; equal points is a draw
 * - the season ranking pays its top alliances through the mailbox
 */

export const SEASON_DURATION_DAYS = 30;
export const WONDER_CONTEST_DAYS = 3;
export const WONDER_HOLD_HOURS = 8;
export const WONDER_HOLD_SECONDS = WONDER_HOLD_HOURS * 3_600;
export const WAR_DURATION_HOURS = 24;
export const WONDER_COORDINATES = { x: 500, y: 500 };
export const WONDER_GUARDIAN_POWER = 25_000;
export const WONDER_POINTS_PER_HOUR = 10;
export const RANKING_SIZE = 10;

export const WAR_POINTS = {
  TERRITORY_CAPTURE: 100,
  DEFENSE_HOLD: 50,
  WONDER_SEIZURE: 500,
  WAR_VICTORY: 300,
} as const;

export type WarEngagementKind = keyof typeof WAR_POINTS;

export interface RewardBundle {
  silver: number;
  gems: number;
  specialScrolls: number;
}

export const WAR_REWARDS: { WINNER: RewardBundle; LOSER: RewardBundle } = {
  WINNER: { silver: 5_000, gems: 100, specialScrolls: 0 },
  LOSER: { silver: 1_000, gems: 0, specialScrolls: 0 },
};

export const SEASON_REWARDS: { rank: number; reward: RewardBundle; title: string; frame: string | null }[] = [
  { rank: 1, reward: { silver: 50_000, gems: 2_000, specialScrolls: 10 }, title: 'Bá Chủ Thế Giới', frame: 'CONQUEROR_FRAME' },
  { rank: 2, reward: { silver: 25_000, gems: 1_000, specialScrolls: 5 }, title: 'Thống Trị', frame: 'CONQUEROR_FRAME' },
  { rank: 3, reward: { silver: 10_000, gems: 500, specialScrolls: 3 }, title: 'Chinh Phục', frame: null },
  { rank: 4, reward: { silver: 5_000, gems: 200, specialScrolls: 1 }, title: 'Chiến Binh', frame: null },
];

export function seasonWindow(start: Date, days = SEASON_DURATION_DAYS): { startTime: Date; endTime: Date } {
  return { startTime: start, endTime: new Date(start.getTime() + days * 86_400_000) };
}

export function contestOpensAt(endTime: Date, days = WONDER_CONTEST_DAYS): Date {
  return new Date(endTime.getTime() - days * 86_400_000);
}

/** The Wonder can only change hands during the final contest window. */
export function isContestOpen(season: { startTime: Date; endTime: Date; status: string }, now: Date): boolean {
  if (season.status !== 'ACTIVE') return false;
  return now >= contestOpensAt(season.endTime) && now < season.endTime;
}

export function warWindow(start: Date, hours = WAR_DURATION_HOURS): { startedAt: Date; endsAt: Date } {
  return { startedAt: start, endsAt: new Date(start.getTime() + hours * 3_600_000) };
}

export function secondsRemaining(until: Date, now: Date): number {
  return Math.max(0, Math.ceil((until.getTime() - now.getTime()) / 1000));
}

export function decideWar(input: {
  declaringPoints: number;
  targetPoints: number;
  declaringAllianceId: string;
  targetAllianceId: string;
}): { winnerAllianceId: string | null; draw: boolean } {
  if (input.declaringPoints === input.targetPoints) return { winnerAllianceId: null, draw: true };
  return {
    winnerAllianceId: input.declaringPoints > input.targetPoints ? input.declaringAllianceId : input.targetAllianceId,
    draw: false,
  };
}

export interface RankingEntry {
  allianceId: string;
  name: string;
  tag: string;
  points: number;
}

export interface RankedAlliance extends RankingEntry {
  rank: number;
}

/** Competition ranking: equal points share a rank. */
export function rankAlliances(entries: readonly RankingEntry[], limit = RANKING_SIZE): RankedAlliance[] {
  const sorted = [...entries].sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
  let previousPoints: number | null = null;
  let previousRank = 0;
  return sorted.slice(0, limit).map((entry, index) => {
    const rank = previousPoints === entry.points ? previousRank : index + 1;
    previousPoints = entry.points;
    previousRank = rank;
    return { ...entry, rank };
  });
}

export function seasonRewardFor(rank: number): { reward: RewardBundle; title: string; frame: string | null } | null {
  return SEASON_REWARDS.find(entry => entry.rank === rank) ?? null;
}

export interface WonderProgress {
  seconds: number;
  requiredSeconds: number;
  remainingSeconds: number;
  percent: number;
  complete: boolean;
}

export function wonderProgress(accumulatedSeconds: number): WonderProgress {
  const seconds = Math.max(0, Math.floor(accumulatedSeconds));
  const clamped = Math.min(WONDER_HOLD_SECONDS, seconds);
  return {
    seconds: clamped,
    requiredSeconds: WONDER_HOLD_SECONDS,
    remainingSeconds: Math.max(0, WONDER_HOLD_SECONDS - clamped),
    percent: Math.round((clamped / WONDER_HOLD_SECONDS) * 1000) / 10,
    complete: clamped >= WONDER_HOLD_SECONDS,
  };
}

/**
 * Continuous hold accumulation. Time only counts while the contest window is
 * open; the clock is clamped to the window opening so a hold that started
 * before the window never banks pre-contest seconds.
 */
export function accumulateHold(
  previousSeconds: number,
  heldSince: Date | null,
  lastSettledAt: Date | null,
  now: Date,
  contestOpenAt: Date | null,
): number {
  const base = Math.max(0, Math.floor(previousSeconds));
  if (!heldSince || !contestOpenAt) return base;
  const from = Math.max(
    heldSince.getTime(),
    lastSettledAt?.getTime() ?? heldSince.getTime(),
    contestOpenAt.getTime(),
  );
  const elapsed = Math.max(0, Math.floor((now.getTime() - from) / 1000));
  return Math.min(WONDER_HOLD_SECONDS, base + elapsed);
}

/** Hourly conquest points earned by holding the Wonder. */
export function wonderPointsFor(previousSeconds: number, nextSeconds: number): number {
  const before = Math.floor(previousSeconds / 3_600);
  const after = Math.floor(nextSeconds / 3_600);
  return Math.max(0, after - before) * WONDER_POINTS_PER_HOUR;
}

export function isWonderTile(tile: { terrain?: string | null; resourceType?: string | null }): boolean {
  return tile.terrain === 'WONDER' || tile.resourceType === 'WONDER';
}

export function warRewardFor(won: boolean): RewardBundle {
  return won ? WAR_REWARDS.WINNER : WAR_REWARDS.LOSER;
}

/** The defence of the Wonder is the guardian plus any current holder power. */
export function wonderDefencePower(holderPower: number): number {
  return Math.max(WONDER_GUARDIAN_POWER, WONDER_GUARDIAN_POWER + Math.floor(holderPower * 0.5));
}
