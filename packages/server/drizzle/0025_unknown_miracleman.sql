CREATE TABLE "hero_injuries" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"severity" varchar(20) NOT NULL,
	"penalty_percent" integer NOT NULL,
	"natural_heal_at" timestamp with time zone NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"healed_at" timestamp with time zone,
	"healed_by" varchar(20),
	CONSTRAINT "hero_injuries_severity_check" CHECK ("hero_injuries"."severity" IN ('MINOR', 'MODERATE', 'SEVERE'))
);
--> statement-breakpoint
CREATE TABLE "hero_resurrection_cycles" (
	"hero_id" varchar(36) PRIMARY KEY NOT NULL,
	"cycle_start_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resurrection_count" integer DEFAULT 0 NOT NULL,
	"last_resurrected_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "hero_treatments" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"building_id" varchar(36),
	"injury_id" varchar(36),
	"treatment_type" varchar(20) NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finishes_at" timestamp with time zone,
	"completed_at" timestamp with time zone,
	"cost_silver" bigint DEFAULT 0 NOT NULL,
	"cost_items" jsonb DEFAULT '{}'::jsonb NOT NULL,
	CONSTRAINT "hero_treatments_type_check" CHECK ("hero_treatments"."treatment_type" IN ('INJURY', 'RESURRECTION')),
	CONSTRAINT "hero_treatments_status_check" CHECK ("hero_treatments"."status" IN ('ACTIVE', 'COMPLETED', 'CANCELLED'))
);
--> statement-breakpoint
ALTER TABLE "hero_injuries" ADD CONSTRAINT "hero_injuries_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_injuries" ADD CONSTRAINT "hero_injuries_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_resurrection_cycles" ADD CONSTRAINT "hero_resurrection_cycles_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_treatments" ADD CONSTRAINT "hero_treatments_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_treatments" ADD CONSTRAINT "hero_treatments_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_treatments" ADD CONSTRAINT "hero_treatments_building_id_base_buildings_id_fk" FOREIGN KEY ("building_id") REFERENCES "public"."base_buildings"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_treatments" ADD CONSTRAINT "hero_treatments_injury_id_hero_injuries_id_fk" FOREIGN KEY ("injury_id") REFERENCES "public"."hero_injuries"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_hero_injuries_hero" ON "hero_injuries" USING btree ("hero_id","healed_at");--> statement-breakpoint
CREATE INDEX "idx_hero_treatments_status" ON "hero_treatments" USING btree ("status","finishes_at");