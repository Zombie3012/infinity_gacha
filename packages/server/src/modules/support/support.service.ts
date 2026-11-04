import { and, desc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { accounts, supportTicketMessages, supportTickets } from '../../database/drizzle-schema.js';

export class SupportError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'SupportError';
  }
}

export const TICKET_STATUSES = ['OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'] as const;
export type TicketStatus = (typeof TICKET_STATUSES)[number];

/** Allowed transitions; CLOSED is terminal. */
export const STATUS_TRANSITIONS: Record<TicketStatus, TicketStatus[]> = {
  OPEN: ['IN_PROGRESS', 'RESOLVED', 'CLOSED'],
  IN_PROGRESS: ['RESOLVED', 'CLOSED'],
  RESOLVED: ['CLOSED', 'IN_PROGRESS'],
  CLOSED: [],
};

export function canTransition(from: string, to: string): boolean {
  if (!TICKET_STATUSES.includes(from as TicketStatus) || !TICKET_STATUSES.includes(to as TicketStatus)) return false;
  return STATUS_TRANSITIONS[from as TicketStatus].includes(to as TicketStatus);
}

export class SupportService {
  async create(accountId: string, subjectInput: unknown, bodyInput: unknown, categoryInput: unknown, now = new Date()) {
    const subject = String(subjectInput ?? '').trim();
    const body = String(bodyInput ?? '').trim();
    if (!subject || subject.length > 150) throw new SupportError('Tiêu đề phải từ 1–150 ký tự.');
    if (body.length < 10 || body.length > 4000) throw new SupportError('Nội dung phải từ 10–4.000 ký tự.');
    const category = String(categoryInput ?? 'GENERAL').toUpperCase().slice(0, 30);
    const id = uuidv4();
    const [ticket] = await db.insert(supportTickets).values({
      id, accountId, subject, body, category, status: 'OPEN', priority: 'NORMAL', createdAt: now, updatedAt: now,
    }).returning();
    await db.insert(supportTicketMessages).values({
      id: uuidv4(), ticketId: id, authorType: 'PLAYER', authorId: accountId, body, createdAt: now,
    });
    return ticket;
  }

  async listForAccount(accountId: string) {
    const tickets = await db.select().from(supportTickets)
      .where(eq(supportTickets.accountId, accountId)).orderBy(desc(supportTickets.createdAt)).limit(50);
    if (tickets.length === 0) return [];
    const messages = await db.select().from(supportTicketMessages)
      .where(inArray(supportTicketMessages.ticketId, tickets.map(row => row.id)))
      .orderBy(supportTicketMessages.createdAt);
    return tickets.map(ticket => ({ ...ticket, messages: messages.filter(row => row.ticketId === ticket.id) }));
  }

  async replyAsPlayer(accountId: string, ticketId: string, bodyInput: unknown, now = new Date()) {
    const body = String(bodyInput ?? '').trim();
    if (body.length < 1 || body.length > 4000) throw new SupportError('Nội dung phải từ 1–4.000 ký tự.');
    const [ticket] = await db.select().from(supportTickets)
      .where(and(eq(supportTickets.id, ticketId), eq(supportTickets.accountId, accountId))).limit(1);
    if (!ticket) throw new SupportError('Không tìm thấy yêu cầu hỗ trợ.', 404);
    if (ticket.status === 'CLOSED') throw new SupportError('Yêu cầu đã đóng.', 409);
    await db.insert(supportTicketMessages).values({
      id: uuidv4(), ticketId, authorType: 'PLAYER', authorId: accountId, body, createdAt: now,
    });
    await db.update(supportTickets).set({ updatedAt: now, status: ticket.status === 'RESOLVED' ? 'OPEN' : ticket.status })
      .where(eq(supportTickets.id, ticketId));
    return { ticketId, replied: true };
  }

  async listForOperators(status?: string) {
    const rows = await db.select({
      id: supportTickets.id,
      subject: supportTickets.subject,
      category: supportTickets.category,
      status: supportTickets.status,
      priority: supportTickets.priority,
      createdAt: supportTickets.createdAt,
      updatedAt: supportTickets.updatedAt,
      username: accounts.username,
      accountId: supportTickets.accountId,
    }).from(supportTickets)
      .innerJoin(accounts, eq(accounts.id, supportTickets.accountId))
      .where(status ? eq(supportTickets.status, status.toUpperCase()) : undefined)
      .orderBy(desc(supportTickets.createdAt)).limit(100);
    return rows;
  }

  async detail(ticketId: string) {
    const [ticket] = await db.select().from(supportTickets).where(eq(supportTickets.id, ticketId)).limit(1);
    if (!ticket) throw new SupportError('Không tìm thấy yêu cầu hỗ trợ.', 404);
    const messages = await db.select().from(supportTicketMessages)
      .where(eq(supportTicketMessages.ticketId, ticketId)).orderBy(supportTicketMessages.createdAt);
    return { ...ticket, messages };
  }

  async replyAsOperator(ticketId: string, bodyInput: unknown, actor: string, now = new Date()) {
    const body = String(bodyInput ?? '').trim();
    if (body.length < 1 || body.length > 4000) throw new SupportError('Nội dung phải từ 1–4.000 ký tự.');
    const [ticket] = await db.select().from(supportTickets).where(eq(supportTickets.id, ticketId)).limit(1);
    if (!ticket) throw new SupportError('Không tìm thấy yêu cầu hỗ trợ.', 404);
    await db.insert(supportTicketMessages).values({
      id: uuidv4(), ticketId, authorType: 'OPERATOR', authorId: actor, body, createdAt: now,
    });
    await db.update(supportTickets).set({
      updatedAt: now,
      ...(ticket.status === 'OPEN' ? { status: 'IN_PROGRESS' } : {}),
    }).where(eq(supportTickets.id, ticketId));
    return { ticketId, replied: true, status: ticket.status === 'OPEN' ? 'IN_PROGRESS' : ticket.status };
  }

  async changeStatus(ticketId: string, statusInput: unknown, now = new Date()) {
    const status = String(statusInput ?? '').toUpperCase();
    if (!TICKET_STATUSES.includes(status as TicketStatus)) throw new SupportError('status không hợp lệ.');
    const [ticket] = await db.select().from(supportTickets).where(eq(supportTickets.id, ticketId)).limit(1);
    if (!ticket) throw new SupportError('Không tìm thấy yêu cầu hỗ trợ.', 404);
    if (!canTransition(ticket.status, status)) throw new SupportError('ERR_SUPPORT_INVALID_TRANSITION', 409);
    const [updated] = await db.update(supportTickets).set({
      status, updatedAt: now,
      ...(status === 'CLOSED' ? { closedAt: now } : {}),
    }).where(eq(supportTickets.id, ticketId)).returning();
    return updated;
  }

  async openCount() {
    const [row] = await db.select({ total: sql<number>`count(*)::int` }).from(supportTickets)
      .where(inArray(supportTickets.status, ['OPEN', 'IN_PROGRESS']));
    return row?.total ?? 0;
  }
}

export const supportService = new SupportService();
