CREATE TABLE "hero_skill_instances" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"skill_code" varchar(50) NOT NULL,
	"skill_level" integer DEFAULT 1 NOT NULL,
	"is_unlocked" boolean DEFAULT false NOT NULL,
	"behavior_mode" varchar(10) DEFAULT 'AUTO' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_hero_skill_instance" UNIQUE("hero_id","skill_code")
);
--> statement-breakpoint
CREATE TABLE "hero_skill_templates" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"hero_class" varchar(30) NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" varchar(500) NOT NULL,
	"effect_type" varchar(30) NOT NULL,
	"effect_value" double precision NOT NULL,
	"upgrade_increment" double precision DEFAULT 0.1 NOT NULL,
	"cooldown_seconds" integer DEFAULT 3 NOT NULL,
	"unlock_level" integer DEFAULT 3 NOT NULL,
	"max_level" integer DEFAULT 5 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"is_sample" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
ALTER TABLE "hero_skill_instances" ADD CONSTRAINT "hero_skill_instances_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_skill_instances" ADD CONSTRAINT "hero_skill_instances_skill_code_hero_skill_templates_code_fk" FOREIGN KEY ("skill_code") REFERENCES "public"."hero_skill_templates"("code") ON DELETE cascade ON UPDATE no action;