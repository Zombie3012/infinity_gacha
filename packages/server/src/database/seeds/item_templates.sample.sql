-- P2 item catalogue (mirrors the item ids already used by shop, crafting and rewards).
INSERT INTO item_templates (code, name, category, rarity, description, is_active)
VALUES
  ('SAMPLE_HERO_EXP_100', 'Sách EXP Hero Sơ Cấp (+1.000)', 'DEVELOPMENT', 2, 'Thêm 1.000 EXP cho Hero.', true),
  ('SAMPLE_HERO_EXP_1000', 'Sách EXP Hero Trung Cấp (+100.000)', 'DEVELOPMENT', 3, 'Thêm 100.000 EXP cho Hero.', true),
  ('SAMPLE_HERO_EXP_10000', 'Sách EXP Hero Cao Cấp (+10.000.000)', 'DEVELOPMENT', 4, 'Thêm 10.000.000 EXP cho Hero.', true),
  ('SAMPLE_HERO_PROMOTION_SEAL', 'Ấn Thăng Bậc Hero', 'DEVELOPMENT', 3, 'Nguyên liệu đột phá giới hạn cấp Hero.', true),
  ('SAMPLE_HERO_AWAKENING_CORE', 'Lõi Thức Tỉnh Hero', 'DEVELOPMENT', 4, 'Nguyên liệu thức tỉnh Hero.', true),
  ('SAMPLE_HERO_SKILL_BOOK', 'Sách Kỹ Năng Hero', 'DEVELOPMENT', 3, 'Nguyên liệu nâng cấp kỹ năng Hero.', true),
  ('TELEPORT_STONE', 'Đá dịch chuyển', 'CONSUMABLE', 3, 'Dùng trên map PvE để tạo điểm thu hồi tổ đội tại ô đang đứng, tồn tại tới hết tầng.', true),
  ('FOOD', 'Lương khô', 'CONSUMABLE', 1, 'Một phần ăn cho Hero hoặc khẩu phần thám hiểm.', true),
  ('FOOD_RAW', 'Lương thực thô', 'MATERIAL', 1, 'Nguyên liệu nấu tại Nhà bếp.', true),
  ('MEDICINE', 'Dược liệu điều trị', 'CONSUMABLE', 3, 'Dùng cho chữa trị khẩn cấp tại Viện Y Tế.', true),
  ('MANA_POTION', 'Thuốc ma lực', 'CONSUMABLE', 2, 'Hồi 50% MP tối đa cho Hero sử dụng.', true),
  ('STRENGTH_POTION', 'Thuốc cường lực', 'CONSUMABLE', 3, 'Tăng 20% ATK trong một trận PvE. Không cộng dồn.', true),
  ('RESURRECTION_GEM_7', 'Ngọc hồi sinh 7★', 'CONSUMABLE', 7, 'Dùng 1 viên tại Sử Điện Anh Hùng để hồi sinh một Hero về 100% HP, không phí thêm. Trang bị đã rơi không được tạo lại.', true),
  ('DIVINE_TEAR', 'Thần Lệ', 'CONSUMABLE', 5, 'Vật phẩm lịch sử, đã ngừng dùng để hồi sinh.', false),
  ('WOOD', 'Gỗ', 'MATERIAL', 1, 'Vật liệu xây dựng và nâng cấp công trình.', true),
  ('STONE', 'Đá', 'MATERIAL', 1, 'Vật liệu xây dựng và nâng cấp công trình.', true),
  ('IRON', 'Quặng sắt', 'MATERIAL', 2, 'Nguyên liệu chế tạo tại Xưởng Rèn.', true),
  ('ENHANCEMENT_STONE', 'Đá Tăng Cường', 'MATERIAL', 3, 'Nâng cấp trang bị tại Xưởng Rèn.', true),
  ('STAMINA_POTION', 'Bình Thể Lực Nhỏ', 'CONSUMABLE', 2, 'Hồi phục thể lực cho một Hero.', true),
  ('MOON_CAKE', 'Bánh Trăng', 'CONSUMABLE', 3, 'Món ăn đặc biệt bán vào cuối tuần.', true),
  ('ROAST_CHICKEN', 'Gà Quay', 'FOOD', 3, 'Món khoái khẩu của một số Hero.', true),
  ('HONEY_BREAD', 'Bánh Mật Ong', 'FOOD', 2, 'Món khoái khẩu của một số Hero.', true),
  ('SPICED_STEW', 'Hầm Gia Vị', 'FOOD', 3, 'Món khoái khẩu của một số Hero.', true),
  ('CLASS_CHANGE_TOKEN', 'Ấn Chuyển Nghề', 'CONSUMABLE', 4, 'Vật phẩm bắt buộc để đổi Class cho Hero.', true)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  rarity = EXCLUDED.rarity,
  description = EXCLUDED.description,
  is_active = EXCLUDED.is_active;

INSERT INTO item_templates(code,name,category,rarity,description,is_active)
SELECT 'ALCHEMY_HERB_' || star, 'Dược liệu ' || star || '★', 'MATERIAL', star,
  'Dược liệu giả kim. Bản đầu chỉ thu thập dược liệu 1★ trong PvE.', true FROM generate_series(1,7) star
ON CONFLICT(code) DO NOTHING;
