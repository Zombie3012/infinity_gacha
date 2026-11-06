-- =========================================================================
-- Infinite Gacha - Consolidated Database Schema (PostgreSQL DDL)
-- Covers Phases P0, P1, P2, P3
-- =========================================================================

-- Domain 01: Account & Master Management
CREATE TABLE IF NOT EXISTS accounts (
    id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(32) NOT NULL UNIQUE,
    email VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (status IN ('ACTIVE', 'SUSPENDED', 'BANNED'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_username_case_insensitive ON accounts (LOWER(username));

CREATE TABLE IF NOT EXISTS account_sessions (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    revoked_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS player_profiles (
    account_id VARCHAR(36) PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    display_name VARCHAR(32) NOT NULL,
    avatar_url VARCHAR(255),
    settings JSONB NOT NULL DEFAULT '{}'::JSONB,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS masters (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
    master_name VARCHAR(50) NOT NULL,
    level INT NOT NULL DEFAULT 1,
    exp BIGINT NOT NULL DEFAULT 0,
    silver_coins BIGINT NOT NULL DEFAULT 10000,
    gems BIGINT NOT NULL DEFAULT 0,
    gem_debt BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS master_level_configs (
    level INT PRIMARY KEY,
    exp_required BIGINT NOT NULL,
    is_sample BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS master_skill_templates (
    code VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(500) NOT NULL,
    unlock_level INT NOT NULL DEFAULT 1,
    duration_seconds INT NOT NULL,
    heal_max_hp_percent_per_second DOUBLE PRECISION NOT NULL,
    cooldown_seconds INT NOT NULL DEFAULT 15,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS feature_unlock_configs (
    feature_code VARCHAR(50) PRIMARY KEY,
    feature_name VARCHAR(100) NOT NULL,
    required_master_level INT NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS hero_templates (
    id VARCHAR(36) PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    default_rarity INT NOT NULL CHECK (default_rarity BETWEEN 1 AND 5),
    hero_class VARCHAR(30) NOT NULL,
    element VARCHAR(20) NOT NULL,
    base_hp INT NOT NULL,
    base_atk INT NOT NULL,
    base_def INT NOT NULL,
    base_spd INT NOT NULL
);

CREATE TABLE IF NOT EXISTS master_items (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    item_id VARCHAR(50) NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_item UNIQUE (master_id, item_id)
);

-- Domain 02 & 03: Gacha & Hero System
CREATE TABLE IF NOT EXISTS banners (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    banner_type VARCHAR(20) NOT NULL, -- STANDARD, SPECIAL, LIMITED
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    start_date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_date TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS master_banner_pity (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    banner_id VARCHAR(36) NOT NULL REFERENCES banners(id) ON DELETE CASCADE,
    pity_counter INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_banner UNIQUE (master_id, banner_id)
);

CREATE TABLE IF NOT EXISTS summon_reward_pool (
    id VARCHAR(36) PRIMARY KEY,
    banner_id VARCHAR(36) NOT NULL REFERENCES banners(id) ON DELETE CASCADE,
    reward_id VARCHAR(50) NOT NULL,
    reward_name VARCHAR(100) NOT NULL,
    reward_type VARCHAR(20) NOT NULL CHECK (reward_type IN ('HERO', 'MATERIAL')),
    pool_group VARCHAR(30) NOT NULL CHECK (pool_group IN ('FIVE_STAR_HERO', 'OTHER_HERO', 'MATERIAL')),
    hero_template_code VARCHAR(50) REFERENCES hero_templates(code),
    rarity INT,
    weight INT NOT NULL CHECK (weight > 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_banner_reward_group UNIQUE (banner_id, reward_id, pool_group)
);

CREATE TABLE IF NOT EXISTS summon_sessions (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    banner_id VARCHAR(36) NOT NULL REFERENCES banners(id),
    scroll_type VARCHAR(20) NOT NULL,
    roll_count INT NOT NULL CHECK (roll_count IN (1, 10)),
    pity_before INT NOT NULL,
    pity_after INT NOT NULL,
    idempotency_key VARCHAR(80),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_summon_idempotency UNIQUE (master_id, idempotency_key)
);

CREATE TABLE IF NOT EXISTS summon_history (
    id VARCHAR(36) PRIMARY KEY,
    session_id VARCHAR(36) NOT NULL REFERENCES summon_sessions(id) ON DELETE CASCADE,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    banner_id VARCHAR(36) NOT NULL REFERENCES banners(id),
    roll_number INT NOT NULL,
    pity_number INT NOT NULL,
    reward_type VARCHAR(20) NOT NULL,
    reward_id VARCHAR(50) NOT NULL,
    reward_name VARCHAR(100) NOT NULL,
    rarity INT NOT NULL DEFAULT 0,
    was_five_star BOOLEAN NOT NULL DEFAULT FALSE,
    was_duplicate BOOLEAN NOT NULL DEFAULT FALSE,
    thien_menh_granted INT NOT NULL DEFAULT 0,
    summon_origin VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_summon_session_roll UNIQUE (session_id, roll_number)
);

CREATE TABLE IF NOT EXISTS master_summon_inventory (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    scroll_type VARCHAR(20) NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_scroll_type UNIQUE (master_id, scroll_type)
);

CREATE TABLE IF NOT EXISTS weekly_scroll_exchanges (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    period_key VARCHAR(10) NOT NULL,
    quantity INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_weekly_exchange UNIQUE (master_id, period_key)
);

CREATE TABLE IF NOT EXISTS currency_transactions (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    currency_type VARCHAR(20) NOT NULL,
    amount_delta BIGINT NOT NULL,
    transaction_type VARCHAR(30) NOT NULL,
    reference_id VARCHAR(36),
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS heroes (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    config_id VARCHAR(50) NOT NULL REFERENCES hero_templates(code),
    name VARCHAR(100) NOT NULL,
    rarity INT NOT NULL, -- 1 to 5
    category VARCHAR(20) NOT NULL, -- NORMAL, SPECIAL, LIMITED
    state VARCHAR(20) NOT NULL DEFAULT 'HEALTHY', -- HEALTHY, INJURED, CRITICALLY_INJURED, DISABLED, DEAD
    level INT NOT NULL DEFAULT 1,
    exp BIGINT NOT NULL DEFAULT 0,
    hp INT NOT NULL,
    max_hp INT NOT NULL,
    attack INT NOT NULL,
    defense INT NOT NULL,
    speed INT NOT NULL,
    talent_points INT NOT NULL DEFAULT 0,
    thien_menh INT NOT NULL DEFAULT 0,
    hunger INT NOT NULL DEFAULT 0,
    fatigue INT NOT NULL DEFAULT 0,
    loyalty INT NOT NULL DEFAULT 100,
    is_locked BOOLEAN NOT NULL DEFAULT FALSE,
    promotion_rank INT NOT NULL DEFAULT 0,
    awakening_rank INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_hero_template UNIQUE (master_id, config_id)
);



-- Domain 04 & 05: Combat & Dungeon Exploration
CREATE TABLE IF NOT EXISTS worlds (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    world_seed VARCHAR(36) NOT NULL UNIQUE,
    difficulty_multiplier FLOAT NOT NULL DEFAULT 1.0,
    current_floor INT NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS combat_sessions (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    world_id VARCHAR(36) NOT NULL REFERENCES worlds(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    active_buff_id VARCHAR(40),
    last_buff_change_at TIMESTAMP WITH TIME ZONE,
    cooldown_until TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP WITH TIME ZONE,
    combat_state JSONB,
    battle_report JSONB
);

CREATE TABLE IF NOT EXISTS equipment_templates (
    id VARCHAR(36) PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    slot_type VARCHAR(30) NOT NULL,
    rarity INT NOT NULL DEFAULT 1,
    bonus_hp INT NOT NULL DEFAULT 0,
    bonus_atk INT NOT NULL DEFAULT 0,
    bonus_def INT NOT NULL DEFAULT 0,
    bonus_spd INT NOT NULL DEFAULT 0,
    bonus_str INT NOT NULL DEFAULT 0,
    bonus_int INT NOT NULL DEFAULT 0,
    bonus_sta INT NOT NULL DEFAULT 0,
    bonus_agi INT NOT NULL DEFAULT 0,
    bonus_matk INT NOT NULL DEFAULT 0,
    bonus_mdef INT NOT NULL DEFAULT 0,
    v2_stats JSONB NOT NULL DEFAULT '{}'::jsonb,
    is_sample BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS hero_death_records (
    id VARCHAR(36) PRIMARY KEY,
    hero_id VARCHAR(36) NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    combat_session_id VARCHAR(36) NOT NULL REFERENCES combat_sessions(id) ON DELETE CASCADE,
    summon_origin VARCHAR(20) NOT NULL,
    death_type VARCHAR(20) NOT NULL,
    dropped_equipment JSONB NOT NULL DEFAULT '[]',
    cause VARCHAR(100) NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS equipment_instances (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    template_code VARCHAR(50) NOT NULL REFERENCES equipment_templates(code),
    equipped_hero_id VARCHAR(36) REFERENCES heroes(id) ON DELETE SET NULL,
    location VARCHAR(20) NOT NULL DEFAULT 'INVENTORY' CHECK (location IN ('INVENTORY', 'EQUIPPED', 'FLOOR_DROP')),
    drop_world_id VARCHAR(36) REFERENCES worlds(id) ON DELETE SET NULL,
    drop_floor INT,
    dropped_at TIMESTAMP WITH TIME ZONE,
    picked_up_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK ((location = 'EQUIPPED' AND equipped_hero_id IS NOT NULL) OR (location <> 'EQUIPPED' AND equipped_hero_id IS NULL))
);
CREATE INDEX IF NOT EXISTS idx_equipment_master_location ON equipment_instances (master_id, location);
CREATE INDEX IF NOT EXISTS idx_equipment_floor_drop ON equipment_instances (drop_world_id, drop_floor);

CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_combat_per_master
    ON combat_sessions (master_id) WHERE status = 'ACTIVE';


CREATE TABLE IF NOT EXISTS master_parties (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    name VARCHAR(60) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_party_name UNIQUE (master_id, name)
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_master_default_party ON master_parties(master_id) WHERE is_default = TRUE;

CREATE TABLE IF NOT EXISTS combat_party_slots (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    party_id VARCHAR(36) NOT NULL REFERENCES master_parties(id) ON DELETE CASCADE,
    hero_id VARCHAR(36) NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    slot_index INT NOT NULL CHECK (slot_index BETWEEN 0 AND 4),
    CONSTRAINT uq_combat_party_party_slot UNIQUE (party_id, slot_index),
    CONSTRAINT uq_combat_party_party_hero UNIQUE (party_id, hero_id)
);

CREATE TABLE IF NOT EXISTS enemy_templates (
    id VARCHAR(36) PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    base_hp INT NOT NULL,
    base_atk INT NOT NULL,
    base_def INT NOT NULL,
    base_spd INT NOT NULL,
    base_exp_reward INT NOT NULL,
    base_silver_reward INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS dungeon_event_templates (
    id VARCHAR(36) PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(250) NOT NULL,
    event_type VARCHAR(20) NOT NULL,
    weight INT NOT NULL,
    silver_reward INT NOT NULL DEFAULT 0,
    heal_percent DOUBLE PRECISION NOT NULL DEFAULT 0,
    enemy_attack_multiplier DOUBLE PRECISION NOT NULL DEFAULT 1,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Domain 08: Base Building & Production (P1)
CREATE TABLE IF NOT EXISTS base_buildings (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    building_type VARCHAR(30) NOT NULL,
    level INT NOT NULL DEFAULT 1,
    production_rate_per_hour INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_master_building UNIQUE (master_id, building_type)
);

CREATE TABLE IF NOT EXISTS medical_records (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    hero_id VARCHAR(36) NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    state VARCHAR(30) NOT NULL, -- CRITICALLY_INJURED, DISABLED
    admission_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    treatment_completes_at TIMESTAMP WITH TIME ZONE NOT NULL,
    resurrection_count INT NOT NULL DEFAULT 0
);

-- Domain 11 & 12: Economy & Live Operations (P2)
CREATE TABLE IF NOT EXISTS iap_transactions (
    id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    product_id VARCHAR(50) NOT NULL,
    platform VARCHAR(20) NOT NULL, -- GOOGLE_PLAY, APPLE_APPSTORE
    order_id VARCHAR(100) NOT NULL UNIQUE,
    amount_paid_cents INT NOT NULL,
    currency VARCHAR(10) NOT NULL DEFAULT 'USD',
    gems_granted INT NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'COMPLETED', -- COMPLETED, REFUNDED, CHARGEBACK
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS leaderboards (
    id VARCHAR(36) PRIMARY KEY,
    leaderboard_type VARCHAR(30) NOT NULL, -- DUNGEON_PROGRESS, TOTAL_COMBAT_POWER
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    score BIGINT NOT NULL,
    secondary_score BIGINT NOT NULL DEFAULT 0,
    rank INT NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_leaderboard_entry UNIQUE (leaderboard_type, master_id)
);

-- Domain 13: Multiplayer & World Conquest (P3)
CREATE TABLE IF NOT EXISTS world_regions (
    region_id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    min_x INT NOT NULL,
    max_x INT NOT NULL,
    min_y INT NOT NULL,
    max_y INT NOT NULL,
    recommended_level INT NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS global_world_tiles (
    tile_id VARCHAR(36) PRIMARY KEY,
    pos_x INT NOT NULL,
    pos_y INT NOT NULL,
    region_id VARCHAR(36) NOT NULL REFERENCES world_regions(region_id),
    tile_type VARCHAR(30) NOT NULL,
    owner_master_id VARCHAR(36) REFERENCES masters(id) ON DELETE SET NULL,
    owner_alliance_id VARCHAR(36),
    resource_type VARCHAR(30),
    production_rate_per_hour INT NOT NULL DEFAULT 0,
    outpost_level INT NOT NULL DEFAULT 0,
    protection_expires_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_tile_coordinates UNIQUE (pos_x, pos_y)
);

CREATE TABLE IF NOT EXISTS player_armies (
    army_id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    army_name VARCHAR(50) NOT NULL,
    commander_hero_id VARCHAR(36) NOT NULL REFERENCES heroes(id),
    status VARCHAR(30) NOT NULL DEFAULT 'IDLE',
    origin_x INT NOT NULL,
    origin_y INT NOT NULL,
    current_x FLOAT NOT NULL,
    current_y FLOAT NOT NULL,
    target_x INT NOT NULL,
    target_y INT NOT NULL,
    departure_time TIMESTAMP WITH TIME ZONE NOT NULL,
    eta_time TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE IF NOT EXISTS peace_shields (
    shield_id VARCHAR(36) PRIMARY KEY,
    master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    shield_type VARCHAR(30) NOT NULL,
    activated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS alliances (
    alliance_id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    tag VARCHAR(10) NOT NULL UNIQUE,
    emblem_icon VARCHAR(100) NOT NULL,
    leader_master_id VARCHAR(36) NOT NULL REFERENCES masters(id),
    member_count INT NOT NULL DEFAULT 1,
    max_members INT NOT NULL DEFAULT 30,
    alliance_level INT NOT NULL DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS alliance_members (
    id VARCHAR(36) PRIMARY KEY,
    alliance_id VARCHAR(36) NOT NULL REFERENCES alliances(alliance_id) ON DELETE CASCADE,
    master_id VARCHAR(36) NOT NULL UNIQUE REFERENCES masters(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'MEMBER',
    contribution_points BIGINT NOT NULL DEFAULT 0,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    cooldown_expires_at TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS pvp_battle_records (
    battle_id VARCHAR(36) PRIMARY KEY,
    attacker_master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    defender_master_id VARCHAR(36) NOT NULL REFERENCES masters(id) ON DELETE CASCADE,
    battle_type VARCHAR(30) NOT NULL,
    winner_master_id VARCHAR(36) NOT NULL REFERENCES masters(id),
    battle_log JSONB NOT NULL,
    plundered_resources JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Editable development sample: cumulative Hero EXP thresholds and per-level stat growth.
CREATE TABLE IF NOT EXISTS hero_level_configs (
    level INT PRIMARY KEY,
    cumulative_exp_required BIGINT NOT NULL,
    stat_growth_multiplier DOUBLE PRECISION NOT NULL DEFAULT 1.05,
    is_sample BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS hero_development_configs (
    id VARCHAR(36) PRIMARY KEY,
    action VARCHAR(20) NOT NULL,
    rank INT NOT NULL,
    material_item_id VARCHAR(50) NOT NULL,
    material_quantity INT NOT NULL,
    required_hero_level INT NOT NULL DEFAULT 1,
    required_promotion_rank INT NOT NULL DEFAULT 0,
    max_level_after INT NOT NULL DEFAULT 20,
    stat_growth_multiplier FLOAT NOT NULL DEFAULT 1,
    is_sample BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_hero_development_action_rank UNIQUE (action, rank)
);

CREATE TABLE IF NOT EXISTS hero_skill_templates (
    code VARCHAR(50) PRIMARY KEY,
    hero_class VARCHAR(30) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description VARCHAR(500) NOT NULL,
    effect_type VARCHAR(30) NOT NULL,
    effect_value DOUBLE PRECISION NOT NULL,
    upgrade_increment DOUBLE PRECISION NOT NULL DEFAULT 0.1,
    cooldown_seconds INT NOT NULL DEFAULT 3,
    unlock_level INT NOT NULL DEFAULT 3,
    max_level INT NOT NULL DEFAULT 5,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_sample BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS hero_skill_instances (
    id VARCHAR(36) PRIMARY KEY,
    hero_id VARCHAR(36) NOT NULL REFERENCES heroes(id) ON DELETE CASCADE,
    skill_code VARCHAR(50) NOT NULL REFERENCES hero_skill_templates(code) ON DELETE CASCADE,
    skill_level INT NOT NULL DEFAULT 1,
    is_unlocked BOOLEAN NOT NULL DEFAULT FALSE,
    behavior_mode VARCHAR(10) NOT NULL DEFAULT 'AUTO',
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_hero_skill_instance UNIQUE (hero_id, skill_code)
);
