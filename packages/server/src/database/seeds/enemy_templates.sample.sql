-- Editable sample enemy templates for the first PvE implementation.
-- Values are prototype tuning data, not approved production balance.
INSERT INTO enemy_templates
    (id, code, name, base_hp, base_atk, base_def, base_spd, base_exp_reward, base_silver_reward, is_active)
VALUES
    ('enemy-sample-001', 'SAMPLE_MOSS_SLIME', 'Moss Slime', 300, 30, 15, 60, 20, 15, TRUE),
    ('enemy-sample-002', 'SAMPLE_FOREST_BANDIT', 'Forest Bandit', 450, 45, 20, 85, 30, 20, TRUE),
    ('enemy-sample-003', 'SAMPLE_STONE_GOLEM', 'Stone Golem', 700, 55, 50, 35, 50, 35, TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    base_hp = EXCLUDED.base_hp,
    base_atk = EXCLUDED.base_atk,
    base_def = EXCLUDED.base_def,
    base_spd = EXCLUDED.base_spd,
    base_exp_reward = EXCLUDED.base_exp_reward,
    base_silver_reward = EXCLUDED.base_silver_reward,
    is_active = EXCLUDED.is_active;
