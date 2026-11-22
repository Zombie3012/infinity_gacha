import type { GameDatabase } from '../../database/transaction.js';
import { and, asc, eq, inArray, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  achievementProgress, achievements, heroes, masterItems, masters, questDefinitions, questProgress,
} from '../../database/drizzle-schema.js';
import {
  DAILY_QUEST_COUNT, clampProgress, dailyPeriodKey, isClaimable, normalizeReward, periodKeyFor, selectDailyQuestCodes,
  statusFor, weeklyPeriodKey, type ObjectiveType, type QuestStatus, type QuestType,
} from './quest-rules.js';

export class QuestError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'QuestError';
  }
}

type DefinitionRow = typeof questDefinitions.$inferSelect;

const shape = (definition: DefinitionRow, row: typeof questProgress.$inferSelect) => ({
  code: definition.code,
  name: definition.name,
  description: definition.description,
  questType: definition.questType,
  objectiveType: definition.objectiveType,
  targetCount: definition.targetCount,
  reward: normalizeReward(definition.reward),
  progress: row.progress,
  status: row.status,
  periodKey: row.periodKey,
  completedAt: row.completedAt,
  claimedAt: row.claimedAt,
});

export class QuestService {
  /** Instantiate the quest rows a Master should see right now. */
  async ensure(masterId: string, now = new Date()) {
    const definitions = await db.select().from(questDefinitions)
      .where(eq(questDefinitions.isActive, true)).orderBy(asc(questDefinitions.sortOrder), asc(questDefinitions.code));
    if (definitions.length === 0) return;

    const existing = await db.select().from(questProgress).where(eq(questProgress.masterId, masterId));
    const known = new Set(existing.map(row => `${row.questCode}|${row.periodKey}`));
    const inserts: (typeof questProgress.$inferInsert)[] = [];

    const dailyPool = definitions.filter(row => row.questType === 'DAILY').map(row => row.code);
    const dailyCodes = new Set(selectDailyQuestCodes(dailyPool, now, DAILY_QUEST_COUNT));

    for (const definition of definitions) {
      const type = definition.questType as QuestType;
      if (type === 'SIDE') continue; // side quests are accepted explicitly
      if (type === 'DAILY' && !dailyCodes.has(definition.code)) continue;
      const periodKey = periodKeyFor(type, now);
      if (known.has(`${definition.code}|${periodKey}`)) continue;
      inserts.push({
        id: uuidv4(), masterId, questCode: definition.code, periodKey,
        progress: 0, status: 'ACTIVE', acceptedAt: now,
      });
    }
    if (inserts.length > 0) await db.insert(questProgress).values(inserts).onConflictDoNothing();
  }

  private async rowsFor(masterId: string) {
    const rows = await db.select({ progress: questProgress, definition: questDefinitions })
      .from(questProgress).innerJoin(questDefinitions, eq(questDefinitions.code, questProgress.questCode))
      .where(eq(questProgress.masterId, masterId));
    return rows;
  }

  async overview(masterId: string, now = new Date()) {
    await this.ensure(masterId, now);
    const rows = await this.rowsFor(masterId);
    const currentDaily = dailyPeriodKey(now);
    const currentWeekly = weeklyPeriodKey(now);

    const main = rows.filter(row => row.definition.questType === 'MAIN').map(row => shape(row.definition, row.progress));
    const side = rows.filter(row => row.definition.questType === 'SIDE').map(row => shape(row.definition, row.progress));
    const daily = rows.filter(row => row.definition.questType === 'DAILY' && row.progress.periodKey === currentDaily)
      .map(row => shape(row.definition, row.progress));
    const weekly = rows.filter(row => row.definition.questType === 'WEEKLY' && row.progress.periodKey === currentWeekly)
      .map(row => shape(row.definition, row.progress));

    const acceptedSide = new Set(side.map(row => row.code));
    const availableSide = (await db.select().from(questDefinitions)
      .where(and(eq(questDefinitions.isActive, true), eq(questDefinitions.questType, 'SIDE')))
      .orderBy(asc(questDefinitions.sortOrder)))
      .filter(row => !acceptedSide.has(row.code))
      .map(row => ({
        code: row.code, name: row.name, description: row.description, questType: row.questType,
        objectiveType: row.objectiveType, targetCount: row.targetCount, reward: normalizeReward(row.reward),
      }));

    return {
      periods: { daily: currentDaily, weekly: currentWeekly },
      main,
      side,
      availableSide,
      daily,
      weekly,
      summary: {
        completed: [...main, ...side, ...daily, ...weekly].filter(row => row.status === 'COMPLETED').length,
        claimed: [...main, ...side, ...daily, ...weekly].filter(row => row.status === 'CLAIMED').length,
        dailyTarget: DAILY_QUEST_COUNT,
      },
      achievements: await this.achievementOverview(masterId),
    };
  }

