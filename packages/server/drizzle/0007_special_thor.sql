CREATE TABLE "equipment_instances" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"template_code" varchar(50) NOT NULL,
	"equipped_hero_id" varchar(36),
	"location" varchar(20) DEFAULT 'INVENTORY' NOT NULL,
	"drop_world_id" varchar(36),
	"drop_floor" integer,
	"dropped_at" timestamp with time zone,
	"picked_up_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "ck_equipment_location" CHECK ("equipment_instances"."location" IN ('INVENTORY', 'EQUIPPED', 'FLOOR_DROP')),
	CONSTRAINT "ck_equipment_location_links" CHECK (("equipment_instances"."location" = 'EQUIPPED' AND "equipment_instances"."equipped_hero_id" IS NOT NULL) OR ("equipment_instances"."location" <> 'EQUIPPED' AND "equipment_instances"."equipped_hero_id" IS NULL))
);
--> statement-breakpoint
CREATE TABLE "equipment_templates" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"slot_type" varchar(30) NOT NULL,
	"rarity" integer DEFAULT 1 NOT NULL,
	"bonus_hp" integer DEFAULT 0 NOT NULL,
	"bonus_atk" integer DEFAULT 0 NOT NULL,
	"bonus_def" integer DEFAULT 0 NOT NULL,
	"bonus_spd" integer DEFAULT 0 NOT NULL,
	"is_sample" boolean DEFAULT true NOT NULL,
	CONSTRAINT "equipment_templates_code_unique" UNIQUE("code")
);
--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD CONSTRAINT "equipment_instances_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD CONSTRAINT "equipment_instances_template_code_equipment_templates_code_fk" FOREIGN KEY ("template_code") REFERENCES "public"."equipment_templates"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD CONSTRAINT "equipment_instances_equipped_hero_id_heroes_id_fk" FOREIGN KEY ("equipped_hero_id") REFERENCES "public"."heroes"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "equipment_instances" ADD CONSTRAINT "equipment_instances_drop_world_id_worlds_id_fk" FOREIGN KEY ("drop_world_id") REFERENCES "public"."worlds"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_equipment_master_location" ON "equipment_instances" USING btree ("master_id","location");--> statement-breakpoint
CREATE INDEX "idx_equipment_floor_drop" ON "equipment_instances" USING btree ("drop_world_id","drop_floor");