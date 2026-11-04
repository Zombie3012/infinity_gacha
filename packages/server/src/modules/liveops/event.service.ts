import { and, asc, desc, eq, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  eventMissionProgress, eventMissions, liveEvents, masterItems, masters,
} from '../../database/drizzle-schema.js';
import {
  acceptsClaims, acceptsProgress, eventPhase, eventWindow, majorCooldownViolated, normalizeRewardShape,
  overlapsStandard, type EventPhase, type EventType,
} from './liveops-rules.js';

export class EventError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'EventError';
  }
}

export class EventService {
  async createEvent(input: {
    code?: unknown; name?: unknown; description?: unknown; eventType?: unknown; startAt?: unknown;
  }) {
    const code = String(input.code ?? '').trim().toUpperCase();
    if (!/^[A-Z0-9_]{3,50}$/.test(code)) throw new EventError('code phải là chữ in hoa/số/underscore (3–50).');
    const name = String(input.name ?? '').trim();
    if (!name || name.length > 150) throw new EventError('name phải từ 1–150 ký tự.');
    const eventType = String(input.eventType ?? 'STANDARD').toUpperCase() as EventType;
    if (!['STANDARD', 'MAJOR', 'MINOR'].includes(eventType)) throw new EventError('eventType không hợp lệ.');
    const startAt = new Date(String(input.startAt ?? ''));
    if (Number.isNaN(startAt.getTime())) throw new EventError('startAt không hợp lệ.');

    const { endAt, claimDeadline } = eventWindow(startAt, eventType);
    const [row] = await db.insert(liveEvents).values({
      id: uuidv4(), code, name, description: String(input.description ?? ''),
      eventType, status: 'SCHEDULED', startAt, endAt, claimDeadline,
    }).returning();
    return row;
  }

  async addMission(eventId: string, input: { code?: unknown; name?: unknown; objectiveType?: unknown; targetCount?: unknown; reward?: unknown; sortOrder?: unknown }) {
    const code = String(input.code ?? '').trim().toUpperCase();
    if (!/^[A-Z0-9_]{2,50}$/.test(code)) throw new EventError('mission code không hợp lệ.');
    const objectiveTypes = ['WIN_BATTLE', 'CLEAR_FLOOR', 'CRAFT_ITEM', 'SPEND_SILVER', 'COLLECT_RESOURCE'];
    const objectiveType = String(input.objectiveType ?? '').toUpperCase();
    if (!objectiveTypes.includes(objectiveType)) throw new EventError('objectiveType không hợp lệ.');
    const targetCount = Math.max(1, Math.floor(Number(input.targetCount) || 1));
    const [event] = await db.select().from(liveEvents).where(eq(liveEvents.id, eventId)).limit(1);
    if (!event) throw new EventError('Sự kiện không tồn tại.', 404);
    const [row] = await db.insert(eventMissions).values({
      id: uuidv4(), eventId, code, name: String(input.name ?? code), objectiveType, targetCount,
      reward: normalizeRewardShape(input.reward), sortOrder: Math.floor(Number(input.sortOrder) || 100),
    }).returning();
    return row;
  }

