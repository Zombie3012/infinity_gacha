-- Combat v2 imprints (novel-inspired: S/A/B ranks, extra trait/ability).
-- ability_code/ability_params drive the engine hooks in shared/src/combat/imprints.ts;
-- rank_level (1-3) scales the numeric magnitudes at runtime.
INSERT INTO imprint_definitions
    (code, name, rank, tier, bonus_str, bonus_int, bonus_sta, bonus_agi, bonus_hp, bonus_atk, bonus_def, ability, ability_code, ability_params, is_enabled)
VALUES
    ('TRUE_BLACK_DRAGON_BLOOD', 'True Black Dragon Blood', 'S', 1, 30, 30, 30, 30, 300, 40, 30, 'Tăng sát thương và kháng hiệu ứng khi HP thấp.', 'LOW_HP_EMPOWER', '{"hpThresholdPct": 40, "damageBonus": 15, "tenacity": 20}'::jsonb, TRUE),
    ('PHOENIX_FLAME', 'Phoenix Flame', 'S', 2, 10, 20, 20, 20, 250, 20, 20, 'Hồi sinh một lần với 30% HP mỗi trận.', 'PHOENIX_REVIVE', '{"hpPct": 30, "times": 1}'::jsonb, TRUE),
    ('IRON_WILL', 'Iron Will', 'A', 1, 10, 5, 25, 5, 200, 10, 25, 'Giảm 10% thời gian khống chế.', 'CC_RESISTANCE', '{"tenacity": 10}'::jsonb, TRUE),
    ('SWIFT_SHADOW', 'Swift Shadow', 'A', 2, 5, 5, 5, 30, 100, 15, 5, 'Tăng Crit và Evasion.', 'CRIT_EVASION', '{"critRate": 5, "evasion": 5}'::jsonb, TRUE),
    ('ARCANE_CORE', 'Arcane Core', 'A', 3, 0, 35, 10, 10, 120, 0, 10, 'Tăng MATK và MP Regen.', 'ARCANE_EMPOWER', '{"matkPercent": 10, "mpRegenPct": 5}'::jsonb, TRUE),
    ('BATTLE_INSTINCT', 'Battle Instinct', 'B', 1, 15, 0, 10, 10, 100, 10, 5, 'Tăng nhẹ ATK và chính xác.', 'ACCURACY_EMPOWER', '{"atkPercent": 8, "accuracy": 5}'::jsonb, TRUE)
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
    ability_code = EXCLUDED.ability_code,
    ability_params = EXCLUDED.ability_params,
    is_enabled = EXCLUDED.is_enabled;
