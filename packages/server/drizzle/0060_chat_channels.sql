CREATE TABLE IF NOT EXISTS "chat_messages" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "channel" varchar(16) NOT NULL,
  "sender_master_id" varchar(36) NOT NULL REFERENCES "masters"("id") ON DELETE CASCADE,
  "recipient_master_id" varchar(36) REFERENCES "masters"("id") ON DELETE CASCADE,
  "body" text NOT NULL,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX IF NOT EXISTS "idx_chat_messages_channel" ON "chat_messages" ("channel", "created_at");
CREATE INDEX IF NOT EXISTS "idx_chat_messages_private" ON "chat_messages" ("sender_master_id", "recipient_master_id", "created_at");
