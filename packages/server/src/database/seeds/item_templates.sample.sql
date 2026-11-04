-- P2 item catalogue (mirrors the item ids already used by shop, crafting and rewards).
INSERT INTO item_templates (code, name, category, rarity, description, is_active)
VALUES
  ('FOOD', 'Lương khô', 'CONSUMABLE', 1, 'Một phần ăn cho Hero hoặc khẩu phần thám hiểm.', true),
  ('FOOD_RAW', 'Lương thực thô', 'MATERIAL', 1, 'Nguyên liệu nấu tại Nhà bếp.', true),
  ('MEDICINE', 'Dược liệu điều trị', 'CONSUMABLE', 3, 'Dùng cho chữa trị khẩn cấp tại Viện Y Tế.', true),
  ('DIVINE_TEAR', 'Thần Lệ', 'CONSUMABLE', 5, 'Vật phẩm hồi sinh Hero Limited/Special.', true),
  ('WOOD', 'Gỗ', 'MATERIAL', 1, 'Vật liệu xây dựng và nâng cấp công trình.', true),
  ('STONE', 'Đá', 'MATERIAL', 1, 'Vật liệu xây dựng và nâng cấp công trình.', true),
  ('IRON', 'Quặng sắt', 'MATERIAL', 2, 'Nguyên liệu chế tạo tại Xưởng Rèn.', true),
  ('ENHANCEMENT_STONE', 'Đá Tăng Cường', 'MATERIAL', 3, 'Nâng cấp trang bị tại Xưởng Rèn.', true),
  ('STAMINA_POTION', 'Bình Thể Lực Nhỏ', 'CONSUMABLE', 2, 'Hồi phục thể lực cho một Hero.', true),
  ('MOON_CAKE', 'Bánh Trăng', 'CONSUMABLE', 3, 'Món ăn đặc biệt bán vào cuối tuần.', true),
  ('ROAST_CHICKEN', 'Gà Quay', 'FOOD', 3, 'Món khoái khẩu của một số Hero.', true),
  ('HONEY_BREAD', 'Bánh Mật Ong', 'FOOD', 2, 'Món khoái khẩu của một số Hero.', true),
  ('SPICED_STEW', 'Hầm Gia Vị', 'FOOD', 3, 'Món khoái khẩu của một số Hero.', true)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  rarity = EXCLUDED.rarity,
  description = EXCLUDED.description,
  is_active = EXCLUDED.is_active;
