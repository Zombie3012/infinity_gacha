CREATE TABLE "hero_class_definitions" (
	"code" varchar(20) PRIMARY KEY NOT NULL,
	"name" varchar(50) NOT NULL,
	"base_crit_rate" double precision DEFAULT 5 NOT NULL,
	"growth_str" double precision DEFAULT 1 NOT NULL,
	"growth_int" double precision DEFAULT 1 NOT NULL,
	"growth_sta" double precision DEFAULT 1 NOT NULL,
	"growth_agi" double precision DEFAULT 1 NOT NULL,
	"passive" varchar(300) DEFAULT '' NOT NULL,
	"is_enabled" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
CREATE TABLE "hero_element_affinities" (
	"hero_id" varchar(36) PRIMARY KEY NOT NULL,
	"fire" integer DEFAULT 0 NOT NULL,
	"water" integer DEFAULT 0 NOT NULL,
	"wind" integer DEFAULT 0 NOT NULL,
	"earth" integer DEFAULT 0 NOT NULL,
	"light" integer DEFAULT 0 NOT NULL,
	"dark" integer DEFAULT 0 NOT NULL,
	"lightning" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "hero_affinity_range" CHECK (
    "hero_element_affinities"."fire" BETWEEN 0 AND 100 AND "hero_element_affinities"."water" BETWEEN 0 AND 100
    AND "hero_element_affinities"."wind" BETWEEN 0 AND 100 AND "hero_element_affinities"."earth" BETWEEN 0 AND 100
    AND "hero_element_affinities"."light" BETWEEN 0 AND 100 AND "hero_element_affinities"."dark" BETWEEN 0 AND 100
    AND "hero_element_affinities"."lightning" BETWEEN 0 AND 100)
);
--> statement-breakpoint
CREATE TABLE "hero_subclasses" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"subclass_code" varchar(30) NOT NULL,
	"acquired_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_hero_subclass" UNIQUE("hero_id","subclass_code")
);
--> statement-breakpoint
CREATE TABLE "subclass_definitions" (
	"code" varchar(30) PRIMARY KEY NOT NULL,
	"name" varchar(50) NOT NULL,
	"primary_stat" varchar(10) NOT NULL,
	"required_value" integer NOT NULL,
	"required_level" integer DEFAULT 20 NOT NULL,
	"effect" varchar(300) DEFAULT '' NOT NULL,
	"is_enabled" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "base_str" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "base_int" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "base_sta" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "base_agi" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "archetype_weights" jsonb DEFAULT '{"str":0.25,"int":0.25,"sta":0.25,"agi":0.25}'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "class_options" jsonb;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "class_code" varchar(20) DEFAULT 'UNCLASSIFIED' NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "combat_role" varchar(20) DEFAULT 'PHYSICAL_DPS' NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_templates" ADD COLUMN "is_enabled" boolean DEFAULT true NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "base_str" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "base_int" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "base_sta" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "base_agi" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "class_code" varchar(20) DEFAULT 'UNCLASSIFIED' NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "combat_role" varchar(20) DEFAULT 'PHYSICAL_DPS' NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "training_stats" jsonb DEFAULT '{"str":0,"int":0,"sta":0,"agi":0}'::jsonb NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "mp" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "max_mp" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "current_hp_pct" double precision DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "heroes" ADD COLUMN "current_mp_pct" double precision DEFAULT 1 NOT NULL;--> statement-breakpoint
ALTER TABLE "hero_element_affinities" ADD CONSTRAINT "hero_element_affinities_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_subclasses" ADD CONSTRAINT "hero_subclasses_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_subclasses" ADD CONSTRAINT "hero_subclasses_subclass_code_subclass_definitions_code_fk" FOREIGN KEY ("subclass_code") REFERENCES "public"."subclass_definitions"("code") ON DELETE cascade ON UPDATE no action;