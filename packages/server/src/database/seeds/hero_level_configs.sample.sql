-- Sample Hero progression curve for development; replace with approved production balance.
-- EXP is lifetime cumulative EXP. Level thresholds use an exponential per-level cost (base 100, growth 1.5).
-- Each level-up multiplies current HP/ATK/DEF/SPD by 1.05; excess EXP carries forward.
INSERT INTO hero_level_configs (level, cumulative_exp_required, stat_growth_multiplier, is_sample)
VALUES
    (2, 100, 1.05, TRUE),
    (3, 250, 1.05, TRUE),
    (4, 475, 1.05, TRUE),
    (5, 813, 1.05, TRUE),
    (6, 1319, 1.05, TRUE),
    (7, 2078, 1.05, TRUE),
    (8, 3217, 1.05, TRUE),
    (9, 4926, 1.05, TRUE),
    (10, 7489, 1.05, TRUE),
    (11, 11333, 1.05, TRUE),
    (12, 17100, 1.05, TRUE),
    (13, 25750, 1.05, TRUE),
    (14, 38725, 1.05, TRUE),
    (15, 58187, 1.05, TRUE),
    (16, 87380, 1.05, TRUE),
    (17, 131169, 1.05, TRUE),
    (18, 196853, 1.05, TRUE),
    (19, 295379, 1.05, TRUE),
    (20, 443168, 1.05, TRUE)
ON CONFLICT (level) DO UPDATE SET
    cumulative_exp_required = EXCLUDED.cumulative_exp_required,
    stat_growth_multiplier = EXCLUDED.stat_growth_multiplier,
    is_sample = EXCLUDED.is_sample;

-- Promotion sample expands the Hero level cap by 5 per rank, up to level 40.
INSERT INTO hero_level_configs (level, cumulative_exp_required, stat_growth_multiplier, is_sample)
SELECT level, ROUND(100 * (POWER(1.5, level - 1) - 1) / 0.5)::BIGINT, 1.05, TRUE
FROM generate_series(21, 40) AS level
ON CONFLICT (level) DO UPDATE SET
    cumulative_exp_required = EXCLUDED.cumulative_exp_required,
    stat_growth_multiplier = EXCLUDED.stat_growth_multiplier,
    is_sample = EXCLUDED.is_sample;
