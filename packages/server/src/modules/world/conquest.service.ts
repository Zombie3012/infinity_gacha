import { and, asc, desc, eq, inArray, lte, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  allianceMembers, alliances, allianceWars, heroes, masters, warEngagements, wonderHoldings,
  worldConquestRankings, worldConquestSeasons, worldTiles,
} from '../../database/drizzle-schema.js';
import { topCombatPower } from '../liveops/liveops-rules.js';
import { mailboxService } from '../shop/mailbox.service.js';
import { currencyService } from '../economy/currency.service.js';
import { allianceService } from './alliance.service.js';
import { resolvePvp } from './pvp-rules.js';
import {
  WAR_POINTS, WONDER_COORDINATES, WONDER_HOLD_SECONDS, accumulateHold, contestOpensAt, decideWar,
  isContestOpen, rankAlliances, seasonRewardFor, seasonWindow, secondsRemaining, warRewardFor, warWindow,
  wonderDefencePower, wonderPointsFor, wonderProgress, type RewardBundle, type WarEngagementKind,
} from './conquest-rules.js';

export class ConquestError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ConquestError';
  }
}

type SeasonRow = typeof worldConquestSeasons.$inferSelect;
type WarRow = typeof allianceWars.$inferSelect;

const allianceName = (row: { name: string; tag: string }) => `${row.tag} · ${row.name}`;

export class ConquestService {
  // --- seasons ---------------------------------------------------------

  private async latestSeason(): Promise<SeasonRow | undefined> {
    const [row] = await db.select().from(worldConquestSeasons)
      .orderBy(desc(worldConquestSeasons.seasonNumber)).limit(1);
    return row;
  }

  private async createSeason(number: number, start: Date): Promise<SeasonRow> {
    const window = seasonWindow(start);
    const [row] = await db.insert(worldConquestSeasons).values({
      id: uuidv4(), seasonNumber: number, startTime: window.startTime, endTime: window.endTime,
      status: 'ACTIVE', createdAt: start,
    }).returning();
    // Each season opens with an unclaimed Wonder.
    await db.update(wonderHoldings).set({
      allianceId: null, heldSince: null, accumulatedSeconds: 0, lastSettledAt: start, updatedAt: start,
    }).catch(() => undefined);
    return row;
  }

  /**
   * Returns the running season, concluding an expired one and starting its
   * successor. A new season also starts immediately after an early Wonder win.
   */
  async ensureActiveSeason(now = new Date()): Promise<SeasonRow> {
    const season = await this.latestSeason();
    if (!season) return this.createSeason(1, now);
    if (season.status === 'ACTIVE' && now < season.endTime) return season;

    if (season.status === 'ACTIVE') {
      const conqueror = await this.wonderConqueror(season);
      await this.concludeSeason(season, conqueror, now);
    }
    return this.createSeason(season.seasonNumber + 1, now);
  }

  /** FUN-13-07-004: the alliance that held the Wonder for 8h during the contest. */
  private async wonderConqueror(_season: SeasonRow): Promise<string | null> {
    const holding = await this.holdingRow();
    if (!holding?.allianceId || holding.accumulatedSeconds < WONDER_HOLD_SECONDS) return null;
    return holding.allianceId;
  }

  // --- wonder ----------------------------------------------------------

  private async wonderTile() {
    const [tile] = await db.select().from(worldTiles)
      .where(and(eq(worldTiles.x, WONDER_COORDINATES.x), eq(worldTiles.y, WONDER_COORDINATES.y))).limit(1);
    return tile;
  }

  private async holdingRow() {
    const tile = await this.wonderTile();
    if (!tile) return undefined;
    const [row] = await db.select().from(wonderHoldings).where(eq(wonderHoldings.tileId, tile.id)).limit(1);
    if (row) return row;
    const [created] = await db.insert(wonderHoldings).values({
      tileId: tile.id, allianceId: null, heldSince: null, accumulatedSeconds: 0,
      lastSettledAt: new Date(), updatedAt: new Date(),
    }).onConflictDoNothing().returning();
    if (created) return created;
    const [again] = await db.select().from(wonderHoldings).where(eq(wonderHoldings.tileId, tile.id)).limit(1);
    return again;
  }

