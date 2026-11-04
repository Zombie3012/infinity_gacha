/**
 * Domain 13 / MOD-13-06 (P3) alliance rules.
 *
 * Sample tuning (prototype):
 * - a Master needs level 20 and pays 5,000 Gems or 500,000 Silver to found one
 * - names are 3-20 characters, tags are 2-5 letters/digits, both unique
 * - an alliance starts at 30 members and grows by 10 per Alliance Tech level,
 *   capped at 100 (Tech level 8)
 * - leaving or being removed locks the Master out of alliances for 24 hours
 * - the Leader manages every role, an Officer approves requests, manages
 *   members and edits the notice board, a Member only chats
 * - a Leader must hand over leadership before leaving a populated alliance
 */

export type AllianceRole = 'LEADER' | 'OFFICER' | 'MEMBER';

export const ALLIANCE_CREATE_LEVEL = 20;
export const ALLIANCE_CREATE_GEM_COST = 5_000;
export const ALLIANCE_CREATE_SILVER_COST = 500_000;
export const ALLIANCE_BASE_MAX_MEMBERS = 30;
export const ALLIANCE_MAX_MEMBERS = 100;
export const ALLIANCE_MEMBERS_PER_TECH_LEVEL = 10;
export const ALLIANCE_MAX_TECH_LEVEL = 8;
export const ALLIANCE_LEAVE_COOLDOWN_HOURS = 24;
export const ALLIANCE_NAME_MIN = 3;
export const ALLIANCE_NAME_MAX = 20;
export const ALLIANCE_TAG_MIN = 2;
export const ALLIANCE_TAG_MAX = 5;
export const ALLIANCE_MOTTO_MAX = 120;
export const ALLIANCE_NOTICE_MAX = 500;
export const ALLIANCE_CHAT_MAX = 300;
export const ALLIANCE_CHAT_PAGE = 50;
export const ALLIANCE_TECH_BASE_COST_SILVER = 100_000;

export const ROLE_RANK: Record<AllianceRole, number> = { MEMBER: 1, OFFICER: 2, LEADER: 3 };

export function isAllianceRole(value: unknown): value is AllianceRole {
  return value === 'LEADER' || value === 'OFFICER' || value === 'MEMBER';
}

export function roleRank(role: unknown): number {
  return isAllianceRole(role) ? ROLE_RANK[role] : 0;
}

export function maxMembersForLevel(level: number): number {
  const safe = Math.max(1, Math.min(ALLIANCE_MAX_TECH_LEVEL, Math.floor(level) || 1));
  return Math.min(ALLIANCE_MAX_MEMBERS, ALLIANCE_BASE_MAX_MEMBERS + (safe - 1) * ALLIANCE_MEMBERS_PER_TECH_LEVEL);
}

export function techCost(level: number): number {
  return ALLIANCE_TECH_BASE_COST_SILVER * Math.max(1, Math.min(ALLIANCE_MAX_TECH_LEVEL, Math.floor(level) || 1));
}

export interface RuleCheck {
  ok: boolean;
  reason?: string;
}

export interface AllianceIdentity {
  name: string;
  tag: string;
  motto: string;
  emblemIcon: string;
  language: string;
}

/**
 * Normalises and validates the identity fields shown in the alliance browser.
 * Names keep their casing but are compared case-insensitively by the service.
 */
export function validateAllianceIdentity(input: {
  name?: unknown;
  tag?: unknown;
  motto?: unknown;
  emblemIcon?: unknown;
  language?: unknown;
}): { ok: boolean; reason?: string; value?: AllianceIdentity } {
  const name = String(input.name ?? '').trim();
  const tag = String(input.tag ?? '').trim().toUpperCase();
  const motto = String(input.motto ?? '').trim();
  const emblemIcon = String(input.emblemIcon ?? '⚔').trim().slice(0, 100) || '⚔';
  const language = String(input.language ?? 'vi').trim().toLowerCase() || 'vi';

  if (name.length < ALLIANCE_NAME_MIN || name.length > ALLIANCE_NAME_MAX) {
    return { ok: false, reason: 'ERR_ALLIANCE_NAME_INVALID' };
  }
  if (!/^[\p{L}\p{N} _-]+$/u.test(name)) return { ok: false, reason: 'ERR_ALLIANCE_NAME_INVALID' };
  if (!/^[A-Z0-9]{2,5}$/.test(tag)) return { ok: false, reason: 'ERR_ALLIANCE_TAG_INVALID' };
  if (motto.length > ALLIANCE_MOTTO_MAX) return { ok: false, reason: 'ERR_ALLIANCE_MOTTO_INVALID' };
  if (!/^[a-z]{2,10}$/.test(language)) return { ok: false, reason: 'ERR_ALLIANCE_LANGUAGE_INVALID' };

  return { ok: true, value: { name, tag, motto, emblemIcon, language } };
}

