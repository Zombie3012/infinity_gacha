CREATE TABLE "hero_level_configs" (
	"level" integer PRIMARY KEY NOT NULL,
	"cumulative_exp_required" bigint NOT NULL,
	"stat_growth_multiplier" double precision DEFAULT 1.05 NOT NULL,
	"is_sample" boolean DEFAULT true NOT NULL
);