  /** Scenario 3.2 / 3.3: activation enforces overlap and MAJOR cooldown rules. */
  async activate(eventId: string, now = new Date()) {
    const [event] = await db.select().from(liveEvents).where(eq(liveEvents.id, eventId)).limit(1);
    if (!event) throw new EventError('Sự kiện không tồn tại.', 404);
    if (event.status === 'ACTIVE') return event;
    if (event.status === 'CLOSED') throw new EventError('Sự kiện đã kết thúc.', 409);
    if (now < event.startAt) throw new EventError('Chưa tới giờ bắt đầu sự kiện.', 409);
    if (now >= event.endAt) throw new EventError('Sự kiện đã quá thời gian diễn ra.', 409);

    if (event.eventType === 'STANDARD') {
      const running = await db.select().from(liveEvents)
        .where(and(eq(liveEvents.eventType, 'STANDARD'), eq(liveEvents.status, 'ACTIVE'), inArray(liveEvents.id, [event.id])));
      const others = await db.select().from(liveEvents)
        .where(and(eq(liveEvents.eventType, 'STANDARD'), eq(liveEvents.status, 'ACTIVE')));
      const conflicts = others.filter(row => row.id !== event.id);
      if (conflicts.length > 0 || running.length > 0) {
        const overlap = overlapsStandard({ startAt: event.startAt, endAt: event.endAt }, conflicts);
        if (overlap || conflicts.length > 0) throw new EventError('ERR_LIVEOPS_STANDARD_EVENT_OVERLAP', 409);
      }
    }

    if (event.eventType === 'MAJOR') {
      const [previous] = await db.select().from(liveEvents)
        .where(and(eq(liveEvents.eventType, 'MAJOR'), eq(liveEvents.status, 'CLOSED')))
        .orderBy(desc(liveEvents.endAt)).limit(1);
      if (majorCooldownViolated(event.startAt, previous?.endAt ?? null)) {
        throw new EventError('ERR_MAJOR_EVENT_COOLDOWN_VIOLATION', 409);
      }
    }

    const [updated] = await db.update(liveEvents).set({ status: 'ACTIVE', activatedAt: now })
      .where(eq(liveEvents.id, event.id)).returning();
    return updated;
  }

  async close(eventId: string, now = new Date()) {
    const [updated] = await db.update(liveEvents).set({ status: 'CLOSED', closedAt: now })
      .where(and(eq(liveEvents.id, eventId), inArray(liveEvents.status, ['ACTIVE', 'SCHEDULED']))).returning();
    if (!updated) throw new EventError('Sự kiện không tồn tại hoặc đã kết thúc.', 404);
    return updated;
  }

  async list() {
    return db.select().from(liveEvents).orderBy(desc(liveEvents.startAt)).limit(50);
  }

  /** Player view: active events with their missions and this Master's progress. */
  async forMaster(masterId: string, now = new Date()) {
    const events = await db.select().from(liveEvents)
      .where(inArray(liveEvents.status, ['ACTIVE'])).orderBy(asc(liveEvents.endAt));
    const visible = events.filter(event => now < event.claimDeadline);
    if (visible.length === 0) return [];

    const missions = await db.select().from(eventMissions)
      .where(inArray(eventMissions.eventId, visible.map(event => event.id))).orderBy(asc(eventMissions.sortOrder));
    if (missions.length === 0) return visible.map(event => ({ ...event, phase: eventPhase(event.startAt, event.endAt, event.claimDeadline, now), missions: [] }));

    const existing = await db.select().from(eventMissionProgress)
      .where(and(eq(eventMissionProgress.masterId, masterId), inArray(eventMissionProgress.missionId, missions.map(row => row.id))));
    const known = new Set(existing.map(row => row.missionId));
    const missing = missions.filter(row => !known.has(row.id));
    if (missing.length > 0) {
      await db.insert(eventMissionProgress).values(missing.map(row => ({
        id: uuidv4(), masterId, missionId: row.id, progress: 0, status: 'ACTIVE',
      }))).onConflictDoNothing();
    }
    const progressRows = await db.select().from(eventMissionProgress)
      .where(and(eq(eventMissionProgress.masterId, masterId), inArray(eventMissionProgress.missionId, missions.map(row => row.id))));
    const progressByMission = new Map(progressRows.map(row => [row.missionId, row]));

    return visible.map(event => ({
      ...event,
      phase: eventPhase(event.startAt, event.endAt, event.claimDeadline, now),
      missions: missions.filter(mission => mission.eventId === event.id).map(mission => {
        const progress = progressByMission.get(mission.id);
        return {
          ...mission,
          progress: progress?.progress ?? 0,
          status: progress?.status ?? 'ACTIVE',
          canClaim: progress?.status === 'COMPLETED' && acceptsClaims(event.claimDeadline, now),
        };
      }),
    }));
  }

