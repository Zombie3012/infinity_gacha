CREATE TABLE "account_external_identities" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"account_id" varchar(36) NOT NULL,
	"provider" varchar(20) NOT NULL,
	"provider_user_id" varchar(128) NOT NULL,
	"linked_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "account_external_identity_provider_check" CHECK ("account_external_identities"."provider" IN ('GOOGLE', 'APPLE'))
);
--> statement-breakpoint
CREATE TABLE "account_recovery_tokens" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"account_id" varchar(36) NOT NULL,
	"token_hash" varchar(64) NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "account_external_identities" ADD CONSTRAINT "account_external_identities_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "account_recovery_tokens" ADD CONSTRAINT "account_recovery_tokens_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_external_identity" ON "account_external_identities" USING btree ("provider","provider_user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_account_provider" ON "account_external_identities" USING btree ("account_id","provider");--> statement-breakpoint
CREATE INDEX "idx_recovery_tokens_account" ON "account_recovery_tokens" USING btree ("account_id","expires_at");