CREATE TABLE "hero_chronicles" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"hero_id" varchar(36),
	"name" varchar(100) NOT NULL,
	"rarity" integer NOT NULL,
	"class_code" varchar(30) NOT NULL,
	"biography" text NOT NULL,
	"status" varchar(20) DEFAULT 'ALIVE' NOT NULL,
	"summoned_at" timestamp with time zone NOT NULL,
	"events" jsonb DEFAULT '[]'::jsonb NOT NULL,
	CONSTRAINT "uq_chronicle_hero" UNIQUE("hero_id"),
	CONSTRAINT "ck_chronicle_rarity" CHECK ("hero_chronicles"."rarity" BETWEEN 1 AND 7),
	CONSTRAINT "ck_chronicle_status" CHECK ("hero_chronicles"."status" IN ('ALIVE','DEAD','SACRIFICED'))
);
--> statement-breakpoint
ALTER TABLE "heroes" ALTER COLUMN "category" SET DEFAULT 'HERO';--> statement-breakpoint
ALTER TABLE "hero_chronicles" ADD CONSTRAINT "hero_chronicles_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_chronicles" ADD CONSTRAINT "hero_chronicles_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "idx_chronicle_master" ON "hero_chronicles" USING btree ("master_id","summoned_at","id");
--> statement-breakpoint
-- Origin remains a historical summon/payment field, never a mortality rule.
UPDATE heroes SET category = 'HERO', state = CASE WHEN state = 'DISABLED' OR hp <= 0 THEN 'DEAD' ELSE state END,
 hp = CASE WHEN state IN ('DEAD','DISABLED') OR hp <= 0 THEN 0 ELSE hp END,
 current_hp_pct = CASE WHEN state IN ('DEAD','DISABLED') OR hp <= 0 THEN 0 ELSE current_hp_pct END;
