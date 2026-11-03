CREATE TABLE "dungeon_event_templates" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" varchar(250) NOT NULL,
	"event_type" varchar(20) NOT NULL,
	"weight" integer NOT NULL,
	"silver_reward" integer DEFAULT 0 NOT NULL,
	"heal_percent" double precision DEFAULT 0 NOT NULL,
	"enemy_attack_multiplier" double precision DEFAULT 1 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "dungeon_event_templates_code_unique" UNIQUE("code")
);
