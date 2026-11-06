-- DM-08 Multi-Floor Waiting Room building catalogue (Pick Me Up: Infinite Gacha architecture).
-- Remove legacy resource-gathering plots (Lumber, Mine, Farm) before upserting the official catalogue.
DELETE FROM base_buildings WHERE building_type IN ('LUMBER', 'MINE', 'FARM');
DELETE FROM building_types WHERE code IN ('LUMBER', 'MINE', 'FARM');

INSERT INTO building_types (code, name, category, description, max_level, max_workers, required_world_level, build_cost_silver, production)
VALUES
  ('HOUSE', 'Dormitory (Nhà Nghỉ)', 'UTILITY', 'Nhà nghỉ cho Hero hồi phục thể lực sau lao động và chiến đấu. Có thể nâng cấp thành Party Mansion khi Master đạt cấp 30.', 5, 0, 1, 1200, NULL),
  ('PARTY_MANSION', 'Party Mansion (Biệt Thự Tổ Đội)', 'UTILITY', 'Biệt thự tổ đội nâng cấp từ Nhà Nghỉ khi Master đạt cấp 30, gia tăng tốc độ hồi phục và gắn kết đội hình.', 5, 2, 2, 5000, NULL),
  ('WAREHOUSE', 'Warehouse (Nhà Kho)', 'STORAGE', 'Nhà kho lưu trữ nguyên liệu, vật phẩm tiêu hao và trang bị chiến đấu của Căn cứ.', 5, 1, 1, 1000, NULL),
  ('TRAINING_CENTER', 'Training Center (Khu Huấn Luyện)', 'TRAINING', 'Khu huấn luyện thực chiến giúp Hero rèn luyện chỉ số cơ bản (STR/INT/STA/AGI) và nâng cấp kỹ năng.', 5, 3, 1, 1800, NULL),
  ('FORGE', 'Forge (Xưởng Rèn Trang Bị)', 'CRAFTING', 'Xưởng rèn nơi thao tác chế tạo vũ khí, giáp trụ, cường hóa và ghép sao trang bị.', 5, 2, 1, 2200, NULL),
  ('KITCHEN', 'Kitchen (Bếp Quân Lương)', 'PRODUCTION', 'Nhà bếp chế biến lương thực thô thành khẩu phần ăn cho Hero.', 5, 2, 1, 1600, '{"resourceType":"FOOD","ratePerHour":40,"capacity":400}'::jsonb),
  ('MEDICAL', 'Medical Facility (Bệnh Xá)', 'MEDICAL', 'Cơ sở chữa trị vết thương chuyên sâu và cấp cứu Hero sau trận đấu.', 5, 1, 1, 2400, NULL),
  ('HALL_OF_MAGIC', 'Hall of Magic (Đại Sảnh Ma Thuật)', 'MAGIC', 'Đại sảnh Ma thuật gồm 3 phân khu: Library (Thư viện), Alchemy Workshop (Xưởng giả kim) và Magic Research Lab (Phòng nghiên cứu ma thuật).', 5, 3, 2, 4000, NULL),
  ('LIBRARY', 'Library (Thư Viện Ma Thuật)', 'MAGIC_SUB', 'Phân khu Thư viện thuộc Đại sảnh Ma thuật: lưu trữ cổ thư, biên soạn Sách EXP và nghiên cứu kỹ năng.', 5, 2, 2, 2000, '{"resourceType":"SAMPLE_HERO_EXP_100","ratePerHour":4,"capacity":40}'::jsonb),
  ('ALCHEMY_WORKSHOP', 'Alchemy Workshop (Xưởng Giả Kim)', 'MAGIC_SUB', 'Phân khu Xưởng Giả Kim thuộc Đại sảnh Ma thuật: điều chế dược phẩm và đá cường hóa trang bị.', 5, 2, 2, 2200, '{"resourceType":"ENHANCEMENT_STONE","ratePerHour":6,"capacity":60}'::jsonb),
  ('MAGIC_RESEARCH_LAB', 'Magic Research Lab (Phòng Nghiên Cứu Ma Thuật)', 'MAGIC_SUB', 'Phân khu Phòng Nghiên Cứu Ma Thuật: nghiên cứu cộng hưởng nguyên tố, ma pháp trận và chuyển chức (Class Change).', 5, 2, 2, 2600, NULL)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  max_level = EXCLUDED.max_level,
  max_workers = EXCLUDED.max_workers,
  required_world_level = EXCLUDED.required_world_level,
  build_cost_silver = EXCLUDED.build_cost_silver,
  production = EXCLUDED.production;
