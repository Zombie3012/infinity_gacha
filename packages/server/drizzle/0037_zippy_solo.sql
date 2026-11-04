CREATE TABLE "pvp_battles" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"tile_id" varchar(36) NOT NULL,
	"attacker_master_id" varchar(36) NOT NULL,
	"defender_master_id" varchar(36),
	"expedition_id" varchar(36),
	"winner" varchar(10) NOT NULL,
	"attacker_power" integer NOT NULL,
	"defender_power" integer NOT NULL,
	"rounds" integer DEFAULT 0 NOT NULL,
	"report" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "pvp_winner_check" CHECK ("pvp_battles"."winner" IN ('ATTACKER', 'DEFENDER'))
);
--> statement-breakpoint
ALTER TABLE "pvp_battles" ADD CONSTRAINT "pvp_battles_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pvp_battles" ADD CONSTRAINT "pvp_battles_attacker_master_id_masters_id_fk" FOREIGN KEY ("attacker_master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pvp_battles" ADD CONSTRAINT "pvp_battles_defender_master_id_masters_id_fk" FOREIGN KEY ("defender_master_id") REFERENCES "public"."masters"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pvp_battles" ADD CONSTRAINT "pvp_battles_expedition_id_hero_expeditions_id_fk" FOREIGN KEY ("expedition_id") REFERENCES "public"."hero_expeditions"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_pvp_attacker" ON "pvp_battles" USING btree ("attacker_master_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_pvp_defender" ON "pvp_battles" USING btree ("defender_master_id","created_at");