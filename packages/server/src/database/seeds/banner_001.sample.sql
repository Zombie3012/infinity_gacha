-- Sample standard banner and reward pool for development.
-- Roster assumption: use the first seeded Hero(s) by rarity, since no specific codes were selected.
-- The server applies 0.4% base 5-star chance and splits the remaining rate using 49.6:50.
-- Equal weights within each group make selected Heroes/materials equally likely within that group.
-- Banner runs for 14 days from the first application of this seed.

BEGIN;

INSERT INTO hero_templates
    (id, code, name, default_rarity, hero_class, element, base_hp, base_atk, base_def, base_spd)
VALUES
    ('hero-3s-001', 'HERO_3S_BLADE', 'Earthbreaker', 3, 'WARRIOR', 'EARTH', 820, 88, 48, 105),
    ('hero-3s-002', 'HERO_3S_ARCHER', 'Tempest Archer', 3, 'ARCHER', 'WIND', 780, 102, 40, 120),
    ('hero-3s-003', 'HERO_3S_MAGE', 'Abyssal Mage', 3, 'MAGE', 'WATER', 750, 112, 38, 110),
    ('hero-4s-001', 'HERO_4S_BLADE', 'Dragon Slayer', 4, 'WARRIOR', 'EARTH', 1040, 112, 62, 112),
    ('hero-4s-002', 'HERO_4S_ARCHER', 'Phantom Ranger', 4, 'ARCHER', 'WIND', 990, 130, 52, 128),
    ('hero-5s-001', 'HERO_5S_BLADE', 'Worldbreaker', 5, 'WARRIOR', 'EARTH', 1320, 145, 78, 120)
ON CONFLICT (code) DO NOTHING;

INSERT INTO banners (id, name, banner_type, is_active, start_date, end_date)
VALUES ('banner-001', 'Banner 001', 'NORMAL', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '14 days')
ON CONFLICT (id) DO NOTHING;

INSERT INTO summon_reward_pool
    (id, banner_id, reward_id, reward_name, reward_type, pool_group, hero_template_code, rarity, weight, is_active)
VALUES
    ('banner-001-hero-5s-001', 'banner-001', 'HERO_5S_BLADE', 'Worldbreaker', 'HERO', 'FIVE_STAR_HERO', 'HERO_5S_BLADE', 5, 1, TRUE),
    ('banner-001-hero-4s-001', 'banner-001', 'HERO_4S_BLADE', 'Dragon Slayer', 'HERO', 'OTHER_HERO', 'HERO_4S_BLADE', 4, 1, TRUE),
    ('banner-001-hero-4s-002', 'banner-001', 'HERO_4S_ARCHER', 'Phantom Ranger', 'HERO', 'OTHER_HERO', 'HERO_4S_ARCHER', 4, 1, TRUE),
    ('banner-001-hero-3s-001', 'banner-001', 'HERO_3S_BLADE', 'Earthbreaker', 'HERO', 'OTHER_HERO', 'HERO_3S_BLADE', 3, 1, TRUE),
    ('banner-001-hero-3s-002', 'banner-001', 'HERO_3S_ARCHER', 'Tempest Archer', 'HERO', 'OTHER_HERO', 'HERO_3S_ARCHER', 3, 1, TRUE),
    ('banner-001-hero-3s-003', 'banner-001', 'HERO_3S_MAGE', 'Abyssal Mage', 'HERO', 'OTHER_HERO', 'HERO_3S_MAGE', 3, 1, TRUE),
    ('banner-001-material-001', 'banner-001', 'SAMPLE_TRASH_BROKEN_CHARM', 'Broken charm shard (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-002', 'banner-001', 'SAMPLE_TRASH_DULL_SHARD', 'Dull crystal shard (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-003', 'banner-001', 'SAMPLE_TRASH_TORN_SCROLL', 'Torn talisman paper (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-004', 'banner-001', 'SAMPLE_HERO_EXP_100', 'Hero EXP Book · +100 EXP (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-005', 'banner-001', 'SAMPLE_HERO_PROMOTION_SEAL', 'Hero Promotion Seal (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-006', 'banner-001', 'SAMPLE_HERO_AWAKENING_CORE', 'Hero Awakening Core (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE),
    ('banner-001-material-007', 'banner-001', 'SAMPLE_HERO_SKILL_BOOK', 'Hero Skill Book (sample)', 'MATERIAL', 'MATERIAL', NULL, NULL, 1, TRUE)
ON CONFLICT (banner_id, reward_id, pool_group) DO UPDATE SET
    reward_name = EXCLUDED.reward_name,
    reward_type = EXCLUDED.reward_type,
    hero_template_code = EXCLUDED.hero_template_code,
    rarity = EXCLUDED.rarity,
    weight = EXCLUDED.weight,
    is_active = EXCLUDED.is_active;

COMMIT;
