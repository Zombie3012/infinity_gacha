-- Sample starter equipment for local development. Reapply after creating new Masters to grant each one missing starter items.
BEGIN;

INSERT INTO equipment_templates
    (id, code, name, slot_type, rarity, bonus_hp, bonus_atk, bonus_def, bonus_spd, is_sample)
VALUES
    ('equipment-template-sample-001', 'SAMPLE_IRON_SWORD', 'Sample Iron Sword', 'MAIN_HAND', 1, 0, 8, 0, 0, TRUE),
    ('equipment-template-sample-002', 'SAMPLE_LEATHER_CHEST', 'Sample Leather Chest', 'CHEST', 1, 40, 0, 6, 0, TRUE),
    ('equipment-template-sample-003', 'SAMPLE_SWIFT_CHARM', 'Sample Swift Charm', 'ACCESSORY', 1, 0, 0, 0, 4, TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, slot_type = EXCLUDED.slot_type, rarity = EXCLUDED.rarity,
    bonus_hp = EXCLUDED.bonus_hp, bonus_atk = EXCLUDED.bonus_atk,
    bonus_def = EXCLUDED.bonus_def, bonus_spd = EXCLUDED.bonus_spd,
    is_sample = EXCLUDED.is_sample;

INSERT INTO equipment_instances (id, master_id, template_code, location)
SELECT
    substr(h, 1, 8) || '-' || substr(h, 9, 4) || '-' || substr(h, 13, 4) || '-' || substr(h, 17, 4) || '-' || substr(h, 21, 12),
    master_id, template_code, 'INVENTORY'
FROM (
    SELECT m.id AS master_id, t.code AS template_code, md5(m.id || ':' || t.code || ':sample-starter') AS h
    FROM masters m CROSS JOIN equipment_templates t
    WHERE t.code IN ('SAMPLE_IRON_SWORD', 'SAMPLE_LEATHER_CHEST', 'SAMPLE_SWIFT_CHARM')
      AND NOT EXISTS (SELECT 1 FROM equipment_instances existing WHERE existing.master_id = m.id AND existing.template_code = t.code)
) starter_items
ON CONFLICT (id) DO NOTHING;

COMMIT;
