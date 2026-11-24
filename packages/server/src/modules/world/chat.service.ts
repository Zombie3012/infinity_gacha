import { and, desc, eq, ilike, or } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import { chatMessages, masters } from '../../database/drizzle-schema.js';
import { friendService } from './friend.service.js';

export class ChatError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'ChatError';
  }
}

export interface ChatStreamPayload {
  channel: 'WORLD' | 'ALLIANCE' | 'PRIVATE';
  allianceId?: string;
  message: Record<string, unknown>;
}

type SseListener = (payload: ChatStreamPayload) => void;

export class ChatService {
  private worldBuffer: Array<Record<string, unknown>> = [];
  private listeners = new Map<string, Set<SseListener>>();

  subscribe(masterId: string, listener: SseListener): () => void {
    let set = this.listeners.get(masterId);
    if (!set) {
      set = new Set();
      this.listeners.set(masterId, set);
    }
    set.add(listener);
    return () => {
      const cur = this.listeners.get(masterId);
      if (cur) {
        cur.delete(listener);
        if (cur.size === 0) this.listeners.delete(masterId);
      }
    };
  }

  private emitToMaster(masterId: string, payload: ChatStreamPayload): void {
    const set = this.listeners.get(masterId);
    if (!set) return;
    for (const fn of set) {
      try { fn(payload); } catch { /* ignore closed listener */ }
    }
  }

  private emitToAll(payload: ChatStreamPayload): void {
    for (const set of this.listeners.values()) {
      for (const fn of set) {
        try { fn(payload); } catch { /* ignore closed listener */ }
      }
    }
  }

  broadcastAlliance(memberMasterIds: string[], allianceId: string, message: Record<string, unknown>): void {
    const payload: ChatStreamPayload = { channel: 'ALLIANCE', allianceId, message };
    for (const mid of memberMasterIds) {
      this.emitToMaster(mid, payload);
    }
  }

  private cleanBody(bodyInput: unknown): string {
    const body = String(bodyInput ?? '').trim();
    if (!body) throw new ChatError('Nội dung tin nhắn không được để trống.', 400);
    if (body.length > 500) throw new ChatError('Tin nhắn tối đa 500 ký tự.', 400);
    return body;
  }

  async listWorld(limit = 50) {
    // WORLD channel is live in-memory only; never loads historical DB messages across sessions.
    const cap = Math.min(100, Math.max(1, limit));
    return { messages: this.worldBuffer.slice(-cap) };
  }

  async sendWorld(masterId: string, bodyInput: unknown) {
    const body = this.cleanBody(bodyInput);
    const [sender] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!sender) throw new ChatError('Không tìm thấy Master.', 404);

    const message = {
      id: uuidv4(),
      channel: 'WORLD',
      senderMasterId: masterId,
      senderName: sender.masterName,
      recipientMasterId: null,
      body,
      createdAt: new Date().toISOString(),
    };
    this.worldBuffer.push(message);
    if (this.worldBuffer.length > 100) {
      this.worldBuffer.splice(0, this.worldBuffer.length - 100);
    }
    this.emitToAll({ channel: 'WORLD', message });

    return { message };
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
    if (await friendService.isBlockedBetween(masterId, recipient.id)) {
      throw new ChatError('Không thể gửi tin nhắn riêng vì một trong hai bên đã chặn nhau.', 403);
    }

    const [created] = await db.insert(chatMessages).values({
      id: uuidv4(),
      channel: 'PRIVATE',
      senderMasterId: masterId,
      recipientMasterId: recipient.id,
      body,
    }).returning();

    const message = {
      ...created,
      senderName: sender.masterName,
      recipientName: recipient.masterName,
    };
    this.emitToMaster(masterId, { channel: 'PRIVATE', message });
    this.emitToMaster(recipient.id, { channel: 'PRIVATE', message });

    return { message };
  }
}

export const chatService = new ChatService();
