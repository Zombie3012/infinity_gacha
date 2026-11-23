ALTER TABLE "hero_survival_states" ADD COLUMN IF NOT EXISTS "housing_building_id" varchar(36) REFERENCES "base_buildings"("id") ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS "idx_hero_survival_housing" ON "hero_survival_states" ("housing_building_id");
