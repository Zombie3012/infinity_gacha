import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  ALLIANCE_CREATE_GEM_COST, ALLIANCE_CREATE_SILVER_COST, ALLIANCE_MAX_MEMBERS, ALLIANCE_MAX_TECH_LEVEL,
  canCreateAlliance, canLeave, canManageMember, canRequestJoin, canUpgradeTech, cooldownUntil,
  creationPayment, maxMembersForLevel, roleRank, searchMatches, techCost, validateAllianceIdentity,
  validateChatMessage, validateNotice,
} from '../dist/modules/world/alliance-rules.js';

const now = new Date('2026-11-04T00:00:00Z');

test('P3 Alliance - identity validation', async (t) => {
  await t.test('accepts a 3-20 character name and a 2-5 character tag', () => {
    const result = validateAllianceIdentity({ name: 'Bình Minh', tag: 'bm1', motto: 'Cùng tiến' });
    assert.equal(result.ok, true);
    assert.equal(result.value.tag, 'BM1');
    assert.equal(result.value.language, 'vi');
  });

  await t.test('rejects short names, bad tags and long mottos', () => {
    assert.equal(validateAllianceIdentity({ name: 'AB', tag: 'BM' }).reason, 'ERR_ALLIANCE_NAME_INVALID');
    assert.equal(validateAllianceIdentity({ name: 'Bình Minh', tag: 'B' }).reason, 'ERR_ALLIANCE_TAG_INVALID');
    assert.equal(validateAllianceIdentity({ name: 'Bình Minh', tag: 'B M' }).reason, 'ERR_ALLIANCE_TAG_INVALID');
    assert.equal(validateAllianceIdentity({ name: 'Bình Minh', tag: 'BM', motto: 'x'.repeat(121) }).reason, 'ERR_ALLIANCE_MOTTO_INVALID');
    assert.equal(validateAllianceIdentity({ name: 'Bình Minh', tag: 'BM', language: 'vietnamese1' }).reason, 'ERR_ALLIANCE_LANGUAGE_INVALID');
  });
});

test('P3 Alliance - founding rules', async (t) => {
  await t.test('needs no membership and no cooldown', () => {
    assert.equal(canCreateAlliance({ inAlliance: false, cooldownUntil: null, now }).ok, true);
    assert.equal(canCreateAlliance({ inAlliance: true, cooldownUntil: null, now }).reason, 'ERR_ALLIANCE_ALREADY_MEMBER');
    assert.equal(canCreateAlliance({
      inAlliance: false, cooldownUntil: new Date(now.getTime() + 60_000), now,
    }).reason, 'ERR_ALLIANCE_COOLDOWN');
  });

  await t.test('prefers Gems, falls back to Silver when the Gem balance is short', () => {
    assert.deepEqual(creationPayment({ gems: ALLIANCE_CREATE_GEM_COST, silver: 0 }), { ok: true, currency: 'GEM' });
    assert.deepEqual(creationPayment({ gems: 10, silver: ALLIANCE_CREATE_SILVER_COST }), { ok: true, currency: 'SILVER' });
    assert.deepEqual(creationPayment({ gems: 10, silver: 10 }), { ok: false, reason: 'ERR_ALLIANCE_INSUFFICIENT_FUNDS' });
  });

  await t.test('member cap grows by 10 per tech level up to 100', () => {
    assert.equal(maxMembersForLevel(1), 30);
    assert.equal(maxMembersForLevel(4), 60);
    assert.equal(maxMembersForLevel(ALLIANCE_MAX_TECH_LEVEL), ALLIANCE_MAX_MEMBERS);
    assert.equal(maxMembersForLevel(99), 100);
  });

  await t.test('tech upgrades cost Silver and stop at level 8', () => {
    assert.deepEqual(canUpgradeTech({ level: 1, silver: techCost(1) }), { ok: true, cost: techCost(1) });
    assert.equal(canUpgradeTech({ level: 2, silver: 1 }).reason, 'ERR_ALLIANCE_INSUFFICIENT_SILVER');
    assert.equal(canUpgradeTech({ level: ALLIANCE_MAX_TECH_LEVEL, silver: 10_000_000 }).reason, 'ERR_ALLIANCE_TECH_MAX');
  });
});

