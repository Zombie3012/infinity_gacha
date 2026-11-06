ALTER TABLE "equipment_templates" ADD COLUMN "bonus_str" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "bonus_int" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "bonus_sta" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "bonus_agi" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "bonus_matk" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "bonus_mdef" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "equipment_templates" ADD COLUMN "v2_stats" jsonb DEFAULT '{}'::jsonb NOT NULL;