  private async alliancePower(allianceId: string): Promise<number> {
    const members = await db.select({ masterId: allianceMembers.masterId }).from(allianceMembers)
      .where(eq(allianceMembers.allianceId, allianceId));
    if (members.length === 0) return 0;
    const rows = await db.select({ hp: heroes.maxHp, attack: heroes.attack, defense: heroes.defense, speed: heroes.speed })
      .from(heroes).where(inArray(heroes.masterId, members.map(row => row.masterId)));
    return topCombatPower(rows.map(row => ({ hp: row.hp, attack: row.attack, defense: row.defense, speed: row.speed })));
  }

  /** Accrues continuous hold seconds and hourly conquest points. */
  private async advanceWonder(season: SeasonRow, now: Date) {
    const tile = await this.wonderTile();
    if (!tile) return null;
    const holding = await this.holdingRow();
    if (!holding) return null;

    if (holding.allianceId) {
      const open = isContestOpen(season, now);
      const next = accumulateHold(
        holding.accumulatedSeconds, holding.heldSince, holding.lastSettledAt, now,
        open ? contestOpensAt(season.endTime) : null,
      );
      const points = wonderPointsFor(holding.accumulatedSeconds, next);
      if (points > 0 && season.status === 'ACTIVE') {
        await this.addSeasonPoints(season.id, holding.allianceId, points, now);
      }
      const stale = !holding.lastSettledAt || now.getTime() - holding.lastSettledAt.getTime() > 1000;
      if (next !== holding.accumulatedSeconds || (open && stale)) {
        await db.update(wonderHoldings).set({
          accumulatedSeconds: next, lastSettledAt: now, updatedAt: now,
        }).where(eq(wonderHoldings.tileId, holding.tileId));
        holding.accumulatedSeconds = next;
      }
    }
    return holding;
  }

  private async wonderState(season: SeasonRow, now: Date) {
    const tile = await this.wonderTile();
    const holding = await this.holdingRow();
    const holder = holding?.allianceId
      ? (await db.select().from(alliances).where(eq(alliances.id, holding.allianceId)).limit(1))[0]
      : undefined;
    const progress = wonderProgress(holding?.accumulatedSeconds ?? 0);
    return {
      tile: tile ? { id: tile.id, x: tile.x, y: tile.y } : null,
      holder: holder ? { id: holder.id, name: holder.name, tag: holder.tag } : null,
      heldSince: holding?.heldSince ?? null,
      secondsHeld: progress.seconds,
      requiredSeconds: progress.requiredSeconds,
      remainingSeconds: progress.remainingSeconds,
      percent: progress.percent,
      complete: progress.complete,
      contestOpen: isContestOpen(season, now),
      contestOpensAt: contestOpensAt(season.endTime),
      defencePower: wonderDefencePower(holder ? await this.alliancePower(holder.id) : 0),
    };
  }

