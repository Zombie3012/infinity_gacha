CREATE TABLE "hero_survival_states" (
	"hero_instance_id" varchar(36) PRIMARY KEY NOT NULL,
	"hunger_score" double precision DEFAULT 0 NOT NULL,
	"fatigue_score" double precision DEFAULT 0 NOT NULL,
	"is_resting" boolean DEFAULT false NOT NULL,
	"last_tick_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "hero_survival_hunger_range" CHECK ("hero_survival_states"."hunger_score" >= 0 AND "hero_survival_states"."hunger_score" <= 100),
	CONSTRAINT "hero_survival_fatigue_range" CHECK ("hero_survival_states"."fatigue_score" >= 0 AND "hero_survival_states"."fatigue_score" <= 100)
);
--> statement-breakpoint
ALTER TABLE "hero_survival_states" ADD CONSTRAINT "hero_survival_states_hero_instance_id_heroes_id_fk" FOREIGN KEY ("hero_instance_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;