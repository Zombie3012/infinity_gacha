CREATE TABLE "alliance_cooldowns" (
	"master_id" varchar(36) PRIMARY KEY NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"reason" varchar(20) DEFAULT 'LEFT' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "alliance_join_requests" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"alliance_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"status" varchar(20) DEFAULT 'PENDING' NOT NULL,
	"message" varchar(200) DEFAULT '' NOT NULL,
	"resolved_by" varchar(36),
	"resolved_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "alliance_request_status_check" CHECK ("alliance_join_requests"."status" IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'))
);
--> statement-breakpoint
CREATE TABLE "alliance_members" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"alliance_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"role" varchar(20) DEFAULT 'MEMBER' NOT NULL,
	"contribution_points" bigint DEFAULT 0 NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_alliance_member_master" UNIQUE("master_id"),
	CONSTRAINT "alliance_member_role_check" CHECK ("alliance_members"."role" IN ('LEADER', 'OFFICER', 'MEMBER'))
);
--> statement-breakpoint
CREATE TABLE "alliance_messages" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"alliance_id" varchar(36) NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"message_type" varchar(10) DEFAULT 'TEXT' NOT NULL,
	"body" varchar(300) DEFAULT '' NOT NULL,
	"coordinates" jsonb,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "alliance_message_type_check" CHECK ("alliance_messages"."message_type" IN ('TEXT', 'PING'))
);
--> statement-breakpoint
CREATE TABLE "alliance_wars" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"declaring_alliance_id" varchar(36) NOT NULL,
	"target_alliance_id" varchar(36) NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"ends_at" timestamp with time zone NOT NULL,
	"declaring_points" integer DEFAULT 0 NOT NULL,
	"target_points" integer DEFAULT 0 NOT NULL,
	"winner_alliance_id" varchar(36),
	"resolved_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "alliance_war_status_check" CHECK ("alliance_wars"."status" IN ('ACTIVE', 'RESOLVED', 'CANCELLED'))
);
--> statement-breakpoint
CREATE TABLE "alliances" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"name" varchar(50) NOT NULL,
	"tag" varchar(10) NOT NULL,
	"emblem_icon" varchar(100) DEFAULT '⚔' NOT NULL,
	"motto" varchar(120) DEFAULT '' NOT NULL,
	"language" varchar(10) DEFAULT 'vi' NOT NULL,
	"min_combat_power" integer DEFAULT 0 NOT NULL,
	"leader_master_id" varchar(36) NOT NULL,
	"member_count" integer DEFAULT 1 NOT NULL,
	"max_members" integer DEFAULT 30 NOT NULL,
	"alliance_level" integer DEFAULT 1 NOT NULL,
	"notice_board" text DEFAULT '' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_alliance_name" UNIQUE("name"),
	CONSTRAINT "uq_alliance_tag" UNIQUE("tag")
);
--> statement-breakpoint
CREATE TABLE "war_engagements" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"war_id" varchar(36) NOT NULL,
	"attacker_alliance_id" varchar(36) NOT NULL,
	"defender_alliance_id" varchar(36) NOT NULL,
	"master_id" varchar(36),
	"tile_id" varchar(36),
	"kind" varchar(30) NOT NULL,
	"points" integer DEFAULT 0 NOT NULL,
	"detail" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "war_engagement_kind_check" CHECK ("war_engagements"."kind" IN ('TERRITORY_CAPTURE', 'DEFENSE_HOLD', 'WONDER_SEIZURE', 'WAR_VICTORY'))
);
--> statement-breakpoint
CREATE TABLE "wonder_holdings" (
	"tile_id" varchar(36) PRIMARY KEY NOT NULL,
	"alliance_id" varchar(36),
	"held_since" timestamp with time zone,
	"accumulated_seconds" integer DEFAULT 0 NOT NULL,
	"last_settled_at" timestamp with time zone,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "world_conquest_rankings" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"season_id" varchar(36) NOT NULL,
	"alliance_id" varchar(36) NOT NULL,
	"final_rank" integer,
	"total_conquest_points" integer DEFAULT 0 NOT NULL,
	"reward_claimed" boolean DEFAULT false NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_conquest_ranking" UNIQUE("season_id","alliance_id")
);
--> statement-breakpoint
CREATE TABLE "world_conquest_seasons" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"season_number" integer NOT NULL,
	"start_time" timestamp with time zone NOT NULL,
	"end_time" timestamp with time zone NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"conquering_alliance_id" varchar(36),
	"concluded_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "world_conquest_seasons_season_number_unique" UNIQUE("season_number"),
	CONSTRAINT "conquest_season_status_check" CHECK ("world_conquest_seasons"."status" IN ('UPCOMING', 'ACTIVE', 'CONCLUDED'))
);
--> statement-breakpoint
ALTER TABLE "alliance_cooldowns" ADD CONSTRAINT "alliance_cooldowns_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_join_requests" ADD CONSTRAINT "alliance_join_requests_alliance_id_alliances_id_fk" FOREIGN KEY ("alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_join_requests" ADD CONSTRAINT "alliance_join_requests_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_join_requests" ADD CONSTRAINT "alliance_join_requests_resolved_by_masters_id_fk" FOREIGN KEY ("resolved_by") REFERENCES "public"."masters"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_members" ADD CONSTRAINT "alliance_members_alliance_id_alliances_id_fk" FOREIGN KEY ("alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_members" ADD CONSTRAINT "alliance_members_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_messages" ADD CONSTRAINT "alliance_messages_alliance_id_alliances_id_fk" FOREIGN KEY ("alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_messages" ADD CONSTRAINT "alliance_messages_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_wars" ADD CONSTRAINT "alliance_wars_declaring_alliance_id_alliances_id_fk" FOREIGN KEY ("declaring_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_wars" ADD CONSTRAINT "alliance_wars_target_alliance_id_alliances_id_fk" FOREIGN KEY ("target_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliance_wars" ADD CONSTRAINT "alliance_wars_winner_alliance_id_alliances_id_fk" FOREIGN KEY ("winner_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "alliances" ADD CONSTRAINT "alliances_leader_master_id_masters_id_fk" FOREIGN KEY ("leader_master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "war_engagements" ADD CONSTRAINT "war_engagements_war_id_alliance_wars_id_fk" FOREIGN KEY ("war_id") REFERENCES "public"."alliance_wars"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "war_engagements" ADD CONSTRAINT "war_engagements_attacker_alliance_id_alliances_id_fk" FOREIGN KEY ("attacker_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "war_engagements" ADD CONSTRAINT "war_engagements_defender_alliance_id_alliances_id_fk" FOREIGN KEY ("defender_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "war_engagements" ADD CONSTRAINT "war_engagements_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "war_engagements" ADD CONSTRAINT "war_engagements_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "wonder_holdings" ADD CONSTRAINT "wonder_holdings_tile_id_world_tiles_id_fk" FOREIGN KEY ("tile_id") REFERENCES "public"."world_tiles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "wonder_holdings" ADD CONSTRAINT "wonder_holdings_alliance_id_alliances_id_fk" FOREIGN KEY ("alliance_id") REFERENCES "public"."alliances"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "world_conquest_rankings" ADD CONSTRAINT "world_conquest_rankings_season_id_world_conquest_seasons_id_fk" FOREIGN KEY ("season_id") REFERENCES "public"."world_conquest_seasons"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "world_conquest_rankings" ADD CONSTRAINT "world_conquest_rankings_alliance_id_alliances_id_fk" FOREIGN KEY ("alliance_id") REFERENCES "public"."alliances"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "world_conquest_seasons" ADD CONSTRAINT "world_conquest_seasons_conquering_alliance_id_alliances_id_fk" FOREIGN KEY ("conquering_alliance_id") REFERENCES "public"."alliances"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_alliance_cooldown_expiry" ON "alliance_cooldowns" USING btree ("expires_at");--> statement-breakpoint
CREATE INDEX "idx_alliance_requests_pending" ON "alliance_join_requests" USING btree ("alliance_id","status","created_at");--> statement-breakpoint
CREATE INDEX "idx_alliance_requests_master" ON "alliance_join_requests" USING btree ("master_id","status");--> statement-breakpoint
CREATE INDEX "idx_alliance_members_alliance" ON "alliance_members" USING btree ("alliance_id");--> statement-breakpoint
CREATE INDEX "idx_alliance_messages_alliance" ON "alliance_messages" USING btree ("alliance_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_alliance_wars_status" ON "alliance_wars" USING btree ("status","ends_at");--> statement-breakpoint
CREATE INDEX "idx_alliance_wars_declaring" ON "alliance_wars" USING btree ("declaring_alliance_id");--> statement-breakpoint
CREATE INDEX "idx_alliance_wars_target" ON "alliance_wars" USING btree ("target_alliance_id");--> statement-breakpoint
CREATE INDEX "idx_alliance_leader" ON "alliances" USING btree ("leader_master_id");--> statement-breakpoint
CREATE INDEX "idx_war_engagements_war" ON "war_engagements" USING btree ("war_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_conquest_rankings_points" ON "world_conquest_rankings" USING btree ("season_id","total_conquest_points");--> statement-breakpoint
CREATE INDEX "idx_conquest_seasons_status" ON "world_conquest_seasons" USING btree ("status","end_time");