  /** FUN-13-07-003: an alliance storms the Central Imperial Wonder. */
  async siegeWonder(masterId: string, now = new Date()) {
    const membership = await db.select({ member: allianceMembers, alliance: alliances })
      .from(allianceMembers).innerJoin(alliances, eq(alliances.id, allianceMembers.allianceId))
      .where(eq(allianceMembers.masterId, masterId)).limit(1);
    if (membership.length === 0) throw new ConquestError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const own = membership[0];
    if (own.member.role === 'MEMBER') throw new ConquestError('ERR_ALLIANCE_ROLE_TOO_LOW', 403);

    const season = await this.ensureActiveSeason(now);
    if (!isContestOpen(season, now)) throw new ConquestError('ERR_WONDER_NOT_CONTESTED', 409);

    const holding = await this.advanceWonder(season, now);
    if (!holding?.tileId) throw new ConquestError('ERR_WONDER_UNAVAILABLE', 503);
    if (holding.allianceId === own.alliance.id) throw new ConquestError('ERR_WONDER_ALREADY_HELD', 409);

    const attackerPower = await this.alliancePower(own.alliance.id);
    if (attackerPower <= 0) throw new ConquestError('ERR_ALLIANCE_NO_POWER', 409);
    const defenderPower = wonderDefencePower(holding?.allianceId ? await this.alliancePower(holding.allianceId) : 0);
    const battle = resolvePvp(attackerPower, defenderPower, `${season.id}:${own.alliance.id}:${Math.floor(now.getTime() / 60_000)}`);
    const won = battle.winner === 'ATTACKER';

    if (won) {
      await db.transaction(async tx => {
        await tx.update(wonderHoldings).set({
          allianceId: own.alliance.id, heldSince: now, accumulatedSeconds: 0, lastSettledAt: now, updatedAt: now,
        }).where(eq(wonderHoldings.tileId, holding!.tileId));
      });
      await this.addSeasonPoints(season.id, own.alliance.id, WAR_POINTS.WONDER_SEIZURE, now);
      await this.recordEngagement({
        warId: await this.activeWarId(own.alliance.id, holding?.allianceId ?? null),
        attackerAllianceId: own.alliance.id,
        defenderAllianceId: holding?.allianceId ?? null,
        masterId, tileId: holding?.tileId ?? null, kind: 'WONDER_SEIZURE',
        points: WAR_POINTS.WONDER_SEIZURE, detail: { attackerPower, defenderPower, rounds: battle.rounds }, now,
      });
    } else if (holding?.allianceId) {
      await this.addSeasonPoints(season.id, holding.allianceId, WAR_POINTS.DEFENSE_HOLD, now);
      await this.recordEngagement({
        warId: await this.activeWarId(own.alliance.id, holding.allianceId),
        attackerAllianceId: own.alliance.id,
        defenderAllianceId: holding.allianceId,
        masterId, tileId: holding.tileId, kind: 'DEFENSE_HOLD',
        points: WAR_POINTS.DEFENSE_HOLD, detail: { attackerPower, defenderPower, rounds: battle.rounds }, now,
      });
    }

    return {
      won, winner: battle.winner, rounds: battle.rounds,
      attackerPower, defenderPower,
      alliance: { id: own.alliance.id, name: own.alliance.name, tag: own.alliance.tag },
      previousHolder: holding?.allianceId ?? null,
      holderAllianceId: won ? own.alliance.id : holding?.allianceId ?? null,
      progress: won ? wonderProgress(0) : wonderProgress(holding?.accumulatedSeconds ?? 0),
    };
  }

  // --- conquest points and ranking ------------------------------------

  async addSeasonPoints(seasonId: string, allianceId: string, points: number, now = new Date()) {
    if (points <= 0) return;
    await db.insert(worldConquestRankings).values({
      id: uuidv4(), seasonId, allianceId, totalConquestPoints: points, rewardClaimed: false, updatedAt: now,
    }).onConflictDoUpdate({
      target: [worldConquestRankings.seasonId, worldConquestRankings.allianceId],
      set: {
        totalConquestPoints: sql`${worldConquestRankings.totalConquestPoints} + ${points}`,
        updatedAt: now,
      },
    });
  }

  /** FUN-13-07-006: ranking for a season (defaults to the running one). */
  async ranking(seasonIdInput?: string, limit = 10) {
    const season = seasonIdInput
      ? (await db.select().from(worldConquestSeasons).where(eq(worldConquestSeasons.id, seasonIdInput)).limit(1))[0]
      : await this.latestSeason();
    if (!season) return { season: null, entries: [] };

    const rows = await db.select({
      allianceId: worldConquestRankings.allianceId,
      name: alliances.name,
      tag: alliances.tag,
      points: worldConquestRankings.totalConquestPoints,
      finalRank: worldConquestRankings.finalRank,
    }).from(worldConquestRankings)
      .innerJoin(alliances, eq(alliances.id, worldConquestRankings.allianceId))
      .where(eq(worldConquestRankings.seasonId, season.id))
      .orderBy(desc(worldConquestRankings.totalConquestPoints), asc(alliances.name));

    const ranked = rankAlliances(rows.map(row => ({
      allianceId: row.allianceId, name: row.name, tag: row.tag, points: row.points,
    })), limit);
    return {
      season: {
        id: season.id, seasonNumber: season.seasonNumber, status: season.status,
        startTime: season.startTime, endTime: season.endTime,
        conqueringAllianceId: season.conqueringAllianceId,
      },
      entries: ranked.map(entry => ({
        ...entry,
        finalRank: rows.find(row => row.allianceId === entry.allianceId)?.finalRank ?? null,
      })),
    };
  }

  async seasons(limit = 10) {
    return db.select().from(worldConquestSeasons)
      .orderBy(desc(worldConquestSeasons.seasonNumber)).limit(limit);
  }

  // --- wars ------------------------------------------------------------

