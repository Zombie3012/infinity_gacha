ALTER TABLE "pve_squads" DROP CONSTRAINT "pve_squads_party_id_master_parties_id_fk";
--> statement-breakpoint
ALTER TABLE "pve_squads" ALTER COLUMN "party_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "pve_squads" ADD CONSTRAINT "pve_squads_party_id_master_parties_id_fk" FOREIGN KEY ("party_id") REFERENCES "public"."master_parties"("id") ON DELETE set null ON UPDATE no action;
--> statement-breakpoint
-- Exclusive PvE Hero reservations also cover older service paths. Acquiring the
-- Hero row lock makes deployment race safely with equipment/work/expedition changes.
CREATE FUNCTION pve_assert_hero_idle(target_hero_id varchar) RETURNS void LANGUAGE plpgsql AS $$
DECLARE reserved_map varchar;
BEGIN
  IF target_hero_id IS NULL THEN RETURN; END IF;
  PERFORM h.id FROM heroes h INNER JOIN masters m ON m.id = h.master_id
    WHERE h.id = target_hero_id FOR UPDATE OF h;
  IF NOT FOUND THEN RETURN; END IF; -- account/hero cascade cleanup
  SELECT map_id INTO reserved_map FROM pve_hero_reservations WHERE hero_id = target_hero_id;
  IF reserved_map IS NOT NULL AND reserved_map IS DISTINCT FROM current_setting('app.pve_map_id', true) THEN
    RAISE EXCEPTION 'ERR_PVE_HERO_DEPLOYED' USING ERRCODE = '23514';
  END IF;
END;
$$;
--> statement-breakpoint
CREATE FUNCTION pve_guard_hero_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM pve_assert_hero_idle(OLD.id);
    RETURN OLD;
  END IF;
  -- Passive survival ticks may update these fields while a squad is away.
  IF (to_jsonb(NEW) - ARRAY['updated_at', 'hunger', 'fatigue']) IS DISTINCT FROM
     (to_jsonb(OLD) - ARRAY['updated_at', 'hunger', 'fatigue']) THEN
    PERFORM pve_assert_hero_idle(OLD.id);
  END IF;
  RETURN NEW;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER pve_hero_mutation_guard BEFORE UPDATE OR DELETE ON heroes
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_mutation();
--> statement-breakpoint
CREATE FUNCTION pve_guard_hero_link() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE before_id varchar; after_id varchar;
BEGIN
  IF TG_OP <> 'INSERT' THEN before_id := to_jsonb(OLD)->>TG_ARGV[0]; END IF;
  IF TG_OP <> 'DELETE' THEN after_id := to_jsonb(NEW)->>TG_ARGV[0]; END IF;
  IF before_id IS NOT NULL THEN PERFORM pve_assert_hero_idle(before_id); END IF;
  IF after_id IS DISTINCT FROM before_id THEN PERFORM pve_assert_hero_idle(after_id); END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER pve_gear_guard BEFORE INSERT OR UPDATE OR DELETE ON equipment_instances
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('equipped_hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_party_membership_guard BEFORE INSERT OR UPDATE OR DELETE ON combat_party_slots
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_skill_guard BEFORE INSERT OR UPDATE OR DELETE ON hero_skill_instances
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_imprint_guard BEFORE INSERT OR UPDATE OR DELETE ON hero_imprints
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_affinity_guard BEFORE INSERT OR UPDATE OR DELETE ON hero_element_affinities
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_subclass_guard BEFORE INSERT OR UPDATE OR DELETE ON hero_subclasses
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_worker_guard BEFORE INSERT OR UPDATE OR DELETE ON building_worker_assignments
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_instance_id');
--> statement-breakpoint
CREATE TRIGGER pve_treatment_guard BEFORE INSERT OR UPDATE OR DELETE ON hero_treatments
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE TRIGGER pve_expedition_guard BEFORE INSERT OR UPDATE OR DELETE ON expedition_members
  FOR EACH ROW EXECUTE FUNCTION pve_guard_hero_link('hero_id');
--> statement-breakpoint
CREATE FUNCTION pve_guard_party_delete() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM masters WHERE id = OLD.master_id) AND EXISTS
    (SELECT 1 FROM pve_squads WHERE party_id = OLD.id AND status IN ('IDLE', 'MOVING', 'FIGHTING')) THEN
    RAISE EXCEPTION 'ERR_PVE_HERO_DEPLOYED' USING ERRCODE = '23514';
  END IF;
  RETURN OLD;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER pve_party_delete_guard BEFORE DELETE ON master_parties
  FOR EACH ROW EXECUTE FUNCTION pve_guard_party_delete();
--> statement-breakpoint
CREATE FUNCTION pve_guard_legacy_combat() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('ACTIVE', 'RESOLVING') THEN
    PERFORM id FROM masters WHERE id = NEW.master_id FOR UPDATE;
    IF EXISTS (SELECT 1 FROM pve_maps WHERE master_id = NEW.master_id AND status = 'ACTIVE') THEN
      RAISE EXCEPTION 'ERR_PVE_MAP_ACTIVE' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
--> statement-breakpoint
CREATE TRIGGER pve_legacy_combat_guard BEFORE INSERT OR UPDATE ON combat_sessions
  FOR EACH ROW EXECUTE FUNCTION pve_guard_legacy_combat();

--> statement-breakpoint
CREATE TRIGGER pve_legacy_dungeon_guard BEFORE INSERT OR UPDATE ON dungeon_instances
  FOR EACH ROW EXECUTE FUNCTION pve_guard_legacy_combat();
--> statement-breakpoint
-- Preserve configured bosses; classify the existing sample guardian only when no boss is configured.
UPDATE enemy_templates SET is_boss = TRUE
  WHERE code = 'SAMPLE_STONE_GOLEM' AND is_active = TRUE
    AND NOT EXISTS (SELECT 1 FROM enemy_templates WHERE is_active = TRUE AND is_boss = TRUE);
