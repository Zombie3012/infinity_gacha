import { and, desc, eq, lt, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { mailboxMessages, masterItems, masters } from '../../database/drizzle-schema.js';
import { DEFAULT_MAIL_LIFETIME_DAYS, mailExpiresAt, normalizeAttachments } from './shop-rules.js';

export class MailboxError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'MailboxError';
  }
}

export interface SendMailInput {
  masterId: string;
  sender?: string;
  subject: string;
  body: string;
  attachments?: unknown;
  lifetimeDays?: number;
}

const serialise = (row: typeof mailboxMessages.$inferSelect) => ({
  ...row,
  attachments: normalizeAttachments(row.attachments),
});

export class MailboxService {
  /** Messages past their expiry date are purged lazily before every read. */
  async purgeExpired(masterId: string, now = new Date()) {
    const deleted = await db.delete(mailboxMessages)
      .where(and(eq(mailboxMessages.masterId, masterId), lt(mailboxMessages.expiresAt, now)))
      .returning({ id: mailboxMessages.id });
    return deleted.length;
  }

  async send(input: SendMailInput) {
    const subject = typeof input.subject === 'string' ? input.subject.trim() : '';
    if (!subject || subject.length > 150) throw new MailboxError('subject phải từ 1–150 ký tự.');
    const body = typeof input.body === 'string' ? input.body : '';
    if (body.length > 4000) throw new MailboxError('body quá dài.');
    const [master] = await db.select({ id: masters.id }).from(masters).where(eq(masters.id, input.masterId)).limit(1);
    if (!master) throw new MailboxError('Không tìm thấy Master.', 404);

    const now = new Date();
    const attachments = normalizeAttachments(input.attachments);
    const [row] = await db.insert(mailboxMessages).values({
      id: uuidv4(),
      masterId: input.masterId,
      sender: (input.sender ?? 'SYSTEM').slice(0, 30),
      subject,
      body,
      attachments,
      expiresAt: mailExpiresAt(now, input.lifetimeDays ?? DEFAULT_MAIL_LIFETIME_DAYS),
      createdAt: now,
    }).returning();
    return serialise(row);
  }

  async list(masterId: string, now = new Date()) {
    const purged = await this.purgeExpired(masterId, now);
    const rows = await db.select().from(mailboxMessages)
      .where(eq(mailboxMessages.masterId, masterId))
      .orderBy(desc(mailboxMessages.createdAt)).limit(50);
    return {
      purged,
      unclaimed: rows.filter(row => !row.isClaimed).map(serialise),
      claimed: rows.filter(row => row.isClaimed).slice(0, 20).map(serialise),
    };
  }

  /** Scenario 14.1: attachments move into the wallet/bag atomically. */
  async claim(masterId: string, messageId: string, now = new Date()) {
    const [message] = await db.select().from(mailboxMessages)
      .where(and(eq(mailboxMessages.id, messageId), eq(mailboxMessages.masterId, masterId))).limit(1);
    if (!message) throw new MailboxError('Không tìm thấy thư.', 404);
    if (message.isClaimed) throw new MailboxError('Thư đã được nhận.', 409);
    if (message.expiresAt <= now) throw new MailboxError('ERR_MAIL_EXPIRED', 410);

    const attachments = normalizeAttachments(message.attachments);
    await db.transaction(async tx => {
      if (attachments.silver > 0) {
        await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} + ${attachments.silver}`, updatedAt: now })
          .where(eq(masters.id, masterId));
      }
      for (const entry of attachments.items) {
        await tx.insert(masterItems).values({
          id: uuidv4(), masterId, itemId: entry.itemId, quantity: entry.quantity, updatedAt: now,
        }).onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${entry.quantity}`, updatedAt: now },
        });
      }
      await tx.update(mailboxMessages).set({ isClaimed: true, claimedAt: now })
        .where(eq(mailboxMessages.id, message.id));
    });

    return { messageId, silver: attachments.silver, items: attachments.items };
  }
}

export const mailboxService = new MailboxService();