  async declareWar(masterId: string, targetAllianceId: string, now = new Date()) {
    const [own] = await db.select({ member: allianceMembers, alliance: alliances })
      .from(allianceMembers).innerJoin(alliances, eq(alliances.id, allianceMembers.allianceId))
      .where(eq(allianceMembers.masterId, masterId)).limit(1);
    if (!own) throw new ConquestError('ERR_ALLIANCE_NOT_MEMBER', 403);
    if (own.member.role !== 'LEADER') throw new ConquestError('ERR_ALLIANCE_LEADER_ONLY', 403);
    if (targetAllianceId === own.alliance.id) throw new ConquestError('ERR_ALLIANCE_WAR_SELF', 409);

    const [target] = await db.select().from(alliances).where(eq(alliances.id, targetAllianceId)).limit(1);
    if (!target) throw new ConquestError('Không tìm thấy liên minh.', 404);

    const active = await db.select({ id: allianceWars.id }).from(allianceWars).where(and(
      eq(allianceWars.status, 'ACTIVE'),
      sql`(${allianceWars.declaringAllianceId} in (${own.alliance.id}, ${targetAllianceId})
        or ${allianceWars.targetAllianceId} in (${own.alliance.id}, ${targetAllianceId}))`,
    )).limit(1);
    if (active.length > 0) throw new ConquestError('ERR_ALLIANCE_WAR_BUSY', 409);

    const window = warWindow(now);
    const [war] = await db.insert(allianceWars).values({
      id: uuidv4(), declaringAllianceId: own.alliance.id, targetAllianceId,
      status: 'ACTIVE', startedAt: window.startedAt, endsAt: window.endsAt,
      declaringPoints: 0, targetPoints: 0, createdAt: now,
    }).returning();
    return this.decorateWar(war, own.alliance.id, now);
  }

  private decorateWar(war: WarRow, viewerAllianceId: string | null, now: Date) {
    return {
      ...war,
      secondsRemaining: secondsRemaining(war.endsAt, now),
      viewerSide: viewerAllianceId === null
        ? null
        : war.declaringAllianceId === viewerAllianceId ? 'DECLARING' : war.targetAllianceId === viewerAllianceId ? 'TARGET' : null,
    };
  }

  async listWars(masterId: string, now = new Date()) {
    await this.settleWars(now);
    const [own] = await db.select({ allianceId: allianceMembers.allianceId }).from(allianceMembers)
      .where(eq(allianceMembers.masterId, masterId)).limit(1);
    if (!own) return { allianceId: null, wars: [] };

    const rows = await db.select().from(allianceWars).where(sql`
      ${allianceWars.declaringAllianceId} = ${own.allianceId} or ${allianceWars.targetAllianceId} = ${own.allianceId}
    `).orderBy(desc(allianceWars.createdAt)).limit(20);
    const alliancesById = await this.allianceLookup(rows.flatMap(row => [row.declaringAllianceId, row.targetAllianceId]));

    return {
      allianceId: own.allianceId,
      wars: rows.map(row => {
        const opponentId = row.declaringAllianceId === own.allianceId ? row.targetAllianceId : row.declaringAllianceId;
        const opponent = alliancesById.get(opponentId);
        return {
          ...this.decorateWar(row, own.allianceId, now),
          opponent: opponent ? { id: opponent.id, name: opponent.name, tag: opponent.tag } : null,
        };
      }),
    };
  }

  async warDetail(masterId: string, warId: string, now = new Date()) {
    await this.settleWars(now);
    const [own] = await db.select({ allianceId: allianceMembers.allianceId }).from(allianceMembers)
      .where(eq(allianceMembers.masterId, masterId)).limit(1);
    if (!own) throw new ConquestError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const [war] = await db.select().from(allianceWars).where(eq(allianceWars.id, warId)).limit(1);
    if (!war) throw new ConquestError('Không tìm thấy cuộc chiến.', 404);
    if (war.declaringAllianceId !== own.allianceId && war.targetAllianceId !== own.allianceId) {
      throw new ConquestError('ERR_ALLIANCE_WAR_NOT_PARTICIPANT', 403);
    }
    const lookup = await this.allianceLookup([war.declaringAllianceId, war.targetAllianceId]);
    const engagements = await db.select().from(warEngagements)
      .where(eq(warEngagements.warId, war.id)).orderBy(desc(warEngagements.createdAt)).limit(20);
    return {
      ...this.decorateWar(war, own.allianceId, now),
      declaring: lookup.get(war.declaringAllianceId) ?? null,
      target: lookup.get(war.targetAllianceId) ?? null,
      engagements,
    };
  }

