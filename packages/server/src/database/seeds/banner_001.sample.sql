-- Dual-banner pure-rate procedural summon configuration (no pity):
--   1. banner-001 (NORMAL):  1 Normal Scroll/roll, Heroes 1★–3★ (50%) + Materials (50%)
--   2. banner-002 (SPECIAL): 100 Gems/roll, Heroes 2★–5★ (50%, 5★ = 0.4%) + Materials (50%)

BEGIN;

INSERT INTO hero_templates
    (id, code, name, default_rarity, hero_class, element, base_hp, base_atk, base_def, base_spd)
VALUES
    ('procedural-1s', 'PROCEDURAL_1S', 'Procedural Hero 1★', 1, 'UNCLASSIFIED', 'NEUTRAL', 200, 30, 15, 60),
    ('procedural-2s', 'PROCEDURAL_2S', 'Procedural Hero 2★', 2, 'UNCLASSIFIED', 'NEUTRAL', 260, 40, 20, 65),
    ('procedural-3s', 'PROCEDURAL_3S', 'Procedural Hero 3★', 3, 'WARRIOR', 'FIRE', 340, 52, 26, 70),
    ('procedural-4s', 'PROCEDURAL_4S', 'Procedural Hero 4★', 4, 'WARRIOR', 'FIRE', 440, 68, 34, 75),
    ('procedural-5s', 'PROCEDURAL_5S', 'Procedural Hero 5★', 5, 'WARRIOR', 'FIRE', 560, 86, 44, 80)
ON CONFLICT (code) DO NOTHING;

INSERT INTO banners (id, name, banner_type, is_active, start_date, end_date)
VALUES
    ('banner-001', 'Triệu Hồi Thường – Khế Ước Phàm Trần', 'NORMAL', TRUE, CURRENT_TIMESTAMP - INTERVAL '1 day', NULL),
    ('banner-002', 'Triệu Hồi Đặc Biệt – Khế Ước Tinh Tú', 'SPECIAL', TRUE, CURRENT_TIMESTAMP - INTERVAL '1 day', NULL)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    banner_type = EXCLUDED.banner_type,
    is_active = EXCLUDED.is_active,
    start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date;

DELETE FROM summon_reward_pool WHERE banner_id IN ('banner-001', 'banner-002');

INSERT INTO summon_reward_pool
    (id, banner_id, reward_id, reward_name, reward_type, pool_group, hero_template_code, rarity, weight, is_active)
VALUES
    -- Banner 001 (NORMAL): 1★-3★ Heroes (500/1000 = 50%) + Materials (500/1000 = 50%)
    ('banner-001-hero-3s', 'banner-001', 'PROCEDURAL_3S', 'Anh Hùng 3★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_3S', 3, 50, TRUE),
    ('banner-001-hero-2s', 'banner-001', 'PROCEDURAL_2S', 'Anh Hùng 2★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_2S', 2, 180, TRUE),
    ('banner-001-hero-1s', 'banner-001', 'PROCEDURAL_1S', 'Anh Hùng 1★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_1S', 1, 270, TRUE),
    ('banner-001-mat-exp', 'banner-001', 'SAMPLE_HERO_EXP_100', 'Sách Kinh Nghiệm +100 EXP', 'MATERIAL', 'MATERIAL', NULL, NULL, 150, TRUE),
    ('banner-001-mat-promo', 'banner-001', 'SAMPLE_HERO_PROMOTION_SEAL', 'Ấn Thăng Cấp Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 80, TRUE),
    ('banner-001-mat-skill', 'banner-001', 'SAMPLE_HERO_SKILL_BOOK', 'Sách Kỹ Năng Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 60, TRUE),
    ('banner-001-mat-awaken', 'banner-001', 'SAMPLE_HERO_AWAKENING_CORE', 'Lõi Thức Tỉnh Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 50, TRUE),
    ('banner-001-mat-charm', 'banner-001', 'SAMPLE_TRASH_BROKEN_CHARM', 'Mảnh Bùa Vỡ', 'MATERIAL', 'MATERIAL', NULL, NULL, 60, TRUE),
    ('banner-001-mat-shard', 'banner-001', 'SAMPLE_TRASH_DULL_SHARD', 'Đá Pha Lê Mờ', 'MATERIAL', 'MATERIAL', NULL, NULL, 50, TRUE),
    ('banner-001-mat-scroll', 'banner-001', 'SAMPLE_TRASH_TORN_SCROLL', 'Giấy Bùa Rách', 'MATERIAL', 'MATERIAL', NULL, NULL, 50, TRUE),

    -- Banner 002 (SPECIAL): 2★-5★ Heroes (500/1000 = 50%, 5★ = 0.4%) + Materials (500/1000 = 50%)
    ('banner-002-hero-5s', 'banner-002', 'PROCEDURAL_5S', 'Anh Hùng 5★ (Ngẫu Nhiên)', 'HERO', 'FIVE_STAR_HERO', 'PROCEDURAL_5S', 5, 4, TRUE),
    ('banner-002-hero-4s', 'banner-002', 'PROCEDURAL_4S', 'Anh Hùng 4★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_4S', 4, 36, TRUE),
    ('banner-002-hero-3s', 'banner-002', 'PROCEDURAL_3S', 'Anh Hùng 3★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_3S', 3, 160, TRUE),
    ('banner-002-hero-2s', 'banner-002', 'PROCEDURAL_2S', 'Anh Hùng 2★ (Ngẫu Nhiên)', 'HERO', 'OTHER_HERO', 'PROCEDURAL_2S', 2, 300, TRUE),
    ('banner-002-mat-exp', 'banner-002', 'SAMPLE_HERO_EXP_100', 'Sách Kinh Nghiệm +100 EXP', 'MATERIAL', 'MATERIAL', NULL, NULL, 160, TRUE),
    ('banner-002-mat-promo', 'banner-002', 'SAMPLE_HERO_PROMOTION_SEAL', 'Ấn Thăng Cấp Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 120, TRUE),
    ('banner-002-mat-skill', 'banner-002', 'SAMPLE_HERO_SKILL_BOOK', 'Sách Kỹ Năng Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 110, TRUE),
    ('banner-002-mat-awaken', 'banner-002', 'SAMPLE_HERO_AWAKENING_CORE', 'Lõi Thức Tỉnh Anh Hùng', 'MATERIAL', 'MATERIAL', NULL, NULL, 110, TRUE)
ON CONFLICT (banner_id, reward_id, pool_group) DO UPDATE SET
    reward_name = EXCLUDED.reward_name,
    reward_type = EXCLUDED.reward_type,
    hero_template_code = EXCLUDED.hero_template_code,
    rarity = EXCLUDED.rarity,
    weight = EXCLUDED.weight,
    is_active = EXCLUDED.is_active;

COMMIT;
