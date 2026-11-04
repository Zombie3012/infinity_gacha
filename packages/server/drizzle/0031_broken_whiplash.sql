CREATE TABLE "iap_products" (
	"code" varchar(50) PRIMARY KEY NOT NULL,
	"name" varchar(100) NOT NULL,
	"description" text NOT NULL,
	"price_cents" integer NOT NULL,
	"currency" varchar(3) DEFAULT 'USD' NOT NULL,
	"gems" integer DEFAULT 0 NOT NULL,
	"silver" integer DEFAULT 0 NOT NULL,
	"items" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"sort_order" integer DEFAULT 100 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "payment_transactions" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"product_code" varchar(50) NOT NULL,
	"store" varchar(10) NOT NULL,
	"store_transaction_id" varchar(128),
	"status" varchar(20) DEFAULT 'PENDING' NOT NULL,
	"gems" integer DEFAULT 0 NOT NULL,
	"silver" integer DEFAULT 0 NOT NULL,
	"items" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"price_cents" integer DEFAULT 0 NOT NULL,
	"currency" varchar(3) DEFAULT 'USD' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"refunded_at" timestamp with time zone,
	"refund_reason" text,
	CONSTRAINT "payment_status_check" CHECK ("payment_transactions"."status" IN ('PENDING', 'COMPLETED', 'REFUNDED', 'FAILED')),
	CONSTRAINT "payment_store_check" CHECK ("payment_transactions"."store" IN ('APPLE', 'GOOGLE'))
);
--> statement-breakpoint
ALTER TABLE "payment_transactions" ADD CONSTRAINT "payment_transactions_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payment_transactions" ADD CONSTRAINT "payment_transactions_product_code_iap_products_code_fk" FOREIGN KEY ("product_code") REFERENCES "public"."iap_products"("code") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_payment_store_receipt" ON "payment_transactions" USING btree ("store","store_transaction_id");--> statement-breakpoint
CREATE INDEX "idx_payment_master" ON "payment_transactions" USING btree ("master_id","created_at");