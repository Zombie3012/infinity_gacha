/**
 * Domain 12 (P1) quest and achievement rules.
 *
 * Sample tuning:
 * - daily quests roll over at 00:00 UTC+7
 * - weekly quests roll over on Thursday 00:00 UTC+7, matching the scroll exchange cap
 * - progress is capped at the objective target; the quest flips to COMPLETED once met
 * - achievements are lifetime counters and never reset
 */

export const QUEST_TIME_ZONE_OFFSET_MINUTES = 7 * 60;
export const DAILY_QUEST_COUNT = 5;

export type QuestType = 'MAIN' | 'SIDE' | 'DAILY' | 'WEEKLY';
export type QuestStatus = 'ACTIVE' | 'COMPLETED' | 'CLAIMED';
export type ObjectiveType =
  | 'WIN_BATTLE'
  | 'CLEAR_FLOOR'
  | 'CRAFT_ITEM'
  | 'SPEND_SILVER'
  | 'COLLECT_RESOURCE'
  | 'UPGRADE_BUILDING'
  | 'OWN_HEROES';

function shifted(now: Date): Date {
  return new Date(now.getTime() + QUEST_TIME_ZONE_OFFSET_MINUTES * 60_000);
}

export function dailyPeriodKey(now: Date): string {
  return shifted(now).toISOString().slice(0, 10);
}

/** Week starts on Thursday 00:00 UTC+7 (1 = Monday … 4 = Thursday). */
export function weeklyPeriodKey(now: Date): string {
  const local = shifted(now);
  const weekday = local.getUTCDay(); // 0 = Sunday
  const daysSinceThursday = (weekday + 3) % 7;
  const thursday = new Date(local.getTime() - daysSinceThursday * 86_400_000);
  return `W${thursday.toISOString().slice(0, 10)}`;
}

export function periodKeyFor(type: QuestType, now: Date): string {
  if (type === 'DAILY') return dailyPeriodKey(now);
  if (type === 'WEEKLY') return weeklyPeriodKey(now);
  return '';
}

export function clampProgress(current: number, delta: number, target: number): number {
  const next = Math.max(0, current) + Math.max(0, delta);
  return Math.min(Math.max(1, target), next);
}

export function statusFor(progress: number, target: number, current: QuestStatus): QuestStatus {
  if (current === 'CLAIMED') return 'CLAIMED';
  return progress >= target ? 'COMPLETED' : 'ACTIVE';
}

export function isClaimable(status: QuestStatus): boolean {
  return status === 'COMPLETED';
}

export interface QuestReward {
  silver: number;
  gems: number;
  items: { itemId: string; quantity: number }[];
}

export function normalizeReward(raw: unknown): QuestReward {
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

/** Deterministic daily rotation: the same date always yields the same selection. */
export function selectDailyQuestCodes(pool: readonly string[], now: Date, count = DAILY_QUEST_COUNT): string[] {
  const seed = dailyPeriodKey(now);
  return [...pool]
    .map(code => {
      let hash = 2166136261;
      for (const char of `${seed}:${code}`) {
        hash ^= char.charCodeAt(0);
        hash = Math.imul(hash, 16777619);
      }
      return { code, weight: Math.abs(hash) };
    })
    .sort((a, b) => a.weight - b.weight)
    .slice(0, Math.min(count, pool.length))
    .map(row => row.code);
}
