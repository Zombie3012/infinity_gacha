-- Editable development sample. EXP is the amount required to advance from the previous level.
-- Level 2 matches Acceptance_Criteria_P0_Draft.md (1000 EXP); later costs grow by 1.5x.
INSERT INTO master_level_configs (level, exp_required, is_sample)
VALUES
    (2, 1000, TRUE),
    (3, 1500, TRUE),
    (4, 2250, TRUE),
    (5, 3375, TRUE),
    (6, 5063, TRUE),
    (7, 7594, TRUE),
    (8, 11391, TRUE),
    (9, 17086, TRUE),
    (10, 25629, TRUE),
    (11, 38443, TRUE),
    (12, 57665, TRUE),
    (13, 86498, TRUE),
    (14, 129746, TRUE),
    (15, 194619, TRUE),
    (16, 291929, TRUE),
    (17, 437894, TRUE),
    (18, 656841, TRUE),
    (19, 985262, TRUE),
    (20, 1477893, TRUE)
ON CONFLICT (level) DO UPDATE SET
    exp_required = EXCLUDED.exp_required,
    is_sample = EXCLUDED.is_sample;
