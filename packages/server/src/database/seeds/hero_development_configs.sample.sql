-- Prototype rules only. Edit these rows to tune or replace promotion and awakening requirements.
INSERT INTO hero_development_configs
    (id, action, rank, material_item_id, material_quantity, required_hero_level, required_promotion_rank, max_level_after, stat_growth_multiplier, is_sample)
VALUES
    ('hero-dev-promotion-01', 'PROMOTION', 1, 'SAMPLE_HERO_PROMOTION_SEAL', 5, 20, 0, 25, 1.00, TRUE),
    ('hero-dev-promotion-02', 'PROMOTION', 2, 'SAMPLE_HERO_PROMOTION_SEAL', 10, 25, 1, 30, 1.00, TRUE),
    ('hero-dev-promotion-03', 'PROMOTION', 3, 'SAMPLE_HERO_PROMOTION_SEAL', 15, 30, 2, 35, 1.00, TRUE),
    ('hero-dev-promotion-04', 'PROMOTION', 4, 'SAMPLE_HERO_PROMOTION_SEAL', 20, 35, 3, 40, 1.00, TRUE),
    ('hero-dev-awakening-01', 'AWAKENING', 1, 'SAMPLE_HERO_AWAKENING_CORE', 3, 1, 1, 20, 1.05, TRUE),
    ('hero-dev-awakening-02', 'AWAKENING', 2, 'SAMPLE_HERO_AWAKENING_CORE', 6, 1, 2, 20, 1.05, TRUE),
    ('hero-dev-awakening-03', 'AWAKENING', 3, 'SAMPLE_HERO_AWAKENING_CORE', 9, 1, 3, 20, 1.05, TRUE)
ON CONFLICT (action, rank) DO UPDATE SET
    material_item_id = EXCLUDED.material_item_id,
    material_quantity = EXCLUDED.material_quantity,
    required_hero_level = EXCLUDED.required_hero_level,
    required_promotion_rank = EXCLUDED.required_promotion_rank,
    max_level_after = EXCLUDED.max_level_after,
    stat_growth_multiplier = EXCLUDED.stat_growth_multiplier,
    is_sample = EXCLUDED.is_sample;
