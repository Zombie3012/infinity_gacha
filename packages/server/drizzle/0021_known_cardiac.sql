CREATE TABLE "dungeon_floors" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"dungeon_template_id" varchar(36) NOT NULL,
	"floor_number" integer NOT NULL,
	"name" varchar(100) NOT NULL,
	"recommended_power" integer DEFAULT 100 NOT NULL,
	"unlock_requirements" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"base_rewards" jsonb DEFAULT '{"silver":100,"masterExp":300}'::jsonb NOT NULL,
	"first_clear_rewards" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "dungeon_instances" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"world_id" varchar(36) NOT NULL,
	"dungeon_floor_id" varchar(36) NOT NULL,
	"world_seed" varchar(36) NOT NULL,
	"seed_algorithm_version" integer DEFAULT 1 NOT NULL,
	"floor_number" integer NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"current_room_index" integer DEFAULT 0 NOT NULL,
	"floor_state" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "dungeon_templates" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" text NOT NULL,
	"total_floors" integer DEFAULT 10 NOT NULL,
	"min_master_level" integer DEFAULT 1 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "dungeon_templates_code_unique" UNIQUE("code")
);
--> statement-breakpoint
ALTER TABLE "worlds" ADD COLUMN "seed_algorithm_version" integer DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "dungeon_floors" ADD CONSTRAINT "dungeon_floors_dungeon_template_id_dungeon_templates_id_fk" FOREIGN KEY ("dungeon_template_id") REFERENCES "public"."dungeon_templates"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "dungeon_instances" ADD CONSTRAINT "dungeon_instances_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "dungeon_instances" ADD CONSTRAINT "dungeon_instances_world_id_worlds_id_fk" FOREIGN KEY ("world_id") REFERENCES "public"."worlds"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "dungeon_instances" ADD CONSTRAINT "dungeon_instances_dungeon_floor_id_dungeon_floors_id_fk" FOREIGN KEY ("dungeon_floor_id") REFERENCES "public"."dungeon_floors"("id") ON DELETE cascade ON UPDATE no action;