import { and, asc, desc, eq, ilike, inArray, isNull, ne, or, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  allianceMembers,
  alliances,
  baseBuildings,
  friendDailyGifts,
  friendships,
  heroes,
  masters,
} from '../../database/drizzle-schema.js';

export class FriendError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'FriendError';
  }
}

const DAILY_GIFT_SILVER = 200;

function todayDateKey(): string {
  return new Date().toISOString().slice(0, 10);
}

export class FriendService {
  async isBlockedBetween(masterA: string, masterB: string): Promise<boolean> {
    const [row] = await db
      .select({ id: friendships.id })
      .from(friendships)
      .where(
        and(
          eq(friendships.status, 'BLOCKED'),
          or(
            and(eq(friendships.requesterMasterId, masterA), eq(friendships.addresseeMasterId, masterB)),
            and(eq(friendships.requesterMasterId, masterB), eq(friendships.addresseeMasterId, masterA)),
          ),
        ),
      )
      .limit(1);
    return Boolean(row);
  }

  async listFriends(masterId: string) {
    const rows = await db
      .select()
      .from(friendships)
      .where(
        and(
          or(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, masterId)),
          inArray(friendships.status, ['ACCEPTED', 'BLOCKED']),
        ),
      );

    const acceptedIds: string[] = [];
    const blockedIds: string[] = [];
    for (const r of rows) {
      if (r.status === 'ACCEPTED') {
        acceptedIds.push(r.requesterMasterId === masterId ? r.addresseeMasterId : r.requesterMasterId);
      } else if (r.status === 'BLOCKED' && r.requesterMasterId === masterId) {
        blockedIds.push(r.addresseeMasterId);
      }
    }

    const allTargetIds = Array.from(new Set([...acceptedIds, ...blockedIds]));
    const masterRows = allTargetIds.length
      ? await db
          .select({ id: masters.id, masterName: masters.masterName })
          .from(masters)
          .where(inArray(masters.id, allTargetIds))
      : [];
    const masterMap = new Map(masterRows.map(m => [m.id, m]));

    const today = todayDateKey();
    const sentRows = acceptedIds.length
      ? await db
          .select({ receiverMasterId: friendDailyGifts.receiverMasterId })
          .from(friendDailyGifts)
          .where(
            and(
              eq(friendDailyGifts.senderMasterId, masterId),
              eq(friendDailyGifts.giftDate, today),
            ),
          )
      : [];
    const sentSet = new Set(sentRows.map(s => s.receiverMasterId));

    const unclaimedRows = await db
      .select({
        id: friendDailyGifts.id,
        senderMasterId: friendDailyGifts.senderMasterId,
        silverAmount: friendDailyGifts.silverAmount,
      })
      .from(friendDailyGifts)
      .where(
        and(
          eq(friendDailyGifts.receiverMasterId, masterId),
          isNull(friendDailyGifts.claimedAt),
        ),
      );
    const unclaimedSenderSet = new Set(unclaimedRows.map(u => u.senderMasterId));

