CREATE TABLE "combat_sessions" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"world_id" varchar(36) NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"active_buff_id" varchar(40),
	"last_buff_change_at" timestamp with time zone,
	"cooldown_until" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "combat_sessions" ADD CONSTRAINT "combat_sessions_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "combat_sessions" ADD CONSTRAINT "combat_sessions_world_id_worlds_id_fk" FOREIGN KEY ("world_id") REFERENCES "public"."worlds"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_one_active_combat_per_master" ON "combat_sessions" USING btree ("master_id") WHERE "combat_sessions"."status" = 'ACTIVE';