  private async allianceLookup(ids: string[]) {
    const unique = [...new Set(ids)].filter(Boolean);
    if (unique.length === 0) return new Map<string, { id: string; name: string; tag: string }>();
    const rows = await db.select({ id: alliances.id, name: alliances.name, tag: alliances.tag })
      .from(alliances).where(inArray(alliances.id, unique));
    return new Map(rows.map(row => [row.id, row]));
  }

  private async activeWarId(allianceA: string, allianceB: string | null): Promise<string | null> {
    if (!allianceB || allianceA === allianceB) return null;
    const [row] = await db.select({ id: allianceWars.id }).from(allianceWars).where(and(
      eq(allianceWars.status, 'ACTIVE'),
      sql`(${allianceWars.declaringAllianceId} = ${allianceA} and ${allianceWars.targetAllianceId} = ${allianceB})
        or (${allianceWars.declaringAllianceId} = ${allianceB} and ${allianceWars.targetAllianceId} = ${allianceA})`,
    )).limit(1);
    return row?.id ?? null;
  }

  private async recordEngagement(input: {
    warId: string | null;
    attackerAllianceId: string;
    defenderAllianceId: string | null;
    masterId: string | null;
    tileId: string | null;
    kind: WarEngagementKind;
    points: number;
    detail: Record<string, unknown>;
    now: Date;
  }) {
    if (!input.warId || !input.defenderAllianceId) return null;
    const [row] = await db.insert(warEngagements).values({
      id: uuidv4(), warId: input.warId, attackerAllianceId: input.attackerAllianceId,
      defenderAllianceId: input.defenderAllianceId, masterId: input.masterId, tileId: input.tileId,
      kind: input.kind, points: input.points, detail: input.detail, createdAt: input.now,
    }).returning();
    return row;
  }

  /**
   * Hook called from the expedition settlement: a won hero raid on a member of
   * an enemy alliance scores war points (MOD-13-07 FUN-13-07-002/003).
   */
  async recordPvp(input: {
    attackerMasterId: string;
    defenderMasterId: string | null;
    tileId: string;
    attackerWon: boolean;
    now?: Date;
  }) {
    const now = input.now ?? new Date();
    if (!input.defenderMasterId) return { recorded: false };
    const [attacker, defender] = await Promise.all([
      db.select({ allianceId: allianceMembers.allianceId }).from(allianceMembers)
        .where(eq(allianceMembers.masterId, input.attackerMasterId)).limit(1),
      db.select({ allianceId: allianceMembers.allianceId }).from(allianceMembers)
        .where(eq(allianceMembers.masterId, input.defenderMasterId)).limit(1),
    ]);
    const attackerAllianceId = attacker[0]?.allianceId;
    const defenderAllianceId = defender[0]?.allianceId;
    if (!attackerAllianceId || !defenderAllianceId || attackerAllianceId === defenderAllianceId) {
      return { recorded: false };
    }

    const [war] = await db.select().from(allianceWars)
      .where(eq(allianceWars.id, (await this.activeWarId(attackerAllianceId, defenderAllianceId)) ?? '-'))
      .limit(1);
    if (!war) return { recorded: false };

    const season = await this.ensureActiveSeason(now);
    const kind: WarEngagementKind = input.attackerWon ? 'TERRITORY_CAPTURE' : 'DEFENSE_HOLD';
    const points = WAR_POINTS[kind];
    const scoringAllianceId = input.attackerWon ? attackerAllianceId : defenderAllianceId;

    if (war.declaringAllianceId === scoringAllianceId) {
      await db.update(allianceWars).set({ declaringPoints: sql`${allianceWars.declaringPoints} + ${points}` })
        .where(eq(allianceWars.id, war.id));
    } else {
      await db.update(allianceWars).set({ targetPoints: sql`${allianceWars.targetPoints} + ${points}` })
        .where(eq(allianceWars.id, war.id));
    }
    if (season.status === 'ACTIVE') await this.addSeasonPoints(season.id, scoringAllianceId, points, now);
    await this.recordEngagement({
      warId: war.id, attackerAllianceId, defenderAllianceId, masterId: input.attackerMasterId,
      tileId: input.tileId, kind, points,
      detail: { attackerWon: input.attackerWon }, now,
    });
    return { recorded: true, warId: war.id, kind, points, scoringAllianceId };
  }

