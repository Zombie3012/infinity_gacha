ALTER TABLE "pve_squads" DROP CONSTRAINT "ck_pve_squad_position";--> statement-breakpoint
ALTER TABLE "pve_maps" ADD COLUMN "exploration" jsonb;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD COLUMN "area_id" varchar(80) DEFAULT 'floor' NOT NULL;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD COLUMN "pending_portal_id" varchar(100);--> statement-breakpoint
ALTER TABLE "pve_squads" ADD CONSTRAINT "ck_pve_squad_position" CHECK ("pve_squads"."x" BETWEEN 0 AND 19 AND "pve_squads"."y" BETWEEN 0 AND 19);