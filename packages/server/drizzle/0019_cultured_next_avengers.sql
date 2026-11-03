CREATE TABLE "master_parties" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"name" varchar(60) NOT NULL,
	"is_default" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_master_party_name" UNIQUE("master_id","name")
);
--> statement-breakpoint
ALTER TABLE "combat_party_slots" DROP CONSTRAINT "uq_combat_party_master_slot";--> statement-breakpoint
ALTER TABLE "combat_party_slots" DROP CONSTRAINT "uq_combat_party_master_hero";--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD COLUMN "party_id" varchar(36);--> statement-breakpoint
ALTER TABLE "master_parties" ADD CONSTRAINT "master_parties_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "uq_master_default_party" ON "master_parties" USING btree ("master_id") WHERE "master_parties"."is_default" = true;--> statement-breakpoint
INSERT INTO "master_parties" ("id", "master_id", "name", "is_default")
SELECT substr(md5(m."id"), 1, 8) || '-' || substr(md5(m."id"), 9, 4) || '-' || substr(md5(m."id"), 13, 4) || '-' || substr(md5(m."id"), 17, 4) || '-' || substr(md5(m."id"), 21, 12), m."id", 'Party 1', true
FROM "masters" m ON CONFLICT ("master_id", "name") DO NOTHING;--> statement-breakpoint
UPDATE "combat_party_slots" s SET "party_id" = p."id" FROM "master_parties" p WHERE p."master_id" = s."master_id" AND p."is_default" = true;--> statement-breakpoint
ALTER TABLE "combat_party_slots" ALTER COLUMN "party_id" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD CONSTRAINT "combat_party_slots_party_id_master_parties_id_fk" FOREIGN KEY ("party_id") REFERENCES "public"."master_parties"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD CONSTRAINT "uq_combat_party_party_slot" UNIQUE("party_id","slot_index");--> statement-breakpoint
ALTER TABLE "combat_party_slots" ADD CONSTRAINT "uq_combat_party_party_hero" UNIQUE("party_id","hero_id");