  async achievementOverview(masterId: string) {
    const definitions = await db.select().from(achievements)
      .where(eq(achievements.isActive, true)).orderBy(asc(achievements.threshold), asc(achievements.code));
    const progressRows = await db.select().from(achievementProgress).where(eq(achievementProgress.masterId, masterId));
    const byCode = new Map(progressRows.map(row => [row.achievementCode, row]));
    const [heroCount] = await db.select({ total: sql<number>`count(*)::int` }).from(heroes).where(eq(heroes.masterId, masterId));

    const result = [];
    for (const definition of definitions) {
      const stored = byCode.get(definition.code);
      let progress = stored?.progress ?? 0;
      if (definition.metric === 'OWN_HEROES') progress = heroCount?.total ?? 0;
      const unlocked = progress >= definition.threshold;
      result.push({
        code: definition.code,
        name: definition.name,
        description: definition.description,
        category: definition.category,
        metric: definition.metric,
        threshold: definition.threshold,
        progress,
        reward: normalizeReward(definition.reward),
        unlocked,
        claimed: Boolean(stored?.claimedAt),
      });
    }
    return result;
  }

  async accept(masterId: string, code: string, now = new Date()) {
    const [definition] = await db.select().from(questDefinitions).where(eq(questDefinitions.code, code)).limit(1);
    if (!definition || definition.questType !== 'SIDE') throw new QuestError('Nhiệm vụ phụ không tồn tại.', 404);
    const [existing] = await db.select().from(questProgress)
      .where(and(eq(questProgress.masterId, masterId), eq(questProgress.questCode, code), eq(questProgress.periodKey, ''))).limit(1);
    if (existing) throw new QuestError('Nhiệm vụ đã được nhận.', 409);
    const [row] = await db.insert(questProgress).values({
      id: uuidv4(), masterId, questCode: code, periodKey: '', progress: 0, status: 'ACTIVE', acceptedAt: now,
    }).returning();
    return shape(definition, row);
  }

  /** Push gameplay events into active quests and lifetime achievements. */
  async recordEvent(masterId: string, objectiveType: ObjectiveType, amount = 1, now = new Date(), database: GameDatabase = db) {
    const rows = await database.select({ progress: questProgress, definition: questDefinitions })
      .from(questProgress).innerJoin(questDefinitions, eq(questDefinitions.code, questProgress.questCode))
      .where(and(eq(questProgress.masterId, masterId), eq(questProgress.status, 'ACTIVE'), eq(questDefinitions.objectiveType, objectiveType), lte(questProgress.acceptedAt, now)));
    let updated = 0;
    for (const row of rows) {
      const nextProgress = clampProgress(row.progress.progress, amount, row.definition.targetCount);
      const nextStatus = statusFor(nextProgress, row.definition.targetCount, row.progress.status as QuestStatus);
      await database.update(questProgress).set({
        progress: nextProgress,
        status: nextStatus,
        ...(nextStatus === 'COMPLETED' && row.progress.status !== 'COMPLETED' ? { completedAt: now } : {}),
      }).where(eq(questProgress.id, row.progress.id));
      updated += 1;
    }

    const achievementRows = await database.select().from(achievements)
      .where(and(eq(achievements.isActive, true), eq(achievements.metric, objectiveType)));
    for (const achievement of achievementRows) {
      const [stored] = await database.select().from(achievementProgress)
        .where(and(eq(achievementProgress.masterId, masterId), eq(achievementProgress.achievementCode, achievement.code))).limit(1);
      const nextProgress = Math.min(achievement.threshold, (stored?.progress ?? 0) + Math.max(0, amount));
      const unlocked = nextProgress >= achievement.threshold;
      await database.insert(achievementProgress).values({
        masterId, achievementCode: achievement.code, progress: nextProgress,
        unlockedAt: unlocked ? (stored?.unlockedAt ?? now) : null,
      }).onConflictDoUpdate({
        target: [achievementProgress.masterId, achievementProgress.achievementCode],
        set: { progress: nextProgress, ...(unlocked && !stored?.unlockedAt ? { unlockedAt: now } : {}) },
      });
    }
    return { questsUpdated: updated };
  }

