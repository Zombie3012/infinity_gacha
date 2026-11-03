CREATE TABLE "hero_templates" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"default_rarity" integer NOT NULL,
	"hero_class" varchar(30) NOT NULL,
	"element" varchar(20) NOT NULL,
	"base_hp" integer NOT NULL,
	"base_atk" integer NOT NULL,
	"base_def" integer NOT NULL,
	"base_spd" integer NOT NULL,
	CONSTRAINT "hero_templates_code_unique" UNIQUE("code")
);
--> statement-breakpoint
CREATE TABLE "heroes" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"config_id" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"rarity" integer NOT NULL,
	"category" varchar(20) NOT NULL,
	"state" varchar(20) DEFAULT 'HEALTHY' NOT NULL,
	"level" integer DEFAULT 1 NOT NULL,
	"exp" bigint DEFAULT 0 NOT NULL,
	"hp" integer NOT NULL,
	"max_hp" integer NOT NULL,
	"attack" integer NOT NULL,
	"defense" integer NOT NULL,
	"speed" integer NOT NULL,
	"talent_points" integer DEFAULT 0 NOT NULL,
	"thien_menh" integer DEFAULT 0 NOT NULL,
	"hunger" integer DEFAULT 0 NOT NULL,
	"fatigue" integer DEFAULT 0 NOT NULL,
	"loyalty" integer DEFAULT 100 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_master_hero_template" UNIQUE("master_id","config_id")
);
--> statement-breakpoint
CREATE TABLE "master_items" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"item_id" varchar(50) NOT NULL,
	"quantity" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_master_item" UNIQUE("master_id","item_id")
);
--> statement-breakpoint
CREATE TABLE "summon_history" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"session_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"banner_id" varchar(36) NOT NULL,
	"roll_number" integer NOT NULL,
	"pity_number" integer NOT NULL,
	"reward_type" varchar(20) NOT NULL,
	"reward_id" varchar(50) NOT NULL,
	"reward_name" varchar(100) NOT NULL,
	"rarity" integer DEFAULT 0 NOT NULL,
	"was_five_star" boolean DEFAULT false NOT NULL,
	"was_duplicate" boolean DEFAULT false NOT NULL,
	"thien_menh_granted" integer DEFAULT 0 NOT NULL,
	"summon_origin" varchar(20),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_summon_session_roll" UNIQUE("session_id","roll_number")
);
--> statement-breakpoint
CREATE TABLE "summon_reward_pool" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"banner_id" varchar(36) NOT NULL,
	"reward_id" varchar(50) NOT NULL,
	"reward_name" varchar(100) NOT NULL,
	"reward_type" varchar(20) NOT NULL,
	"pool_group" varchar(30) NOT NULL,
	"hero_template_code" varchar(50),
	"rarity" integer,
	"weight" integer NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "uq_banner_reward_group" UNIQUE("banner_id","reward_id","pool_group")
);
--> statement-breakpoint
CREATE TABLE "summon_sessions" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"banner_id" varchar(36) NOT NULL,
	"scroll_type" varchar(20) NOT NULL,
	"roll_count" integer NOT NULL,
	"pity_before" integer NOT NULL,
	"pity_after" integer NOT NULL,
	"idempotency_key" varchar(80),
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_master_summon_idempotency" UNIQUE("master_id","idempotency_key")
);
--> statement-breakpoint
ALTER TABLE "heroes" ADD CONSTRAINT "heroes_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "heroes" ADD CONSTRAINT "heroes_config_id_hero_templates_code_fk" FOREIGN KEY ("config_id") REFERENCES "public"."hero_templates"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "master_items" ADD CONSTRAINT "master_items_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_history" ADD CONSTRAINT "summon_history_session_id_summon_sessions_id_fk" FOREIGN KEY ("session_id") REFERENCES "public"."summon_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_history" ADD CONSTRAINT "summon_history_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_history" ADD CONSTRAINT "summon_history_banner_id_banners_id_fk" FOREIGN KEY ("banner_id") REFERENCES "public"."banners"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_reward_pool" ADD CONSTRAINT "summon_reward_pool_banner_id_banners_id_fk" FOREIGN KEY ("banner_id") REFERENCES "public"."banners"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_reward_pool" ADD CONSTRAINT "summon_reward_pool_hero_template_code_hero_templates_code_fk" FOREIGN KEY ("hero_template_code") REFERENCES "public"."hero_templates"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_sessions" ADD CONSTRAINT "summon_sessions_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "summon_sessions" ADD CONSTRAINT "summon_sessions_banner_id_banners_id_fk" FOREIGN KEY ("banner_id") REFERENCES "public"."banners"("id") ON DELETE no action ON UPDATE no action;