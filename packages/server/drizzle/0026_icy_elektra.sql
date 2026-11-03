CREATE TABLE "hero_personality_traits" (
	"hero_id" varchar(36) PRIMARY KEY NOT NULL,
	"core_trait" varchar(30) NOT NULL,
	"social_trait" varchar(30) NOT NULL,
	"behavioral_trait" varchar(30) NOT NULL,
	"special_trait" varchar(30) NOT NULL,
	"favorite_food" varchar(50) NOT NULL,
	"loyalty_score" integer DEFAULT 50 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "hero_personality_loyalty_range" CHECK ("hero_personality_traits"."loyalty_score" >= 0 AND "hero_personality_traits"."loyalty_score" <= 100)
);
--> statement-breakpoint
CREATE TABLE "hero_relationships" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"hero_a_id" varchar(36) NOT NULL,
	"hero_b_id" varchar(36) NOT NULL,
	"affinity_points" integer DEFAULT 0 NOT NULL,
	"last_interaction_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "hero_personality_traits" ADD CONSTRAINT "hero_personality_traits_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_relationships" ADD CONSTRAINT "hero_relationships_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_relationships" ADD CONSTRAINT "hero_relationships_hero_a_id_heroes_id_fk" FOREIGN KEY ("hero_a_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_relationships" ADD CONSTRAINT "hero_relationships_hero_b_id_heroes_id_fk" FOREIGN KEY ("hero_b_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_hero_relationship_pair" ON "hero_relationships" USING btree ("hero_a_id","hero_b_id");--> statement-breakpoint
CREATE INDEX "idx_hero_relationship_master" ON "hero_relationships" USING btree ("master_id");