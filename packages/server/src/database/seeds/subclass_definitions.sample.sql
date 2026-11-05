-- Combat v2 subclass catalogue. A Hero may hold up to three subclasses.
INSERT INTO subclass_definitions
    (code, name, primary_stat, required_value, required_level, effect, is_enabled)
VALUES
    ('BLACKSMITH', 'Thợ rèn', 'str', 150, 20, 'Giảm 10% chi phí rèn và nâng cấp trang bị.', TRUE),
    ('ALCHEMIST', 'Nhà giả kim', 'int', 180, 20, 'Tăng 25% hiệu quả thuốc hồi phục.', TRUE),
    ('JEWELER', 'Thợ kim hoàn', 'int', 150, 20, 'Chế trang sức và đá quý; cần thêm AGI 100.', TRUE),
    ('COOK', 'Đầu bếp', 'sta', 120, 20, 'Tăng 20% hiệu quả thức ăn và buff.', TRUE),
    ('HUNTER', 'Thợ săn', 'agi', 150, 20, 'Tăng 25% thịt và da thu được khi săn.', TRUE),
    ('RESOURCE_GATHERER', 'Thu thập tài nguyên', 'sta', 100, 20, 'Tăng 15% tài nguyên thu hoạch.', TRUE),
    ('RUNE_MASTER', 'Bậc thầy rune', 'int', 220, 40, 'Mở thêm 1 slot khắc ấn.', TRUE)
ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    primary_stat = EXCLUDED.primary_stat,
    required_value = EXCLUDED.required_value,
    required_level = EXCLUDED.required_level,
    effect = EXCLUDED.effect,
    is_enabled = EXCLUDED.is_enabled;
