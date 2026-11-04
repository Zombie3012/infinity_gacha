/**
 * Domain 12 (P2) LiveOps rules: event scheduling windows and leaderboard maths.
 *
 * Sample tuning:
 * - STANDARD events last 14 days, MAJOR events 21 days, MINOR events 7 days
 * - every event keeps a 48h claim grace window after `end_at`
 * - a new MAJOR event needs 7 clear days after the previous one closed
 * - DUNGEON_PROGRESS ranks by highest floor, then fewest combat rounds
 * - COMBAT_POWER sums the five strongest Heroes
 * - season rewards: top 1 / top 3 / top 10 / top 50 tiers
 */

export const EVENT_DURATION_DAYS: Record<string, number> = { STANDARD: 14, MAJOR: 21, MINOR: 7 };
export const CLAIM_GRACE_HOURS = 48;
export const MAJOR_EVENT_COOLDOWN_DAYS = 7;
export const LEADERBOARD_BOARDS = ['DUNGEON_PROGRESS', 'COMBAT_POWER'] as const;
export type LeaderboardBoard = (typeof LEADERBOARD_BOARDS)[number];
export type EventType = 'STANDARD' | 'MAJOR' | 'MINOR';
export type EventPhase = 'SCHEDULED' | 'ACTIVE' | 'GRACE' | 'ENDED';

export function isLeaderboardBoard(value: string): value is LeaderboardBoard {
  return (LEADERBOARD_BOARDS as readonly string[]).includes(value);
}

export function eventWindow(startAt: Date, type: EventType): { endAt: Date; claimDeadline: Date } {
  const days = EVENT_DURATION_DAYS[type] ?? 14;
  const endAt = new Date(startAt.getTime() + days * 86_400_000);
  const claimDeadline = new Date(endAt.getTime() + CLAIM_GRACE_HOURS * 3_600_000);
  return { endAt, claimDeadline };
}

/** Scenario 3.4: progress stops at `end_at`, claims stay open until the deadline. */
export function eventPhase(startAt: Date, endAt: Date, claimDeadline: Date, now: Date): EventPhase {
  if (now < startAt) return 'SCHEDULED';
  if (now < endAt) return 'ACTIVE';
  if (now < claimDeadline) return 'GRACE';
  return 'ENDED';
}

export function acceptsProgress(startAt: Date, endAt: Date, now: Date): boolean {
  return now >= startAt && now < endAt;
}

export function acceptsClaims(claimDeadline: Date, now: Date): boolean {
  return now < claimDeadline;
}

/** Scenario 3.2: two STANDARD events may not run at the same time. */
export function overlapsStandard(
  candidate: { startAt: Date; endAt: Date },
  running: { startAt: Date; endAt: Date }[],
): boolean {
  return running.some(other => candidate.startAt < other.endAt && other.startAt < candidate.endAt);
}

/** Scenario 3.3: MAJOR events need a cooldown after the previous one closed. */
export function majorCooldownViolated(candidateStart: Date, previousEnd: Date | null, cooldownDays = MAJOR_EVENT_COOLDOWN_DAYS): boolean {
  if (!previousEnd) return false;
  const earliest = new Date(previousEnd.getTime() + cooldownDays * 86_400_000);
  return candidateStart < earliest;
}

export interface CombatStats {
  hp: number;
  attack: number;
  defense: number;
  speed: number;
}

export function combatPower(stats: CombatStats): number {
  return Math.round(
    stats.attack * 3 + stats.defense * 2 + stats.speed * 2 + Math.max(0, stats.hp) / 10,
  );
}

export function topCombatPower(heroes: CombatStats[], limit = 5): number {
  return heroes
    .map(combatPower)
    .sort((a, b) => b - a)
    .slice(0, limit)
    .reduce((sum, value) => sum + value, 0);
}

export interface RankInput {
  masterId: string;
  floor: number;
  rounds: number;
  combatPower: number;
}

export interface RankedEntry extends RankInput {
  rank: number;
  score: number;
}

export function rankDungeonProgress(entries: RankInput[]): RankedEntry[] {
  return [...entries]
    .sort((a, b) => b.floor - a.floor || a.rounds - b.rounds || a.masterId.localeCompare(b.masterId))
    .map((entry, index) => ({ ...entry, rank: index + 1, score: entry.floor * 1_000_000 - entry.rounds }));
}

export function rankCombatPower(entries: RankInput[]): RankedEntry[] {
  return [...entries]
    .sort((a, b) => b.combatPower - a.combatPower || a.masterId.localeCompare(b.masterId))
    .map((entry, index) => ({ ...entry, rank: index + 1, score: entry.combatPower }));
}

export interface RankReward {
  silver: number;
  gems: number;
}

export function rewardForRank(rank: number): RankReward | null {
  if (rank <= 1) return { silver: 50_000, gems: 300 };
  if (rank <= 3) return { silver: 30_000, gems: 150 };
  if (rank <= 10) return { silver: 15_000, gems: 80 };
  if (rank <= 50) return { silver: 5_000, gems: 20 };
  return null;
}

export interface EventReward {
  silver: number;
  gems: number;
  items: { itemId: string; quantity: number }[];
}

export function normalizeRewardShape(raw: unknown): EventReward {
  const source = raw && typeof raw === 'object' ? raw as Record<string, unknown> : {};
  const itemsRaw = Array.isArray(source.items) ? source.items : [];
  return {
    silver: Math.max(0, Math.floor(Number(source.silver) || 0)),
    gems: Math.max(0, Math.floor(Number(source.gems) || 0)),
    items: itemsRaw
      .map(entry => {
        const row = entry as Record<string, unknown>;
        return { itemId: String(row.itemId ?? ''), quantity: Math.max(0, Math.floor(Number(row.quantity) || 0)) };
      })
      .filter(row => row.itemId && row.quantity > 0),
  };
}