test('P3 Alliance - joining and cooldown', async (t) => {
  await t.test('join refuses duplicates, full guilds and active cooldowns', () => {
    const base = { inAlliance: false, cooldownUntil: null, now, memberCount: 1, maxMembers: 30, alreadyPending: false };
    assert.equal(canRequestJoin(base).ok, true);
    assert.equal(canRequestJoin({ ...base, alreadyPending: true }).reason, 'ERR_ALLIANCE_REQUEST_PENDING');
    assert.equal(canRequestJoin({ ...base, memberCount: 30 }).reason, 'ERR_ALLIANCE_FULL');
    assert.equal(canRequestJoin({ ...base, inAlliance: true }).reason, 'ERR_ALLIANCE_ALREADY_MEMBER');
    assert.equal(canRequestJoin({ ...base, cooldownUntil: new Date(now.getTime() + 1) }).reason, 'ERR_ALLIANCE_COOLDOWN');
  });

  await t.test('leaving starts a 24h cooldown', () => {
    assert.equal(cooldownUntil(now).getTime() - now.getTime(), 24 * 3_600_000);
  });

  await t.test('a leader with members must hand over before leaving', () => {
    assert.equal(canLeave(1, 'LEADER').ok, true);
    assert.equal(canLeave(4, 'LEADER').reason, 'ERR_ALLIANCE_LEADER_MUST_TRANSFER');
    assert.equal(canLeave(4, 'OFFICER').ok, true);
  });
});

test('P3 Alliance - member management hierarchy', async (t) => {
  const rank = roleRank('OFFICER');
  assert.equal(rank, 2);

  await t.test('officers approve requests and manage plain members only', () => {
    assert.equal(canManageMember('OFFICER', 'APPROVE').ok, true);
    assert.equal(canManageMember('OFFICER', 'KICK', 'MEMBER').ok, true);
    assert.equal(canManageMember('OFFICER', 'KICK', 'OFFICER').reason, 'ERR_ALLIANCE_TARGET_ROLE_TOO_HIGH');
    assert.equal(canManageMember('OFFICER', 'PROMOTE', 'MEMBER').reason, 'ERR_ALLIANCE_LEADER_ONLY');
  });

  await t.test('only the leader transfers leadership, disbands and upgrades tech', () => {
    assert.equal(canManageMember('OFFICER', 'TRANSFER', 'OFFICER').reason, 'ERR_ALLIANCE_LEADER_ONLY');
    assert.equal(canManageMember('LEADER', 'TRANSFER', 'MEMBER').ok, true);
    assert.equal(canManageMember('LEADER', 'DISBAND').ok, true);
    assert.equal(canManageMember('OFFICER', 'UPGRADE').reason, 'ERR_ALLIANCE_LEADER_ONLY');
    assert.equal(canManageMember('MEMBER', 'NOTICE').reason, 'ERR_ALLIANCE_ROLE_TOO_LOW');
    assert.equal(canManageMember(null, 'NOTICE').reason, 'ERR_ALLIANCE_NOT_MEMBER');
  });

  await t.test('leaders cannot demote themselves through the target rule', () => {
    assert.equal(canManageMember('LEADER', 'DEMOTE', 'LEADER').reason, 'ERR_ALLIANCE_TARGET_ROLE_TOO_HIGH');
  });
});

test('P3 Alliance - communication and search', async (t) => {
  await t.test('chat accepts text, coordinate pings and both', () => {
    assert.deepEqual(validateChatMessage({ body: 'Tấn công (500, 500)!' }).value,
      { body: 'Tấn công (500, 500)!', coordinates: null });
    assert.equal(validateChatMessage({ coordinates: { x: 500, y: 500 } }).value.coordinates.x, 500);
    assert.equal(validateChatMessage({}).reason, 'ERR_ALLIANCE_CHAT_EMPTY');
    assert.equal(validateChatMessage({ coordinates: { x: 1001, y: 0 } }).reason, 'ERR_ALLIANCE_PING_INVALID');
    assert.equal(validateChatMessage({ coordinates: { x: 1.5, y: 2 } }).reason, 'ERR_ALLIANCE_PING_INVALID');
    assert.equal(validateChatMessage({ body: 'x'.repeat(301) }).reason, 'ERR_ALLIANCE_CHAT_TOO_LONG');
  });

  await t.test('notice is bounded', () => {
    assert.equal(validateNotice('Chào mừng').value, 'Chào mừng');
    assert.equal(validateNotice('x'.repeat(501)).reason, 'ERR_ALLIANCE_NOTICE_TOO_LONG');
  });

  await t.test('search matches name or tag and can require a free slot', () => {
    const guild = { name: 'Bình Minh', tag: 'BM1', language: 'vi', minCombatPower: 5000, memberCount: 10, maxMembers: 30 };
    assert.equal(searchMatches(guild, { query: 'bình' }), true);
    assert.equal(searchMatches(guild, { query: 'bm1' }), true);
    assert.equal(searchMatches(guild, { query: 'other' }), false);
    assert.equal(searchMatches(guild, { language: 'en' }), false);
    assert.equal(searchMatches(guild, { minCombatPower: 6000 }), true);
    assert.equal(searchMatches(guild, { minCombatPower: 4000 }), false);
    assert.equal(searchMatches({ ...guild, memberCount: 30 }, { hasSlots: true }), false);
  });
});
