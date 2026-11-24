CREATE TABLE IF NOT EXISTS "friendships" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "requester_master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "addressee_master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "status" varchar(16) NOT NULL DEFAULT 'PENDING',
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "uq_friendships_pair" UNIQUE ("requester_master_id", "addressee_master_id"),
  CONSTRAINT "ck_friendships_not_self" CHECK ("requester_master_id" <> "addressee_master_id"),
  CONSTRAINT "ck_friendships_status" CHECK ("status" IN ('PENDING', 'ACCEPTED', 'BLOCKED'))
);
CREATE INDEX IF NOT EXISTS "idx_friendships_requester" ON "friendships" ("requester_master_id", "status");
CREATE INDEX IF NOT EXISTS "idx_friendships_addressee" ON "friendships" ("addressee_master_id", "status");

CREATE TABLE IF NOT EXISTS "friend_daily_gifts" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "sender_master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "receiver_master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "gift_date" varchar(10) NOT NULL,
  "silver_amount" integer NOT NULL DEFAULT 200,
  "claimed_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT "uq_friend_daily_gift" UNIQUE ("sender_master_id", "receiver_master_id", "gift_date")
);
CREATE INDEX IF NOT EXISTS "idx_friend_daily_gifts_receiver" ON "friend_daily_gifts" ("receiver_master_id", "gift_date", "claimed_at");
