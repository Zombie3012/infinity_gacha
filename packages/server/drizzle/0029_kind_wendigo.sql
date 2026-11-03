CREATE TABLE "achievement_progress" (
	"master_id" varchar(36) NOT NULL,
	"achievement_code" varchar(50) NOT NULL,
	"progress" integer DEFAULT 0 NOT NULL,
	"unlocked_at" timestamp with time zone,
	"claimed_at" timestamp with time zone,
	CONSTRAINT "achievement_progress_master_id_achievement_code_pk" PRIMARY KEY("master_id","achievement_code")
);
--> statement-breakpoint
CREATE TABLE "achievements" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(150) NOT NULL,
	"description" text NOT NULL,
	"category" varchar(20) NOT NULL,
	"metric" varchar(30) NOT NULL,
	"threshold" integer NOT NULL,
	"reward" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "quest_definitions" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(150) NOT NULL,
	"description" text NOT NULL,
	"quest_type" varchar(10) NOT NULL,
	"objective_type" varchar(30) NOT NULL,
	"target_count" integer DEFAULT 1 NOT NULL,
	"reward" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"required_level" integer DEFAULT 1 NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"sort_order" integer DEFAULT 100 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "quest_definitions_type_check" CHECK ("quest_definitions"."quest_type" IN ('MAIN', 'SIDE', 'DAILY', 'WEEKLY'))
);
--> statement-breakpoint
CREATE TABLE "quest_progress" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"quest_code" varchar(50) NOT NULL,
	"period_key" varchar(20) DEFAULT '' NOT NULL,
	"progress" integer DEFAULT 0 NOT NULL,
	"status" varchar(20) DEFAULT 'ACTIVE' NOT NULL,
	"accepted_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"claimed_at" timestamp with time zone,
	CONSTRAINT "quest_progress_status_check" CHECK ("quest_progress"."status" IN ('ACTIVE', 'COMPLETED', 'CLAIMED'))
);
--> statement-breakpoint
ALTER TABLE "achievement_progress" ADD CONSTRAINT "achievement_progress_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "achievement_progress" ADD CONSTRAINT "achievement_progress_achievement_code_achievements_code_fk" FOREIGN KEY ("achievement_code") REFERENCES "public"."achievements"("code") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_progress" ADD CONSTRAINT "quest_progress_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "quest_progress" ADD CONSTRAINT "quest_progress_quest_code_quest_definitions_code_fk" FOREIGN KEY ("quest_code") REFERENCES "public"."quest_definitions"("code") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_quest_progress" ON "quest_progress" USING btree ("master_id","quest_code","period_key");