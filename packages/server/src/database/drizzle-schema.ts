import { integer, pgTable, timestamp, unique, uniqueIndex, index, varchar, bigint, doublePrecision, boolean, jsonb, check, text } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';

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
  configId: varchar('config_id', { length: 50 }).notNull().references(() => heroTemplates.code),
  name: varchar('name', { length: 100 }).notNull(),
  rarity: integer('rarity').notNull(),
  category: varchar('category', { length: 20 }).notNull(),
  state: varchar('state', { length: 20 }).default('HEALTHY').notNull(),
  level: integer('level').default(1).notNull(),
  exp: bigint('exp', { mode: 'bigint' }).default(sql`0`).notNull(),
  hp: integer('hp').notNull(),
  maxHp: integer('max_hp').notNull(),
  attack: integer('attack').notNull(),
  defense: integer('defense').notNull(),
  speed: integer('speed').notNull(),
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
}, (table) => [unique('uq_master_hero_template').on(table.masterId, table.configId)]);

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
