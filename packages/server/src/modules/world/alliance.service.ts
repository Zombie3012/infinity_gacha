import { and, asc, desc, eq, gt, inArray, sql } from 'drizzle-orm';
import { v4 as uuidv4 } from 'uuid';
import { db } from '../../database/db.js';
import {
  allianceCooldowns, allianceJoinRequests, allianceMembers, allianceMessages, alliances, heroes, masters,
} from '../../database/drizzle-schema.js';
import { topCombatPower } from '../liveops/liveops-rules.js';
import { fetchMasterTopCombatPower } from '../hero/hero-combat-power.js';
import {
  ALLIANCE_CREATE_GEM_COST, ALLIANCE_CREATE_SILVER_COST, ALLIANCE_CHAT_PAGE, isAllianceRole,
  canCreateAlliance, canLeave, canManageMember, canRequestJoin, canUpgradeTech, cooldownUntil, creationPayment,
  maxMembersForLevel, roleRank, searchMatches, validateAllianceIdentity, validateChatMessage, validateNotice,
  type ManageAction,
} from './alliance-rules.js';

export class AllianceError extends Error {
  constructor(message: string, readonly statusCode = 400) {
    super(message);
    this.name = 'AllianceError';
  }
}

type MemberRow = typeof allianceMembers.$inferSelect;
type AllianceRow = typeof alliances.$inferSelect;

const serialiseMember = (member: MemberRow, master: { masterName: string; level: number }) => ({
  masterId: member.masterId,
  name: master.masterName,
  level: master.level,
  role: member.role,
  contributionPoints: member.contributionPoints.toString(),
  joinedAt: member.joinedAt,
});

const serialiseAlliance = (row: AllianceRow) => ({
  id: row.id,
  name: row.name,
  tag: row.tag,
  emblemIcon: row.emblemIcon,
  motto: row.motto,
  language: row.language,
  minCombatPower: row.minCombatPower,
  leaderMasterId: row.leaderMasterId,
  memberCount: row.memberCount,
  maxMembers: row.maxMembers,
  allianceLevel: row.allianceLevel,
  noticeBoard: row.noticeBoard,
  createdAt: row.createdAt,
});

export class AllianceService {
  private async masterRow(masterId: string) {
    const [master] = await db.select().from(masters).where(eq(masters.id, masterId)).limit(1);
    if (!master) throw new AllianceError('Không tìm thấy Master.', 404);
    return master;
  }

  private async membership(masterId: string) {
    const [row] = await db.select({ member: allianceMembers, alliance: alliances })
      .from(allianceMembers).innerJoin(alliances, eq(alliances.id, allianceMembers.allianceId))
      .where(eq(allianceMembers.masterId, masterId)).limit(1);
    return row ?? null;
  }

  private async activeCooldown(masterId: string, now: Date) {
    const [row] = await db.select().from(allianceCooldowns)
      .where(and(eq(allianceCooldowns.masterId, masterId), gt(allianceCooldowns.expiresAt, now))).limit(1);
    return row ?? null;
  }

  private async combatPowerByMaster(masterIds: string[]): Promise<Map<string, number>> {
    const result = new Map<string, number>();
    if (masterIds.length === 0) return result;
    await Promise.all(masterIds.map(async masterId => {
      const power = await fetchMasterTopCombatPower(masterId, 5);
      result.set(masterId, power);
    }));
    return result;
  }

