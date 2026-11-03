-- DM-12 quest and achievement catalogue (sample prototype rewards).
INSERT INTO quest_definitions (code, name, description, quest_type, objective_type, target_count, reward, required_level, is_active, sort_order)
VALUES
  ('MAIN_CLEAR_FLOOR', 'Bước chân đầu tiên', 'Hoàn thành một tầng Dungeon để mở rộng hành trình.', 'MAIN', 'CLEAR_FLOOR', 1, '{"silver":10000}'::jsonb, 1, true, 10),
  ('SIDE_CRAFT_2', 'Người thợ tập sự', 'Chế tạo 2 trang bị tại Xưởng Rèn.', 'SIDE', 'CRAFT_ITEM', 2, '{"silver":2000}'::jsonb, 1, true, 20),
  ('SIDE_COLLECT_200', 'Chủ kho cần mẫn', 'Thu thập 200 tài nguyên từ công trình.', 'SIDE', 'COLLECT_RESOURCE', 200, '{"silver":1500}'::jsonb, 1, true, 30),
  ('DAILY_WIN_1', 'Khởi động ngày mới', 'Thắng 1 trận Dungeon.', 'DAILY', 'WIN_BATTLE', 1, '{"silver":200}'::jsonb, 1, true, 40),
  ('DAILY_WIN_2', 'Chiến binh trong ngày', 'Thắng 2 trận Dungeon.', 'DAILY', 'WIN_BATTLE', 2, '{"silver":500}'::jsonb, 1, true, 41),
  ('DAILY_CRAFT_1', 'Một món mỗi ngày', 'Chế tạo 1 trang bị.', 'DAILY', 'CRAFT_ITEM', 1, '{"silver":300,"items":[{"itemId":"ENHANCEMENT_STONE","quantity":1}]}'::jsonb, 1, true, 42),
  ('DAILY_SPEND_1000', 'Tay mua nhanh', 'Chi 1.000 Xu Bạc tại Cửa hàng.', 'DAILY', 'SPEND_SILVER', 1000, '{"silver":200}'::jsonb, 1, true, 43),
  ('DAILY_COLLECT_100', 'Thu hoạch buổi sáng', 'Thu thập 100 tài nguyên.', 'DAILY', 'COLLECT_RESOURCE', 100, '{"silver":300,"items":[{"itemId":"FOOD","quantity":1}]}'::jsonb, 1, true, 44),
  ('WEEKLY_WIN_10', 'Mười trận tuần này', 'Thắng 10 trận Dungeon trong tuần.', 'WEEKLY', 'WIN_BATTLE', 10, '{"silver":5000}'::jsonb, 1, true, 50),
  ('WEEKLY_CRAFT_5', 'Xưởng rèn bận rộn', 'Chế tạo 5 trang bị trong tuần.', 'WEEKLY', 'CRAFT_ITEM', 5, '{"items":[{"itemId":"ENHANCEMENT_STONE","quantity":10}]}'::jsonb, 1, true, 51),
  ('WEEKLY_SPEND_10000', 'Đại gia tuần lễ', 'Chi 10.000 Xu Bạc trong tuần.', 'WEEKLY', 'SPEND_SILVER', 10000, '{"silver":3000}'::jsonb, 1, true, 52)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  quest_type = EXCLUDED.quest_type,
  objective_type = EXCLUDED.objective_type,
  target_count = EXCLUDED.target_count,
  reward = EXCLUDED.reward,
  required_level = EXCLUDED.required_level,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;

INSERT INTO achievements (code, name, description, category, metric, threshold, reward, is_active)
VALUES
  ('ACH_HERO_10', 'Bộ sưu tập khởi đầu', 'Sở hữu 10 Hero.', 'COLLECTION', 'OWN_HEROES', 10, '{"gems":100}'::jsonb, true),
  ('ACH_HERO_20', 'Bộ sưu tập huyền thoại', 'Sở hữu 20 Hero.', 'COLLECTION', 'OWN_HEROES', 20, '{"gems":300}'::jsonb, true),
  ('ACH_WIN_25', 'Bách thắng', 'Thắng 25 trận Dungeon.', 'EXPLORATION', 'WIN_BATTLE', 25, '{"gems":50}'::jsonb, true),
  ('ACH_CRAFT_10', 'Thợ rèn lành nghề', 'Chế tạo 10 trang bị.', 'BASE', 'CRAFT_ITEM', 10, '{"gems":50}'::jsonb, true),
  ('ACH_SPEND_50000', 'Ông trùm kinh tế', 'Chi 50.000 Xu Bạc.', 'ECONOMY', 'SPEND_SILVER', 50000, '{"gems":100}'::jsonb, true)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  metric = EXCLUDED.metric,
  threshold = EXCLUDED.threshold,
  reward = EXCLUDED.reward,
  is_active = EXCLUDED.is_active;
