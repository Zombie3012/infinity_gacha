CREATE TABLE "master_world_status" (
	"master_id" varchar(36) PRIMARY KEY NOT NULL,
	"unlocked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"base_x" integer NOT NULL,
	"base_y" integer NOT NULL,
	"shield_until" timestamp with time zone NOT NULL
);
--> statement-breakpoint
CREATE TABLE "territories" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"master_id" varchar(36),
	"level" integer DEFAULT 1 NOT NULL,
	"status" varchar(20) DEFAULT 'OWNED' NOT NULL,
	"claimed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"protected_until" timestamp with time zone,
	"release_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "territories_tile_id_unique" UNIQUE("tile_id"),
	CONSTRAINT "territory_status_check" CHECK ("territories"."status" IN ('OWNED', 'ABANDONING', 'UNOWNED'))
);
--> statement-breakpoint
CREATE TABLE "territory_events" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"master_id" varchar(36),
	"action" varchar(20) NOT NULL,
	"detail" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "tile_discoveries" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"discovered_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "world_tiles" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"x" integer NOT NULL,
	"y" integer NOT NULL,
	"terrain" varchar(30) NOT NULL,
	"resource_type" varchar(30) NOT NULL,
	"base_yield_per_hour" double precision NOT NULL,
	"required_power" integer DEFAULT 0 NOT NULL,
	"is_outer_rim" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "master_world_status" ADD CONSTRAINT "master_world_status_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "territories" ADD CONSTRAINT "territories_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "territories" ADD CONSTRAINT "territories_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "territory_events" ADD CONSTRAINT "territory_events_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "territory_events" ADD CONSTRAINT "territory_events_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tile_discoveries" ADD CONSTRAINT "tile_discoveries_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tile_discoveries" ADD CONSTRAINT "tile_discoveries_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_territory_master" ON "territories" USING btree ("master_id");--> statement-breakpoint
CREATE INDEX "idx_territory_events_tile" ON "territory_events" USING btree ("tile_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_tile_discovery" ON "tile_discoveries" USING btree ("master_id","tile_id");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_world_tile_coords" ON "world_tiles" USING btree ("x","y");