  /** UC-P3-07: everything the alliance screen needs for the caller. */
  async overview(masterId: string, now = new Date()) {
    const membership = await this.membership(masterId);
    const cooldown = await this.activeCooldown(masterId, now);

    if (!membership) {
      const [pending] = await db.select().from(allianceJoinRequests)
        .where(and(eq(allianceJoinRequests.masterId, masterId), eq(allianceJoinRequests.status, 'PENDING')))
        .orderBy(desc(allianceJoinRequests.createdAt)).limit(1);
      const [pendingAlliance] = pending ? await db.select().from(alliances).where(eq(alliances.id, pending.allianceId)).limit(1) : [];
      return {
        inAlliance: false,
        alliance: null,
        membership: null,
        members: [],
        requests: [],
        permissions: { canManage: false, canUpgradeTech: false, canDeclareWar: false },
        cooldown: cooldown ? { expiresAt: cooldown.expiresAt, reason: cooldown.reason } : null,
        pendingRequest: pending ? {
          id: pending.id, allianceId: pending.allianceId, allianceName: pendingAlliance?.name ?? null, createdAt: pending.createdAt,
        } : null,
      };
    }

    const { member, alliance } = membership;
    const memberRows = await db.select({ member: allianceMembers, master: masters })
      .from(allianceMembers).innerJoin(masters, eq(masters.id, allianceMembers.masterId))
      .where(eq(allianceMembers.allianceId, alliance.id)).orderBy(asc(allianceMembers.joinedAt));
    const power = await this.combatPowerByMaster(memberRows.map(row => row.member.masterId));

    const canManage = roleRank(member.role) >= roleRank('OFFICER');
    const requests = canManage
      ? await db.select({
        request: allianceJoinRequests, name: masters.masterName, level: masters.level,
      }).from(allianceJoinRequests)
        .innerJoin(masters, eq(masters.id, allianceJoinRequests.masterId))
        .where(and(eq(allianceJoinRequests.allianceId, alliance.id), eq(allianceJoinRequests.status, 'PENDING')))
        .orderBy(asc(allianceJoinRequests.createdAt))
      : [];

    return {
      inAlliance: true,
      alliance: serialiseAlliance(alliance),
      membership: {
        masterId: member.masterId, role: member.role,
        contributionPoints: member.contributionPoints.toString(), joinedAt: member.joinedAt,
      },
      members: memberRows.map(row => ({
        ...serialiseMember(row.member, row.master), power: power.get(row.member.masterId) ?? 0,
      })),
      requests: requests.map(row => ({
        id: row.request.id, masterId: row.request.masterId, name: row.name, level: row.level,
        message: row.request.message, createdAt: row.request.createdAt,
      })),
      permissions: {
        canManage,
        canUpgradeTech: member.role === 'LEADER',
        canDeclareWar: member.role === 'LEADER',
      },
      cooldown: null,
      pendingRequest: null,
    };
  }

  /** UC-P3-07: browse/filter alliances and mark the caller's pending request. */
  async search(masterId: string, filters: { query?: unknown; language?: unknown; minCombatPower?: unknown; hasSlots?: unknown }) {
    const [membership, pendingRows] = await Promise.all([
      this.membership(masterId),
      db.select({ allianceId: allianceJoinRequests.allianceId }).from(allianceJoinRequests)
        .where(and(eq(allianceJoinRequests.masterId, masterId), eq(allianceJoinRequests.status, 'PENDING'))),
    ]);
    const pending = new Set(pendingRows.map(row => row.allianceId));
    const rows = await db.select().from(alliances).orderBy(desc(alliances.memberCount), asc(alliances.name));
    const minCombatPower = filters.minCombatPower === undefined || filters.minCombatPower === ''
      ? undefined
      : Math.max(0, Math.floor(Number(filters.minCombatPower) || 0));

    const filtered = rows.filter(row => searchMatches(row, {
      query: String(filters.query ?? ''),
      language: filters.language ? String(filters.language) : undefined,
      minCombatPower,
      hasSlots: filters.hasSlots === true || filters.hasSlots === 'true',
    }));
    const leaders = filtered.length === 0 ? [] : await db.select({ id: masters.id, name: masters.masterName })
      .from(masters).where(inArray(masters.id, [...new Set(filtered.map(row => row.leaderMasterId))]));
    const leaderName = new Map(leaders.map(row => [row.id, row.name]));

    return {
      alliances: filtered.slice(0, 50).map(row => ({
        ...serialiseAlliance(row),
        leaderName: leaderName.get(row.leaderMasterId) ?? null,
        pending: pending.has(row.id),
        full: row.memberCount >= row.maxMembers,
      })),
      myAllianceId: membership?.alliance.id ?? null,
      pendingCount: pending.size,
    };
  }

