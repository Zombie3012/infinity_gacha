-- DM-08 Multi-Floor Waiting Room building catalogue (Pick Me Up: Infinite Gacha architecture).
-- Remove legacy resource-gathering plots (Lumber, Mine, Farm) before upserting the official catalogue.
DELETE FROM base_buildings WHERE building_type IN ('LUMBER', 'MINE', 'FARM');
DELETE FROM building_types WHERE code IN ('LUMBER', 'MINE', 'FARM');

INSERT INTO building_types (code, name, category, description, max_level, max_workers, required_world_level, build_cost_silver, production)
VALUES
  ('SHOP_AIRSHIP', 'Thương Thuyền Khinh Khí', 'UTILITY', 'Cửa hàng khinh khí cầu neo tại căn cứ, bán vật phẩm và trang bị. Giá tạm thời 1 bạc mỗi món.', 1, 0, 1, 1000, NULL),
  ('ALLIANCE_HALL', 'Đại Sảnh Liên Minh', 'UTILITY', 'Hội quán Liên Minh trong Lâu đài: lập hội, tìm kiếm, gia nhập, quản lý thành viên và thông báo nội bộ.', 1, 0, 1, 1500, NULL),
  ('HERO_CHRONICLE', 'Sử Điện Anh Hùng', 'UTILITY', 'Lưu tiểu sử, hành trình và hồ sơ tử trận của từng Hero; hồi sinh bằng Ngọc hồi sinh 7★.', 1, 0, 1, 1200, NULL),
  ('HOUSE', 'Dormitory – Khu Cư Trú', 'UTILITY', 'Khu cư trú có 3 cấp (5 / 7 / 10 người), giúp Hero hồi phục thể lực và tinh thần theo hệ số cấp độ (1.0x / 1.5x / 2.0x).', 3, 0, 1, 1200, NULL),
  ('PARTY_MANSION', 'Party Mansion – Biệt Thự Tổ Đội', 'UTILITY', 'Công trình độc lập dành riêng cho Tổ đội (tối đa 5 người), tốc độ hồi phục thể lực & tinh thần gấp đôi (x2) Khu Cư Trú Lv.3.', 3, 0, 2, 5000, NULL),
  ('WAREHOUSE', 'Warehouse – Nhà Kho', 'STORAGE', 'Nhà kho 3 cấp (không cần Hero làm việc), mỗi cấp mở thêm +100 slot ô đồ (+100 / +200 / +300 ô).', 3, 0, 1, 1000, NULL),
  ('TRAINING_CENTER', 'Training Center – Khu Huấn Luyện', 'TRAINING', 'Khu huấn luyện thực chiến (tối đa 2 công trình theo cấp Master). Số Hero tối đa: Lv.1: 3 Hero, Lv.2: 5 Hero, Lv.3: 7 Hero.', 3, 7, 1, 1800, NULL),
  ('FORGE', 'Forge – Xưởng Rèn Trang Bị', 'CRAFTING', 'Xưởng rèn 3 cấp nơi chế tạo vũ khí, giáp trụ, cường hóa và ghép sao trang bị.', 3, 3, 1, 2200, NULL),
  ('KITCHEN', 'Kitchen – Bếp', 'PRODUCTION', 'Bếp 3 cấp (mỗi cấp +1 Hero làm việc): tự động nấu 20 / 40 / 80 FOOD mỗi giờ và chế biến món ăn đặc biệt tạo Buff.', 3, 3, 1, 1600, '{"resourceType":"FOOD","ratePerHour":20,"capacity":200}'::jsonb),
  ('MEDICAL', 'Recovery Center – Trung Tâm Hồi Phục', 'MEDICAL', 'Trung tâm hồi phục 3 cấp (1 Hero phụ trách): mở 2 / 4 / 6 slot chữa trị chấn thương theo từng cấp độ.', 3, 1, 1, 2400, NULL),
  ('HALL_OF_MAGIC', 'Hall of Magic – Đại Sảnh Ma Thuật', 'MAGIC', 'Đại sảnh Ma thuật 3 cấp (mở theo cấp Master, 2 người mỗi phân khu = tổng 6 Hero): Thư Viện Ma Thuật, Xưởng Giả Kim và Phòng Nghiên Cứu.', 3, 6, 2, 4000, NULL)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  max_level = EXCLUDED.max_level,
  max_workers = EXCLUDED.max_workers,
  required_world_level = EXCLUDED.required_world_level,
  build_cost_silver = EXCLUDED.build_cost_silver,
  production = EXCLUDED.production;
