CREATE TABLE "pve_battles" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"map_id" varchar(36) NOT NULL,
	"squad_id" varchar(36) NOT NULL,
	"tile_id" integer NOT NULL,
	"combat_session_id" varchar(36) NOT NULL,
	"report" jsonb NOT NULL,
	"settlement" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pve_battles_combat_session_id_unique" UNIQUE("combat_session_id")
);
--> statement-breakpoint
CREATE TABLE "pve_commands" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"key" varchar(80) NOT NULL,
	"operation" varchar(100) NOT NULL,
	"request_hash" varchar(64) NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_pve_command_key" UNIQUE("master_id","key")
);
--> statement-breakpoint
CREATE TABLE "pve_events" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"map_id" varchar(36) NOT NULL,
	"revision" integer NOT NULL,
	"kind" varchar(30) NOT NULL,
	"data" jsonb NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_pve_event_revision" UNIQUE("map_id","revision")
);
--> statement-breakpoint
CREATE TABLE "pve_hero_reservations" (
	"hero_id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"map_id" varchar(36) NOT NULL,
	"squad_id" varchar(36) NOT NULL,
	"reserved_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "pve_maps" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"world_id" varchar(36) NOT NULL,
	"floor" integer NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"layout" jsonb NOT NULL,
	"encounter_catalog" jsonb NOT NULL,
	"discovered" jsonb NOT NULL,
	"cleared" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"collected" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"revision" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"cleared_at" timestamp with time zone,
	CONSTRAINT "uq_pve_world_floor" UNIQUE("world_id","floor"),
	CONSTRAINT "ck_pve_map_status" CHECK ("pve_maps"."status" IN ('ACTIVE', 'CLEARED')),
	CONSTRAINT "ck_pve_floor" CHECK ("pve_maps"."floor" >= 1)
);
--> statement-breakpoint
CREATE TABLE "pve_party_plans" (
	"party_id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"plan" jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "pve_squads" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"map_id" varchar(36) NOT NULL,
	"party_id" varchar(36) NOT NULL,
	"name" varchar(60) NOT NULL,
	"plan" jsonb NOT NULL,
	"status" varchar(20) DEFAULT 'IDLE' NOT NULL,
	"x" integer DEFAULT 0 NOT NULL,
	"y" integer DEFAULT 0 NOT NULL,
	"route" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"next_step_at" timestamp with time zone,
	"last_battle_id" varchar(36),
	"deployed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"withdrawn_at" timestamp with time zone,
	CONSTRAINT "ck_pve_squad_status" CHECK ("pve_squads"."status" IN ('IDLE', 'MOVING', 'FIGHTING', 'WITHDRAWN', 'DEFEATED')),
	CONSTRAINT "ck_pve_squad_position" CHECK ("pve_squads"."x" BETWEEN 0 AND 11 AND "pve_squads"."y" BETWEEN 0 AND 11)
);
--> statement-breakpoint
ALTER TABLE "pve_battles" ADD CONSTRAINT "pve_battles_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_battles" ADD CONSTRAINT "pve_battles_map_id_pve_maps_id_fk" FOREIGN KEY ("map_id") REFERENCES "public"."pve_maps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_battles" ADD CONSTRAINT "pve_battles_squad_id_pve_squads_id_fk" FOREIGN KEY ("squad_id") REFERENCES "public"."pve_squads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_battles" ADD CONSTRAINT "pve_battles_combat_session_id_combat_sessions_id_fk" FOREIGN KEY ("combat_session_id") REFERENCES "public"."combat_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_commands" ADD CONSTRAINT "pve_commands_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_events" ADD CONSTRAINT "pve_events_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_events" ADD CONSTRAINT "pve_events_map_id_pve_maps_id_fk" FOREIGN KEY ("map_id") REFERENCES "public"."pve_maps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_hero_reservations" ADD CONSTRAINT "pve_hero_reservations_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_hero_reservations" ADD CONSTRAINT "pve_hero_reservations_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_hero_reservations" ADD CONSTRAINT "pve_hero_reservations_map_id_pve_maps_id_fk" FOREIGN KEY ("map_id") REFERENCES "public"."pve_maps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_hero_reservations" ADD CONSTRAINT "pve_hero_reservations_squad_id_pve_squads_id_fk" FOREIGN KEY ("squad_id") REFERENCES "public"."pve_squads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_maps" ADD CONSTRAINT "pve_maps_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_maps" ADD CONSTRAINT "pve_maps_world_id_worlds_id_fk" FOREIGN KEY ("world_id") REFERENCES "public"."worlds"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_party_plans" ADD CONSTRAINT "pve_party_plans_party_id_master_parties_id_fk" FOREIGN KEY ("party_id") REFERENCES "public"."master_parties"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_party_plans" ADD CONSTRAINT "pve_party_plans_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD CONSTRAINT "pve_squads_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD CONSTRAINT "pve_squads_map_id_pve_maps_id_fk" FOREIGN KEY ("map_id") REFERENCES "public"."pve_maps"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD CONSTRAINT "pve_squads_party_id_master_parties_id_fk" FOREIGN KEY ("party_id") REFERENCES "public"."master_parties"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_pve_battle_master" ON "pve_battles" USING btree ("master_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_pve_active_master" ON "pve_maps" USING btree ("master_id") WHERE "pve_maps"."status" = 'ACTIVE';--> statement-breakpoint
CREATE UNIQUE INDEX "uq_pve_deployed_party" ON "pve_squads" USING btree ("party_id") WHERE "pve_squads"."status" IN ('IDLE', 'MOVING', 'FIGHTING');--> statement-breakpoint
CREATE INDEX "idx_pve_due_steps" ON "pve_squads" USING btree ("master_id","next_step_at");