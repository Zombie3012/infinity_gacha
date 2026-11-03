CREATE TABLE "mailbox_messages" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"sender" varchar(30) DEFAULT 'SYSTEM' NOT NULL,
	"subject" varchar(150) NOT NULL,
	"body" text NOT NULL,
	"attachments" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"is_claimed" boolean DEFAULT false NOT NULL,
	"claimed_at" timestamp with time zone,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "shop_items" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" text NOT NULL,
	"item_id" varchar(50) NOT NULL,
	"category" varchar(20) NOT NULL,
	"price_silver" bigint NOT NULL,
	"daily_limit" integer DEFAULT 0 NOT NULL,
	"rotation_days" integer[] DEFAULT '{}'::integer[] NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"sort_order" integer DEFAULT 100 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "shop_purchase_limits" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"shop_item_code" varchar(50) NOT NULL,
	"period_key" varchar(20) NOT NULL,
	"quantity" integer DEFAULT 0 NOT NULL
);
--> statement-breakpoint
ALTER TABLE "mailbox_messages" ADD CONSTRAINT "mailbox_messages_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "shop_purchase_limits" ADD CONSTRAINT "shop_purchase_limits_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_mailbox_master" ON "mailbox_messages" USING btree ("master_id","is_claimed","expires_at");--> statement-breakpoint
CREATE UNIQUE INDEX "uq_shop_purchase_limit" ON "shop_purchase_limits" USING btree ("master_id","shop_item_code","period_key");