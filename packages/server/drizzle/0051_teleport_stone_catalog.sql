-- Custom SQL migration file, put your code below! --
INSERT INTO item_templates (code, name, category, rarity, description, is_active)
VALUES ('TELEPORT_STONE', 'Đá dịch chuyển', 'CONSUMABLE', 3,
  'Dùng trên map PvE để tạo điểm thu hồi tổ đội tại ô đang đứng, tồn tại tới hết tầng.', true)
ON CONFLICT (code) DO NOTHING;
--> statement-breakpoint
INSERT INTO shop_items (code, name, description, item_id, category, price_silver, daily_limit, rotation_days, is_active, sort_order)
VALUES ('TELEPORT_STONE', 'Đá dịch chuyển', 'Tạo điểm thu hồi tổ đội trên map PvE, kể cả tầng cấm thu hồi tự do.',
  'TELEPORT_STONE', 'CONSUMABLE', 800, 3, '{}', true, 25)
ON CONFLICT (code) DO NOTHING;