  /** FUN-13-07-004: resolve every war whose 24h window has elapsed. */
  async settleWars(now = new Date()) {
    const due = await db.select().from(allianceWars)
      .where(and(eq(allianceWars.status, 'ACTIVE'), lte(allianceWars.endsAt, now)));
    for (const war of due) {
      const { winnerAllianceId, draw } = decideWar({
        declaringPoints: war.declaringPoints, targetPoints: war.targetPoints,
        declaringAllianceId: war.declaringAllianceId, targetAllianceId: war.targetAllianceId,
      });
      await db.update(allianceWars).set({
        status: 'RESOLVED', winnerAllianceId, resolvedAt: now,
      }).where(eq(allianceWars.id, war.id));

      if (!winnerAllianceId) continue;
      const season = await this.latestSeason();
      if (season?.status === 'ACTIVE') {
        await this.addSeasonPoints(season.id, winnerAllianceId, WAR_POINTS.WAR_VICTORY, now);
      }
      await this.recordEngagement({
        warId: war.id, attackerAllianceId: winnerAllianceId,
        defenderAllianceId: winnerAllianceId === war.declaringAllianceId ? war.targetAllianceId : war.declaringAllianceId,
        masterId: null, tileId: null, kind: 'WAR_VICTORY', points: WAR_POINTS.WAR_VICTORY,
        detail: { declaringPoints: war.declaringPoints, targetPoints: war.targetPoints, draw }, now,
      });
      await this.payWarRewards(war, winnerAllianceId, now);
    }
    return due.length;
  }

  /** FUN-13-07-005: war rewards for both sides of a resolved war. */
  private async payWarRewards(war: WarRow, winnerAllianceId: string, now: Date) {
    const participants = [
      { allianceId: war.declaringAllianceId, won: winnerAllianceId === war.declaringAllianceId },
      { allianceId: war.targetAllianceId, won: winnerAllianceId === war.targetAllianceId },
    ];
    for (const side of participants) {
      const reward = warRewardFor(side.won);
      await this.payAllianceReward(side.allianceId, reward, side.won
        ? 'Chiến thắng liên minh chiến'
        : 'Kết thúc liên minh chiến',
      side.won
        ? 'Liên minh của bạn đã thắng chiến dịch 24 giờ. Phần thưởng chiến thắng được gửi kèm.'
        : 'Liên minh chiến đã khép lại. Phần thưởng tham chiến được gửi kèm.',
      now);
    }
  }

  /** FUN-13-07-004/005: close a season and pay the ranking rewards. */
  async concludeSeason(season: SeasonRow, conqueringAllianceId: string | null, now = new Date()) {
    if (season.status === 'CONCLUDED') return season;
    const [locked] = await db.select().from(worldConquestSeasons)
      .where(eq(worldConquestSeasons.id, season.id)).for('update').limit(1);
    if (!locked || locked.status === 'CONCLUDED') return locked ?? season;

    const rows = await db.select({
      allianceId: worldConquestRankings.allianceId,
      name: alliances.name, tag: alliances.tag,
      points: worldConquestRankings.totalConquestPoints,
    }).from(worldConquestRankings)
      .innerJoin(alliances, eq(alliances.id, worldConquestRankings.allianceId))
      .where(eq(worldConquestRankings.seasonId, season.id))
      .orderBy(desc(worldConquestRankings.totalConquestPoints), asc(alliances.name));

    const ranked = rankAlliances(rows.map(row => ({
      allianceId: row.allianceId, name: row.name, tag: row.tag, points: row.points,
    })), rows.length || 10);

    for (const entry of ranked) {
      const tier = seasonRewardFor(entry.rank);
      await db.update(worldConquestRankings).set({ finalRank: entry.rank, updatedAt: now })
        .where(and(
          eq(worldConquestRankings.seasonId, season.id),
          eq(worldConquestRankings.allianceId, entry.allianceId),
        ));
      if (!tier) continue;
      await this.payAllianceReward(entry.allianceId, tier.reward,
        `Thưởng mùa giải ${season.seasonNumber} — hạng ${entry.rank}`,
        `Liên minh của bạn đạt hạng ${entry.rank} mùa ${season.seasonNumber}.`,
        now);
    }

    // FUN-13-07-005: a Conqueror Alliance always receives the throne bundle,
    // even when it did not finish first on conquest points.
    const conqueror = conqueringAllianceId
      ? ranked.find(entry => entry.allianceId === conqueringAllianceId)
      : undefined;
    if (conqueringAllianceId && conqueror && conqueror.rank !== 1) {
      const crown = seasonRewardFor(1);
      if (crown) {
        await this.payAllianceReward(conqueringAllianceId, crown.reward,
          `Mùa giải ${season.seasonNumber} — Bá Chủ Thế Giới`,
          `Liên minh của bạn đã giữ Kỳ Quan Trung Tâm 8 giờ và trở thành Bá Chủ Thế Giới mùa ${season.seasonNumber}.`,
          now);
      }
    }

    const [updated] = await db.update(worldConquestSeasons).set({
      status: 'CONCLUDED', conqueringAllianceId, concludedAt: now,
    }).where(eq(worldConquestSeasons.id, season.id)).returning();
    return updated;
  }

