import { and, desc, eq, ilike, or } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { chatMessages, masters } from '../../database/drizzle-schema.js';

export class ChatError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ChatError';
  }
}

export class ChatService {
  private cleanBody(bodyInput: unknown): string {
    const body = String(bodyInput ?? '').trim();
    if (!body) throw new ChatError('Nội dung tin nhắn không được để trống.', 400);
    if (body.length > 500) throw new ChatError('Tin nhắn tối đa 500 ký tự.', 400);
    return body;
  }

  async listWorld(limit = 50) {
    const rows = await db
      .select({
        id: chatMessages.id,
        channel: chatMessages.channel,
        senderMasterId: chatMessages.senderMasterId,
        senderName: masters.masterName,
        body: chatMessages.body,
        createdAt: chatMessages.createdAt,
      })
      .from(chatMessages)
      .innerJoin(masters, eq(masters.id, chatMessages.senderMasterId))
      .where(eq(chatMessages.channel, 'WORLD'))
      .orderBy(desc(chatMessages.createdAt))
      .limit(Math.min(100, Math.max(1, limit)));

    return { messages: rows.reverse() };
  }

  async sendWorld(masterId: string, bodyInput: unknown) {
    const body = this.cleanBody(bodyInput);
    const [sender] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!sender) throw new ChatError('Không tìm thấy Master.', 404);

    const [created] = await db.insert(chatMessages).values({
      id: uuidv4(),
      channel: 'WORLD',
      senderMasterId: masterId,
      recipientMasterId: null,
      body,
    }).returning();

    return {
      message: {
        ...created,
        senderName: sender.masterName,
      },
    };
  }

  async listPrivate(masterId: string, peerQuery?: string, limit = 50) {
    let peerIdFilter: string | null = null;
    const q = String(peerQuery ?? '').trim();
    if (q) {
      const [peer] = await db.select().from(masters)
        .where(or(eq(masters.id, q), ilike(masters.masterName, q)))
        .limit(1);
      if (peer) peerIdFilter = peer.id;
      else return { messages: [] };
    }

    const cond = peerIdFilter
      ? and(
          eq(chatMessages.channel, 'PRIVATE'),
          or(
            and(eq(chatMessages.senderMasterId, masterId), eq(chatMessages.recipientMasterId, peerIdFilter)),
            and(eq(chatMessages.senderMasterId, peerIdFilter), eq(chatMessages.recipientMasterId, masterId)),
          ),
        )
      : and(
          eq(chatMessages.channel, 'PRIVATE'),
          or(eq(chatMessages.senderMasterId, masterId), eq(chatMessages.recipientMasterId, masterId)),
        );

    const rows = await db.select().from(chatMessages)
      .where(cond)
      .orderBy(desc(chatMessages.createdAt))
      .limit(Math.min(100, Math.max(1, limit)));

    const masterIds = Array.from(new Set(rows.flatMap(r => [r.senderMasterId, r.recipientMasterId].filter(Boolean) as string[])));
    const masterRows = masterIds.length
      ? await db.select({ id: masters.id, masterName: masters.masterName }).from(masters)
      : [];
    const nameMap = new Map(masterRows.map(m => [m.id, m.masterName]));

    return {
      messages: rows.reverse().map(r => ({
        ...r,
        senderName: nameMap.get(r.senderMasterId) ?? 'Master',
        recipientName: r.recipientMasterId ? (nameMap.get(r.recipientMasterId) ?? 'Master') : null,
      })),
    };
  }

  async sendPrivate(masterId: string, input: { recipientMasterId?: unknown; recipientName?: unknown; body?: unknown }) {
    const body = this.cleanBody(input.body);
    const [sender] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!sender) throw new ChatError('Không tìm thấy Master.', 404);

    const targetId = String(input.recipientMasterId ?? '').trim();
    const targetName = String(input.recipientName ?? '').trim();
    if (!targetId && !targetName) {
      throw new ChatError('Vui lòng nhập tên hoặc ID Master người nhận.', 400);
    }

    const target = targetId || targetName;
    const [recipient] = await db.select().from(masters)
      .where(or(eq(masters.id, target), ilike(masters.masterName, target)))
      .limit(1);

    if (!recipient) throw new ChatError('Không tìm thấy Master người nhận.', 404);
    if (recipient.id === masterId) throw new ChatError('Không thể tự nhắn tin riêng cho chính mình.', 400);

    const [created] = await db.insert(chatMessages).values({
      id: uuidv4(),
      channel: 'PRIVATE',
      senderMasterId: masterId,
      recipientMasterId: recipient.id,
      body,
    }).returning();

    return {
      message: {
        ...created,
        senderName: sender.masterName,
        recipientName: recipient.masterName,
      },
    };
  }
}

export const chatService = new ChatService();
