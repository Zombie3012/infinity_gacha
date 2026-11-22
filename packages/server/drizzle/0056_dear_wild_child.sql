CREATE TABLE "magic_production_nodes" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"building_id" varchar(36) NOT NULL,
	"wing" varchar(30) NOT NULL,
	"resource_type" varchar(30) NOT NULL,
	"base_rate_per_hour" double precision NOT NULL,
	"current_stored" double precision DEFAULT 0 NOT NULL,
	"max_capacity" double precision NOT NULL,
	"last_harvest_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_magic_production_wing" UNIQUE("building_id","wing")
);
--> statement-breakpoint
ALTER TABLE "magic_production_nodes" ADD CONSTRAINT "magic_production_nodes_building_id_base_buildings_id_fk" FOREIGN KEY ("building_id") REFERENCES "public"."base_buildings"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
-- The three wing codes remain internal function identifiers, not physical buildings.
CREATE FUNCTION consolidate_magic_buildings(owner_id varchar DEFAULT NULL) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE owner record; old_ids varchar[]; hall_id varchar; target_level integer; output record;
 earned integer; merged integer := 0;
BEGIN
 FOR owner IN SELECT DISTINCT master_id FROM base_buildings
  WHERE building_type IN ('LIBRARY','ALCHEMY_WORKSHOP','MAGIC_RESEARCH_LAB') AND (owner_id IS NULL OR master_id=owner_id)
 LOOP
  PERFORM 1 FROM masters WHERE id=owner.master_id FOR UPDATE;
  SELECT array_agg(id ORDER BY created_at,id),max(least(3,level + CASE WHEN status='UPGRADING' THEN 1 ELSE 0 END))
   INTO old_ids,target_level FROM base_buildings WHERE master_id=owner.master_id
    AND building_type IN ('LIBRARY','ALCHEMY_WORKSHOP','MAGIC_RESEARCH_LAB');
  IF old_ids IS NULL THEN CONTINUE; END IF;
  -- Pay all earned output in its original item tier before removing old plots.
  FOR output IN SELECT n.*,b.building_type,
   coalesce((SELECT sum(greatest(0,w.efficiency_boost-1)) FROM building_worker_assignments w WHERE w.building_id=b.id),0) boost,
   EXISTS(SELECT 1 FROM building_worker_assignments w JOIN heroes h ON h.id=w.hero_instance_id
    WHERE w.building_id=b.id AND h.class_code='MAGE' AND h.hp>0 AND h.state NOT IN ('DEAD','DISABLED')) has_mage
   FROM base_production_nodes n JOIN base_buildings b ON b.id=n.building_id WHERE b.id=ANY(old_ids)
  LOOP
   earned := ceil(least(output.max_capacity,output.current_stored + greatest(0,extract(epoch FROM now()-output.last_harvest_at)/3600)
    * output.base_rate_per_hour * (1+output.boost) * CASE WHEN output.building_type='LIBRARY' AND NOT output.has_mage THEN 0 ELSE 1 END));
   IF earned>0 THEN
    INSERT INTO master_items(id,master_id,item_id,quantity) VALUES(gen_random_uuid()::text,owner.master_id,output.resource_type,earned)
    ON CONFLICT(master_id,item_id) DO UPDATE SET quantity=master_items.quantity+EXCLUDED.quantity,updated_at=now();
   END IF;
  END LOOP;
  SELECT id INTO hall_id FROM base_buildings WHERE master_id=owner.master_id AND building_type='HALL_OF_MAGIC' ORDER BY created_at,id LIMIT 1;
  IF hall_id IS NULL THEN hall_id:=old_ids[1]; END IF;
  UPDATE base_buildings SET building_type='HALL_OF_MAGIC',level=greatest(target_level,least(3,level+CASE WHEN status='UPGRADING' THEN 1 ELSE 0 END)),
   status='READY',upgrade_finishes_at=NULL,updated_at=now() WHERE id=hall_id RETURNING level INTO target_level;
  UPDATE building_worker_assignments SET building_id=hall_id WHERE building_id=ANY(old_ids);
  -- Keep the Hall's six slots; surplus Heroes return to the unassigned pool intact.
  DELETE FROM building_worker_assignments WHERE id IN (SELECT id FROM (
   SELECT id,row_number() OVER(ORDER BY assigned_at,id) r FROM building_worker_assignments WHERE building_id=hall_id
  ) slots WHERE r>6);
  DELETE FROM base_production_nodes WHERE building_id=ANY(old_ids);
  DELETE FROM base_buildings WHERE id=ANY(old_ids) AND id<>hall_id;
  merged:=merged+cardinality(old_ids);
 END LOOP;
 RETURN merged;
END $$;
--> statement-breakpoint
SELECT consolidate_magic_buildings();
--> statement-breakpoint
INSERT INTO magic_production_nodes(id,building_id,wing,resource_type,base_rate_per_hour,max_capacity)
SELECT gen_random_uuid()::text,b.id,p.wing,
 CASE WHEN p.wing='ALCHEMY_WORKSHOP' THEN 'ENHANCEMENT_STONE' WHEN b.level=1 THEN 'SAMPLE_HERO_EXP_100' WHEN b.level=2 THEN 'SAMPLE_HERO_EXP_1000' ELSE 'SAMPLE_HERO_EXP_10000' END,
 CASE WHEN p.wing='ALCHEMY_WORKSHOP' THEN CASE b.level WHEN 1 THEN 15 WHEN 2 THEN 30 ELSE 60 END ELSE CASE b.level WHEN 1 THEN 100 WHEN 2 THEN 50 ELSE 15 END END,
 CASE WHEN p.wing='ALCHEMY_WORKSHOP' THEN CASE b.level WHEN 1 THEN 150 WHEN 2 THEN 300 ELSE 600 END ELSE CASE b.level WHEN 1 THEN 1000 WHEN 2 THEN 500 ELSE 150 END END
 FROM base_buildings b CROSS JOIN (VALUES('LIBRARY'),('ALCHEMY_WORKSHOP')) p(wing) WHERE b.building_type='HALL_OF_MAGIC'
ON CONFLICT(building_id,wing) DO NOTHING;
--> statement-breakpoint
DELETE FROM building_types WHERE code IN ('LIBRARY','ALCHEMY_WORKSHOP','MAGIC_RESEARCH_LAB');