  private async payAllianceReward(
    allianceId: string, reward: RewardBundle, subject: string, body: string, now: Date,
  ) {
    const memberIds = await allianceService.memberIds(allianceId);
    if (memberIds.length === 0) return;
    const [alliance] = await db.select({ name: alliances.name, tag: alliances.tag })
      .from(alliances).where(eq(alliances.id, allianceId)).limit(1);
    for (const masterId of memberIds) {
      if (reward.silver > 0) {
        await mailboxService.send({
          masterId, sender: 'SYSTEM', subject,
          body: `${body}\n${alliance ? allianceName(alliance) : ''}`,
          attachments: { silver: reward.silver },
        }).catch(error => console.error('[conquest] reward mail failed', error));
      }
      if (reward.gems > 0) {
        await db.update(masters).set({ gems: sql`${masters.gems} + ${reward.gems}`, updatedAt: now })
          .where(eq(masters.id, masterId)).catch(error => console.error('[conquest] gem reward failed', error));
      }
      if (reward.specialScrolls > 0) {
        await currencyService.addCurrency(masterId, {
          scrollType: 'SPECIAL', scrollDelta: reward.specialScrolls, transactionType: 'CONQUEST_REWARD',
        }).catch(error => console.error('[conquest] scroll reward failed', error));
      }
    }
  }

  // --- overview --------------------------------------------------------

  /** UC-P3-08: season, wonder and war state for the caller. */
  async overview(masterId: string, now = new Date()) {
    await this.settleWars(now);
    let season = await this.ensureActiveSeason(now);
    const holding = await this.advanceWonder(season, now);
    if (holding?.allianceId && holding.accumulatedSeconds >= WONDER_HOLD_SECONDS && isContestOpen(season, now)) {
      const concluded = await this.concludeSeason(season, holding.allianceId, now);
      season = concluded;
    }

    const [membership] = await db.select({ allianceId: allianceMembers.allianceId, role: allianceMembers.role })
      .from(allianceMembers).where(eq(allianceMembers.masterId, masterId)).limit(1);
    const [myAlliance] = membership
      ? await db.select({ id: alliances.id, name: alliances.name, tag: alliances.tag })
        .from(alliances).where(eq(alliances.id, membership.allianceId)).limit(1)
      : [];
    const [myRanking] = membership
      ? await db.select().from(worldConquestRankings)
        .where(and(
          eq(worldConquestRankings.seasonId, season.id),
          eq(worldConquestRankings.allianceId, membership.allianceId),
        )).limit(1)
      : [];

    const ranking = await this.ranking(season.id, 10);
    return {
      season: {
        id: season.id, seasonNumber: season.seasonNumber, status: season.status,
        startTime: season.startTime, endTime: season.endTime,
        conqueringAllianceId: season.conqueringAllianceId, concludedAt: season.concludedAt,
        contestOpen: isContestOpen(season, now),
        contestOpensAt: contestOpensAt(season.endTime),
        daysRemaining: Math.max(0, Math.ceil((season.endTime.getTime() - now.getTime()) / 86_400_000)),
      },
      wonder: await this.wonderState(season, now),
      ranking: ranking.entries,
      myAlliance: myAlliance ? {
        ...myAlliance, role: membership.role,
        points: myRanking?.totalConquestPoints ?? 0,
        rank: ranking.entries.find(entry => entry.allianceId === myAlliance.id)?.rank ?? null,
        canDeclareWar: membership.role === 'LEADER',
        canSiege: membership.role === 'LEADER' || membership.role === 'OFFICER',
      } : null,
      wars: (await this.listWars(masterId, now)).wars,
    };
  }
}

export const conquestService = new ConquestService();