export function canCreateAlliance(input: {
  masterLevel: number;
  inAlliance: boolean;
  cooldownUntil: Date | null;
  now: Date;
}): RuleCheck {
  if (input.inAlliance) return { ok: false, reason: 'ERR_ALLIANCE_ALREADY_MEMBER' };
  if (input.masterLevel < ALLIANCE_CREATE_LEVEL) return { ok: false, reason: 'ERR_ALLIANCE_LEVEL_REQUIRED' };
  if (input.cooldownUntil && input.cooldownUntil > input.now) return { ok: false, reason: 'ERR_ALLIANCE_COOLDOWN' };
  return { ok: true };
}

/** Scenario UC-P3-07: pay 5,000 Gems, or fall back to 500,000 Silver. */
export function creationPayment(input: { gems: bigint | number; silver: bigint | number }): {
  ok: boolean;
  currency?: 'GEM' | 'SILVER';
  reason?: string;
} {
  if (Number(input.gems) >= ALLIANCE_CREATE_GEM_COST) return { ok: true, currency: 'GEM' };
  if (Number(input.silver) >= ALLIANCE_CREATE_SILVER_COST) return { ok: true, currency: 'SILVER' };
  return { ok: false, reason: 'ERR_ALLIANCE_INSUFFICIENT_FUNDS' };
}

export function cooldownUntil(now: Date, hours = ALLIANCE_LEAVE_COOLDOWN_HOURS): Date {
  return new Date(now.getTime() + hours * 3_600_000);
}

export function canRequestJoin(input: {
  inAlliance: boolean;
  cooldownUntil: Date | null;
  now: Date;
  memberCount: number;
  maxMembers: number;
  alreadyPending: boolean;
}): RuleCheck {
  if (input.inAlliance) return { ok: false, reason: 'ERR_ALLIANCE_ALREADY_MEMBER' };
  if (input.cooldownUntil && input.cooldownUntil > input.now) return { ok: false, reason: 'ERR_ALLIANCE_COOLDOWN' };
  if (input.alreadyPending) return { ok: false, reason: 'ERR_ALLIANCE_REQUEST_PENDING' };
  if (input.memberCount >= input.maxMembers) return { ok: false, reason: 'ERR_ALLIANCE_FULL' };
  return { ok: true };
}

export type ManageAction = 'APPROVE' | 'REJECT' | 'PROMOTE' | 'DEMOTE' | 'KICK' | 'TRANSFER' | 'NOTICE' | 'UPGRADE' | 'DISBAND';

/**
 * Role matrix for alliance management. `targetRole` is null for actions that do
 * not touch another member (notice board, tech upgrade, disband).
 */
export function canManageMember(actorRole: unknown, action: ManageAction, targetRole?: unknown): RuleCheck {
  const actor = roleRank(actorRole);
  if (actor < ROLE_RANK.MEMBER) return { ok: false, reason: 'ERR_ALLIANCE_NOT_MEMBER' };

  if (action === 'APPROVE' || action === 'REJECT' || action === 'NOTICE') {
    if (actor < ROLE_RANK.OFFICER) return { ok: false, reason: 'ERR_ALLIANCE_ROLE_TOO_LOW' };
    return { ok: true };
  }
  if (action === 'UPGRADE' || action === 'DISBAND' || action === 'TRANSFER') {
    if (actor < ROLE_RANK.LEADER) return { ok: false, reason: 'ERR_ALLIANCE_LEADER_ONLY' };
    if (action === 'TRANSFER' && targetRole === null) return { ok: false, reason: 'ERR_ALLIANCE_TARGET_REQUIRED' };
    return { ok: true };
  }

  // PROMOTE / DEMOTE / KICK: never on yourself, never on someone above or equal to you.
  if (targetRole === undefined || targetRole === null) return { ok: false, reason: 'ERR_ALLIANCE_TARGET_REQUIRED' };
  const target = roleRank(targetRole);
  if (target === 0) return { ok: false, reason: 'ERR_ALLIANCE_TARGET_REQUIRED' };
  if (actor < ROLE_RANK.OFFICER) return { ok: false, reason: 'ERR_ALLIANCE_ROLE_TOO_LOW' };
  if (target >= actor) return { ok: false, reason: 'ERR_ALLIANCE_TARGET_ROLE_TOO_HIGH' };
  if (action === 'PROMOTE' && actor < ROLE_RANK.LEADER) return { ok: false, reason: 'ERR_ALLIANCE_LEADER_ONLY' };
  if (action === 'DEMOTE' && actor < ROLE_RANK.LEADER) return { ok: false, reason: 'ERR_ALLIANCE_LEADER_ONLY' };
  return { ok: true };
}

