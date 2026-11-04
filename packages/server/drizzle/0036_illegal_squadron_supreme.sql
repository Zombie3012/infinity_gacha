CREATE TABLE "expedition_members" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"expedition_id" varchar(36) NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"slot_index" integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
CREATE TABLE "hero_expeditions" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"mission" varchar(20) NOT NULL,
	"status" varchar(20) DEFAULT 'TRAVELING' NOT NULL,
	"depart_at" timestamp with time zone DEFAULT now() NOT NULL,
	"arrive_at" timestamp with time zone NOT NULL,
	"return_at" timestamp with time zone,
	"result" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "expedition_mission_check" CHECK ("hero_expeditions"."mission" IN ('SCOUT', 'ATTACK')),
	CONSTRAINT "expedition_status_check" CHECK ("hero_expeditions"."status" IN ('TRAVELING', 'RETURNING', 'COMPLETED', 'RECALLED'))
);
--> statement-breakpoint
CREATE TABLE "tile_clearances" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"cleared_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "expedition_members" ADD CONSTRAINT "expedition_members_expedition_id_hero_expeditions_id_fk" FOREIGN KEY ("expedition_id") REFERENCES "public"."hero_expeditions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "expedition_members" ADD CONSTRAINT "expedition_members_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "hero_expeditions_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_expeditions" ADD CONSTRAINT "hero_expeditions_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tile_clearances" ADD CONSTRAINT "tile_clearances_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tile_clearances" ADD CONSTRAINT "tile_clearances_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_expedition_hero" ON "expedition_members" USING btree ("expedition_id","hero_id");--> statement-breakpoint
CREATE INDEX "idx_expedition_master" ON "hero_expeditions" USING btree ("master_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_tile_clearance" ON "tile_clearances" USING btree ("master_id","tile_id");