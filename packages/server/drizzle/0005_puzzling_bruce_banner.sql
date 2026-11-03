CREATE TABLE "combat_party_slots" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"slot_index" integer NOT NULL,
	CONSTRAINT "uq_combat_party_master_slot" UNIQUE("master_id","slot_index"),
	CONSTRAINT "uq_combat_party_master_hero" UNIQUE("master_id","hero_id")
);
--> statement-breakpoint
CREATE TABLE "enemy_templates" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"base_hp" integer NOT NULL,
	"base_atk" integer NOT NULL,
	"base_def" integer NOT NULL,
	"base_spd" integer NOT NULL,
	"base_exp_reward" integer NOT NULL,
	"base_silver_reward" integer NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "enemy_templates_code_unique" UNIQUE("code")
);
--> statement-breakpoint
CREATE TABLE "hero_death_records" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"combat_session_id" varchar(36) NOT NULL,
	"summon_origin" varchar(20) NOT NULL,
	"death_type" varchar(20) NOT NULL,
	"dropped_equipment" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"cause" varchar(100) NOT NULL,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "combat_sessions" ADD COLUMN "combat_state" jsonb;--> statement-breakpoint
ALTER TABLE "combat_sessions" ADD COLUMN "battle_report" jsonb;--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD CONSTRAINT "combat_party_slots_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD CONSTRAINT "combat_party_slots_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_death_records" ADD CONSTRAINT "hero_death_records_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_death_records" ADD CONSTRAINT "hero_death_records_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_death_records" ADD CONSTRAINT "hero_death_records_combat_session_id_combat_sessions_id_fk" FOREIGN KEY ("combat_session_id") REFERENCES "public"."combat_sessions"("id") ON DELETE cascade ON UPDATE no action;