    return {
      friends: acceptedIds
        .map(fid => {
          const m = masterMap.get(fid);
          if (!m) return null;
          return {
            friendMasterId: m.id,
            masterName: m.masterName,
            giftSentToday: sentSet.has(fid),
            giftReceivedUnclaimed: unclaimedSenderSet.has(fid),
          };
        })
        .filter(Boolean),
      blocked: blockedIds
        .map(bid => {
          const m = masterMap.get(bid);
          if (!m) return null;
          return {
            friendMasterId: m.id,
            masterName: m.masterName,
          };
        })
        .filter(Boolean),
      unclaimedGiftCount: unclaimedRows.length,
    };
  }

  async listRequests(masterId: string) {
    const rows = await db
      .select()
      .from(friendships)
      .where(
        and(
          eq(friendships.status, 'PENDING'),
          or(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, masterId)),
        ),
      )
      .orderBy(desc(friendships.createdAt));

    const otherIds = Array.from(
      new Set(rows.map(r => (r.requesterMasterId === masterId ? r.addresseeMasterId : r.requesterMasterId))),
    );
    const masterRows = otherIds.length
      ? await db
          .select({ id: masters.id, masterName: masters.masterName })
          .from(masters)
          .where(inArray(masters.id, otherIds))
      : [];
    const masterMap = new Map(masterRows.map(m => [m.id, m]));

    const incoming = rows
      .filter(r => r.addresseeMasterId === masterId)
      .map(r => {
        const m = masterMap.get(r.requesterMasterId);
        return {
          requestId: r.id,
          masterId: r.requesterMasterId,
          masterName: m?.masterName ?? 'Master',
          createdAt: r.createdAt,
        };
      });

    const outgoing = rows
      .filter(r => r.requesterMasterId === masterId)
      .map(r => {
        const m = masterMap.get(r.addresseeMasterId);
        return {
          requestId: r.id,
          masterId: r.addresseeMasterId,
          masterName: m?.masterName ?? 'Master',
          createdAt: r.createdAt,
        };
      });

    return { incoming, outgoing };
  }

  async searchMasters(masterId: string, queryInput: string) {
    const q = String(queryInput ?? '').trim();
    const candidates = await db
      .select({ id: masters.id, masterName: masters.masterName })
      .from(masters)
      .where(
        q
          ? and(ne(masters.id, masterId), or(ilike(masters.masterName, `%${q}%`), eq(masters.id, q)))
          : ne(masters.id, masterId),
      )
      .orderBy(asc(masters.masterName), asc(masters.id))
      .limit(20);

    if (!candidates.length) return { results: [] };

    const ids = candidates.map(c => c.id);
    const rels = await db
      .select()
      .from(friendships)
      .where(
        or(
          and(eq(friendships.requesterMasterId, masterId), inArray(friendships.addresseeMasterId, ids)),
          and(eq(friendships.addresseeMasterId, masterId), inArray(friendships.requesterMasterId, ids)),
        ),
      );

    const relMap = new Map<string, string>();
    for (const r of rels) {
      const other = r.requesterMasterId === masterId ? r.addresseeMasterId : r.requesterMasterId;
      if (r.status === 'BLOCKED') {
        relMap.set(other, 'BLOCKED');
      } else if (r.status === 'ACCEPTED') {
        relMap.set(other, 'FRIEND');
      } else if (r.status === 'PENDING') {
        relMap.set(other, r.requesterMasterId === masterId ? 'PENDING_OUT' : 'PENDING_IN');
      }
    }

    return {
      results: candidates.map(c => ({
        masterId: c.id,
        masterName: c.masterName,
        relationStatus: relMap.get(c.id) ?? 'NONE',
      })),
    };
  }

  async sendRequest(masterId: string, input: { targetMasterId?: unknown; targetName?: unknown; query?: unknown }) {
    const targetKey = String(input.targetMasterId ?? input.targetName ?? input.query ?? '').trim();
    if (!targetKey) throw new FriendError('Vui lòng nhập tên hoặc ID Master cần kết bạn.', 400);

    const [target] = await db
      .select({ id: masters.id, masterName: masters.masterName })
      .from(masters)
      .where(or(eq(masters.id, targetKey), ilike(masters.masterName, targetKey)))
      .limit(1);

    if (!target) throw new FriendError('Không tìm thấy Master này.', 404);
    if (target.id === masterId) throw new FriendError('Không thể tự gửi lời mời kết bạn cho chính mình.', 400);

    const existing = await db
      .select()
      .from(friendships)
      .where(
        or(
          and(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, target.id)),
          and(eq(friendships.requesterMasterId, target.id), eq(friendships.addresseeMasterId, masterId)),
        ),
      );

    for (const row of existing) {
      if (row.status === 'BLOCKED') {
        throw new FriendError('Không thể gửi lời mời do một trong hai bên đã chặn nhau.', 403);
      }
      if (row.status === 'ACCEPTED') {
        throw new FriendError('Hai người đã là bạn bè.', 400);
      }
      if (row.status === 'PENDING') {
        if (row.requesterMasterId === masterId) {
          throw new FriendError('Bạn đã gửi lời mời kết bạn tới Master này rồi.', 400);
        }
        // Reverse pending request exists: auto-accept!
        const [accepted] = await db
          .update(friendships)
          .set({ status: 'ACCEPTED', updatedAt: new Date() })
          .where(eq(friendships.id, row.id))
          .returning();
        return { friendship: accepted, autoAccepted: true };
      }
    }

    const [created] = await db
      .insert(friendships)
      .values({
        id: uuidv4(),
        requesterMasterId: masterId,
        addresseeMasterId: target.id,
        status: 'PENDING',
      })
      .returning();

    return { friendship: created, autoAccepted: false };
  }

  async acceptRequest(masterId: string, requestId: string) {
    const [row] = await db.select().from(friendships).where(eq(friendships.id, requestId)).limit(1);
    if (!row) throw new FriendError('Không tìm thấy lời mời kết bạn.', 404);
    if (row.addresseeMasterId !== masterId) throw new FriendError('Bạn không có quyền chấp nhận lời mời này.', 403);
    if (row.status !== 'PENDING') throw new FriendError('Lời mời kết bạn không còn ở trạng thái chờ.', 400);

    const [updated] = await db
      .update(friendships)
      .set({ status: 'ACCEPTED', updatedAt: new Date() })
      .where(eq(friendships.id, requestId))
      .returning();
    return { friendship: updated };
  }

  async declineRequest(masterId: string, requestId: string) {
    const [row] = await db.select().from(friendships).where(eq(friendships.id, requestId)).limit(1);
    if (!row) throw new FriendError('Không tìm thấy lời mời kết bạn.', 404);
    if (row.addresseeMasterId !== masterId && row.requesterMasterId !== masterId) {
      throw new FriendError('Bạn không có quyền từ chối lời mời này.', 403);
    }
    if (row.status !== 'PENDING') throw new FriendError('Lời mời kết bạn không còn ở trạng thái chờ.', 400);

    await db.delete(friendships).where(eq(friendships.id, requestId));
    return { declined: true };
  }

  async removeFriend(masterId: string, friendMasterId: string) {
    const deleted = await db
      .delete(friendships)
      .where(
        and(
          eq(friendships.status, 'ACCEPTED'),
          or(
            and(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, friendMasterId)),
            and(eq(friendships.requesterMasterId, friendMasterId), eq(friendships.addresseeMasterId, masterId)),
          ),
        ),
      )
      .returning();
    if (!deleted.length) throw new FriendError('Không tìm thấy quan hệ bạn bè.', 404);
    return { removed: true };
  }

  async blockMaster(masterId: string, targetMasterId: string) {
    if (masterId === targetMasterId) throw new FriendError('Không thể tự chặn chính mình.', 400);
    const [target] = await db.select({ id: masters.id }).from(masters).where(eq(masters.id, targetMasterId)).limit(1);
    if (!target) throw new FriendError('Không tìm thấy Master cần chặn.', 404);

    // Remove any non-blocked or existing relationship initiated by either side where requester is masterId or accepted/pending
    await db
      .delete(friendships)
      .where(
        or(
          and(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, targetMasterId)),
          and(
            eq(friendships.requesterMasterId, targetMasterId),
            eq(friendships.addresseeMasterId, masterId),
            ne(friendships.status, 'BLOCKED'),
          ),
        ),
      );

    const [created] = await db
      .insert(friendships)
      .values({
        id: uuidv4(),
        requesterMasterId: masterId,
        addresseeMasterId: targetMasterId,
        status: 'BLOCKED',
      })
      .returning();

    return { blocked: true, friendship: created };
  }

  async unblockMaster(masterId: string, targetMasterId: string) {
    const deleted = await db
      .delete(friendships)
      .where(
        and(
          eq(friendships.requesterMasterId, masterId),
          eq(friendships.addresseeMasterId, targetMasterId),
          eq(friendships.status, 'BLOCKED'),
        ),
      )
      .returning();
    if (!deleted.length) throw new FriendError('Master này chưa nằm trong danh sách chặn của bạn.', 404);
    return { unblocked: true };
  }

  async sendGift(masterId: string, friendMasterId: string) {
    const [friendRel] = await db
      .select({ id: friendships.id })
      .from(friendships)
      .where(
        and(
          eq(friendships.status, 'ACCEPTED'),
          or(
            and(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, friendMasterId)),
            and(eq(friendships.requesterMasterId, friendMasterId), eq(friendships.addresseeMasterId, masterId)),
          ),
        ),
      )
      .limit(1);

    if (!friendRel) throw new FriendError('Chỉ có thể tặng quà tình bạn cho người đã kết bạn.', 400);

    const giftDate = todayDateKey();
    const [existing] = await db
      .select({ id: friendDailyGifts.id })
      .from(friendDailyGifts)
      .where(
        and(
          eq(friendDailyGifts.senderMasterId, masterId),
          eq(friendDailyGifts.receiverMasterId, friendMasterId),
          eq(friendDailyGifts.giftDate, giftDate),
        ),
      )
      .limit(1);

    if (existing) throw new FriendError('Hôm nay bạn đã tặng quà cho người bạn này rồi.', 400);

    const [gift] = await db
      .insert(friendDailyGifts)
      .values({
        id: uuidv4(),
        senderMasterId: masterId,
        receiverMasterId: friendMasterId,
        giftDate,
        silverAmount: DAILY_GIFT_SILVER,
      })
      .returning();

    return { gift };
  }

  async claimAllGifts(masterId: string) {
    return await db.transaction(async tx => {
      const pending = await tx
        .select()
        .from(friendDailyGifts)
        .where(and(eq(friendDailyGifts.receiverMasterId, masterId), isNull(friendDailyGifts.claimedAt)));

      if (!pending.length) {
        return { claimedCount: 0, totalSilver: 0 };
      }

      const ids = pending.map(p => p.id);
      const totalSilver = pending.reduce((sum, p) => sum + p.silverAmount, 0);

      await tx
        .update(friendDailyGifts)
        .set({ claimedAt: new Date() })
        .where(inArray(friendDailyGifts.id, ids));

      await tx
        .update(masters)
        .set({ silverCoins: sql`${masters.silverCoins} + ${totalSilver}` })
        .where(eq(masters.id, masterId));

      return { claimedCount: pending.length, totalSilver };
    });
  }

  async getPublicProfile(masterId: string, targetMasterId: string) {
    if (await this.isBlockedBetween(masterId, targetMasterId)) {
      throw new FriendError('Không thể xem hồ sơ do đã chặn nhau.', 403);
    }

    const [target] = await db
      .select({
        id: masters.id,
        masterName: masters.masterName,
      })
      .from(masters)
      .where(eq(masters.id, targetMasterId))
      .limit(1);

    if (!target) throw new FriendError('Không tìm thấy hồ sơ Master.', 404);

    const [memberRow] = await db
      .select({ allianceId: allianceMembers.allianceId, role: allianceMembers.role })
      .from(allianceMembers)
      .where(eq(allianceMembers.masterId, targetMasterId))
      .limit(1);

    let allianceName: string | null = null;
    if (memberRow?.allianceId) {
      const [al] = await db
        .select({ name: alliances.name })
        .from(alliances)
        .where(eq(alliances.id, memberRow.allianceId))
        .limit(1);
      allianceName = al?.name ?? null;
    }

    const topHeroes = await db
      .select({
        id: heroes.id,
        name: heroes.name,
        rarity: heroes.rarity,
        level: heroes.level,
        classCode: heroes.classCode,
      })
      .from(heroes)
      .where(eq(heroes.masterId, targetMasterId))
      .orderBy(desc(heroes.rarity), desc(heroes.level))
      .limit(5);

    const [{ totalHeroes }] = await db
      .select({ totalHeroes: sql<number>`count(*)::int` })
      .from(heroes)
      .where(eq(heroes.masterId, targetMasterId));

    return {
      profile: {
        masterId: target.id,
        masterName: target.masterName,
        allianceName,
        heroCount: Number(totalHeroes ?? 0),
        topHeroes,
      },
    };
  }

  async getFriendBase(masterId: string, friendMasterId: string) {
    if (await this.isBlockedBetween(masterId, friendMasterId)) {
      throw new FriendError('Không thể thăm Lâu Đài do đã chặn nhau.', 403);
    }
    const [friendRel] = await db
      .select({ id: friendships.id })
      .from(friendships)
      .where(
        and(
          eq(friendships.status, 'ACCEPTED'),
          or(
            and(eq(friendships.requesterMasterId, masterId), eq(friendships.addresseeMasterId, friendMasterId)),
            and(eq(friendships.requesterMasterId, friendMasterId), eq(friendships.addresseeMasterId, masterId)),
          ),
        ),
      )
      .limit(1);
    if (!friendRel) {
      throw new FriendError('Chỉ có thể thăm Lâu Đài của người đã kết bạn.', 403);
    }

    const [target] = await db
      .select({ id: masters.id, masterName: masters.masterName })
      .from(masters)
      .where(eq(masters.id, friendMasterId))
      .limit(1);
    if (!target) throw new FriendError('Không tìm thấy Master này.', 404);

    const buildings = await db
      .select({
        id: baseBuildings.id,
        buildingType: baseBuildings.buildingType,
        plotIndex: baseBuildings.plotIndex,
        level: baseBuildings.level,
        status: baseBuildings.status,
      })
      .from(baseBuildings)
      .where(eq(baseBuildings.masterId, friendMasterId));

    return {
      master: {
        masterId: target.id,
        masterName: target.masterName,
      },
      buildings,
    };
  }
}

export const friendService = new FriendService();
