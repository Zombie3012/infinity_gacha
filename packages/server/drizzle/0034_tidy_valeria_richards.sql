CREATE TABLE "support_ticket_messages" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"ticket_id" varchar(36) NOT NULL,
	"author_type" varchar(10) NOT NULL,
	"author_id" varchar(64) NOT NULL,
	"body" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "support_message_author_check" CHECK ("support_ticket_messages"."author_type" IN ('PLAYER', 'OPERATOR'))
);
--> statement-breakpoint
CREATE TABLE "support_tickets" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"account_id" varchar(36) NOT NULL,
	"subject" varchar(150) NOT NULL,
	"body" text NOT NULL,
	"category" varchar(30) DEFAULT 'GENERAL' NOT NULL,
	"status" varchar(20) DEFAULT 'OPEN' NOT NULL,
	"priority" varchar(10) DEFAULT 'NORMAL' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"closed_at" timestamp with time zone,
	CONSTRAINT "support_ticket_status_check" CHECK ("support_tickets"."status" IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED'))
);
--> statement-breakpoint
ALTER TABLE "support_ticket_messages" ADD CONSTRAINT "support_ticket_messages_ticket_id_support_tickets_id_fk" FOREIGN KEY ("ticket_id") REFERENCES "public"."support_tickets"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "support_tickets" ADD CONSTRAINT "support_tickets_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_support_messages_ticket" ON "support_ticket_messages" USING btree ("ticket_id","created_at");--> statement-breakpoint
CREATE INDEX "idx_support_tickets_status" ON "support_tickets" USING btree ("status","created_at");