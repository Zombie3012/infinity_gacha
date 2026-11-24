-- M1/M2: Airship Port (Bến Thiên Hành) + Dynamic Fog of War (1h) + Emerging World Dungeons

CREATE TABLE IF NOT EXISTS "master_airships" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "blueprint_code" varchar(32) NOT NULL,
  "name" varchar(64) NOT NULL,
  "size_class" varchar(16) NOT NULL,
  "grid_w" integer NOT NULL,
  "grid_h" integer NOT NULL,
  "dock_x" integer NOT NULL DEFAULT 0,
  "dock_y" integer NOT NULL DEFAULT 0,
  "rotation" integer NOT NULL DEFAULT 0,
  "level" integer NOT NULL DEFAULT 1,
  "hp" integer NOT NULL DEFAULT 100,
  "max_hp" integer NOT NULL DEFAULT 100,
  "status" varchar(20) NOT NULL DEFAULT 'DOCKED',
  "busy_until" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "ck_airship_blueprint" CHECK ("blueprint_code" IN ('SCOUT_SKIFF', 'RESCUE_CUTTER', 'WAR_DREADNOUGHT', 'TRANSPORT_CARRIER')),
  CONSTRAINT "ck_airship_size_class" CHECK ("size_class" IN ('SMALL', 'MEDIUM', 'LARGE')),
  CONSTRAINT "ck_airship_rotation" CHECK ("rotation" IN (0, 90)),
  CONSTRAINT "ck_airship_status" CHECK ("status" IN ('DOCKED', 'CRAFTING', 'DEPLOYED', 'REPAIRING', 'STRANDED'))
);
CREATE INDEX IF NOT EXISTS "idx_master_airships_master" ON "master_airships" ("master_id", "status");

CREATE TABLE IF NOT EXISTS "master_airship_techs" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "tech_code" varchar(40) NOT NULL,
  "unlocked_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "uq_master_airship_tech" UNIQUE ("master_id", "tech_code")
);

CREATE TABLE IF NOT EXISTS "master_tile_vision" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "tile_id" varchar(36) NOT NULL REFERENCES "world_tiles"("id") ON DELETE CASCADE,
  "visible_until" timestamp with time zone NOT NULL,
  "last_scouted_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "uq_master_tile_vision" UNIQUE ("master_id", "tile_id")
);
CREATE INDEX IF NOT EXISTS "idx_master_tile_vision_expiry" ON "master_tile_vision" ("master_id", "visible_until");

CREATE TABLE IF NOT EXISTS "world_dungeons" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "tile_id" varchar(36) NOT NULL REFERENCES "world_tiles"("id") ON DELETE CASCADE,
  "name" varchar(96) NOT NULL,
  "rank" varchar(8) NOT NULL,
  "recommended_power" integer NOT NULL DEFAULT 1000,
  "max_party_size" integer NOT NULL DEFAULT 5,
  "boss_name" varchar(64) NOT NULL,
  "rewards" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "status" varchar(16) NOT NULL DEFAULT 'ACTIVE',
  "spawned_at" timestamp with time zone DEFAULT now() NOT NULL,
  "expires_at" timestamp with time zone NOT NULL,
  "cleared_by_master_id" varchar(36) REFERENCES "masters"("id") ON DELETE SET NULL,
  CONSTRAINT "ck_world_dungeon_rank" CHECK ("rank" IN ('D', 'C', 'B', 'A', 'S')),
  CONSTRAINT "ck_world_dungeon_status" CHECK ("status" IN ('ACTIVE', 'CLEARED', 'EXPIRED'))
);
CREATE INDEX IF NOT EXISTS "idx_world_dungeons_active" ON "world_dungeons" ("status", "expires_at");

-- Extend hero_expeditions for Airships, Emerging Dungeons, Rescue & Redirect
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "airship_id" varchar(36) REFERENCES "master_airships"("id") ON DELETE SET NULL;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "dungeon_id" varchar(36) REFERENCES "world_dungeons"("id") ON DELETE SET NULL;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "origin_x" integer;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "origin_y" integer;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "path_tiles" jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "rescue_target_expedition_id" varchar(36);
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "stranded_at" timestamp with time zone;
ALTER TABLE "hero_expeditions" ADD COLUMN IF NOT EXISTS "redirected_at" timestamp with time zone;

ALTER TABLE "hero_expeditions" DROP CONSTRAINT IF EXISTS "expedition_mission_check";
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "expedition_mission_check"
  CHECK ("mission" IN ('SCOUT', 'ATTACK', 'DUNGEON', 'RESCUE'));

ALTER TABLE "hero_expeditions" DROP CONSTRAINT IF EXISTS "expedition_status_check";
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "expedition_status_check"
  CHECK ("status" IN ('TRAVELING', 'RETURNING', 'STRANDED', 'COMPLETED', 'RECALLED'));