--> statement-breakpoint
CREATE FUNCTION chronicle_biography(hero_name text, hero_key text, hero_class text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
 SELECT hero_name || ' xuất thân từ ' ||
 (ARRAY['miền biên viễn phủ sương','thành phố bên bờ biển','thung lũng giữa núi','ngôi làng ven rừng'])[1 + get_byte(decode(md5(hero_key),'hex'),0) % 4]
 || '. Trước khi được triệu hồi, người anh hùng này đã chọn con đường ' || hero_class ||
 ' và mang theo lời nguyện ' ||
 (ARRAY['bảo vệ những người không thể tự chiến đấu','tìm lại dấu tích quê hương','khám phá bí mật của ngọn tháp','đưa đồng đội trở về an toàn'])[1 + get_byte(decode(md5(hero_key),'hex'),1) % 4]
 || '. Từ ngày đến căn cứ, mỗi hành trình đều được Sử Điện ghi lại.';
$$;
--> statement-breakpoint
INSERT INTO hero_chronicles(id,master_id,hero_id,name,rarity,class_code,biography,status,summoned_at,events)
SELECT h.id,h.master_id,h.id,h.name,h.rarity,h.class_code,
 chronicle_biography(h.name,h.id,h.class_code),CASE WHEN h.state='DEAD' THEN 'DEAD' ELSE 'ALIVE' END,h.created_at,
 (SELECT jsonb_agg(e ORDER BY (e->>'at')::timestamptz) FROM (
   SELECT jsonb_build_object('type','SUMMONED','at',h.created_at) e
   UNION ALL SELECT jsonb_build_object('type','DIED','at',d.recorded_at,'referenceId',d.combat_session_id,'detail',d.cause)
    FROM hero_death_records d WHERE d.hero_id=h.id
   UNION ALL SELECT jsonb_build_object('type','RESURRECTED','at',t.completed_at)
    FROM hero_treatments t WHERE t.hero_id=h.id AND t.treatment_type='RESURRECTION' AND t.status='COMPLETED'
   UNION ALL SELECT jsonb_build_object('type','DIED','at',h.updated_at,'detail','Tình trạng tử trận được khôi phục từ dữ liệu cũ.')
    WHERE h.state='DEAD' AND NOT EXISTS(SELECT 1 FROM hero_death_records d WHERE d.hero_id=h.id)
 ) history)
FROM heroes h;
--> statement-breakpoint
CREATE FUNCTION normalize_hero_lifecycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
 NEW.category := 'HERO';
 IF NEW.state IN ('DEAD','DISABLED') OR NEW.hp <= 0 THEN
  NEW.state := 'DEAD'; NEW.hp := 0; NEW.current_hp_pct := 0;
 END IF;
 RETURN NEW;
END $$;
--> statement-breakpoint
CREATE TRIGGER heroes_normalize_lifecycle BEFORE INSERT OR UPDATE ON heroes
 FOR EACH ROW EXECUTE FUNCTION normalize_hero_lifecycle();
--> statement-breakpoint
CREATE FUNCTION record_hero_chronicle() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE additions jsonb := '[]'::jsonb;
BEGIN
 IF TG_OP='DELETE' THEN
  UPDATE hero_chronicles SET hero_id=NULL,
   status=CASE WHEN OLD.state='DEAD' THEN 'DEAD' ELSE 'SACRIFICED' END,
   events=events || jsonb_build_array(jsonb_build_object('type',CASE WHEN OLD.state='DEAD' THEN 'ARCHIVED' ELSE 'SACRIFICED' END,'at',clock_timestamp()))
   WHERE id=OLD.id;
  RETURN OLD;
 END IF;
 IF TG_OP='INSERT' THEN
  additions := jsonb_build_array(jsonb_build_object('type','SUMMONED','at',NEW.created_at));
  IF NEW.state='DEAD' THEN additions := additions || jsonb_build_array(jsonb_build_object('type','DIED','at',NEW.created_at)); END IF;
  INSERT INTO hero_chronicles(id,master_id,hero_id,name,rarity,class_code,biography,status,summoned_at,events)
   VALUES(NEW.id,NEW.master_id,NEW.id,NEW.name,NEW.rarity,NEW.class_code,chronicle_biography(NEW.name,NEW.id,NEW.class_code),
    CASE WHEN NEW.state='DEAD' THEN 'DEAD' ELSE 'ALIVE' END,NEW.created_at,additions);
 ELSE
  IF OLD.state<>'DEAD' AND NEW.state='DEAD' THEN
   additions := additions || jsonb_build_array(jsonb_build_object('type','DIED','at',clock_timestamp()));
  ELSIF OLD.state='DEAD' AND NEW.state<>'DEAD' THEN
   additions := additions || jsonb_build_array(jsonb_build_object('type','RESURRECTED','at',clock_timestamp()));
  END IF;
  IF OLD.rarity<>NEW.rarity THEN
   additions := additions || jsonb_build_array(jsonb_build_object('type','STAR_PROMOTED','at',clock_timestamp(),'detail',NEW.rarity || '★'));
  END IF;
  UPDATE hero_chronicles SET name=NEW.name,rarity=NEW.rarity,class_code=NEW.class_code,
   status=CASE WHEN NEW.state='DEAD' THEN 'DEAD' ELSE 'ALIVE' END,events=events || additions WHERE id=NEW.id;
 END IF;
 RETURN NEW;
END $$;
--> statement-breakpoint
CREATE TRIGGER heroes_chronicle_write AFTER INSERT OR UPDATE ON heroes
 FOR EACH ROW EXECUTE FUNCTION record_hero_chronicle();
--> statement-breakpoint
CREATE TRIGGER heroes_chronicle_delete BEFORE DELETE ON heroes
 FOR EACH ROW EXECUTE FUNCTION record_hero_chronicle();
--> statement-breakpoint
INSERT INTO building_types(code,name,category,description,max_level,max_workers,required_world_level,build_cost_silver)
 VALUES('HERO_CHRONICLE','Sử Điện Anh Hùng','UTILITY','Lưu tiểu sử và hành trình của từng Hero đã triệu hồi, tưởng niệm người tử trận và hồi sinh bằng Ngọc hồi sinh 7★.',1,0,1,1200);
--> statement-breakpoint
INSERT INTO item_templates(code,name,category,rarity,description,is_active)
 VALUES('RESURRECTION_GEM_7','Ngọc hồi sinh 7★','CONSUMABLE',7,'Tiêu hao 1 viên hồi sinh một Hero tử trận về 100% HP tại Sử Điện Anh Hùng, không thêm phí. Trang bị đã rơi không được tạo lại.',true);
--> statement-breakpoint
UPDATE item_templates SET is_active=false,description='Vật phẩm lịch sử, đã ngừng dùng để hồi sinh. Cơ chế mới dùng Ngọc hồi sinh 7★.' WHERE code='DIVINE_TEAR';
--> statement-breakpoint
UPDATE shop_items SET is_active=false WHERE item_id='DIVINE_TEAR';
--> statement-breakpoint
INSERT INTO hero_development_configs(id,action,rank,material_item_id,material_quantity,required_hero_level,required_promotion_rank,max_level_after,stat_growth_multiplier,is_sample)
 VALUES('hero-dev-promotion-05','PROMOTION',5,'SAMPLE_HERO_PROMOTION_SEAL',25,50,4,60,1.05,true),
 ('hero-dev-promotion-06','PROMOTION',6,'SAMPLE_HERO_PROMOTION_SEAL',30,60,5,70,1.05,true);
--> statement-breakpoint
INSERT INTO hero_level_configs(level,cumulative_exp_required,stat_growth_multiplier,is_sample)
 SELECT level,round(100 * (power(1.5::numeric,level-1)-1)/0.5)::bigint,1.05,true FROM generate_series(51,70) level;
