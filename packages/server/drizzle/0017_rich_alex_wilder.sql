CREATE TABLE "hero_development_configs" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"action" varchar(20) NOT NULL,
	"rank" integer NOT NULL,
	"material_item_id" varchar(50) NOT NULL,
	"material_quantity" integer NOT NULL,
	"required_hero_level" integer DEFAULT 1 NOT NULL,
	"required_promotion_rank" integer DEFAULT 0 NOT NULL,
	"max_level_after" integer DEFAULT 20 NOT NULL,
	"stat_growth_multiplier" double precision DEFAULT 1 NOT NULL,
	"is_sample" boolean DEFAULT true NOT NULL,
	CONSTRAINT "uq_hero_development_action_rank" UNIQUE("action","rank")
);