  private async grantReward(masterId: string, reward: ReturnType<typeof normalizeReward>, now: Date) {
    if (reward.silver > 0 || reward.gems > 0) {
      await db.update(masters).set({
        ...(reward.silver > 0 ? { silverCoins: sql`${masters.silverCoins} + ${reward.silver}` } : {}),
        ...(reward.gems > 0 ? { gems: sql`${masters.gems} + ${reward.gems}` } : {}),
        updatedAt: now,
      }).where(eq(masters.id, masterId));
    }
    for (const entry of reward.items) {
      await db.insert(masterItems).values({
        id: uuidv4(), masterId, itemId: entry.itemId, quantity: entry.quantity, updatedAt: now,
      }).onConflictDoUpdate({
        target: [masterItems.masterId, masterItems.itemId],
        set: { quantity: sql`${masterItems.quantity} + ${entry.quantity}`, updatedAt: now },
      });
    }
  }

  async claimQuest(masterId: string, code: string, now = new Date()) {
    const [definition] = await db.select().from(questDefinitions).where(eq(questDefinitions.code, code)).limit(1);
    if (!definition) throw new QuestError('Nhiệm vụ không tồn tại.', 404);
    const periodKey = periodKeyFor(definition.questType as QuestType, now);
    const [row] = await db.select().from(questProgress)
      .where(and(eq(questProgress.masterId, masterId), eq(questProgress.questCode, code), eq(questProgress.periodKey, periodKey)))
      .limit(1);
    if (!row) throw new QuestError('Bạn chưa nhận nhiệm vụ này.', 404);
    if (!isClaimable(row.status as QuestStatus)) throw new QuestError('Nhiệm vụ chưa hoàn thành.', 409);

    const reward = normalizeReward(definition.reward);
    await db.transaction(async tx => {
      await this.grantReward(masterId, reward, now);
      await tx.update(questProgress).set({ status: 'CLAIMED', claimedAt: now }).where(eq(questProgress.id, row.id));
    });
    return { code, reward, claimedAt: now };
  }

  async claimAchievement(masterId: string, code: string, now = new Date()) {
    const [definition] = await db.select().from(achievements).where(eq(achievements.code, code)).limit(1);
    if (!definition) throw new QuestError('Thành tựu không tồn tại.', 404);
    const overview = await this.achievementOverview(masterId);
    const current = overview.find(row => row.code === code);
    if (!current?.unlocked) throw new QuestError('Thành tựu chưa mở khoá.', 409);
    if (current.claimed) throw new QuestError('Thành tựu đã nhận thưởng.', 409);

    const reward = normalizeReward(definition.reward);
    await db.transaction(async tx => {
      await this.grantReward(masterId, reward, now);
      await tx.insert(achievementProgress).values({
        masterId, achievementCode: code, progress: current.progress, unlockedAt: now, claimedAt: now,
      }).onConflictDoUpdate({
        target: [achievementProgress.masterId, achievementProgress.achievementCode],
        set: { claimedAt: now, unlockedAt: now },
      });
    });
    return { code, reward, claimedAt: now };
  }
}

export const questService = new QuestService();
