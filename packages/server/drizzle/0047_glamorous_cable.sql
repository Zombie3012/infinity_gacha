DROP INDEX "idx_pve_battle_master";--> statement-breakpoint
CREATE INDEX "idx_pve_reservation_master" ON "pve_hero_reservations" USING btree ("master_id");--> statement-breakpoint
CREATE INDEX "idx_pve_reservation_squad" ON "pve_hero_reservations" USING btree ("squad_id");--> statement-breakpoint
CREATE INDEX "idx_pve_reservation_map" ON "pve_hero_reservations" USING btree ("map_id");--> statement-breakpoint
CREATE INDEX "idx_pve_map_master_latest" ON "pve_maps" USING btree ("master_id","created_at","id");--> statement-breakpoint
CREATE INDEX "idx_pve_squad_map_arrival" ON "pve_squads" USING btree ("map_id","next_step_at","id");--> statement-breakpoint
CREATE INDEX "idx_pve_battle_master" ON "pve_battles" USING btree ("master_id","created_at","id");