-- Sample starter equipment for local development. Reapply after creating new Masters to grant each one missing starter items.
BEGIN;

INSERT INTO equipment_templates
    (id, code, name, slot_type, rarity, bonus_hp, bonus_atk, bonus_def, bonus_spd, bonus_str, bonus_int, bonus_sta, bonus_agi, bonus_matk, bonus_mdef, v2_stats, is_sample)
VALUES
    -- ========================================
    -- STARTER ITEMS (IDs match legacy database rows)
    -- ========================================
    ('equipment-template-sample-001', 'SAMPLE_IRON_SWORD', 'Thanh kiếm sắt', 'MAIN_HAND', 1, 0, 15, 0, 0, 6, 0, 2, 0, 0, 0, '{"armorPen": 5}'::jsonb, TRUE),
    ('equipment-template-sample-002', 'SAMPLE_LEATHER_CHEST', 'Giáp da hộ thân', 'CHEST', 1, 60, 0, 8, 0, 0, 0, 8, 2, 0, 4, '{"damageReduction": 4}'::jsonb, TRUE),
    ('equipment-template-sample-003', 'SAMPLE_SWIFT_CHARM', 'Bùa hộ mệnh thần tốc', 'ACCESSORY', 1, 30, 0, 0, 4, 0, 0, 0, 5, 0, 0, '{"lifesteal": 5, "critRate": 3}'::jsonb, TRUE),

    -- ========================================
    -- ADDITIONAL V2 WEAPONS & GEAR
    -- ========================================
    ('equipment-template-sample-004', 'SAMPLE_STEEL_GREATSWORD', 'Đại kiếm thép', 'MAIN_HAND', 2, 0, 30, 4, 0, 12, 0, 4, 0, 0, 0, '{"armorPen": 8, "critDamage": 10}'::jsonb, TRUE),
    ('equipment-template-sample-005', 'SAMPLE_THIEF_DAGGER', 'Dao găm bóng tối', 'MAIN_HAND', 1, 0, 12, 0, 2, 0, 0, 0, 8, 0, 0, '{"critRate": 6, "evasion": 4}'::jsonb, TRUE),
    ('equipment-template-sample-006', 'SAMPLE_MAGE_WAND', 'Trượng ma thuật', 'MAIN_HAND', 1, 0, 0, 0, 0, 0, 10, 0, 0, 20, 4, '{"magicPen": 5, "mpRegen": 2}'::jsonb, TRUE),
    ('equipment-template-sample-007', 'SAMPLE_HUNTER_BOW', 'Cung thợ săn', 'MAIN_HAND', 1, 0, 14, 0, 2, 0, 0, 0, 7, 0, 0, '{"accuracy": 8, "critRate": 4}'::jsonb, TRUE),
    ('equipment-template-sample-008', 'SAMPLE_OAK_SHIELD', 'Khiên gỗ sồi', 'OFF_HAND', 1, 30, 0, 10, 0, 0, 0, 6, 0, 0, 4, '{"blockRate": 8, "blockEffect": 12}'::jsonb, TRUE),
    ('equipment-template-sample-009', 'SAMPLE_IRON_HELM', 'Mũ giáp sắt', 'HELMET', 1, 40, 0, 6, 0, 0, 0, 5, 0, 0, 4, '{"tenacity": 8}'::jsonb, TRUE),
    ('equipment-template-sample-010', 'SAMPLE_WIND_BOOTS', 'Giày gió lốc', 'BOOTS', 1, 20, 0, 4, 8, 0, 0, 0, 8, 0, 2, '{"evasion": 5}'::jsonb, TRUE),
    ('equipment-template-sample-011', 'SAMPLE_BLOODSTONE_RING', 'Nhẫn huyết thạch', 'ACCESSORY', 2, 100, 8, 0, 0, 5, 0, 4, 0, 0, 0, '{"lifesteal": 8, "damageBonus": 5}'::jsonb, TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, slot_type = EXCLUDED.slot_type, rarity = EXCLUDED.rarity,
    bonus_hp = EXCLUDED.bonus_hp, bonus_atk = EXCLUDED.bonus_atk,
    bonus_def = EXCLUDED.bonus_def, bonus_spd = EXCLUDED.bonus_spd,
    bonus_str = EXCLUDED.bonus_str, bonus_int = EXCLUDED.bonus_int,
    bonus_sta = EXCLUDED.bonus_sta, bonus_agi = EXCLUDED.bonus_agi,
    bonus_matk = EXCLUDED.bonus_matk, bonus_mdef = EXCLUDED.bonus_mdef,
    v2_stats = EXCLUDED.v2_stats,
    is_sample = EXCLUDED.is_sample;

INSERT INTO equipment_instances (id, master_id, template_code, location)
SELECT
    substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-' || substr(h, 13, 4) || '-' || substr(h, 17, 4) || '-' || substr(h, 21, 12),
    master_id, template_code, 'INVENTORY'
FROM (
    SELECT m.id AS master_id, t.code AS template_code, md5(m.id || ':' || t.code || ':sample-starter') AS h
    FROM masters m CROSS JOIN equipment_templates t
    WHERE t.code IN ('SAMPLE_IRON_SWORD', 'SAMPLE_LEATHER_CHEST', 'SAMPLE_SWIFT_CHARM', 'SAMPLE_OAK_SHIELD', 'SAMPLE_WIND_BOOTS')
      AND NOT EXISTS (SELECT 1 FROM equipment_instances existing WHERE existing.master_id = m.id AND existing.template_code = t.code)
) starter_items
ON CONFLICT (id) DO NOTHING;

COMMIT;
