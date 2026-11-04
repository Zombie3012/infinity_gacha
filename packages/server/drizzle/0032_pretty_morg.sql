CREATE TABLE "event_mission_progress" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"mission_id" varchar(36) NOT NULL,
	"progress" integer DEFAULT 0 NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"completed_at" timestamp with time zone,
	"claimed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "event_missions" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"event_id" varchar(36) NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(150) NOT NULL,
	"objective_type" varchar(30) NOT NULL,
	"target_count" integer DEFAULT 1 NOT NULL,
	"reward" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"sort_order" integer DEFAULT 100 NOT NULL
);
--> statement-breakpoint
CREATE TABLE "floor_records" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"floor" integer NOT NULL,
	"rounds" integer NOT NULL,
	"achieved_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "leaderboard_rewards" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"season_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"rank" integer NOT NULL,
	"score" integer NOT NULL,
	"reward" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"claimed_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "leaderboard_seasons" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"board" varchar(30) NOT NULL,
	"period_key" varchar(20) NOT NULL,
	"status" varchar(12) DEFAULT 'OPEN' NOT NULL,
	"closed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "leaderboard_board_check" CHECK ("leaderboard_seasons"."board" IN ('DUNGEON_PROGRESS', 'COMBAT_POWER'))
);
--> statement-breakpoint
CREATE TABLE "live_events" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"code" varchar(50) NOT NULL,
	"name" varchar(150) NOT NULL,
	"description" text NOT NULL,
	"event_type" varchar(10) NOT NULL,
	"status" varchar(12) DEFAULT 'SCHEDULED' NOT NULL,
	"start_at" timestamp with time zone NOT NULL,
	"end_at" timestamp with time zone NOT NULL,
	"claim_deadline" timestamp with time zone NOT NULL,
	"activated_at" timestamp with time zone,
	"closed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "live_events_code_unique" UNIQUE("code"),
	CONSTRAINT "live_events_type_check" CHECK ("live_events"."event_type" IN ('STANDARD', 'MAJOR', 'MINOR')),
	CONSTRAINT "live_events_status_check" CHECK ("live_events"."status" IN ('SCHEDULED', 'ACTIVE', 'CLOSED'))
);
--> statement-breakpoint
ALTER TABLE "event_mission_progress" ADD CONSTRAINT "event_mission_progress_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "event_mission_progress" ADD CONSTRAINT "event_mission_progress_mission_id_event_missions_id_fk" FOREIGN KEY ("mission_id") REFERENCES "public"."event_missions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "event_missions" ADD CONSTRAINT "event_missions_event_id_live_events_id_fk" FOREIGN KEY ("event_id") REFERENCES "public"."live_events"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "floor_records" ADD CONSTRAINT "floor_records_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "leaderboard_rewards" ADD CONSTRAINT "leaderboard_rewards_season_id_leaderboard_seasons_id_fk" FOREIGN KEY ("season_id") REFERENCES "public"."leaderboard_seasons"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "leaderboard_rewards" ADD CONSTRAINT "leaderboard_rewards_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_event_mission_progress" ON "event_mission_progress" USING btree ("master_id","mission_id");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_event_mission_code" ON "event_missions" USING btree ("event_id","code");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_floor_record" ON "floor_records" USING btree ("master_id","floor");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_leaderboard_reward" ON "leaderboard_rewards" USING btree ("season_id","master_id");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_leaderboard_season" ON "leaderboard_seasons" USING btree ("board","period_key");