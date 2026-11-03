-- DM-08 building catalogue (sample prototype balance, not approved production data).
INSERT INTO building_types (code, name, category, description, max_level, max_workers, required_world_level, build_cost_silver, production)
VALUES
  ('HOUSE', 'Dormitory', 'UTILITY', 'Nhà nghỉ cho Hero hồi phục sau lao động và chiến đấu.', 5, 0, 1, 1500, NULL),
  ('FARM', 'Farm', 'PRODUCTION', 'Nông trại trồng lương thực thô cho nhà bếp.', 5, 2, 1, 1200, '{"resourceType":"FOOD_RAW","ratePerHour":50,"capacity":500}'::jsonb),
  ('LUMBER', 'Lumber Mill', 'PRODUCTION', 'Xưởng gỗ khai thác gỗ để xây dựng và nâng cấp.', 5, 2, 1, 1400, '{"resourceType":"WOOD","ratePerHour":80,"capacity":800}'::jsonb),
  ('MINE', 'Stone Quarry', 'PRODUCTION', 'Mỏ đá khai thác đá phục vụ nâng cấp công trình.', 5, 2, 1, 1500, '{"resourceType":"STONE","ratePerHour":100,"capacity":1000}'::jsonb),
  ('FORGE', 'Smithy', 'PRODUCTION', 'Xưởng rèn luyện quặng sắt thành vật liệu chế tạo.', 5, 2, 2, 2500, '{"resourceType":"IRON","ratePerHour":30,"capacity":300}'::jsonb),
  ('KITCHEN', 'Kitchen', 'PRODUCTION', 'Nhà bếp chế biến lương thực thô thành thức ăn cho Hero.', 5, 1, 2, 2000, '{"resourceType":"FOOD","ratePerHour":20,"capacity":200}'::jsonb),
  ('MEDICAL', 'Medical Facility', 'MEDICAL', 'Cơ sở chữa trị vết thương và hồi phục Hero.', 5, 0, 2, 3000, NULL)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  max_level = EXCLUDED.max_level,
  max_workers = EXCLUDED.max_workers,
  required_world_level = EXCLUDED.required_world_level,
  build_cost_silver = EXCLUDED.build_cost_silver,
  production = EXCLUDED.production;
