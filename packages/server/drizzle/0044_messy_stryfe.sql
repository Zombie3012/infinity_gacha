ALTER TABLE "heroes" DROP CONSTRAINT IF EXISTS "uq_master_hero_template";--> statement-breakpoint
ALTER TABLE "hero_treatments" DROP CONSTRAINT IF EXISTS "hero_treatments_status_check";--> statement-breakpoint
ALTER TABLE "heroes" DROP CONSTRAINT IF EXISTS "heroes_config_id_hero_templates_code_fk";
--> statement-breakpoint
ALTER TABLE "hero_treatments" ADD CONSTRAINT "hero_treatments_status_check" CHECK ("hero_treatments"."status" IN ('ACTIVE', 'QUEUED', 'COMPLETED', 'CANCELLED'));