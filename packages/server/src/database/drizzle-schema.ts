import { integer, pgTable, timestamp, unique, uniqueIndex, index, varchar, bigint, doublePrecision, boolean, jsonb, check, text, primaryKey } from 'drizzle-orm/pg-core';
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
  check('hero_treatments_status_check', sql`${table.status} IN ('ACTIVE', 'COMPLETED', 'CANCELLED')`),
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
  priceSilver: bigint('price_silver', { mode: 'bigint' }).notNull(),
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
