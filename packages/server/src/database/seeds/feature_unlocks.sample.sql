-- P0 prototype features remain available from Master level 1 so the first-play loop is usable.
-- Future entries can introduce progression gates without code changes.
INSERT INTO feature_unlock_configs (feature_code, feature_name, required_master_level, is_active)
VALUES
    ('WORLD_CREATION', 'World Creation', 1, TRUE),
    ('SUMMON', 'Heavenly Scroll Summoning', 1, TRUE),
    ('HERO_COLLECTION', 'Hero Collection', 1, TRUE),
    ('PVE_COMBAT', 'PvE Combat', 1, TRUE),
    ('EQUIPMENT', 'Equipment Management', 1, TRUE),
    ('MASTER_SKILLS', 'Master Skills', 1, TRUE)
ON CONFLICT (feature_code) DO UPDATE SET
    feature_name = EXCLUDED.feature_name,
    required_master_level = EXCLUDED.required_master_level,
    is_active = EXCLUDED.is_active;
