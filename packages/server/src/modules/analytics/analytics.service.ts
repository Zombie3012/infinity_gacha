import { and, count, eq, gte, sql } from 'drizzle-orm';
import { db } from '../../database/db.js';
import {
  accountSessions, accounts, combatSessions, currencyTransactions, heroDeathRecords, masters,
  paymentTransactions, summonHistory,
} from '../../database/drizzle-schema.js';

export interface Ratio {
  numerator: number;
  denominator: number;
  rate: number;
}

export function ratio(numerator: number, denominator: number): Ratio {
  const num = Math.max(0, Math.floor(numerator));
  const den = Math.max(0, Math.floor(denominator));
  return { numerator: num, denominator: den, rate: den === 0 ? 0 : Math.round((num / den) * 10000) / 10000 };
}

export class AnalyticsService {
  private since(days: number, now = new Date()): Date {
    return new Date(now.getTime() - days * 86_400_000);
  }

  /** FUN-14-05-001: registrations, activity and Master creation. */
  async players(now = new Date()) {
    const week = this.since(7, now);
    const day = this.since(1, now);
    const [totals] = await db.select({
      accounts: sql<number>`count(*)::int`,
      new7d: sql<number>`count(*) filter (where ${accounts.createdAt} >= ${week})::int`,
      new24h: sql<number>`count(*) filter (where ${accounts.createdAt} >= ${day})::int`,
      restricted: sql<number>`count(*) filter (where ${accounts.status} <> 'ACTIVE')::int`,
    }).from(accounts);
    const [masterTotals] = await db.select({ total: sql<number>`count(*)::int` }).from(masters);
    const [active] = await db.select({ total: sql<number>`count(distinct ${accountSessions.accountId})::int` })
      .from(accountSessions)
      .where(and(gte(accountSessions.createdAt, week), sql`${accountSessions.revokedAt} is null`));
    return {
      accounts: totals?.accounts ?? 0,
      newAccounts7d: totals?.new7d ?? 0,
      newAccounts24h: totals?.new24h ?? 0,
      restrictedAccounts: totals?.restricted ?? 0,
      masters: masterTotals?.total ?? 0,
      activeAccounts7d: active?.total ?? 0,
      masterConversion: ratio(masterTotals?.total ?? 0, totals?.accounts ?? 0),
    };
  }

  /** FUN-14-05-002: summon volume, five-star rate and duplicate rate. */
  async gacha(now = new Date()) {
    const week = this.since(7, now);
    const [totals] = await db.select({
      rolls: sql<number>`count(*)::int`,
      fiveStars: sql<number>`count(*) filter (where ${summonHistory.wasFiveStar})::int`,
      duplicates: sql<number>`count(*) filter (where ${summonHistory.wasDuplicate})::int`,
    }).from(summonHistory);
    const [weekTotals] = await db.select({
      rolls: sql<number>`count(*)::int`,
      fiveStars: sql<number>`count(*) filter (where ${summonHistory.wasFiveStar})::int`,
    }).from(summonHistory).where(gte(summonHistory.createdAt, week));

    const byBanner = await db.select({
      bannerId: summonHistory.bannerId,
      rolls: sql<number>`count(*)::int`,
      fiveStars: sql<number>`count(*) filter (where ${summonHistory.wasFiveStar})::int`,
    }).from(summonHistory).groupBy(summonHistory.bannerId).orderBy(sql`count(*) desc`).limit(10);

    return {
      totalRolls: totals?.rolls ?? 0,
      fiveStarRate: ratio(totals?.fiveStars ?? 0, totals?.rolls ?? 0),
      duplicateRate: ratio(totals?.duplicates ?? 0, totals?.rolls ?? 0),
      last7d: { rolls: weekTotals?.rolls ?? 0, fiveStars: weekTotals?.fiveStars ?? 0, rate: ratio(weekTotals?.fiveStars ?? 0, weekTotals?.rolls ?? 0) },
      byBanner: byBanner.map(row => ({ ...row, rate: ratio(row.fiveStars, row.rolls) })),
    };
  }

  /** FUN-14-05-003: currency flows and paid revenue. */
  async economy(now = new Date()) {
    const week = this.since(7, now);
    const flows = await db.select({
      currencyType: currencyTransactions.currencyType,
      inflow: sql<string>`coalesce(sum(${currencyTransactions.amountDelta}) filter (where ${currencyTransactions.amountDelta} > 0), 0)::text`,
      outflow: sql<string>`coalesce(-sum(${currencyTransactions.amountDelta}) filter (where ${currencyTransactions.amountDelta} < 0), 0)::text`,
      entries: sql<number>`count(*)::int`,
    }).from(currencyTransactions).groupBy(currencyTransactions.currencyType);

    const [payments] = await db.select({
      completed: sql<number>`count(*) filter (where ${paymentTransactions.status} = 'COMPLETED')::int`,
      refunded: sql<number>`count(*) filter (where ${paymentTransactions.status} = 'REFUNDED')::int`,
      revenueCents: sql<number>`coalesce(sum(${paymentTransactions.priceCents}) filter (where ${paymentTransactions.status} = 'COMPLETED'), 0)::int`,
      revenue7dCents: sql<number>`coalesce(sum(${paymentTransactions.priceCents}) filter (where ${paymentTransactions.status} = 'COMPLETED' and ${paymentTransactions.createdAt} >= ${week}), 0)::int`,
    }).from(paymentTransactions);

    const [debt] = await db.select({ total: sql<string>`coalesce(sum(${masters.gemDebt}), 0)::text` }).from(masters);

    return {
      flows: flows.map(row => ({ ...row })),
      payments: {
        completed: payments?.completed ?? 0,
        refunded: payments?.refunded ?? 0,
        revenueUsd: Math.round((payments?.revenueCents ?? 0)) / 100,
        revenueUsd7d: Math.round((payments?.revenue7dCents ?? 0)) / 100,
        refundRate: ratio(payments?.refunded ?? 0, (payments?.completed ?? 0) + (payments?.refunded ?? 0)),
      },
      outstandingGemDebt: Number(debt?.total ?? 0),
    };
  }

