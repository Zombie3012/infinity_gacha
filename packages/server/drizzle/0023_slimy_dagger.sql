CREATE TABLE "base_buildings" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"building_type" varchar(40) NOT NULL,
	"plot_index" integer NOT NULL,
	"level" integer DEFAULT 1 NOT NULL,
	"durability" integer DEFAULT 100 NOT NULL,
	"status" varchar(20) DEFAULT 'READY' NOT NULL,
	"upgrade_finishes_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "base_production_nodes" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"building_id" varchar(36) NOT NULL,
	"resource_type" varchar(30) NOT NULL,
	"base_rate_per_hour" double precision NOT NULL,
	"current_stored" double precision DEFAULT 0 NOT NULL,
	"max_capacity" double precision NOT NULL,
	"last_harvest_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "base_production_nodes_building_id_unique" UNIQUE("building_id")
);
--> statement-breakpoint
CREATE TABLE "building_types" (
	"code" varchar(40) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"category" varchar(20) NOT NULL,
	"description" text NOT NULL,
	"max_level" integer DEFAULT 5 NOT NULL,
	"max_workers" integer DEFAULT 0 NOT NULL,
	"required_world_level" integer DEFAULT 1 NOT NULL,
	"build_cost_silver" integer NOT NULL,
	"production" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "building_worker_assignments" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"building_id" varchar(36) NOT NULL,
	"hero_instance_id" varchar(36) NOT NULL,
	"efficiency_boost" double precision DEFAULT 1 NOT NULL,
	"assigned_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "building_worker_assignments_hero_instance_id_unique" UNIQUE("hero_instance_id")
);
--> statement-breakpoint
ALTER TABLE "worlds" ADD COLUMN "base_zones" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "base_buildings" ADD CONSTRAINT "base_buildings_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "base_buildings" ADD CONSTRAINT "base_buildings_building_type_building_types_code_fk" FOREIGN KEY ("building_type") REFERENCES "public"."building_types"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "base_production_nodes" ADD CONSTRAINT "base_production_nodes_building_id_base_buildings_id_fk" FOREIGN KEY ("building_id") REFERENCES "public"."base_buildings"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "building_worker_assignments" ADD CONSTRAINT "building_worker_assignments_building_id_base_buildings_id_fk" FOREIGN KEY ("building_id") REFERENCES "public"."base_buildings"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "building_worker_assignments" ADD CONSTRAINT "building_worker_assignments_hero_instance_id_heroes_id_fk" FOREIGN KEY ("hero_instance_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_base_buildings_plot" ON "base_buildings" USING btree ("master_id","plot_index");