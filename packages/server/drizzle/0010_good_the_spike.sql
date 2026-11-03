CREATE TABLE "master_level_configs" (
	"level" integer PRIMARY KEY NOT NULL,
	"exp_required" bigint NOT NULL,
	"is_sample" boolean DEFAULT true NOT NULL
);
