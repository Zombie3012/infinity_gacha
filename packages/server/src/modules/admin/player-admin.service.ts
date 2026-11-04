import { and, asc, desc, eq, ilike, or, sql } from 'drizzle-orm';
import { db } from '../../database/db.js';
import {
  accountSessions, accounts, heroes, masters, paymentTransactions, playerProfiles, worlds,
} from '../../database/drizzle-schema.js';
import { mailboxService } from '../shop/mailbox.service.js';
import {
  hasCompensationValue, isRestrictionStatus, normalizeCompensation, validateCompensation,
} from './admin-rules.js';

export class PlayerAdminError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'PlayerAdminError';
  }
}

export class PlayerAdminService {
  async search(queryInput: unknown) {
    const query = String(queryInput ?? '').trim();
    const rows = query
      ? await db.select({
        accountId: accounts.id,
        username: accounts.username,
        status: accounts.status,
        createdAt: accounts.createdAt,
        masterId: masters.id,
        masterName: masters.masterName,
        level: masters.level,
        silverCoins: masters.silverCoins,
      }).from(accounts)
        .leftJoin(masters, eq(masters.accountId, accounts.id))
        .where(or(ilike(accounts.username, `%${query}%`), ilike(masters.masterName, `%${query}%`)))
        .orderBy(asc(accounts.username)).limit(20)
      : [];

    return rows.map(row => ({
      ...row,
      silverCoins: row.silverCoins === null ? null : row.silverCoins.toString(),
    }));
  }

  async detail(accountId: string) {
    const [account] = await db.select().from(accounts).where(eq(accounts.id, accountId)).limit(1);
    if (!account) throw new PlayerAdminError('Không tìm thấy tài khoản.', 404);
    const [master] = await db.select().from(masters).where(eq(masters.accountId, accountId)).limit(1);
    const [world] = master ? await db.select().from(worlds).where(eq(worlds.masterId, master.id)).limit(1) : [];
    const [profile] = await db.select().from(playerProfiles).where(eq(playerProfiles.accountId, accountId)).limit(1);
    const heroCount = master
      ? (await db.select({ total: sql<number>`count(*)::int` }).from(heroes).where(eq(heroes.masterId, master.id)))[0]?.total ?? 0
      : 0;
    const payments = master
      ? await db.select().from(paymentTransactions).where(eq(paymentTransactions.masterId, master.id))
        .orderBy(desc(paymentTransactions.createdAt)).limit(5)
      : [];
    const sessions = await db.select({ id: accountSessions.id, createdAt: accountSessions.createdAt, revokedAt: accountSessions.revokedAt })
      .from(accountSessions).where(eq(accountSessions.accountId, accountId)).orderBy(desc(accountSessions.createdAt)).limit(5);

    return {
      account: { id: account.id, username: account.username, email: account.email, status: account.status, createdAt: account.createdAt },
      profile: profile ?? null,
      master: master ? { ...master, exp: master.exp.toString(), silverCoins: master.silverCoins.toString(), gems: master.gems.toString(), gemDebt: master.gemDebt.toString() } : null,
      world: world ?? null,
      heroCount,
      payments: payments.map(row => ({ ...row })),
      sessions,
    };
  }

  /** Scenarios 5.x: SUSPENDED/BANNED also revoke every live session. */
  async restrict(accountId: string, statusInput: unknown, reasonInput: unknown, actor: string) {
    const status = String(statusInput ?? '').toUpperCase();
    if (!isRestrictionStatus(status)) throw new PlayerAdminError('status phải là SUSPENDED hoặc BANNED.', 400);
    const reason = String(reasonInput ?? '').slice(0, 500);
    const [updated] = await db.update(accounts).set({ status, updatedAt: new Date() })
      .where(eq(accounts.id, accountId)).returning({ id: accounts.id, username: accounts.username, status: accounts.status });
    if (!updated) throw new PlayerAdminError('Không tìm thấy tài khoản.', 404);
    await db.update(accountSessions).set({ revokedAt: new Date() })
      .where(and(eq(accountSessions.accountId, accountId), sql`${accountSessions.revokedAt} is null`));
    return { ...updated, reason, actor };
  }

  async restore(accountId: string, actor: string) {
    const [updated] = await db.update(accounts).set({ status: 'ACTIVE', updatedAt: new Date() })
      .where(eq(accounts.id, accountId)).returning({ id: accounts.id, username: accounts.username, status: accounts.status });
    if (!updated) throw new PlayerAdminError('Không tìm thấy tài khoản.', 404);
    return { ...updated, actor };
  }

  async compensate(accountId: string, payload: unknown, subjectInput: unknown, bodyInput: unknown) {
    const [master] = await db.select({ id: masters.id }).from(masters).where(eq(masters.accountId, accountId)).limit(1);
    if (!master) throw new PlayerAdminError('Tài khoản chưa có Master.', 409);
    const compensation = normalizeCompensation(payload);
    if (!hasCompensationValue(compensation)) throw new PlayerAdminError('Cần ít nhất một khoản bồi thường.', 400);
    const issue = validateCompensation(compensation);
    if (issue) throw new PlayerAdminError(issue, 400);

    const message = await mailboxService.send({
      masterId: master.id,
      sender: 'OPERATOR',
      subject: String(subjectInput ?? 'Bồi thường từ vận hành viên').slice(0, 150),
      body: String(bodyInput ?? 'Khoản bồi thường đính kèm. Cảm ơn bạn đã kiên nhẫn.').slice(0, 4000),
      attachments: { silver: compensation.silver, items: compensation.items },
    });

    // Gems are not a mailbox attachment type, so they are credited directly.
    if (compensation.gems > 0) {
      await db.update(masters).set({ gems: sql`${masters.gems} + ${compensation.gems}`, updatedAt: new Date() })
        .where(eq(masters.id, master.id));
    }
    return { messageId: message.id, compensation };
  }
}

export const playerAdminService = new PlayerAdminService();
