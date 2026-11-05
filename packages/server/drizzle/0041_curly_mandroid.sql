CREATE TABLE "hero_imprints" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"hero_id" varchar(36) NOT NULL,
	"imprint_code" varchar(50) NOT NULL,
	"rank_level" integer DEFAULT 1 NOT NULL,
	"acquired_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_hero_imprint" UNIQUE("hero_id","imprint_code")
);
--> statement-breakpoint
CREATE TABLE "imprint_definitions" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"rank" varchar(2) NOT NULL,
	"tier" integer DEFAULT 1 NOT NULL,
	"bonus_str" integer DEFAULT 0 NOT NULL,
	"bonus_int" integer DEFAULT 0 NOT NULL,
	"bonus_sta" integer DEFAULT 0 NOT NULL,
	"bonus_agi" integer DEFAULT 0 NOT NULL,
	"bonus_hp" integer DEFAULT 0 NOT NULL,
	"bonus_atk" integer DEFAULT 0 NOT NULL,
	"bonus_def" integer DEFAULT 0 NOT NULL,
	"ability" varchar(300) DEFAULT '' NOT NULL,
	"is_enabled" boolean DEFAULT true NOT NULL,
	CONSTRAINT "imprint_rank_check" CHECK ("imprint_definitions"."rank" IN ('S', 'A', 'B'))
);
--> statement-breakpoint
ALTER TABLE "hero_imprints" ADD CONSTRAINT "hero_imprints_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_imprints" ADD CONSTRAINT "hero_imprints_imprint_code_imprint_definitions_code_fk" FOREIGN KEY ("imprint_code") REFERENCES "public"."imprint_definitions"("code") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_imprint_rank" ON "imprint_definitions" USING btree ("rank","tier");