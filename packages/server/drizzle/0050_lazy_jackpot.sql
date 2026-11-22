CREATE TABLE "pve_floor_rules" (
	"floor" integer PRIMARY KEY NOT NULL,
	"recall_policy" varchar(30) DEFAULT 'FREE' NOT NULL,
	CONSTRAINT "ck_pve_rule_floor" CHECK ("pve_floor_rules"."floor" >= 1),
	CONSTRAINT "ck_pve_rule_recall" CHECK ("pve_floor_rules"."recall_policy" IN ('FREE', 'UNTIL_COMPLETE'))
);
--> statement-breakpoint
ALTER TABLE "pve_maps" DROP CONSTRAINT "uq_pve_world_floor";--> statement-breakpoint
ALTER TABLE "pve_maps" DROP CONSTRAINT "ck_pve_map_status";--> statement-breakpoint
ALTER TABLE "pve_maps" ADD COLUMN "run" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "pve_maps" ADD COLUMN "recall_policy" varchar(30) DEFAULT 'FREE' NOT NULL;--> statement-breakpoint
ALTER TABLE "pve_maps" ADD COLUMN "recall_points" jsonb DEFAULT '[]'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "worlds" ADD COLUMN "pve_run" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "pve_maps" ADD CONSTRAINT "uq_pve_world_floor_run" UNIQUE("world_id","floor","run");--> statement-breakpoint
ALTER TABLE "pve_maps" ADD CONSTRAINT "ck_pve_map_recall" CHECK ("pve_maps"."recall_policy" IN ('FREE', 'UNTIL_COMPLETE'));--> statement-breakpoint
ALTER TABLE "pve_maps" ADD CONSTRAINT "ck_pve_map_status" CHECK ("pve_maps"."status" IN ('ACTIVE', 'CLEARED', 'ABANDONED'));