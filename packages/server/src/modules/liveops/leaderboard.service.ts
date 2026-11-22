import type { GameDatabase } from '../../database/transaction.js';
import { and, desc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  floorRecords, heroes, leaderboardRewards, leaderboardSeasons, masters, worlds,
} from '../../database/drizzle-schema.js';
import { mailboxService } from '../shop/mailbox.service.js';
import { weeklyPeriodKey } from '../quest/quest-rules.js';
import {
  fetchMasterHeroesWithPower, fetchMasterTopCombatPower,
} from '../hero/hero-combat-power.js';
import {
  combatPower, rankCombatPower, rankDungeonProgress, rewardForRank, topCombatPower,
  type LeaderboardBoard, type RankInput,
} from './liveops-rules.js';

export class LeaderboardError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'LeaderboardError';
  }
}

export class LeaderboardService {
  /** Build the raw ranking inputs for one board across every Master. */
  async collect(board: LeaderboardBoard): Promise<RankInput[]> {
    const masterRows = await db.select({ id: masters.id, name: masters.masterName }).from(masters);
    if (masterRows.length === 0) return [];
    const ids = masterRows.map(row => row.id);

    const worldsRows = await db.select().from(worlds).where(inArray(worlds.masterId, ids));
    const worldByMaster = new Map(worldsRows.map(row => [row.masterId, row]));
    const floors = await db.select().from(floorRecords).where(inArray(floorRecords.masterId, ids));
    const bestRoundsByMaster = new Map<string, { floor: number; rounds: number }>();
    for (const record of floors) {
      const current = bestRoundsByMaster.get(record.masterId);
      if (!current || record.floor > current.floor || (record.floor === current.floor && record.rounds < current.rounds)) {
        bestRoundsByMaster.set(record.masterId, { floor: record.floor, rounds: record.rounds });
      }
    }

    if (board === 'COMBAT_POWER') {
      const powers = await Promise.all(ids.map(async id => ({
        masterId: id,
        combatPower: await fetchMasterTopCombatPower(id, 5),
      })));
      const powerByMaster = new Map(powers.map(p => [p.masterId, p.combatPower]));
      return masterRows.map(master => ({
        masterId: master.id,
        floor: worldByMaster.get(master.id)?.currentFloor ?? 1,
        rounds: 0,
        combatPower: powerByMaster.get(master.id) ?? 0,
      }));
    }

    return masterRows.map(master => {
      const best = bestRoundsByMaster.get(master.id);
      return {
        masterId: master.id,
        floor: best?.floor ?? worldByMaster.get(master.id)?.currentFloor ?? 1,
        rounds: best?.rounds ?? 9999,
        combatPower: 0,
      };
    });
  }

  async view(board: LeaderboardBoard, masterId?: string, limit = 50) {
    const [inputs, names] = await Promise.all([
      this.collect(board),
      db.select({ id: masters.id, name: masters.masterName }).from(masters),
    ]);
    const nameById = new Map(names.map(row => [row.id, row.name]));
    const ranked = (board === 'COMBAT_POWER' ? rankCombatPower(inputs) : rankDungeonProgress(inputs)).slice(0, limit);
    const [season] = await db.select().from(leaderboardSeasons)
      .where(and(eq(leaderboardSeasons.board, board), eq(leaderboardSeasons.status, 'OPEN')))
      .orderBy(desc(leaderboardSeasons.createdAt)).limit(1);

    return {
      board,
      season: season ? { id: season.id, periodKey: season.periodKey, status: season.status } : null,
      entries: ranked.map(row => ({
        rank: row.rank,
        masterId: row.masterId,
        masterName: nameById.get(row.masterId) ?? '—',
        floor: row.floor,
        rounds: row.rounds,
        combatPower: row.combatPower,
        score: row.score,
      })),
      viewer: masterId ? ranked.find(row => row.masterId === masterId) ?? null : null,
      totalPlayers: inputs.length,
    };
  }

  /**
   * Scenario 4.3: close the season, snapshot the top 50 and post rewards to the
   * in-game mailbox (the mailbox claim flow already exists).
   */
  async closeSeason(board: LeaderboardBoard, actor: string, now = new Date()) {
    const periodKey = weeklyPeriodKey(now);
    const [existing] = await db.select().from(leaderboardSeasons)
      .where(and(eq(leaderboardSeasons.board, board), eq(leaderboardSeasons.periodKey, periodKey))).limit(1);
    if (existing?.status === 'CLOSED') throw new LeaderboardError('Mùa giải đã kết toán.', 409);

    const inputs = await this.collect(board);
    const ranked = (board === 'COMBAT_POWER' ? rankCombatPower(inputs) : rankDungeonProgress(inputs)).slice(0, 50);

    const seasonId = existing?.id ?? uuidv4();
    if (!existing) {
      await db.insert(leaderboardSeasons).values({ id: seasonId, board, periodKey, status: 'OPEN', createdAt: now });
    }

    let rewarded = 0;
    for (const entry of ranked) {
      const reward = rewardForRank(entry.rank);
      if (!reward) continue;
      await db.insert(leaderboardRewards).values({
        id: uuidv4(), seasonId, masterId: entry.masterId, rank: entry.rank, score: entry.score, reward,
      }).onConflictDoNothing();
      await mailboxService.send({
        masterId: entry.masterId,
        sender: 'SYSTEM',
        subject: `Thưởng xếp hạng ${board} — hạng ${entry.rank}`,
        body: `Chúc mừng! Bạn đạt hạng ${entry.rank} trên bảng ${board} mùa ${periodKey}.`,
        attachments: { silver: reward.silver, items: [] },
      }).catch(error => console.error('[leaderboard] reward mail failed', error));
      rewarded += 1;
    }

    await db.update(leaderboardSeasons).set({ status: 'CLOSED', closedAt: now }).where(eq(leaderboardSeasons.id, seasonId));
    return { board, periodKey, seasonId, rewarded, closedBy: actor };
  }

  async seasons(board?: LeaderboardBoard) {
    const rows = await db.select().from(leaderboardSeasons)
      .where(board ? eq(leaderboardSeasons.board, board) : undefined)
      .orderBy(desc(leaderboardSeasons.createdAt)).limit(20);
    return rows;
  }

  /** Record the best (fewest rounds) clear per floor for the dungeon board. */
  async recordFloor(masterId: string, floor: number, rounds: number, now = new Date(), database: GameDatabase = db) {
    if (!Number.isInteger(floor) || floor < 2 || !Number.isFinite(rounds)) return { recorded: false };
    const [existing] = await database.select().from(floorRecords)
      .where(and(eq(floorRecords.masterId, masterId), eq(floorRecords.floor, floor))).limit(1);
    if (existing) {
      if (rounds >= existing.rounds) return { recorded: false };
      await database.update(floorRecords).set({ rounds, achievedAt: now }).where(eq(floorRecords.id, existing.id));
      return { recorded: true, improved: true };
    }
    await database.insert(floorRecords).values({ id: uuidv4(), masterId, floor, rounds, achievedAt: now });
    return { recorded: true, improved: false };
  }

  async combatPowerFor(masterId: string) {
    const heroesWithPower = await fetchMasterHeroesWithPower(masterId);
    const sorted = heroesWithPower.map(h => h.combatPower).sort((a, b) => b - a);
    return {
      total: sorted.slice(0, 5).reduce((sum, v) => sum + v, 0),
      heroes: heroesWithPower.length,
      single: sorted.slice(0, 5),
    };
  }
}

export const leaderboardService = new LeaderboardService();