  /** Scenario 3.4: events stop accepting progress at `end_at`. */
  async recordEvent(masterId: string, objectiveType: string, amount = 1, now = new Date()) {
    const activeEvents = await db.select().from(liveEvents).where(eq(liveEvents.status, 'ACTIVE'));
    const inWindow = activeEvents.filter(event => acceptsProgress(event.startAt, event.endAt, now));
    if (inWindow.length === 0) return { updated: 0 };

    const missions = await db.select().from(eventMissions)
      .where(and(inArray(eventMissions.eventId, inWindow.map(event => event.id)), eq(eventMissions.objectiveType, objectiveType)));
    if (missions.length === 0) return { updated: 0 };

    const rows = await db.select().from(eventMissionProgress)
      .where(and(eq(eventMissionProgress.masterId, masterId), inArray(eventMissionProgress.missionId, missions.map(row => row.id))));
    const byMission = new Map(rows.map(row => [row.missionId, row]));

    let updated = 0;
    for (const mission of missions) {
      const row = byMission.get(mission.id);
      if (!row) continue;
      const nextProgress = Math.min(mission.targetCount, row.progress + Math.max(0, amount));
      const nextStatus = nextProgress >= mission.targetCount ? 'COMPLETED' : row.status;
      await db.update(eventMissionProgress).set({
        progress: nextProgress,
        status: nextStatus,
        ...(nextStatus === 'COMPLETED' && !row.completedAt ? { completedAt: now } : {}),
      }).where(eq(eventMissionProgress.id, row.id));
      updated += 1;
    }
    return { updated };
  }

  async claimMission(masterId: string, missionId: string, now = new Date()) {
    const [row] = await db.select({ progress: eventMissionProgress, mission: eventMissions, event: liveEvents })
      .from(eventMissionProgress)
      .innerJoin(eventMissions, eq(eventMissions.id, eventMissionProgress.missionId))
      .innerJoin(liveEvents, eq(liveEvents.id, eventMissions.eventId))
      .where(and(eq(eventMissionProgress.masterId, masterId), eq(eventMissionProgress.missionId, missionId)))
      .limit(1);
    if (!row) throw new EventError('Bạn chưa tham gia nhiệm vụ này.', 404);
    if (row.progress.status === 'CLAIMED') throw new EventError('Đã nhận thưởng.', 409);
    if (row.progress.status !== 'COMPLETED') throw new EventError('Nhiệm vụ chưa hoàn thành.', 409);
    if (!acceptsClaims(row.event.claimDeadline, now)) throw new EventError('ERR_LIVEOPS_CLAIM_EXPIRED', 410);

    const reward = normalizeRewardShape(row.mission.reward);
    await db.transaction(async tx => {
      if (reward.silver || reward.gems) {
        await tx.update(masters).set({
          ...(reward.silver ? { silverCoins: sql`${masters.silverCoins} + ${reward.silver}` } : {}),
          ...(reward.gems ? { gems: sql`${masters.gems} + ${reward.gems}` } : {}),
          updatedAt: now,
        }).where(eq(masters.id, masterId));
      }
      for (const item of reward.items) {
        await tx.insert(masterItems).values({
          id: uuidv4(), masterId, itemId: item.itemId, quantity: item.quantity, updatedAt: now,
        }).onConflictDoUpdate({
          target: [masterItems.masterId, masterItems.itemId],
          set: { quantity: sql`${masterItems.quantity} + ${item.quantity}`, updatedAt: now },
        });
      }
      await tx.update(eventMissionProgress).set({ status: 'CLAIMED', claimedAt: now }).where(eq(eventMissionProgress.id, row.progress.id));
    });
    return { missionId, reward };
  }
}

export const eventService = new EventService();