  /** FUN-13-06-001 Create Alliance. */
  async create(masterId: string, input: Record<string, unknown>, now = new Date()) {
    const identity = validateAllianceIdentity(input);
    if (!identity.ok) throw new AllianceError(identity.reason ?? 'ERR_ALLIANCE_NAME_INVALID', 400);
    const value = identity.value!;

    const [master, membership, cooldown] = await Promise.all([
      this.masterRow(masterId), this.membership(masterId), this.activeCooldown(masterId, now),
    ]);
    const check = canCreateAlliance({
      masterLevel: master.level, inAlliance: Boolean(membership), cooldownUntil: cooldown?.expiresAt ?? null, now,
    });
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_CANNOT_CREATE', 409);

    const [duplicate] = await db.select({ id: alliances.id }).from(alliances)
      .where(sql`lower(${alliances.name}) = ${value.name.toLowerCase()} or lower(${alliances.tag}) = ${value.tag.toLowerCase()}`)
      .limit(1);
    if (duplicate) throw new AllianceError('ERR_ALLIANCE_NAME_TAKEN', 409);

    const payment = creationPayment({ gems: master.gems, silver: master.silverCoins });
    if (!payment.ok) throw new AllianceError(payment.reason ?? 'ERR_ALLIANCE_INSUFFICIENT_FUNDS', 409);

    const id = uuidv4();
    await db.transaction(async tx => {
      if (payment.currency === 'GEM') {
        await tx.update(masters).set({ gems: sql`${masters.gems} - ${ALLIANCE_CREATE_GEM_COST}`, updatedAt: now })
          .where(eq(masters.id, masterId));
      } else {
        await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${ALLIANCE_CREATE_SILVER_COST}`, updatedAt: now })
          .where(eq(masters.id, masterId));
      }
      await tx.insert(alliances).values({
        id, name: value.name, tag: value.tag, emblemIcon: value.emblemIcon, motto: value.motto,
        language: value.language, minCombatPower: 0, leaderMasterId: masterId,
        memberCount: 1, maxMembers: maxMembersForLevel(1), allianceLevel: 1,
        noticeBoard: '', createdAt: now, updatedAt: now,
      });
      await tx.insert(allianceMembers).values({
        id: uuidv4(), allianceId: id, masterId, role: 'LEADER', joinedAt: now, updatedAt: now,
      });
      await tx.delete(allianceCooldowns).where(eq(allianceCooldowns.masterId, masterId));
    });

    return { ...(await this.overview(masterId, now)), currencySpent: payment.currency, cost: payment.currency === 'GEM' ? ALLIANCE_CREATE_GEM_COST : ALLIANCE_CREATE_SILVER_COST };
  }

  /** FUN-13-06-003 Join Alliance: submit a request that officers approve. */
  async requestJoin(masterId: string, allianceId: string, message: unknown, now = new Date()) {
    const [alliance] = await db.select().from(alliances).where(eq(alliances.id, allianceId)).limit(1);
    if (!alliance) throw new AllianceError('Không tìm thấy liên minh.', 404);

    const [membership, cooldown, pending] = await Promise.all([
      this.membership(masterId),
      this.activeCooldown(masterId, now),
      db.select({ id: allianceJoinRequests.id }).from(allianceJoinRequests)
        .where(and(
          eq(allianceJoinRequests.masterId, masterId),
          eq(allianceJoinRequests.allianceId, allianceId),
          eq(allianceJoinRequests.status, 'PENDING'),
        )).limit(1),
    ]);
    const check = canRequestJoin({
      inAlliance: Boolean(membership), cooldownUntil: cooldown?.expiresAt ?? null, now,
      memberCount: alliance.memberCount, maxMembers: alliance.maxMembers, alreadyPending: pending.length > 0,
    });
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_CANNOT_JOIN', 409);

    const body = String(message ?? '').trim().slice(0, 200);
    const [request] = await db.insert(allianceJoinRequests).values({
      id: uuidv4(), allianceId, masterId, status: 'PENDING', message: body, createdAt: now,
    }).returning();
    return { request: { ...request, allianceName: alliance.name } };
  }

  async cancelRequest(masterId: string, requestId: string, now = new Date()) {
    const [request] = await db.select().from(allianceJoinRequests)
      .where(and(eq(allianceJoinRequests.id, requestId), eq(allianceJoinRequests.masterId, masterId))).limit(1);
    if (!request) throw new AllianceError('Không tìm thấy yêu cầu.', 404);
    if (request.status !== 'PENDING') throw new AllianceError('ERR_ALLIANCE_REQUEST_RESOLVED', 409);
    await db.update(allianceJoinRequests).set({ status: 'CANCELLED', resolvedAt: now })
      .where(eq(allianceJoinRequests.id, requestId));
    return { requestId, status: 'CANCELLED' };
  }

  /** FUN-13-06-005 Manage Alliance Member: approve/reject joining requests. */
  async resolveRequest(masterId: string, requestId: string, approve: boolean, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const check = canManageMember(membership.member.role, approve ? 'APPROVE' : 'REJECT');
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_ROLE_TOO_LOW', 403);

    const [request] = await db.select().from(allianceJoinRequests)
      .where(and(
        eq(allianceJoinRequests.id, requestId),
        eq(allianceJoinRequests.allianceId, membership.alliance.id),
      )).limit(1);
    if (!request) throw new AllianceError('Không tìm thấy yêu cầu.', 404);
    if (request.status !== 'PENDING') throw new AllianceError('ERR_ALLIANCE_REQUEST_RESOLVED', 409);

    if (!approve) {
      await db.update(allianceJoinRequests).set({ status: 'REJECTED', resolvedBy: masterId, resolvedAt: now })
        .where(eq(allianceJoinRequests.id, requestId));
      return { requestId, status: 'REJECTED' };
    }

    const [existingMember, candidateCooldown] = await Promise.all([
      db.select({ id: allianceMembers.id }).from(allianceMembers).where(eq(allianceMembers.masterId, request.masterId)).limit(1),
      this.activeCooldown(request.masterId, now),
    ]);
    if (existingMember.length > 0) throw new AllianceError('ERR_ALLIANCE_ALREADY_MEMBER', 409);
    if (candidateCooldown) throw new AllianceError('ERR_ALLIANCE_COOLDOWN', 409);

    await db.transaction(async tx => {
      const [locked] = await tx.select().from(alliances).where(eq(alliances.id, membership.alliance.id)).for('update').limit(1);
      if (!locked || locked.memberCount >= locked.maxMembers) throw new AllianceError('ERR_ALLIANCE_FULL', 409);
      await tx.insert(allianceMembers).values({
        id: uuidv4(), allianceId: locked.id, masterId: request.masterId, role: 'MEMBER', joinedAt: now, updatedAt: now,
      });
      await tx.update(alliances).set({ memberCount: sql`${alliances.memberCount} + 1`, updatedAt: now })
        .where(eq(alliances.id, locked.id));
      await tx.update(allianceJoinRequests).set({ status: 'APPROVED', resolvedBy: masterId, resolvedAt: now })
        .where(eq(allianceJoinRequests.id, requestId));
      await tx.update(allianceJoinRequests).set({ status: 'CANCELLED', resolvedBy: masterId, resolvedAt: now })
        .where(and(
          eq(allianceJoinRequests.masterId, request.masterId),
          eq(allianceJoinRequests.status, 'PENDING'),
        ));
    });

    return { requestId, status: 'APPROVED', masterId: request.masterId };
  }

  /** FUN-13-06-004 Leave Alliance with the 24h re-join cooldown. */
  async leave(masterId: string, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 404);
    const check = canLeave(membership.alliance.memberCount, membership.member.role);
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_CANNOT_LEAVE', 409);

    const allianceId = membership.alliance.id;
    const expiresAt = cooldownUntil(now);
    await db.transaction(async tx => {
      await tx.delete(allianceMembers).where(and(
        eq(allianceMembers.masterId, masterId), eq(allianceMembers.allianceId, allianceId),
      ));
      if (membership.member.role === 'LEADER') {
        await tx.delete(alliances).where(eq(alliances.id, allianceId));
      } else {
        await tx.update(alliances).set({ memberCount: sql`${alliances.memberCount} - 1`, updatedAt: now })
          .where(eq(alliances.id, allianceId));
      }
      await tx.insert(allianceCooldowns).values({ masterId, expiresAt, reason: 'LEFT', createdAt: now })
        .onConflictDoUpdate({ target: allianceCooldowns.masterId, set: { expiresAt, reason: 'LEFT', createdAt: now } });
    });
    return { left: true, allianceId, cooldownUntil: expiresAt, disbanded: membership.member.role === 'LEADER' };
  }

  /** FUN-13-06-005: kick, promote, demote, transfer leadership. */
  async manage(masterId: string, targetMasterId: string, actionInput: unknown, now = new Date()) {
    const action = String(actionInput ?? '').toUpperCase() as ManageAction;
    if (!['KICK', 'PROMOTE', 'DEMOTE', 'TRANSFER'].includes(action)) {
      throw new AllianceError('ERR_ALLIANCE_ACTION_INVALID', 400);
    }
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    if (targetMasterId === masterId) throw new AllianceError('ERR_ALLIANCE_TARGET_SELF', 409);

    const [target] = await db.select({ member: allianceMembers, master: masters })
      .from(allianceMembers).innerJoin(masters, eq(masters.id, allianceMembers.masterId))
      .where(and(
        eq(allianceMembers.masterId, targetMasterId),
        eq(allianceMembers.allianceId, membership.alliance.id),
      )).limit(1);
    if (!target) throw new AllianceError('Không tìm thấy thành viên.', 404);
    if (!isAllianceRole(target.member.role)) throw new AllianceError('ERR_ALLIANCE_TARGET_REQUIRED', 409);

    const check = canManageMember(membership.member.role, action, target.member.role);
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_ROLE_TOO_LOW', 403);

    if (action === 'KICK') {
      const expiresAt = cooldownUntil(now);
      await db.transaction(async tx => {
        await tx.delete(allianceMembers).where(eq(allianceMembers.id, target.member.id));
        await tx.update(alliances).set({ memberCount: sql`${alliances.memberCount} - 1`, updatedAt: now })
          .where(eq(alliances.id, membership.alliance.id));
        await tx.insert(allianceCooldowns).values({ masterId: targetMasterId, expiresAt, reason: 'KICKED', createdAt: now })
          .onConflictDoUpdate({ target: allianceCooldowns.masterId, set: { expiresAt, reason: 'KICKED', createdAt: now } });
      });
      return { action, targetMasterId, cooldownUntil: expiresAt };
    }

    if (action === 'PROMOTE' || action === 'DEMOTE') {
      const nextRole = action === 'PROMOTE' ? 'OFFICER' : 'MEMBER';
      if (target.member.role === nextRole) throw new AllianceError('ERR_ALLIANCE_ROLE_UNCHANGED', 409);
      await db.update(allianceMembers).set({ role: nextRole, updatedAt: now }).where(eq(allianceMembers.id, target.member.id));
      return { action, targetMasterId, role: nextRole };
    }

    // TRANSFER: the Leader hands the guild over and becomes an Officer.
    await db.transaction(async tx => {
      await tx.update(allianceMembers).set({ role: 'OFFICER', updatedAt: now })
        .where(eq(allianceMembers.id, membership.member.id));
      await tx.update(allianceMembers).set({ role: 'LEADER', updatedAt: now })
        .where(eq(allianceMembers.id, target.member.id));
      await tx.update(alliances).set({ leaderMasterId: targetMasterId, updatedAt: now })
        .where(eq(alliances.id, membership.alliance.id));
    });
    return { action, targetMasterId, role: 'LEADER', previousLeaderRole: 'OFFICER' };
  }

  async updateNotice(masterId: string, body: unknown, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const check = canManageMember(membership.member.role, 'NOTICE');
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_ROLE_TOO_LOW', 403);
    const notice = validateNotice(body);
    if (!notice.ok) throw new AllianceError(notice.reason ?? 'ERR_ALLIANCE_NOTICE_TOO_LONG', 400);
    await db.update(alliances).set({ noticeBoard: notice.value!, updatedAt: now })
      .where(eq(alliances.id, membership.alliance.id));
    return { noticeBoard: notice.value };
  }

  /** Alliance Tech: the Leader spends Silver to raise the member cap. */
  async upgradeTech(masterId: string, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const check = canManageMember(membership.member.role, 'UPGRADE');
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_LEADER_ONLY', 403);

    const master = await this.masterRow(masterId);
    const upgrade = canUpgradeTech({ level: membership.alliance.allianceLevel, silver: master.silverCoins });
    if (!upgrade.ok) throw new AllianceError(upgrade.reason ?? 'ERR_ALLIANCE_TECH_MAX', 409);

    const nextLevel = membership.alliance.allianceLevel + 1;
    const maxMembers = maxMembersForLevel(nextLevel);
    await db.transaction(async tx => {
      await tx.update(masters).set({ silverCoins: sql`${masters.silverCoins} - ${upgrade.cost}`, updatedAt: now })
        .where(eq(masters.id, masterId));
      await tx.update(alliances).set({ allianceLevel: nextLevel, maxMembers, updatedAt: now })
        .where(eq(alliances.id, membership.alliance.id));
    });
    return { allianceLevel: nextLevel, maxMembers, silverSpent: upgrade.cost };
  }

  /** FUN-13-06-005: disband, Leader only. */
  async disband(masterId: string, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 404);
    const check = canManageMember(membership.member.role, 'DISBAND');
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_LEADER_ONLY', 403);
    const memberIds = await db.select({ masterId: allianceMembers.masterId }).from(allianceMembers)
      .where(eq(allianceMembers.allianceId, membership.alliance.id));
    await db.delete(alliances).where(eq(alliances.id, membership.alliance.id));
    return { disbanded: true, allianceId: membership.alliance.id, members: memberIds.length, at: now };
  }

  /** FUN-13-06-006 Alliance Communication: text and coordinate pings. */
  async messages(masterId: string) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const rows = await db.select({ message: allianceMessages, name: masters.masterName })
      .from(allianceMessages).innerJoin(masters, eq(masters.id, allianceMessages.masterId))
      .where(eq(allianceMessages.allianceId, membership.alliance.id))
      .orderBy(desc(allianceMessages.createdAt)).limit(ALLIANCE_CHAT_PAGE);
    return rows.reverse().map(row => ({
      id: row.message.id, masterId: row.message.masterId, name: row.name,
      messageType: row.message.messageType, body: row.message.body,
      coordinates: row.message.coordinates, createdAt: row.message.createdAt,
    }));
  }

  async sendMessage(masterId: string, input: { body?: unknown; coordinates?: unknown }, now = new Date()) {
    const membership = await this.membership(masterId);
    if (!membership) throw new AllianceError('ERR_ALLIANCE_NOT_MEMBER', 403);
    const check = validateChatMessage(input);
    if (!check.ok) throw new AllianceError(check.reason ?? 'ERR_ALLIANCE_CHAT_EMPTY', 400);
    const value = check.value!;
    const [row] = await db.insert(allianceMessages).values({
      id: uuidv4(), allianceId: membership.alliance.id, masterId, messageType: value.coordinates ? 'PING' : 'TEXT',
      body: value.body, coordinates: value.coordinates, createdAt: now,
    }).returning();
    return { ...row };
  }

  /** Helper used by the conquest service to broadcast war events to members. */
  async memberIds(allianceId: string): Promise<string[]> {
    const rows = await db.select({ masterId: allianceMembers.masterId }).from(allianceMembers)
      .where(eq(allianceMembers.allianceId, allianceId));
    return rows.map(row => row.masterId);
  }
}

export const allianceService = new AllianceService();
