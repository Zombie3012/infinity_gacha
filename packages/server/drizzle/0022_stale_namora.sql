CREATE TABLE "audit_logs" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"actor_id" varchar(64) NOT NULL,
	"actor_type" varchar(20) NOT NULL,
	"action" varchar(100) NOT NULL,
	"entity_type" varchar(50) NOT NULL,
	"entity_id" varchar(64) NOT NULL,
	"diff_payload" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "security_alerts" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"account_id" varchar(36) NOT NULL,
	"signal" varchar(50) NOT NULL,
	"severity" varchar(10) NOT NULL,
	"status" varchar(20) DEFAULT 'OPEN' NOT NULL,
	"details" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"resolved_at" timestamp with time zone,
	"resolved_by" varchar(64),
	CONSTRAINT "security_alerts_severity_check" CHECK ("security_alerts"."severity" IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
	CONSTRAINT "security_alerts_status_check" CHECK ("security_alerts"."status" IN ('OPEN', 'RESOLVED'))
);
--> statement-breakpoint
CREATE TABLE "system_configs" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"config_key" varchar(100) NOT NULL,
	"version" integer NOT NULL,
	"config_value" jsonb NOT NULL,
	"is_active" boolean DEFAULT false NOT NULL,
	"updated_by" varchar(64) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "security_alerts" ADD CONSTRAINT "security_alerts_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_audit_logs_created_at" ON "audit_logs" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "idx_audit_logs_entity" ON "audit_logs" USING btree ("entity_type","entity_id");--> statement-breakpoint
CREATE INDEX "idx_audit_logs_action" ON "audit_logs" USING btree ("action");--> statement-breakpoint
CREATE INDEX "idx_security_alerts_account" ON "security_alerts" USING btree ("account_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_system_configs_key_version" ON "system_configs" USING btree ("config_key","version");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_system_configs_active_key" ON "system_configs" USING btree ("config_key") WHERE "system_configs"."is_active" = true;