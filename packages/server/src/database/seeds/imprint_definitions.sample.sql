-- Combat v2 imprints (novel-inspired: S/A/B ranks, extra trait/ability).
INSERT INTO imprint_definitions
    (code, name, rank, tier, bonus_str, bonus_int, bonus_sta, bonus_agi, bonus_hp, bonus_atk, bonus_def, ability, is_enabled)
VALUES
    ('TRUE_BLACK_DRAGON_BLOOD', 'True Black Dragon Blood', 'S', 1, 30, 30, 30, 30, 300, 40, 30, 'Tăng sát thương và kháng hiệu ứng khi HP thấp.', TRUE),
    ('PHOENIX_FLAME', 'Phoenix Flame', 'S', 2, 10, 20, 20, 20, 250, 20, 20, 'Hồi sinh một lần với 30% HP mỗi trận.', TRUE),
    ('IRON_WILL', 'Iron Will', 'A', 1, 10, 5, 25, 5, 200, 10, 25, 'Giảm 10% thời gian khống chế.', TRUE),
    ('SWIFT_SHADOW', 'Swift Shadow', 'A', 2, 5, 5, 5, 30, 100, 15, 5, 'Tăng Crit và Evasion.', TRUE),
    ('ARCANE_CORE', 'Arcane Core', 'A', 3, 0, 35, 10, 10, 120, 0, 10, 'Tăng MATK và MP Regen.', TRUE),
    ('BATTLE_INSTINCT', 'Battle Instinct', 'B', 1, 15, 0, 10, 10, 100, 10, 5, 'Tăng nhẹ ATK và chính xác.', TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    rank = EXCLUDED.rank,
    tier = EXCLUDED.tier,
    bonus_str = EXCLUDED.bonus_str,
    bonus_int = EXCLUDED.bonus_int,
    bonus_sta = EXCLUDED.bonus_sta,
    bonus_agi = EXCLUDED.bonus_agi,
    bonus_hp = EXCLUDED.bonus_hp,
    bonus_atk = EXCLUDED.bonus_atk,
    bonus_def = EXCLUDED.bonus_def,
    ability = EXCLUDED.ability,
    is_enabled = EXCLUDED.is_enabled;