  /** FUN-14-05-004: battle outcomes, pacing and perma-death. */
  async battle() {
    const [sessions] = await db.select({
      total: sql<number>`count(*)::int`,
      completed: sql<number>`count(*) filter (where ${combatSessions.status} = 'COMPLETED')::int`,
      active: sql<number>`count(*) filter (where ${combatSessions.status} = 'ACTIVE')::int`,
      victories: sql<number>`count(*) filter (where ${combatSessions.battleReport} ->> 'result' = 'VICTORY')::int`,
      defeats: sql<number>`count(*) filter (where ${combatSessions.battleReport} ->> 'result' = 'DEFEAT')::int`,
      avgRounds: sql<number>`coalesce(avg((${combatSessions.battleReport} ->> 'rounds')::numeric), 0)::float`,
    }).from(combatSessions);
    const [deaths] = await db.select({
      total: sql<number>`count(*)::int`,
      last7d: sql<number>`count(*) filter (where ${heroDeathRecords.recordedAt} >= now() - interval '7 days')::int`,
    }).from(heroDeathRecords);

    return {
      sessions: sessions?.total ?? 0,
      completed: sessions?.completed ?? 0,
      active: sessions?.active ?? 0,
      victories: sessions?.victories ?? 0,
      defeats: sessions?.defeats ?? 0,
      winRate: ratio(sessions?.victories ?? 0, (sessions?.victories ?? 0) + (sessions?.defeats ?? 0)),
      averageRounds: Math.round((sessions?.avgRounds ?? 0) * 10) / 10,
      heroDeaths: deaths?.total ?? 0,
      heroDeaths7d: deaths?.last7d ?? 0,
    };
  }

  /** FUN-14-05-005: week-over-week activity and returning players. */
  async retention(now = new Date()) {
    const currentStart = this.since(7, now);
    const previousStart = this.since(14, now);

    const [current] = await db.select({ total: sql<number>`count(distinct ${accountSessions.accountId})::int` })
      .from(accountSessions).where(gte(accountSessions.createdAt, currentStart));
    const [previous] = await db.select({ total: sql<number>`count(distinct ${accountSessions.accountId})::int` })
      .from(accountSessions).where(and(gte(accountSessions.createdAt, previousStart), sql`${accountSessions.createdAt} < ${currentStart}`));
    const [returning] = await db.select({ total: sql<number>`count(*)::int` }).from(
      db.select({ accountId: accountSessions.accountId }).from(accountSessions)
        .where(gte(accountSessions.createdAt, currentStart)).groupBy(accountSessions.accountId).as('current_week'),
    ).innerJoin(
      db.select({ accountId: accountSessions.accountId }).from(accountSessions)
        .where(and(gte(accountSessions.createdAt, previousStart), sql`${accountSessions.createdAt} < ${currentStart}`))
        .groupBy(accountSessions.accountId).as('previous_week'),
      sql`current_week.account_id = previous_week.account_id`,
    );

    const [newcomers] = await db.select({ total: sql<number>`count(*)::int` }).from(accounts).where(gte(accounts.createdAt, currentStart));

    return {
      activeThisWeek: current?.total ?? 0,
      activePreviousWeek: previous?.total ?? 0,
      returningPlayers: returning?.total ?? 0,
      newAccountsThisWeek: newcomers?.total ?? 0,
      weekOverWeekRetention: ratio(returning?.total ?? 0, previous?.total ?? 0),
      growth: ratio((current?.total ?? 0) - (previous?.total ?? 0) + (previous?.total ?? 0), Math.max(1, previous?.total ?? 0)),
    };
  }

  async summary(now = new Date()) {
    const [players, gacha, economy, battle, retention] = await Promise.all([
      this.players(now), this.gacha(now), this.economy(now), this.battle(), this.retention(now),
    ]);
    return { generatedAt: now.toISOString(), players, gacha, economy, battle, retention };
  }

  /** Convenience used by tests and the admin UI. */
  async counts() {
    const [accountCount] = await db.select({ total: count() }).from(accounts);
    return { accounts: accountCount?.total ?? 0 };
  }
}

export const analyticsService = new AnalyticsService();
