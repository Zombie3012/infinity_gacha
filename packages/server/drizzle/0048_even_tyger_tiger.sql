ALTER TABLE "pve_squads" ADD COLUMN "auto_explore" boolean DEFAULT false NOT NULL;
--> statement-breakpoint
UPDATE "pve_squads" SET "next_step_at" = LEAST("next_step_at", clock_timestamp() + interval '1 second')
WHERE "status" = 'MOVING' AND "next_step_at" > clock_timestamp();
