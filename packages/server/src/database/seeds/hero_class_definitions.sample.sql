-- Combat v2 class catalogue (mirrors packages/shared/src/combat/stats.ts).
INSERT INTO hero_class_definitions
    (code, name, base_crit_rate, growth_str, growth_int, growth_sta, growth_agi, passive, is_enabled)
VALUES
    ('UNCLASSIFIED', 'Chưa phân loại', 5, 1.00, 1.00, 1.00, 1.00, 'Chưa có nội tại nghề nghiệp.', TRUE),
    ('WARRIOR', 'Chiến binh', 5, 1.20, 0.70, 1.15, 0.90, 'Tăng hiệu quả phòng thủ vật lý.', TRUE),
    ('THIEF', 'Đạo tặc', 50, 0.95, 0.75, 0.85, 1.30, 'Tăng Crit Rate và Evasion.', TRUE),
    ('SPEARMAN', 'Thương binh', 5, 1.20, 0.65, 0.95, 1.10, 'Tăng khả năng xuyên giáp.', TRUE),
    ('ARCHER', 'Cung thủ', 5, 0.95, 0.75, 0.85, 1.30, 'Tăng Accuracy và sát thương tầm xa.', TRUE),
    ('MAGE', 'Pháp sư', 5, 0.60, 1.35, 0.85, 0.95, 'Tăng Magic ATK và hiệu quả phép thuật.', TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    base_crit_rate = EXCLUDED.base_crit_rate,
    growth_str = EXCLUDED.growth_str,
    growth_int = EXCLUDED.growth_int,
    growth_sta = EXCLUDED.growth_sta,
    growth_agi = EXCLUDED.growth_agi,
    passive = EXCLUDED.passive,
    is_enabled = EXCLUDED.is_enabled;
