-- 0064: Full-Planet 600x300 World Tiles (5 Continents + Great Ocean + Imperial Wonder) & RTS Spawn Metadata

ALTER TABLE "world_tiles"
  ADD COLUMN IF NOT EXISTS "continent_id" varchar(40) NOT NULL DEFAULT 'emerald_reach',
  ADD COLUMN IF NOT EXISTS "region_id" varchar(64),
  ADD COLUMN IF NOT EXISTS "zone_tier" integer NOT NULL DEFAULT 1;

ALTER TABLE "master_world_status"
  ADD COLUMN IF NOT EXISTS "continent_id" varchar(40) NOT NULL DEFAULT 'emerald_reach';

CREATE INDEX IF NOT EXISTS "idx_world_tiles_spawn"
  ON "world_tiles" ("is_outer_rim", "continent_id", "zone_tier");

CREATE INDEX IF NOT EXISTS "idx_master_world_base"
  ON "master_world_status" ("base_x", "base_y");
