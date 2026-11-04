-- Editable sample World floor events. Probabilities and effects are prototype tuning.
INSERT INTO dungeon_event_templates
    (id, code, name, description, event_type, weight, silver_reward, heal_percent, enemy_attack_multiplier, is_active)
VALUES
    ('dungeon-event-sample-001', 'SAMPLE_SUPPLY_CACHE', 'Supply Cache', 'A forgotten pouch is hidden under the roots.', 'CACHE', 40, 30, 0, 1.0, TRUE),
    ('dungeon-event-sample-002', 'SAMPLE_MOSS_SPRING', 'Moss Spring', 'A quiet spring restores some Hero HP before combat.', 'REST', 35, 0, 0.15, 1.0, TRUE),
    ('dungeon-event-sample-003', 'SAMPLE_BANDIT_AMBUSH', 'Bandit Ambush', 'Bandits strike first and hit harder.', 'AMBUSH', 25, 0, 0, 1.15, TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name, description = EXCLUDED.description, event_type = EXCLUDED.event_type,
    weight = EXCLUDED.weight, silver_reward = EXCLUDED.silver_reward, heal_percent = EXCLUDED.heal_percent,
    enemy_attack_multiplier = EXCLUDED.enemy_attack_multiplier, is_active = EXCLUDED.is_active;
