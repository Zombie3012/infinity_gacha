ALTER TABLE "worlds" ALTER COLUMN "base_zones" SET DEFAULT 2;
UPDATE "worlds" SET "base_zones" = 2 WHERE "base_zones" < 2;
