import { integer, pgTable, timestamp, unique, uniqueIndex, index, varchar, bigint, doublePrecision, boolean, jsonb, check, text, primaryKey } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
import type { PveLayout, PvePlan, PvePoint, PveExploration } from '@infiniti-gacha/shared';
import type { CombatV2Report } from '../modules/combat/combat-v2.engine.js';

export const accounts = pgTable('accounts', {
  id: varchar('id', { length: 36 }).primaryKey(),
  username: varchar('username', { length: 32 }).notNull().unique(),
  email: varchar('email', { length: 100 }).unique(),
  passwordHash: varchar('password_hash', { length: 255 }).notNull(),
  status: varchar('status', { length: 20 }).notNull().default('ACTIVE'),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_accounts_username_case_insensitive').on(sql`lower(${table.username})`),
  check('accounts_status_check', sql`${table.status} IN ('ACTIVE', 'SUSPENDED', 'BANNED')`),
]);

export const accountSessions = pgTable('account_sessions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  revokedAt: timestamp('revoked_at', { withTimezone: true }),
});

export const playerProfiles = pgTable('player_profiles', {
  accountId: varchar('account_id', { length: 36 }).primaryKey().references(() => accounts.id, { onDelete: 'cascade' }),
  displayName: varchar('display_name', { length: 32 }).notNull(),
  avatarUrl: varchar('avatar_url', { length: 255 }),
  settings: jsonb('settings').$type<{ language?: string; soundEnabled?: boolean; notificationsEnabled?: boolean }>().notNull().default(sql`'{}'::jsonb`),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

export const masters = pgTable('masters', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }).unique(),
  masterName: varchar('master_name', { length: 50 }).notNull(),
  level: integer('level').default(1).notNull(),
  exp: bigint('exp', { mode: 'bigint' }).default(sql`0`).notNull(),
  silverCoins: bigint('silver_coins', { mode: 'bigint' }).default(sql`10000`).notNull(),
  gems: bigint('gems', { mode: 'bigint' }).default(sql`0`).notNull(),
  gemDebt: bigint('gem_debt', { mode: 'bigint' }).default(sql`0`).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

export const worlds = pgTable('worlds', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  worldSeed: varchar('world_seed', { length: 36 }).notNull().unique(),
  seedAlgorithmVersion: integer('seed_algorithm_version').default(1).notNull(),
  difficultyMultiplier: doublePrecision('difficulty_multiplier').default(1).notNull(),
  currentFloor: integer('current_floor').default(1).notNull(),
  pveRun: integer('pve_run').default(0).notNull(),
  baseZones: integer('base_zones').default(1).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const banners = pgTable('banners', {
  id: varchar('id', { length: 36 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  bannerType: varchar('banner_type', { length: 20 }).notNull(),
  isActive: boolean('is_active').default(true).notNull(),
  startDate: timestamp('start_date', { withTimezone: true }).defaultNow().notNull(),
  endDate: timestamp('end_date', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

// Historical schema retained for existing databases. Flat-rate summons do not read or update it.
export const masterBannerPity = pgTable('master_banner_pity', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  bannerId: varchar('banner_id', { length: 36 }).notNull().references(() => banners.id, { onDelete: 'cascade' }),
  pityCounter: integer('pity_counter').default(0).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_master_banner').on(table.masterId, table.bannerId)]);

export const masterSummonInventory = pgTable('master_summon_inventory', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  scrollType: varchar('scroll_type', { length: 20 }).notNull(),
  quantity: integer('quantity').default(0).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_master_scroll_type').on(table.masterId, table.scrollType)]);

export const weeklyScrollExchanges = pgTable('weekly_scroll_exchanges', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  periodKey: varchar('period_key', { length: 10 }).notNull(),
  quantity: integer('quantity').default(0).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_master_weekly_exchange').on(table.masterId, table.periodKey)]);

export const currencyTransactions = pgTable('currency_transactions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  currencyType: varchar('currency_type', { length: 20 }).notNull(),
  amountDelta: bigint('amount_delta', { mode: 'bigint' }).notNull(),
  transactionType: varchar('transaction_type', { length: 30 }).notNull(),
  referenceId: varchar('reference_id', { length: 36 }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const heroTemplates = pgTable('hero_templates', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  defaultRarity: integer('default_rarity').notNull(),
  heroClass: varchar('hero_class', { length: 30 }).notNull(),
  element: varchar('element', { length: 20 }).notNull(),
  baseHp: integer('base_hp').notNull(),
  baseAttack: integer('base_atk').notNull(),
  baseDefense: integer('base_def').notNull(),
  baseSpeed: integer('base_spd').notNull(),
  // Combat v2: the four base stats and the archetype used by the summon roll.
  baseStr: integer('base_str').default(0).notNull(),
  baseInt: integer('base_int').default(0).notNull(),
  baseSta: integer('base_sta').default(0).notNull(),
  baseAgi: integer('base_agi').default(0).notNull(),
  archetypeWeights: jsonb('archetype_weights').$type<{ str: number; int: number; sta: number; agi: number }>()
    .notNull().default({ str: 0.25, int: 0.25, sta: 0.25, agi: 0.25 }),
  classOptions: jsonb('class_options').$type<string[]>(),
  classCode: varchar('class_code', { length: 20 }).default('UNCLASSIFIED').notNull(),
  combatRole: varchar('combat_role', { length: 20 }).default('PHYSICAL_DPS').notNull(),
  isEnabled: boolean('is_enabled').default(true).notNull(),
});

export const summonRewardPool = pgTable('summon_reward_pool', {
  id: varchar('id', { length: 36 }).primaryKey(),
  bannerId: varchar('banner_id', { length: 36 }).notNull().references(() => banners.id, { onDelete: 'cascade' }),
  rewardId: varchar('reward_id', { length: 50 }).notNull(),
  rewardName: varchar('reward_name', { length: 100 }).notNull(),
  rewardType: varchar('reward_type', { length: 20 }).notNull(),
  poolGroup: varchar('pool_group', { length: 30 }).notNull(),
  heroTemplateCode: varchar('hero_template_code', { length: 50 }).references(() => heroTemplates.code),
  rarity: integer('rarity'),
  weight: integer('weight').notNull(),
  isActive: boolean('is_active').default(true).notNull(),
}, (table) => [unique('uq_banner_reward_group').on(table.bannerId, table.rewardId, table.poolGroup)]);

export const heroes = pgTable('heroes', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  configId: varchar('config_id', { length: 50 }).notNull(),
  name: varchar('name', { length: 100 }).notNull(),
  rarity: integer('rarity').notNull(),
  category: varchar('category', { length: 20 }).notNull().default('HERO'),
  state: varchar('state', { length: 20 }).default('HEALTHY').notNull(),
  level: integer('level').default(1).notNull(),
  exp: bigint('exp', { mode: 'bigint' }).default(sql`0`).notNull(),
  hp: integer('hp').notNull(),
  maxHp: integer('max_hp').notNull(),
  attack: integer('attack').notNull(),
  defense: integer('defense').notNull(),
  speed: integer('speed').notNull(),
  // Combat v2: persisted base stats, class and resource percentages.
  baseStr: integer('base_str').default(0).notNull(),
  baseInt: integer('base_int').default(0).notNull(),
  baseSta: integer('base_sta').default(0).notNull(),
  baseAgi: integer('base_agi').default(0).notNull(),
  classCode: varchar('class_code', { length: 20 }).default('UNCLASSIFIED').notNull(),
  combatRole: varchar('combat_role', { length: 20 }).default('PHYSICAL_DPS').notNull(),
  trainingStats: jsonb('training_stats').$type<{ str: number; int: number; sta: number; agi: number }>()
    .notNull().default({ str: 0, int: 0, sta: 0, agi: 0 }),
  /** Level-1 rolled stats; keeps level/class changes reproducible. */
  originStats: jsonb('origin_stats').$type<{ str: number; int: number; sta: number; agi: number }>()
    .notNull().default({ str: 0, int: 0, sta: 0, agi: 0 }),
  mp: integer('mp').default(0).notNull(),
  maxMp: integer('max_mp').default(0).notNull(),
  currentHpPct: doublePrecision('current_hp_pct').default(1).notNull(),
  currentMpPct: doublePrecision('current_mp_pct').default(1).notNull(),
  talentPoints: integer('talent_points').default(0).notNull(),
  thienMenh: integer('thien_menh').default(0).notNull(),
  hunger: integer('hunger').default(0).notNull(),
  fatigue: integer('fatigue').default(0).notNull(),
  loyalty: integer('loyalty').default(100).notNull(),
  isLocked: boolean('is_locked').default(false).notNull(),
  promotionRank: integer('promotion_rank').default(0).notNull(),
  awakeningRank: integer('awakening_rank').default(0).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});

// --- Combat v2: class, subclass and Mage element affinity catalogues ---

export const heroClassDefinitions = pgTable('hero_class_definitions', {
  code: varchar('code', { length: 20 }).primaryKey(),
  name: varchar('name', { length: 50 }).notNull(),
  baseCritRate: doublePrecision('base_crit_rate').notNull().default(5),
  growthStr: doublePrecision('growth_str').notNull().default(1),
  growthInt: doublePrecision('growth_int').notNull().default(1),
  growthSta: doublePrecision('growth_sta').notNull().default(1),
  growthAgi: doublePrecision('growth_agi').notNull().default(1),
  passive: varchar('passive', { length: 300 }).notNull().default(''),
  isEnabled: boolean('is_enabled').default(true).notNull(),
});

export const subclassDefinitions = pgTable('subclass_definitions', {
  code: varchar('code', { length: 30 }).primaryKey(),
  name: varchar('name', { length: 50 }).notNull(),
  primaryStat: varchar('primary_stat', { length: 10 }).notNull(),
  requiredValue: integer('required_value').notNull(),
  requiredLevel: integer('required_level').default(20).notNull(),
  effect: varchar('effect', { length: 300 }).notNull().default(''),
  isEnabled: boolean('is_enabled').default(true).notNull(),
});

export const heroSubclasses = pgTable('hero_subclasses', {
  id: varchar('id', { length: 36 }).primaryKey(),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  subclassCode: varchar('subclass_code', { length: 30 }).notNull().references(() => subclassDefinitions.code, { onDelete: 'cascade' }),
  acquiredAt: timestamp('acquired_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_hero_subclass').on(table.heroId, table.subclassCode)]);

/** Mage-only affinity table; non-Mage Heroes keep no row. */
export const heroElementAffinities = pgTable('hero_element_affinities', {
  heroId: varchar('hero_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  fire: integer('fire').default(0).notNull(),
  water: integer('water').default(0).notNull(),
  wind: integer('wind').default(0).notNull(),
  earth: integer('earth').default(0).notNull(),
  light: integer('light').default(0).notNull(),
  dark: integer('dark').default(0).notNull(),
  lightning: integer('lightning').default(0).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('hero_affinity_range', sql`
    ${table.fire} BETWEEN 0 AND 100 AND ${table.water} BETWEEN 0 AND 100
    AND ${table.wind} BETWEEN 0 AND 100 AND ${table.earth} BETWEEN 0 AND 100
    AND ${table.light} BETWEEN 0 AND 100 AND ${table.dark} BETWEEN 0 AND 100
    AND ${table.lightning} BETWEEN 0 AND 100`),
]);

// --- Combat v2: imprints (Awakening content) ---

export const imprintDefinitions = pgTable('imprint_definitions', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  rank: varchar('rank', { length: 2 }).notNull(),
  tier: integer('tier').default(1).notNull(),
  bonusStr: integer('bonus_str').default(0).notNull(),
  bonusInt: integer('bonus_int').default(0).notNull(),
  bonusSta: integer('bonus_sta').default(0).notNull(),
  bonusAgi: integer('bonus_agi').default(0).notNull(),
  bonusHp: integer('bonus_hp').default(0).notNull(),
  bonusAtk: integer('bonus_atk').default(0).notNull(),
  bonusDef: integer('bonus_def').default(0).notNull(),
  ability: varchar('ability', { length: 300 }).notNull().default(''),
  abilityCode: varchar('ability_code', { length: 40 }).notNull().default(''),
  abilityParams: jsonb('ability_params').$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
  isEnabled: boolean('is_enabled').default(true).notNull(),
}, (table) => [
  check('imprint_rank_check', sql`${table.rank} IN ('S', 'A', 'B')`),
  index('idx_imprint_rank').on(table.rank, table.tier),
]);

export const heroImprints = pgTable('hero_imprints', {
  id: varchar('id', { length: 36 }).primaryKey(),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  imprintCode: varchar('imprint_code', { length: 50 }).notNull().references(() => imprintDefinitions.code, { onDelete: 'cascade' }),
  rankLevel: integer('rank_level').default(1).notNull(),
  acquiredAt: timestamp('acquired_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_hero_imprint').on(table.heroId, table.imprintCode)]);

export const equipmentTemplates = pgTable('equipment_templates', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  slotType: varchar('slot_type', { length: 30 }).notNull(),
  rarity: integer('rarity').notNull().default(1),
  bonusHp: integer('bonus_hp').notNull().default(0),
  bonusAttack: integer('bonus_atk').notNull().default(0),
  bonusDefense: integer('bonus_def').notNull().default(0),
  bonusSpeed: integer('bonus_spd').notNull().default(0),
  // Combat v2 base stats & derived additions
  bonusStr: integer('bonus_str').notNull().default(0),
  bonusInt: integer('bonus_int').notNull().default(0),
  bonusSta: integer('bonus_sta').notNull().default(0),
  bonusAgi: integer('bonus_agi').notNull().default(0),
  bonusMatk: integer('bonus_matk').notNull().default(0),
  bonusMdef: integer('bonus_mdef').notNull().default(0),
  v2Stats: jsonb('v2_stats').$type<Record<string, number>>().notNull().default(sql`'{}'::jsonb`),
  isSample: boolean('is_sample').notNull().default(true),
});

export const equipmentInstances = pgTable('equipment_instances', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  templateCode: varchar('template_code', { length: 50 }).notNull().references(() => equipmentTemplates.code),
  equippedHeroId: varchar('equipped_hero_id', { length: 36 }).references(() => heroes.id, { onDelete: 'set null' }),
  location: varchar('location', { length: 20 }).notNull().default('INVENTORY'),
  dropWorldId: varchar('drop_world_id', { length: 36 }).references(() => worlds.id, { onDelete: 'set null' }),
  dropFloor: integer('drop_floor'),
  droppedAt: timestamp('dropped_at', { withTimezone: true }),
  pickedUpAt: timestamp('picked_up_at', { withTimezone: true }),
  starLevel: integer('star_level').default(1).notNull(),
  enhanceLevel: integer('enhance_level').default(0).notNull(),
  statMultiplier: doublePrecision('stat_multiplier').default(1).notNull(),
  substats: jsonb('substats').$type<{ hp: number; attack: number; defense: number; speed: number }>()
    .notNull().default(sql`'{"hp":0,"attack":0,"defense":0,"speed":0}'::jsonb`),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('ck_equipment_location', sql`${table.location} IN ('INVENTORY', 'EQUIPPED', 'FLOOR_DROP')`),
  check('ck_equipment_location_links', sql`(${table.location} = 'EQUIPPED' AND ${table.equippedHeroId} IS NOT NULL) OR (${table.location} <> 'EQUIPPED' AND ${table.equippedHeroId} IS NULL)`),
  index('idx_equipment_master_location').on(table.masterId, table.location),
  index('idx_equipment_floor_drop').on(table.dropWorldId, table.dropFloor),
]);

export const masterItems = pgTable('master_items', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  itemId: varchar('item_id', { length: 50 }).notNull(),
  quantity: integer('quantity').default(0).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_master_item').on(table.masterId, table.itemId)]);

export const summonSessions = pgTable('summon_sessions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  bannerId: varchar('banner_id', { length: 36 }).notNull().references(() => banners.id),
  scrollType: varchar('scroll_type', { length: 20 }).notNull(),
  rollCount: integer('roll_count').notNull(),
  pityBefore: integer('pity_before').notNull(),
  pityAfter: integer('pity_after').notNull(),
  idempotencyKey: varchar('idempotency_key', { length: 80 }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_master_summon_idempotency').on(table.masterId, table.idempotencyKey)]);

export const summonHistory = pgTable('summon_history', {
  id: varchar('id', { length: 36 }).primaryKey(),
  sessionId: varchar('session_id', { length: 36 }).notNull().references(() => summonSessions.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  bannerId: varchar('banner_id', { length: 36 }).notNull().references(() => banners.id),
  rollNumber: integer('roll_number').notNull(),
  pityNumber: integer('pity_number').notNull(),
  rewardType: varchar('reward_type', { length: 20 }).notNull(),
  rewardId: varchar('reward_id', { length: 50 }).notNull(),
  rewardName: varchar('reward_name', { length: 100 }).notNull(),
  rarity: integer('rarity').default(0).notNull(),
  wasFiveStar: boolean('was_five_star').default(false).notNull(),
  wasDuplicate: boolean('was_duplicate').default(false).notNull(),
  thienMenhGranted: integer('thien_menh_granted').default(0).notNull(),
  summonOrigin: varchar('summon_origin', { length: 20 }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [unique('uq_summon_session_roll').on(table.sessionId, table.rollNumber)]);

export const combatSessions = pgTable('combat_sessions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  worldId: varchar('world_id', { length: 36 }).notNull().references(() => worlds.id, { onDelete: 'cascade' }),
  partyId: varchar('party_id', { length: 36 }).references(() => masterParties.id, { onDelete: 'set null' }),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  activeBuffId: varchar('active_buff_id', { length: 40 }),
  lastBuffChangeAt: timestamp('last_buff_change_at', { withTimezone: true }),
  cooldownUntil: timestamp('cooldown_until', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  finishedAt: timestamp('finished_at', { withTimezone: true }),
  combatState: jsonb('combat_state').$type<Record<string, unknown>>(),
  battleReport: jsonb('battle_report').$type<Record<string, unknown>>(),
}, (table) => [uniqueIndex('uq_one_active_combat_per_master').on(table.masterId).where(sql`${table.status} = 'ACTIVE'`)]);


export const masterParties = pgTable('master_parties', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  name: varchar('name', { length: 60 }).notNull(),
  isDefault: boolean('is_default').notNull().default(false),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, table => [
  unique('uq_master_party_name').on(table.masterId, table.name),
  uniqueIndex('uq_master_default_party').on(table.masterId).where(sql`${table.isDefault} = true`),
]);

export const combatPartySlots = pgTable('combat_party_slots', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  partyId: varchar('party_id', { length: 36 }).notNull().references(() => masterParties.id, { onDelete: 'cascade' }),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  slotIndex: integer('slot_index').notNull(),
}, (table) => [
  unique('uq_combat_party_party_slot').on(table.partyId, table.slotIndex),
  unique('uq_combat_party_party_hero').on(table.partyId, table.heroId),
  check('ck_combat_party_slot_range', sql`${table.slotIndex} BETWEEN 0 AND 4`),
]);

export const enemyTemplates = pgTable('enemy_templates', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  baseHp: integer('base_hp').notNull(),
  baseAttack: integer('base_atk').notNull(),
  baseDefense: integer('base_def').notNull(),
  baseSpeed: integer('base_spd').notNull(),
  baseExpReward: integer('base_exp_reward').notNull(),
  baseSilverReward: integer('base_silver_reward').notNull(),
  isActive: boolean('is_active').default(true).notNull(),
  isBoss: boolean('is_boss').default(false).notNull(),
});


export const heroDeathRecords = pgTable('hero_death_records', {
  id: varchar('id', { length: 36 }).primaryKey(),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  combatSessionId: varchar('combat_session_id', { length: 36 }).notNull().references(() => combatSessions.id, { onDelete: 'cascade' }),
  summonOrigin: varchar('summon_origin', { length: 20 }).notNull(),
  deathType: varchar('death_type', { length: 20 }).notNull(),
  droppedEquipment: jsonb('dropped_equipment').$type<unknown[]>().default([]).notNull(),
  cause: varchar('cause', { length: 100 }).notNull(),
  recordedAt: timestamp('recorded_at', { withTimezone: true }).defaultNow().notNull(),
});



export const dungeonEventTemplates = pgTable('dungeon_event_templates', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  description: varchar('description', { length: 250 }).notNull(),
  eventType: varchar('event_type', { length: 20 }).notNull(),
  weight: integer('weight').notNull(),
  silverReward: integer('silver_reward').notNull().default(0),
  healPercent: doublePrecision('heal_percent').notNull().default(0),
  enemyAttackMultiplier: doublePrecision('enemy_attack_multiplier').notNull().default(1),
  isActive: boolean('is_active').default(true).notNull(),
});


export const heroLevelConfigs = pgTable('hero_level_configs', {
  level: integer('level').primaryKey(),
  cumulativeExpRequired: bigint('cumulative_exp_required', { mode: 'bigint' }).notNull(),
  statGrowthMultiplier: doublePrecision('stat_growth_multiplier').notNull().default(1.05),
  isSample: boolean('is_sample').notNull().default(true),
});

export const heroDevelopmentConfigs = pgTable('hero_development_configs', {
  id: varchar('id', { length: 36 }).primaryKey(),
  action: varchar('action', { length: 20 }).notNull(),
  rank: integer('rank').notNull(),
  materialItemId: varchar('material_item_id', { length: 50 }).notNull(),
  materialQuantity: integer('material_quantity').notNull(),
  requiredHeroLevel: integer('required_hero_level').notNull().default(1),
  requiredPromotionRank: integer('required_promotion_rank').notNull().default(0),
  maxLevelAfter: integer('max_level_after').notNull().default(20),
  statGrowthMultiplier: doublePrecision('stat_growth_multiplier').notNull().default(1),
  isSample: boolean('is_sample').notNull().default(true),
}, table => [unique('uq_hero_development_action_rank').on(table.action, table.rank)]);

export const masterLevelConfigs = pgTable('master_level_configs', {
  level: integer('level').primaryKey(),
  expRequired: bigint('exp_required', { mode: 'bigint' }).notNull(),
  isSample: boolean('is_sample').notNull().default(true),
});

export const masterSkillTemplates = pgTable('master_skill_templates', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  description: varchar('description', { length: 500 }).notNull(),
  unlockLevel: integer('unlock_level').notNull().default(1),
  durationSeconds: integer('duration_seconds').notNull(),
  healMaxHpPercentPerSecond: doublePrecision('heal_max_hp_percent_per_second').notNull(),
  cooldownSeconds: integer('cooldown_seconds').notNull().default(15),
  isActive: boolean('is_active').notNull().default(true),
});

export const heroSkillTemplates = pgTable('hero_skill_templates', {
  code: varchar('code', { length: 50 }).primaryKey(),
  heroClass: varchar('hero_class', { length: 30 }).notNull(),
  name: varchar('name', { length: 100 }).notNull(),
  description: varchar('description', { length: 500 }).notNull(),
  effectType: varchar('effect_type', { length: 30 }).notNull(),
  effectValue: doublePrecision('effect_value').notNull(),
  upgradeIncrement: doublePrecision('upgrade_increment').notNull().default(0.1),
  cooldownSeconds: integer('cooldown_seconds').notNull().default(3),
  unlockLevel: integer('unlock_level').notNull().default(3),
  maxLevel: integer('max_level').notNull().default(5),
  isActive: boolean('is_active').notNull().default(true),
  isSample: boolean('is_sample').notNull().default(true),
});

export const heroSkillInstances = pgTable('hero_skill_instances', {
  id: varchar('id', { length: 36 }).primaryKey(),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  skillCode: varchar('skill_code', { length: 50 }).notNull().references(() => heroSkillTemplates.code, { onDelete: 'cascade' }),
  skillLevel: integer('skill_level').notNull().default(1),
  isUnlocked: boolean('is_unlocked').notNull().default(false),
  behaviorMode: varchar('behavior_mode', { length: 10 }).notNull().default('AUTO'),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, table => [unique('uq_hero_skill_instance').on(table.heroId, table.skillCode)]);

export const featureUnlockConfigs = pgTable('feature_unlock_configs', {
  featureCode: varchar('feature_code', { length: 50 }).primaryKey(),
  featureName: varchar('feature_name', { length: 100 }).notNull(),
  requiredMasterLevel: integer('required_master_level').notNull().default(1),
  isActive: boolean('is_active').notNull().default(true),
});


export const dungeonTemplates = pgTable('dungeon_templates', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 100 }).notNull(),
  description: text('description').notNull(),
  totalFloors: integer('total_floors').default(10).notNull(),
  minMasterLevel: integer('min_master_level').default(1).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const dungeonFloors = pgTable('dungeon_floors', {
  id: varchar('id', { length: 36 }).primaryKey(),
  dungeonTemplateId: varchar('dungeon_template_id', { length: 36 }).notNull().references(() => dungeonTemplates.id, { onDelete: 'cascade' }),
  floorNumber: integer('floor_number').notNull(),
  name: varchar('name', { length: 100 }).notNull(),
  recommendedPower: integer('recommended_power').default(100).notNull(),
  unlockRequirements: jsonb('unlock_requirements').$type<{
    requiredMasterLevel?: number;
    previousFloorCleared?: boolean;
  }>().default({}).notNull(),
  baseRewards: jsonb('base_rewards').$type<{
    silver: number;
    masterExp: number;
    dropItems?: { itemCode: string; dropRate: number; minQuantity: number; maxQuantity: number }[];
  }>().default({ silver: 100, masterExp: 300 }).notNull(),
  firstClearRewards: jsonb('first_clear_rewards').$type<{
    silver?: number;
    normalScrolls?: number;
    specialScrolls?: number;
  }>().default({}).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const dungeonInstances = pgTable('dungeon_instances', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  worldId: varchar('world_id', { length: 36 }).notNull().references(() => worlds.id, { onDelete: 'cascade' }),
  dungeonFloorId: varchar('dungeon_floor_id', { length: 36 }).notNull().references(() => dungeonFloors.id, { onDelete: 'cascade' }),
  worldSeed: varchar('world_seed', { length: 36 }).notNull(),
  seedAlgorithmVersion: integer('seed_algorithm_version').default(1).notNull(),
  floorNumber: integer('floor_number').notNull(),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  currentRoomIndex: integer('current_room_index').default(0).notNull(),
  floorState: jsonb('floor_state').$type<{
    rooms: {
      roomIndex: number;
      roomType: 'COMBAT' | 'EVENT' | 'REST' | 'BOSS';
      cleared: boolean;
      eventCode?: string;
      foes?: { code: string; name: string; hp: number; maxHp: number; attack: number; defense: number; speed: number; element?: string }[];
    }[];
    difficultyMultiplier: number;
  }>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  completedAt: timestamp('completed_at', { withTimezone: true }),
});

// --- Domain 14: system administration, audit and security ---

export const systemConfigs = pgTable('system_configs', {
  id: varchar('id', { length: 36 }).primaryKey(),
  configKey: varchar('config_key', { length: 100 }).notNull(),
  version: integer('version').notNull(),
  configValue: jsonb('config_value').$type<Record<string, unknown>>().notNull(),
  isActive: boolean('is_active').notNull().default(false),
  updatedBy: varchar('updated_by', { length: 64 }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_system_configs_key_version').on(table.configKey, table.version),
  uniqueIndex('uq_system_configs_active_key').on(table.configKey).where(sql`${table.isActive} = true`),
]);

export const auditLogs = pgTable('audit_logs', {
  id: varchar('id', { length: 36 }).primaryKey(),
  actorId: varchar('actor_id', { length: 64 }).notNull(),
  actorType: varchar('actor_type', { length: 20 }).notNull(),
  action: varchar('action', { length: 100 }).notNull(),
  entityType: varchar('entity_type', { length: 50 }).notNull(),
  entityId: varchar('entity_id', { length: 64 }).notNull(),
  diffPayload: jsonb('diff_payload').$type<Record<string, unknown>>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_audit_logs_created_at').on(table.createdAt),
  index('idx_audit_logs_entity').on(table.entityType, table.entityId),
  index('idx_audit_logs_action').on(table.action),
]);

export const securityAlerts = pgTable('security_alerts', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }),
  signal: varchar('signal', { length: 50 }).notNull(),
  severity: varchar('severity', { length: 10 }).notNull(),
  status: varchar('status', { length: 20 }).notNull().default('OPEN'),
  details: jsonb('details').$type<Record<string, unknown>>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  resolvedBy: varchar('resolved_by', { length: 64 }),
}, (table) => [
  index('idx_security_alerts_account').on(table.accountId, table.createdAt),
  check('security_alerts_severity_check', sql`${table.severity} IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')`),
  check('security_alerts_status_check', sql`${table.status} IN ('OPEN', 'RESOLVED')`),
]);

// --- Domain 08 (P1): base, construction and production ---

export const buildingTypes = pgTable('building_types', {
  code: varchar('code', { length: 40 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  category: varchar('category', { length: 20 }).notNull(),
  description: text('description').notNull(),
  maxLevel: integer('max_level').default(5).notNull(),
  maxWorkers: integer('max_workers').default(0).notNull(),
  requiredWorldLevel: integer('required_world_level').default(1).notNull(),
  buildCostSilver: integer('build_cost_silver').notNull(),
  production: jsonb('production').$type<{ resourceType: string; ratePerHour: number; capacity: number } | null>(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const baseBuildings = pgTable('base_buildings', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  buildingType: varchar('building_type', { length: 40 }).notNull().references(() => buildingTypes.code),
  plotIndex: integer('plot_index').notNull(),
  level: integer('level').default(1).notNull(),
  durability: integer('durability').default(100).notNull(),
  status: varchar('status', { length: 20 }).default('READY').notNull(),
  upgradeFinishesAt: timestamp('upgrade_finishes_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_base_buildings_plot').on(table.masterId, table.plotIndex),
]);

export const baseProductionNodes = pgTable('base_production_nodes', {
  id: varchar('id', { length: 36 }).primaryKey(),
  buildingId: varchar('building_id', { length: 36 }).notNull().unique().references(() => baseBuildings.id, { onDelete: 'cascade' }),
  resourceType: varchar('resource_type', { length: 30 }).notNull(),
  baseRatePerHour: doublePrecision('base_rate_per_hour').notNull(),
  currentStored: doublePrecision('current_stored').default(0).notNull(),
  maxCapacity: doublePrecision('max_capacity').notNull(),
  lastHarvestAt: timestamp('last_harvest_at', { withTimezone: true }).defaultNow().notNull(),
});

export const magicProductionNodes = pgTable('magic_production_nodes', {
  id: varchar('id', { length: 36 }).primaryKey(),
  buildingId: varchar('building_id', { length: 36 }).notNull().references(() => baseBuildings.id, { onDelete: 'cascade' }),
  wing: varchar('wing', { length: 30 }).notNull(),
  resourceType: varchar('resource_type', { length: 30 }).notNull(),
  baseRatePerHour: doublePrecision('base_rate_per_hour').notNull(),
  currentStored: doublePrecision('current_stored').default(0).notNull(),
  maxCapacity: doublePrecision('max_capacity').notNull(),
  lastHarvestAt: timestamp('last_harvest_at', { withTimezone: true }).defaultNow().notNull(),
}, table => [unique('uq_magic_production_wing').on(table.buildingId, table.wing)]);

export const buildingWorkerAssignments = pgTable('building_worker_assignments', {
  id: varchar('id', { length: 36 }).primaryKey(),
  buildingId: varchar('building_id', { length: 36 }).notNull().references(() => baseBuildings.id, { onDelete: 'cascade' }),
  heroInstanceId: varchar('hero_instance_id', { length: 36 }).notNull().unique().references(() => heroes.id, { onDelete: 'cascade' }),
  efficiencyBoost: doublePrecision('efficiency_boost').default(1).notNull(),
  assignedAt: timestamp('assigned_at', { withTimezone: true }).defaultNow().notNull(),
});

// --- Domain 09 (P1): hero survival (hunger, fatigue, food) ---

export const heroSurvivalStates = pgTable('hero_survival_states', {
  heroId: varchar('hero_instance_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  hungerScore: doublePrecision('hunger_score').default(0).notNull(),
  fatigueScore: doublePrecision('fatigue_score').default(0).notNull(),
  isResting: boolean('is_resting').default(false).notNull(),
  lastTickAt: timestamp('last_tick_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('hero_survival_hunger_range', sql`${table.hungerScore} >= 0 AND ${table.hungerScore} <= 100`),
  check('hero_survival_fatigue_range', sql`${table.fatigueScore} >= 0 AND ${table.fatigueScore} <= 100`),
]);

// --- Domain 04 (P1): injuries, medical treatments and resurrection ---

export const heroInjuries = pgTable('hero_injuries', {
  id: varchar('id', { length: 36 }).primaryKey(),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  severity: varchar('severity', { length: 20 }).notNull(),
  penaltyPercent: integer('penalty_percent').notNull(),
  naturalHealAt: timestamp('natural_heal_at', { withTimezone: true }).notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).defaultNow().notNull(),
  healedAt: timestamp('healed_at', { withTimezone: true }),
  healedBy: varchar('healed_by', { length: 20 }),
}, (table) => [
  index('idx_hero_injuries_hero').on(table.heroId, table.healedAt),
  check('hero_injuries_severity_check', sql`${table.severity} IN ('MINOR', 'MODERATE', 'SEVERE')`),
]);

export const heroTreatments = pgTable('hero_treatments', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  buildingId: varchar('building_id', { length: 36 }).references(() => baseBuildings.id, { onDelete: 'set null' }),
  injuryId: varchar('injury_id', { length: 36 }).references(() => heroInjuries.id, { onDelete: 'set null' }),
  treatmentType: varchar('treatment_type', { length: 20 }).notNull(),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).defaultNow().notNull(),
  finishesAt: timestamp('finishes_at', { withTimezone: true }),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  costSilver: bigint('cost_silver', { mode: 'bigint' }).default(sql`0`).notNull(),
  costItems: jsonb('cost_items').$type<Record<string, number>>().notNull().default({}),
}, (table) => [
  index('idx_hero_treatments_status').on(table.status, table.finishesAt),
  check('hero_treatments_type_check', sql`${table.treatmentType} IN ('INJURY', 'RESURRECTION')`),
  check('hero_treatments_status_check', sql`${table.status} IN ('ACTIVE', 'QUEUED', 'COMPLETED', 'CANCELLED')`),
]);

export const heroResurrectionCycles = pgTable('hero_resurrection_cycles', {
  heroId: varchar('hero_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  cycleStartAt: timestamp('cycle_start_at', { withTimezone: true }).defaultNow().notNull(),
  resurrectionCount: integer('resurrection_count').default(0).notNull(),
  lastResurrectedAt: timestamp('last_resurrected_at', { withTimezone: true }),
});

// --- Domain 03 (P1): personality, loyalty and relationships ---

export const heroPersonalityTraits = pgTable('hero_personality_traits', {
  heroId: varchar('hero_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  coreTrait: varchar('core_trait', { length: 30 }).notNull(),
  socialTrait: varchar('social_trait', { length: 30 }).notNull(),
  behavioralTrait: varchar('behavioral_trait', { length: 30 }).notNull(),
  specialTrait: varchar('special_trait', { length: 30 }).notNull(),
  favoriteFood: varchar('favorite_food', { length: 50 }).notNull(),
  loyaltyScore: integer('loyalty_score').default(50).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('hero_personality_loyalty_range', sql`${table.loyaltyScore} >= 0 AND ${table.loyaltyScore} <= 100`),
]);

export const heroRelationships = pgTable('hero_relationships', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  heroAId: varchar('hero_a_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  heroBId: varchar('hero_b_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  affinityPoints: integer('affinity_points').default(0).notNull(),
  lastInteractionAt: timestamp('last_interaction_at', { withTimezone: true }).defaultNow().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_hero_relationship_pair').on(table.heroAId, table.heroBId),
  index('idx_hero_relationship_master').on(table.masterId),
]);

// --- Domain 11 (P1): base shop and mailbox ---

export const shopItems = pgTable('shop_items', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  description: text('description').notNull(),
  itemId: varchar('item_id', { length: 50 }).notNull(),
  category: varchar('category', { length: 20 }).notNull(),
  priceSilver: bigint('price_silver', { mode: 'bigint' }).default(sql`1`).notNull(),
  dailyLimit: integer('daily_limit').default(0).notNull(),
  rotationDays: integer('rotation_days').array().notNull().default(sql`'{}'::integer[]`),
  isActive: boolean('is_active').default(true).notNull(),
  sortOrder: integer('sort_order').default(100).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const shopPurchaseLimits = pgTable('shop_purchase_limits', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  shopItemCode: varchar('shop_item_code', { length: 50 }).notNull(),
  periodKey: varchar('period_key', { length: 20 }).notNull(),
  quantity: integer('quantity').default(0).notNull(),
}, (table) => [
  uniqueIndex('uq_shop_purchase_limit').on(table.masterId, table.shopItemCode, table.periodKey),
]);

export const shopPurchases = pgTable('shop_purchases', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  idempotencyKey: varchar('idempotency_key', { length: 80 }).notNull(),
  itemCode: varchar('item_code', { length: 50 }).notNull(),
  quantity: integer('quantity').notNull(),
  result: jsonb('result').$type<Record<string, unknown>>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, table => [unique('uq_shop_purchase_key').on(table.masterId, table.idempotencyKey)]);

export const mailboxMessages = pgTable('mailbox_messages', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  sender: varchar('sender', { length: 30 }).notNull().default('SYSTEM'),
  subject: varchar('subject', { length: 150 }).notNull(),
  body: text('body').notNull(),
  attachments: jsonb('attachments').$type<{ silver?: number; items?: { itemId: string; quantity: number }[] }>().notNull().default({}),
  isClaimed: boolean('is_claimed').default(false).notNull(),
  claimedAt: timestamp('claimed_at', { withTimezone: true }),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_mailbox_master').on(table.masterId, table.isClaimed, table.expiresAt),
]);

// --- Domain 10 (P1): crafting, enhancement and fusion ---

export const craftingRecipes = pgTable('crafting_recipes', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  targetTemplateCode: varchar('target_template_code', { length: 50 }).notNull().references(() => equipmentTemplates.code),
  requiredForgeLevel: integer('required_forge_level').default(1).notNull(),
  requiredMaterials: jsonb('required_materials').$type<{ itemId: string; quantity: number }[]>().notNull(),
  craftFeeSilver: integer('craft_fee_silver').default(0).notNull(),
  isActive: boolean('is_active').default(true).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

// --- Domain 12 (P1): quests and achievements ---

export const questDefinitions = pgTable('quest_definitions', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 150 }).notNull(),
  description: text('description').notNull(),
  questType: varchar('quest_type', { length: 10 }).notNull(),
  objectiveType: varchar('objective_type', { length: 30 }).notNull(),
  targetCount: integer('target_count').default(1).notNull(),
  reward: jsonb('reward').$type<{ silver?: number; gems?: number; items?: { itemId: string; quantity: number }[] }>().notNull().default({}),
  requiredLevel: integer('required_level').default(1).notNull(),
  isActive: boolean('is_active').default(true).notNull(),
  sortOrder: integer('sort_order').default(100).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('quest_definitions_type_check', sql`${table.questType} IN ('MAIN', 'SIDE', 'DAILY', 'WEEKLY')`),
]);

export const questProgress = pgTable('quest_progress', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  questCode: varchar('quest_code', { length: 50 }).notNull().references(() => questDefinitions.code, { onDelete: 'cascade' }),
  periodKey: varchar('period_key', { length: 20 }).default('').notNull(),
  progress: integer('progress').default(0).notNull(),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  acceptedAt: timestamp('accepted_at', { withTimezone: true }).defaultNow().notNull(),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  claimedAt: timestamp('claimed_at', { withTimezone: true }),
}, (table) => [
  uniqueIndex('uq_quest_progress').on(table.masterId, table.questCode, table.periodKey),
  check('quest_progress_status_check', sql`${table.status} IN ('ACTIVE', 'COMPLETED', 'CLAIMED')`),
]);

export const achievements = pgTable('achievements', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 150 }).notNull(),
  description: text('description').notNull(),
  category: varchar('category', { length: 20 }).notNull(),
  metric: varchar('metric', { length: 30 }).notNull(),
  threshold: integer('threshold').notNull(),
  reward: jsonb('reward').$type<{ silver?: number; gems?: number; items?: { itemId: string; quantity: number }[] }>().notNull().default({}),
  isActive: boolean('is_active').default(true).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const achievementProgress = pgTable('achievement_progress', {
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  achievementCode: varchar('achievement_code', { length: 50 }).notNull().references(() => achievements.code, { onDelete: 'cascade' }),
  progress: integer('progress').default(0).notNull(),
  unlockedAt: timestamp('unlocked_at', { withTimezone: true }),
  claimedAt: timestamp('claimed_at', { withTimezone: true }),
}, (table) => [
  primaryKey({ columns: [table.masterId, table.achievementCode] }),
]);

// --- Domain 01 (P1): account linking and recovery ---

export const accountExternalIdentities = pgTable('account_external_identities', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }),
  provider: varchar('provider', { length: 20 }).notNull(),
  providerUserId: varchar('provider_user_id', { length: 128 }).notNull(),
  linkedAt: timestamp('linked_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_external_identity').on(table.provider, table.providerUserId),
  uniqueIndex('uq_account_provider').on(table.accountId, table.provider),
  check('account_external_identity_provider_check', sql`${table.provider} IN ('GOOGLE', 'APPLE')`),
]);

export const accountRecoveryTokens = pgTable('account_recovery_tokens', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }),
  tokenHash: varchar('token_hash', { length: 64 }).notNull(),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  usedAt: timestamp('used_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_recovery_tokens_account').on(table.accountId, table.expiresAt),
]);

// --- Domain 11 (P2): IAP packages, receipts and refunds ---

export const iapProducts = pgTable('iap_products', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  description: text('description').notNull(),
  priceCents: integer('price_cents').notNull(),
  currency: varchar('currency', { length: 3 }).default('USD').notNull(),
  gems: integer('gems').default(0).notNull(),
  silver: integer('silver').default(0).notNull(),
  items: jsonb('items').$type<{ itemId: string; quantity: number }[]>().notNull().default(sql`'[]'::jsonb`),
  isActive: boolean('is_active').default(true).notNull(),
  sortOrder: integer('sort_order').default(100).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

export const paymentTransactions = pgTable('payment_transactions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  productCode: varchar('product_code', { length: 50 }).notNull().references(() => iapProducts.code),
  store: varchar('store', { length: 10 }).notNull(),
  storeTransactionId: varchar('store_transaction_id', { length: 128 }),
  status: varchar('status', { length: 20 }).default('PENDING').notNull(),
  gems: integer('gems').default(0).notNull(),
  silver: integer('silver').default(0).notNull(),
  items: jsonb('items').$type<{ itemId: string; quantity: number }[]>().notNull().default(sql`'[]'::jsonb`),
  priceCents: integer('price_cents').default(0).notNull(),
  currency: varchar('currency', { length: 3 }).default('USD').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  refundedAt: timestamp('refunded_at', { withTimezone: true }),
  refundReason: text('refund_reason'),
}, (table) => [
  uniqueIndex('uq_payment_store_receipt').on(table.store, table.storeTransactionId),
  index('idx_payment_master').on(table.masterId, table.createdAt),
  check('payment_status_check', sql`${table.status} IN ('PENDING', 'COMPLETED', 'REFUNDED', 'FAILED')`),
  check('payment_store_check', sql`${table.store} IN ('APPLE', 'GOOGLE')`),
]);

// --- Domain 12 (P2): LiveOps events and dual PVE leaderboards ---

export const liveEvents = pgTable('live_events', {
  id: varchar('id', { length: 36 }).primaryKey(),
  code: varchar('code', { length: 50 }).notNull().unique(),
  name: varchar('name', { length: 150 }).notNull(),
  description: text('description').notNull(),
  eventType: varchar('event_type', { length: 10 }).notNull(),
  status: varchar('status', { length: 12 }).default('SCHEDULED').notNull(),
  startAt: timestamp('start_at', { withTimezone: true }).notNull(),
  endAt: timestamp('end_at', { withTimezone: true }).notNull(),
  claimDeadline: timestamp('claim_deadline', { withTimezone: true }).notNull(),
  activatedAt: timestamp('activated_at', { withTimezone: true }),
  closedAt: timestamp('closed_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  check('live_events_type_check', sql`${table.eventType} IN ('STANDARD', 'MAJOR', 'MINOR')`),
  check('live_events_status_check', sql`${table.status} IN ('SCHEDULED', 'ACTIVE', 'CLOSED')`),
]);

export const eventMissions = pgTable('event_missions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  eventId: varchar('event_id', { length: 36 }).notNull().references(() => liveEvents.id, { onDelete: 'cascade' }),
  code: varchar('code', { length: 50 }).notNull(),
  name: varchar('name', { length: 150 }).notNull(),
  objectiveType: varchar('objective_type', { length: 30 }).notNull(),
  targetCount: integer('target_count').default(1).notNull(),
  reward: jsonb('reward').$type<{ silver?: number; gems?: number; items?: { itemId: string; quantity: number }[] }>().notNull().default({}),
  sortOrder: integer('sort_order').default(100).notNull(),
}, (table) => [uniqueIndex('uq_event_mission_code').on(table.eventId, table.code)]);

export const eventMissionProgress = pgTable('event_mission_progress', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  missionId: varchar('mission_id', { length: 36 }).notNull().references(() => eventMissions.id, { onDelete: 'cascade' }),
  progress: integer('progress').default(0).notNull(),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  completedAt: timestamp('completed_at', { withTimezone: true }),
  claimedAt: timestamp('claimed_at', { withTimezone: true }),
}, (table) => [uniqueIndex('uq_event_mission_progress').on(table.masterId, table.missionId)]);

export const floorRecords = pgTable('floor_records', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  floor: integer('floor').notNull(),
  rounds: integer('rounds').notNull(),
  achievedAt: timestamp('achieved_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [uniqueIndex('uq_floor_record').on(table.masterId, table.floor)]);

export const leaderboardSeasons = pgTable('leaderboard_seasons', {
  id: varchar('id', { length: 36 }).primaryKey(),
  board: varchar('board', { length: 30 }).notNull(),
  periodKey: varchar('period_key', { length: 20 }).notNull(),
  status: varchar('status', { length: 12 }).default('OPEN').notNull(),
  closedAt: timestamp('closed_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  uniqueIndex('uq_leaderboard_season').on(table.board, table.periodKey),
  check('leaderboard_board_check', sql`${table.board} IN ('DUNGEON_PROGRESS', 'COMBAT_POWER')`),
]);

export const leaderboardRewards = pgTable('leaderboard_rewards', {
  id: varchar('id', { length: 36 }).primaryKey(),
  seasonId: varchar('season_id', { length: 36 }).notNull().references(() => leaderboardSeasons.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  rank: integer('rank').notNull(),
  score: integer('score').notNull(),
  reward: jsonb('reward').$type<{ silver?: number; gems?: number; items?: { itemId: string; quantity: number }[] }>().notNull().default({}),
  claimedAt: timestamp('claimed_at', { withTimezone: true }),
}, (table) => [uniqueIndex('uq_leaderboard_reward').on(table.seasonId, table.masterId)]);

// --- Domain 14 (P2): content catalogue (items) ---

export const itemTemplates = pgTable('item_templates', {
  code: varchar('code', { length: 50 }).primaryKey(),
  name: varchar('name', { length: 100 }).notNull(),
  category: varchar('category', { length: 30 }).notNull(),
  rarity: integer('rarity').default(1).notNull(),
  description: text('description').notNull().default(''),
  isActive: boolean('is_active').default(true).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
});

// --- Domain 14 (P2): customer support tickets ---

export const supportTickets = pgTable('support_tickets', {
  id: varchar('id', { length: 36 }).primaryKey(),
  accountId: varchar('account_id', { length: 36 }).notNull().references(() => accounts.id, { onDelete: 'cascade' }),
  subject: varchar('subject', { length: 150 }).notNull(),
  body: text('body').notNull(),
  category: varchar('category', { length: 30 }).default('GENERAL').notNull(),
  status: varchar('status', { length: 20 }).default('OPEN').notNull(),
  priority: varchar('priority', { length: 10 }).default('NORMAL').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
  closedAt: timestamp('closed_at', { withTimezone: true }),
}, (table) => [
  index('idx_support_tickets_status').on(table.status, table.createdAt),
  check('support_ticket_status_check', sql`${table.status} IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')`),
]);

export const supportTicketMessages = pgTable('support_ticket_messages', {
  id: varchar('id', { length: 36 }).primaryKey(),
  ticketId: varchar('ticket_id', { length: 36 }).notNull().references(() => supportTickets.id, { onDelete: 'cascade' }),
  authorType: varchar('author_type', { length: 10 }).notNull(),
  authorId: varchar('author_id', { length: 64 }).notNull(),
  body: text('body').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_support_messages_ticket').on(table.ticketId, table.createdAt),
  check('support_message_author_check', sql`${table.authorType} IN ('PLAYER', 'OPERATOR')`),
]);

// --- Domain 13 (P3): global world, exploration and territories ---

export const worldTiles = pgTable('world_tiles', {
  id: varchar('id', { length: 36 }).primaryKey(),
  x: integer('x').notNull(),
  y: integer('y').notNull(),
  terrain: varchar('terrain', { length: 30 }).notNull(),
  resourceType: varchar('resource_type', { length: 30 }).notNull(),
  baseYieldPerHour: doublePrecision('base_yield_per_hour').notNull(),
  requiredPower: integer('required_power').default(0).notNull(),
  isOuterRim: boolean('is_outer_rim').default(true).notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [uniqueIndex('uq_world_tile_coords').on(table.x, table.y)]);

export const masterWorldStatus = pgTable('master_world_status', {
  masterId: varchar('master_id', { length: 36 }).primaryKey().references(() => masters.id, { onDelete: 'cascade' }),
  unlockedAt: timestamp('unlocked_at', { withTimezone: true }).defaultNow().notNull(),
  baseX: integer('base_x').notNull(),
  baseY: integer('base_y').notNull(),
  shieldUntil: timestamp('shield_until', { withTimezone: true }).notNull(),
});

export const tileDiscoveries = pgTable('tile_discoveries', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  tileId: varchar('tile_id', { length: 36 }).notNull().references(() => worldTiles.id, { onDelete: 'cascade' }),
  discoveredAt: timestamp('discovered_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [uniqueIndex('uq_tile_discovery').on(table.masterId, table.tileId)]);

export const territories = pgTable('territories', {
  id: varchar('id', { length: 36 }).primaryKey(),
  tileId: varchar('tile_id', { length: 36 }).notNull().unique().references(() => worldTiles.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).references(() => masters.id, { onDelete: 'set null' }),
  level: integer('level').default(1).notNull(),
  status: varchar('status', { length: 20 }).default('OWNED').notNull(),
  claimedAt: timestamp('claimed_at', { withTimezone: true }).defaultNow().notNull(),
  protectedUntil: timestamp('protected_until', { withTimezone: true }),
  releaseAt: timestamp('release_at', { withTimezone: true }),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_territory_master').on(table.masterId),
  check('territory_status_check', sql`${table.status} IN ('OWNED', 'ABANDONING', 'UNOWNED')`),
]);

export const territoryEvents = pgTable('territory_events', {
  id: varchar('id', { length: 36 }).primaryKey(),
  tileId: varchar('tile_id', { length: 36 }).notNull().references(() => worldTiles.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).references(() => masters.id, { onDelete: 'set null' }),
  action: varchar('action', { length: 20 }).notNull(),
  detail: jsonb('detail').$type<Record<string, unknown>>().notNull().default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [index('idx_territory_events_tile').on(table.tileId, table.createdAt)]);

// --- Domain 13 (P3): hero expeditions (no army entity: heroes travel themselves) ---

export const heroExpeditions = pgTable('hero_expeditions', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  tileId: varchar('tile_id', { length: 36 }).notNull().references(() => worldTiles.id, { onDelete: 'cascade' }),
  mission: varchar('mission', { length: 20 }).notNull(),
  status: varchar('status', { length: 20 }).default('TRAVELING').notNull(),
  departAt: timestamp('depart_at', { withTimezone: true }).defaultNow().notNull(),
  arriveAt: timestamp('arrive_at', { withTimezone: true }).notNull(),
  returnAt: timestamp('return_at', { withTimezone: true }),
  result: jsonb('result').$type<Record<string, unknown>>().notNull().default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_expedition_master').on(table.masterId, table.status),
  check('expedition_mission_check', sql`${table.mission} IN ('SCOUT', 'ATTACK')`),
  check('expedition_status_check', sql`${table.status} IN ('TRAVELING', 'RETURNING', 'COMPLETED', 'RECALLED')`),
]);

export const expeditionMembers = pgTable('expedition_members', {
  id: varchar('id', { length: 36 }).primaryKey(),
  expeditionId: varchar('expedition_id', { length: 36 }).notNull().references(() => heroExpeditions.id, { onDelete: 'cascade' }),
  heroId: varchar('hero_id', { length: 36 }).notNull().references(() => heroes.id, { onDelete: 'cascade' }),
  slotIndex: integer('slot_index').default(0).notNull(),
}, (table) => [uniqueIndex('uq_expedition_hero').on(table.expeditionId, table.heroId)]);

export const tileClearances = pgTable('tile_clearances', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  tileId: varchar('tile_id', { length: 36 }).notNull().references(() => worldTiles.id, { onDelete: 'cascade' }),
  clearedAt: timestamp('cleared_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [uniqueIndex('uq_tile_clearance').on(table.masterId, table.tileId)]);

// --- Domain 13 (P3): hero-vs-hero PvP battles ---

export const pvpBattles = pgTable('pvp_battles', {
  id: varchar('id', { length: 36 }).primaryKey(),
  tileId: varchar('tile_id', { length: 36 }).notNull().references(() => worldTiles.id, { onDelete: 'cascade' }),
  attackerMasterId: varchar('attacker_master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  defenderMasterId: varchar('defender_master_id', { length: 36 }).references(() => masters.id, { onDelete: 'set null' }),
  expeditionId: varchar('expedition_id', { length: 36 }).references(() => heroExpeditions.id, { onDelete: 'set null' }),
  winner: varchar('winner', { length: 10 }).notNull(),
  attackerPower: integer('attacker_power').notNull(),
  defenderPower: integer('defender_power').notNull(),
  rounds: integer('rounds').default(0).notNull(),
  report: jsonb('report').$type<Record<string, unknown>>().notNull().default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_pvp_attacker').on(table.attackerMasterId, table.createdAt),
  index('idx_pvp_defender').on(table.defenderMasterId, table.createdAt),
  check('pvp_winner_check', sql`${table.winner} IN ('ATTACKER', 'DEFENDER')`),
]);

// --- Domain 13 (P3): alliances (MOD-13-06) ---

export const alliances = pgTable('alliances', {
  id: varchar('id', { length: 36 }).primaryKey(),
  name: varchar('name', { length: 50 }).notNull(),
  tag: varchar('tag', { length: 10 }).notNull(),
  emblemIcon: varchar('emblem_icon', { length: 100 }).default('⚔').notNull(),
  motto: varchar('motto', { length: 120 }).default('').notNull(),
  language: varchar('language', { length: 10 }).default('vi').notNull(),
  minCombatPower: integer('min_combat_power').default(0).notNull(),
  leaderMasterId: varchar('leader_master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  memberCount: integer('member_count').default(1).notNull(),
  maxMembers: integer('max_members').default(30).notNull(),
  allianceLevel: integer('alliance_level').default(1).notNull(),
  noticeBoard: text('notice_board').default('').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  unique('uq_alliance_name').on(table.name),
  unique('uq_alliance_tag').on(table.tag),
  index('idx_alliance_leader').on(table.leaderMasterId),
]);

export const allianceMembers = pgTable('alliance_members', {
  id: varchar('id', { length: 36 }).primaryKey(),
  allianceId: varchar('alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  role: varchar('role', { length: 20 }).default('MEMBER').notNull(),
  contributionPoints: bigint('contribution_points', { mode: 'bigint' }).default(sql`0`).notNull(),
  joinedAt: timestamp('joined_at', { withTimezone: true }).defaultNow().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  unique('uq_alliance_member_master').on(table.masterId),
  index('idx_alliance_members_alliance').on(table.allianceId),
  check('alliance_member_role_check', sql`${table.role} IN ('LEADER', 'OFFICER', 'MEMBER')`),
]);

export const allianceJoinRequests = pgTable('alliance_join_requests', {
  id: varchar('id', { length: 36 }).primaryKey(),
  allianceId: varchar('alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  status: varchar('status', { length: 20 }).default('PENDING').notNull(),
  message: varchar('message', { length: 200 }).default('').notNull(),
  resolvedBy: varchar('resolved_by', { length: 36 }).references(() => masters.id, { onDelete: 'set null' }),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_alliance_requests_pending').on(table.allianceId, table.status, table.createdAt),
  index('idx_alliance_requests_master').on(table.masterId, table.status),
  check('alliance_request_status_check', sql`${table.status} IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')`),
]);

/** 24h re-join lock after leaving or being removed from an alliance. */
export const allianceCooldowns = pgTable('alliance_cooldowns', {
  masterId: varchar('master_id', { length: 36 }).primaryKey().references(() => masters.id, { onDelete: 'cascade' }),
  expiresAt: timestamp('expires_at', { withTimezone: true }).notNull(),
  reason: varchar('reason', { length: 20 }).default('LEFT').notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [index('idx_alliance_cooldown_expiry').on(table.expiresAt)]);

export const allianceMessages = pgTable('alliance_messages', {
  id: varchar('id', { length: 36 }).primaryKey(),
  allianceId: varchar('alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  messageType: varchar('message_type', { length: 10 }).default('TEXT').notNull(),
  body: varchar('body', { length: 300 }).default('').notNull(),
  coordinates: jsonb('coordinates').$type<{ x: number; y: number } | null>(),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_alliance_messages_alliance').on(table.allianceId, table.createdAt),
  check('alliance_message_type_check', sql`${table.messageType} IN ('TEXT', 'PING')`),
]);

// --- Domain 13 (P3): world war and conquest (MOD-13-07) ---

export const allianceWars = pgTable('alliance_wars', {
  id: varchar('id', { length: 36 }).primaryKey(),
  declaringAllianceId: varchar('declaring_alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  targetAllianceId: varchar('target_alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  startedAt: timestamp('started_at', { withTimezone: true }).defaultNow().notNull(),
  endsAt: timestamp('ends_at', { withTimezone: true }).notNull(),
  declaringPoints: integer('declaring_points').default(0).notNull(),
  targetPoints: integer('target_points').default(0).notNull(),
  winnerAllianceId: varchar('winner_alliance_id', { length: 36 }).references(() => alliances.id, { onDelete: 'set null' }),
  resolvedAt: timestamp('resolved_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_alliance_wars_status').on(table.status, table.endsAt),
  index('idx_alliance_wars_declaring').on(table.declaringAllianceId),
  index('idx_alliance_wars_target').on(table.targetAllianceId),
  check('alliance_war_status_check', sql`${table.status} IN ('ACTIVE', 'RESOLVED', 'CANCELLED')`),
]);

export const warEngagements = pgTable('war_engagements', {
  id: varchar('id', { length: 36 }).primaryKey(),
  warId: varchar('war_id', { length: 36 }).notNull().references(() => allianceWars.id, { onDelete: 'cascade' }),
  attackerAllianceId: varchar('attacker_alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  defenderAllianceId: varchar('defender_alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).references(() => masters.id, { onDelete: 'set null' }),
  tileId: varchar('tile_id', { length: 36 }).references(() => worldTiles.id, { onDelete: 'set null' }),
  kind: varchar('kind', { length: 30 }).notNull(),
  points: integer('points').default(0).notNull(),
  detail: jsonb('detail').$type<Record<string, unknown>>().notNull().default({}),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_war_engagements_war').on(table.warId, table.createdAt),
  check('war_engagement_kind_check', sql`${table.kind} IN ('TERRITORY_CAPTURE', 'DEFENSE_HOLD', 'WONDER_SEIZURE', 'WAR_VICTORY')`),
]);

export const worldConquestSeasons = pgTable('world_conquest_seasons', {
  id: varchar('id', { length: 36 }).primaryKey(),
  seasonNumber: integer('season_number').notNull().unique(),
  startTime: timestamp('start_time', { withTimezone: true }).notNull(),
  endTime: timestamp('end_time', { withTimezone: true }).notNull(),
  status: varchar('status', { length: 20 }).default('ACTIVE').notNull(),
  conqueringAllianceId: varchar('conquering_alliance_id', { length: 36 }).references(() => alliances.id, { onDelete: 'set null' }),
  concludedAt: timestamp('concluded_at', { withTimezone: true }),
  createdAt: timestamp('created_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  index('idx_conquest_seasons_status').on(table.status, table.endTime),
  check('conquest_season_status_check', sql`${table.status} IN ('UPCOMING', 'ACTIVE', 'CONCLUDED')`),
]);

export const worldConquestRankings = pgTable('world_conquest_rankings', {
  id: varchar('id', { length: 36 }).primaryKey(),
  seasonId: varchar('season_id', { length: 36 }).notNull().references(() => worldConquestSeasons.id, { onDelete: 'cascade' }),
  allianceId: varchar('alliance_id', { length: 36 }).notNull().references(() => alliances.id, { onDelete: 'cascade' }),
  finalRank: integer('final_rank'),
  totalConquestPoints: integer('total_conquest_points').default(0).notNull(),
  rewardClaimed: boolean('reward_claimed').default(false).notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
}, (table) => [
  unique('uq_conquest_ranking').on(table.seasonId, table.allianceId),
  index('idx_conquest_rankings_points').on(table.seasonId, table.totalConquestPoints),
]);

/** Central Imperial Wonder control: an alliance holds the tile by accumulating continuous seconds. */
export const wonderHoldings = pgTable('wonder_holdings', {
  tileId: varchar('tile_id', { length: 36 }).primaryKey().references(() => worldTiles.id, { onDelete: 'cascade' }),
  allianceId: varchar('alliance_id', { length: 36 }).references(() => alliances.id, { onDelete: 'set null' }),
  heldSince: timestamp('held_since', { withTimezone: true }),
  accumulatedSeconds: integer('accumulated_seconds').default(0).notNull(),
  lastSettledAt: timestamp('last_settled_at', { withTimezone: true }),
  updatedAt: timestamp('updated_at', { withTimezone: true }).defaultNow().notNull(),
});


// --- Private PvE strategic maps (separate from global territories and legacy sessions) ---

export const heroChronicles = pgTable('hero_chronicles', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  heroId: varchar('hero_id', { length: 36 }).references(() => heroes.id, { onDelete: 'set null' }),
  name: varchar('name', { length: 100 }).notNull(),
  rarity: integer('rarity').notNull(),
  classCode: varchar('class_code', { length: 30 }).notNull(),
  biography: text('biography').notNull(),
  status: varchar('status', { length: 20 }).notNull().default('ALIVE'),
  summonedAt: timestamp('summoned_at', { withTimezone: true }).notNull(),
  events: jsonb('events').$type<{ type: string; at: string; floor?: number; referenceId?: string; detail?: string }[]>().notNull().default([]),
}, table => [
  index('idx_chronicle_master').on(table.masterId, table.summonedAt, table.id),
  unique('uq_chronicle_hero').on(table.heroId),
  check('ck_chronicle_rarity', sql`${table.rarity} BETWEEN 1 AND 7`),
  check('ck_chronicle_status', sql`${table.status} IN ('ALIVE','DEAD','SACRIFICED')`),
]);

export const pveFloorRules = pgTable('pve_floor_rules', {
  floor: integer('floor').primaryKey(),
  recallPolicy: varchar('recall_policy', { length: 30 }).notNull().default('FREE'),
}, table => [
  check('ck_pve_rule_floor', sql`${table.floor} >= 1`),
  check('ck_pve_rule_recall', sql`${table.recallPolicy} IN ('FREE', 'UNTIL_COMPLETE')`),
]);

export const pveMaps = pgTable('pve_maps', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  worldId: varchar('world_id', { length: 36 }).notNull().references(() => worlds.id, { onDelete: 'cascade' }),
  floor: integer('floor').notNull(),
  run: integer('run').default(0).notNull(),
  recallPolicy: varchar('recall_policy', { length: 30 }).notNull().default('FREE'),
  recallPoints: jsonb('recall_points').$type<{ areaId: string; x: number; y: number; createdBy: string }[]>().notNull().default([]),
  status: varchar('status', { length: 20 }).notNull().default('ACTIVE'),
  layout: jsonb('layout').$type<PveLayout>().notNull(),
  exploration: jsonb('exploration').$type<PveExploration>(),
  encounterCatalog: jsonb('encounter_catalog').$type<{
    code: string; name: string; hp: number; attack: number; defense: number; agi: number;
    silver: number; exp: number; boss: boolean;
  }[]>().notNull(),
  discovered: jsonb('discovered').$type<number[]>().notNull(),
  cleared: jsonb('cleared').$type<number[]>().notNull().default([]),
  collected: jsonb('collected').$type<number[]>().notNull().default([]),
  revision: integer('revision').notNull().default(0),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  clearedAt: timestamp('cleared_at', { withTimezone: true }),
}, table => [
  unique('uq_pve_world_floor_run').on(table.worldId, table.floor, table.run),
  uniqueIndex('uq_pve_active_master').on(table.masterId).where(sql`${table.status} = 'ACTIVE'`),
  index('idx_pve_map_master_latest').on(table.masterId, table.createdAt, table.id),
  check('ck_pve_map_status', sql`${table.status} IN ('ACTIVE', 'CLEARED', 'ABANDONED')`),
  check('ck_pve_map_recall', sql`${table.recallPolicy} IN ('FREE', 'UNTIL_COMPLETE')`),
  check('ck_pve_floor', sql`${table.floor} >= 1`),
]);

export const alchemyResearch = pgTable('alchemy_research', {
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  code: varchar('code', { length: 60 }).notNull(),
  researchedAt: timestamp('researched_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [unique('uq_alchemy_research').on(table.masterId, table.code)]);

export const heroConsumables = pgTable('hero_consumables', {
  heroId: varchar('hero_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  config: jsonb('config').$type<import('../modules/base/alchemy-rules.js').ConsumableConfig>().notNull(),
  squadId: varchar('squad_id', { length: 36 }),
  strengthReady: boolean('strength_ready').notNull().default(false),
});

export const pveConsumableDrops = pgTable('pve_consumable_drops', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  mapId: varchar('map_id', { length: 36 }).notNull().references(() => pveMaps.id, { onDelete: 'cascade' }),
  areaId: varchar('area_id', { length: 80 }).notNull(),
  x: integer('x').notNull(), y: integer('y').notNull(),
  items: jsonb('items').$type<{ itemId: string; quantity: number }[]>().notNull(),
});

export const pvePartyPlans = pgTable('pve_party_plans', {
  partyId: varchar('party_id', { length: 36 }).primaryKey().references(() => masterParties.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  plan: jsonb('plan').$type<PvePlan>().notNull(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
});

export const pveSquads = pgTable('pve_squads', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  mapId: varchar('map_id', { length: 36 }).notNull().references(() => pveMaps.id, { onDelete: 'cascade' }),
  partyId: varchar('party_id', { length: 36 }).references(() => masterParties.id, { onDelete: 'set null' }),
  name: varchar('name', { length: 60 }).notNull(),
  plan: jsonb('plan').$type<PvePlan>().notNull(),
  status: varchar('status', { length: 20 }).notNull().default('IDLE'),
  x: integer('x').notNull().default(0),
  y: integer('y').notNull().default(0),
  areaId: varchar('area_id', { length: 80 }).notNull().default('floor'),
  pendingPortalId: varchar('pending_portal_id', { length: 100 }),
  autoExplore: boolean('auto_explore').notNull().default(false),
  route: jsonb('route').$type<PvePoint[]>().notNull().default([]),
  nextStepAt: timestamp('next_step_at', { withTimezone: true }),
  lastBattleId: varchar('last_battle_id', { length: 36 }),
  deployedAt: timestamp('deployed_at', { withTimezone: true }).notNull().defaultNow(),
  withdrawnAt: timestamp('withdrawn_at', { withTimezone: true }),
}, table => [
  uniqueIndex('uq_pve_deployed_party').on(table.partyId).where(sql`${table.status} IN ('IDLE', 'MOVING', 'FIGHTING')`),
  index('idx_pve_due_steps').on(table.masterId, table.nextStepAt),
  index('idx_pve_squad_map_arrival').on(table.mapId, table.nextStepAt, table.id),
  check('ck_pve_squad_status', sql`${table.status} IN ('IDLE', 'MOVING', 'FIGHTING', 'WITHDRAWN', 'DEFEATED')`),
  check('ck_pve_squad_position', sql`${table.x} BETWEEN 0 AND 19 AND ${table.y} BETWEEN 0 AND 19`),
]);

// Authoritative exclusive reservations. Guard triggers also protect older mutation paths.
export const pveHeroReservations = pgTable('pve_hero_reservations', {
  heroId: varchar('hero_id', { length: 36 }).primaryKey().references(() => heroes.id, { onDelete: 'cascade' }),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  mapId: varchar('map_id', { length: 36 }).notNull().references(() => pveMaps.id, { onDelete: 'cascade' }),
  squadId: varchar('squad_id', { length: 36 }).notNull().references(() => pveSquads.id, { onDelete: 'cascade' }),
  reservedAt: timestamp('reserved_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [
  index('idx_pve_reservation_master').on(table.masterId),
  index('idx_pve_reservation_squad').on(table.squadId),
  index('idx_pve_reservation_map').on(table.mapId),
]);

export const pveBattles = pgTable('pve_battles', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  mapId: varchar('map_id', { length: 36 }).notNull().references(() => pveMaps.id, { onDelete: 'cascade' }),
  squadId: varchar('squad_id', { length: 36 }).notNull().references(() => pveSquads.id, { onDelete: 'cascade' }),
  tileId: integer('tile_id').notNull(),
  combatSessionId: varchar('combat_session_id', { length: 36 }).notNull().unique().references(() => combatSessions.id, { onDelete: 'cascade' }),
  report: jsonb('report').$type<CombatV2Report>().notNull(),
  settlement: jsonb('settlement').$type<Record<string, unknown>>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [index('idx_pve_battle_master').on(table.masterId, table.createdAt, table.id)]);

export const pveCommands = pgTable('pve_commands', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  key: varchar('key', { length: 80 }).notNull(),
  operation: varchar('operation', { length: 100 }).notNull(),
  requestHash: varchar('request_hash', { length: 64 }).notNull(),
  result: jsonb('result').$type<Record<string, unknown>>().notNull(),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [unique('uq_pve_command_key').on(table.masterId, table.key)]);

export const pveEvents = pgTable('pve_events', {
  id: varchar('id', { length: 36 }).primaryKey(),
  masterId: varchar('master_id', { length: 36 }).notNull().references(() => masters.id, { onDelete: 'cascade' }),
  mapId: varchar('map_id', { length: 36 }).notNull().references(() => pveMaps.id, { onDelete: 'cascade' }),
  revision: integer('revision').notNull(),
  kind: varchar('kind', { length: 30 }).notNull(),
  data: jsonb('data').$type<Record<string, unknown>>().notNull(),
  occurredAt: timestamp('occurred_at', { withTimezone: true }).notNull().defaultNow(),
}, table => [unique('uq_pve_event_revision').on(table.mapId, table.revision)]);
