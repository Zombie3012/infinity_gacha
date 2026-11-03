-- Development sample. One regeneration tick is applied per real-time second during combat.
INSERT INTO master_skill_templates
    (code, name, description, unlock_level, duration_seconds, heal_max_hp_percent_per_second, cooldown_seconds, is_active)
VALUES
    ('TEAM_REGENERATION', 'Team Regeneration', 'Hồi 1% HP tối đa cho mỗi Hero mỗi giây trong 5 giây.', 1, 5, 0.01, 15, TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    description = EXCLUDED.description,
    unlock_level = EXCLUDED.unlock_level,
    duration_seconds = EXCLUDED.duration_seconds,
    heal_max_hp_percent_per_second = EXCLUDED.heal_max_hp_percent_per_second,
    cooldown_seconds = EXCLUDED.cooldown_seconds,
    is_active = EXCLUDED.is_active;
