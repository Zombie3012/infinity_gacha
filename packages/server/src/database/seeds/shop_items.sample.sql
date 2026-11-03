-- DM-11 base shop catalogue (sample prototype prices).
INSERT INTO shop_items (code, name, description, item_id, category, price_silver, daily_limit, rotation_days, is_active, sort_order)
VALUES
  ('STAMINA_POTION', 'Bình Thể Lực Nhỏ', 'Hồi phục thể lực cho một Hero.', 'STAMINA_POTION', 'CONSUMABLE', 500, 5, '{}', true, 10),
  ('MEDICINE', 'Dược liệu điều trị', 'Dùng cho chữa trị khẩn cấp tại Viện Y Tế.', 'MEDICINE', 'CONSUMABLE', 800, 3, '{}', true, 20),
  ('FOOD', 'Lương khô', 'Một phần ăn cho Hero hoặc khẩu phần thám hiểm.', 'FOOD', 'CONSUMABLE', 200, 20, '{}', true, 30),
  ('FOOD_RAW', 'Lương thực thô', 'Nguyên liệu để Nhà bếp chế biến thành lương khô.', 'FOOD_RAW', 'MATERIAL', 120, 40, '{}', true, 40),
  ('WOOD', 'Gỗ', 'Vật liệu xây dựng và nâng cấp công trình.', 'WOOD', 'MATERIAL', 150, 50, '{}', true, 50),
  ('STONE', 'Đá', 'Vật liệu xây dựng và nâng cấp công trình.', 'STONE', 'MATERIAL', 150, 50, '{}', true, 60),
  ('IRON', 'Quặng sắt', 'Nguyên liệu chế tạo tại Xưởng Rèn.', 'IRON', 'MATERIAL', 300, 30, '{}', true, 70),
  ('DIVINE_TEAR', 'Thần Lệ', 'Vật phẩm hồi sinh Hero Limited/Special.', 'DIVINE_TEAR', 'CONSUMABLE', 5000, 1, '{}', true, 80),
  ('MOON_CAKE', 'Bánh Trăng', 'Món ăn đặc biệt, chỉ bán vào cuối tuần.', 'MOON_CAKE', 'CONSUMABLE', 900, 2, '{0,6}', true, 90)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  item_id = EXCLUDED.item_id,
  category = EXCLUDED.category,
  price_silver = EXCLUDED.price_silver,
  daily_limit = EXCLUDED.daily_limit,
  rotation_days = EXCLUDED.rotation_days,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;
