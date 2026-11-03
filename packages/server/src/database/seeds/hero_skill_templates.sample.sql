-- Editable development skills. Skill effects are configuration only until combat skill execution is implemented.
INSERT INTO hero_skill_templates
    (code, hero_class, name, description, effect_type, effect_value, upgrade_increment, cooldown_seconds, unlock_level, max_level, is_active, is_sample)
VALUES
    ('SAMPLE_SKILL_WARRIOR_HEAVY_STRIKE', 'WARRIOR', 'Heavy Strike', 'Deals a strong single-target physical hit.', 'DAMAGE_SINGLE', 1.50, 0.10, 3, 3, 5, TRUE, TRUE),
    ('SAMPLE_SKILL_ARCHER_PIERCING_SHOT', 'ARCHER', 'Piercing Shot', 'Deals a precise single-target ranged hit.', 'DAMAGE_SINGLE', 1.40, 0.10, 3, 3, 5, TRUE, TRUE),
    ('SAMPLE_SKILL_ASSASSIN_SHADOW_CUT', 'ASSASSIN', 'Shadow Cut', 'Deals a fast, high-impact single-target hit.', 'DAMAGE_SINGLE', 1.60, 0.10, 3, 3, 5, TRUE, TRUE),
    ('SAMPLE_SKILL_MAGE_ARCANE_BOLT', 'MAGE', 'Arcane Bolt', 'Deals a single-target magical hit.', 'DAMAGE_SINGLE', 1.50, 0.10, 3, 3, 5, TRUE, TRUE),
    ('SAMPLE_SKILL_TANK_SHIELD_BASH', 'TANK', 'Shield Bash', 'Deals a defensive single-target hit.', 'DAMAGE_SINGLE', 1.20, 0.10, 3, 3, 5, TRUE, TRUE),
    ('SAMPLE_SKILL_SUPPORT_HEALING_LIGHT', 'SUPPORT', 'Healing Light', 'Restores 10% of the lowest-HP ally maximum HP.', 'HEAL_LOWEST_ALLY', 0.10, 0.02, 4, 3, 5, TRUE, TRUE)
ON CONFLICT (code) DO UPDATE SET
    hero_class = EXCLUDED.hero_class,
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    effect_type = EXCLUDED.effect_type,
    effect_value = EXCLUDED.effect_value,
    upgrade_increment = EXCLUDED.upgrade_increment,
    cooldown_seconds = EXCLUDED.cooldown_seconds,
    unlock_level = EXCLUDED.unlock_level,
    max_level = EXCLUDED.max_level,
    is_active = EXCLUDED.is_active,
    is_sample = EXCLUDED.is_sample;
