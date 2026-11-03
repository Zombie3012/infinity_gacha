CREATE TABLE "feature_unlock_configs" (
	"feature_code" varchar(50) PRIMARY KEY NOT NULL,
	"feature_name" varchar(100) NOT NULL,
	"required_master_level" integer DEFAULT 1 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
CREATE TABLE "master_skill_templates" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" varchar(500) NOT NULL,
	"unlock_level" integer DEFAULT 1 NOT NULL,
	"duration_seconds" integer NOT NULL,
	"heal_max_hp_percent_per_second" double precision NOT NULL,
	"cooldown_seconds" integer DEFAULT 15 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL
);
