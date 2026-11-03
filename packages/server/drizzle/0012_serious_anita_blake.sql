CREATE TABLE "player_profiles" (
	"account_id" varchar(36) PRIMARY KEY NOT NULL,
	"display_name" varchar(32) NOT NULL,
	"avatar_url" varchar(255),
	"settings" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
INSERT INTO "player_profiles" ("account_id", "display_name")
SELECT "id", left("username", 32) FROM "accounts"
ON CONFLICT ("account_id") DO NOTHING;
--> statement-breakpoint
ALTER TABLE "player_profiles" ADD CONSTRAINT "player_profiles_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;
