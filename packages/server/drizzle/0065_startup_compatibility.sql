-- Bring existing databases up to date without rerunning the sample seeds.
-- The original 0045_hero_housing.sql was never registered in the journal.
ALTER TABLE "hero_survival_states"
  ADD COLUMN IF NOT EXISTS "housing_building_id" varchar(36)
  REFERENCES "base_buildings"("id") ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS "idx_hero_survival_housing"
  ON "hero_survival_states" ("housing_building_id");

INSERT INTO "building_types"
  (code, name, category, description, max_level, max_workers, required_world_level, build_cost_silver, production)
VALUES
  ('ALLIANCE_HALL', 'Đại Sảnh Liên Minh', 'UTILITY', 'Hội quán Liên Minh trong Lâu đài: lập hội, tìm kiếm, gia nhập, quản lý thành viên và thông báo nội bộ.', 1, 0, 1, 1500, NULL),
  ('AIRSHIP_PORT', 'Bến Thiên Hành – Cảng Tàu Bay', 'UTILITY', 'Mở khóa khi vượt Tháp tầng 25. Nơi nghiên cứu công nghệ hàng không, chế tạo, nâng cấp, sửa chữa và neo đậu tàu bay theo diện tích lưới (Lv.1: 4x4 đến Lv.5: 8x8 + mở rộng qua Cây Công Nghệ).', 5, 3, 1, 3000, NULL)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  category = EXCLUDED.category,
  description = EXCLUDED.description,
  max_level = EXCLUDED.max_level,
  max_workers = EXCLUDED.max_workers,
  required_world_level = EXCLUDED.required_world_level,
  build_cost_silver = EXCLUDED.build_cost_silver,
  production = EXCLUDED.production;