export function canLeave(allianceMemberCount: number, role: unknown): RuleCheck {
  if (roleRank(role) === 0) return { ok: false, reason: 'ERR_ALLIANCE_NOT_MEMBER' };
  if (role === 'LEADER' && allianceMemberCount > 1) return { ok: false, reason: 'ERR_ALLIANCE_LEADER_MUST_TRANSFER' };
  return { ok: true };
}

export function canUpgradeTech(input: { level: number; silver: bigint | number }): {
  ok: boolean;
  cost?: number;
  reason?: string;
} {
  if (input.level >= ALLIANCE_MAX_TECH_LEVEL) return { ok: false, reason: 'ERR_ALLIANCE_TECH_MAX' };
  const cost = techCost(input.level);
  if (Number(input.silver) < cost) return { ok: false, reason: 'ERR_ALLIANCE_INSUFFICIENT_SILVER' };
  return { ok: true, cost };
}

export function validateNotice(body: unknown): { ok: boolean; reason?: string; value?: string } {
  const notice = String(body ?? '').trim();
  if (notice.length > ALLIANCE_NOTICE_MAX) return { ok: false, reason: 'ERR_ALLIANCE_NOTICE_TOO_LONG' };
  return { ok: true, value: notice };
}

/** Chat accepts text, a coordinate ping, or both (an attached marker). */
export function validateChatMessage(input: { body?: unknown; coordinates?: unknown }): {
  ok: boolean;
  reason?: string;
  value?: { body: string; coordinates: { x: number; y: number } | null };
} {
  const body = String(input.body ?? '').trim();
  const raw = input.coordinates as { x?: unknown; y?: unknown } | null | undefined;
  const coordinates = raw && typeof raw === 'object' && raw.x !== undefined && raw.y !== undefined
    ? { x: Number(raw.x), y: Number(raw.y) }
    : null;

  if (coordinates) {
    if (!Number.isInteger(coordinates.x) || !Number.isInteger(coordinates.y)
      || coordinates.x < 0 || coordinates.x > 1000 || coordinates.y < 0 || coordinates.y > 1000) {
      return { ok: false, reason: 'ERR_ALLIANCE_PING_INVALID' };
    }
  }
  if (body.length > ALLIANCE_CHAT_MAX) return { ok: false, reason: 'ERR_ALLIANCE_CHAT_TOO_LONG' };
  if (body.length === 0 && !coordinates) return { ok: false, reason: 'ERR_ALLIANCE_CHAT_EMPTY' };
  return { ok: true, value: { body, coordinates } };
}

export function searchMatches(
  alliance: { name: string; tag: string; language: string; minCombatPower: number; memberCount: number; maxMembers: number },
  filters: { query?: string; language?: string; minCombatPower?: number; hasSlots?: boolean },
): boolean {
  const query = (filters.query ?? '').trim().toLowerCase();
  if (query && !alliance.name.toLowerCase().includes(query) && !alliance.tag.toLowerCase().includes(query)) return false;
  if (filters.language && filters.language !== alliance.language) return false;
  if (filters.minCombatPower !== undefined && alliance.minCombatPower > filters.minCombatPower) return false;
  if (filters.hasSlots && alliance.memberCount >= alliance.maxMembers) return false;
  return true;
}
