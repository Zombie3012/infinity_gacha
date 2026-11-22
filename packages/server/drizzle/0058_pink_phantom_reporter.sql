CREATE TABLE "pve_consumable_drops" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"map_id" varchar(36) NOT NULL,
	"area_id" varchar(80) NOT NULL,
	"x" integer NOT NULL,
	"y" integer NOT NULL,
	"items" jsonb NOT NULL
);
--> statement-breakpoint
ALTER TABLE "pve_consumable_drops" ADD CONSTRAINT "pve_consumable_drops_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "pve_consumable_drops" ADD CONSTRAINT "pve_consumable_drops_map_id_pve_maps_id_fk" FOREIGN KEY ("map_id") REFERENCES "public"."pve_maps"("id") ON DELETE cascade ON UPDATE no action;