CREATE TABLE "shop_purchases" (
	"id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"idempotency_key" varchar(80) NOT NULL,
	"item_code" varchar(50) NOT NULL,
	"quantity" integer NOT NULL,
	"result" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_shop_purchase_key" UNIQUE("master_id","idempotency_key")
);
--> statement-breakpoint
ALTER TABLE "shop_items" ALTER COLUMN "price_silver" SET DEFAULT 1;--> statement-breakpoint
ALTER TABLE "shop_purchases" ADD CONSTRAINT "shop_purchases_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
INSERT INTO building_types(code,name,category,description,max_level,max_workers,required_world_level,build_cost_silver)
VALUES('SHOP_AIRSHIP','Thương Thuyền Khinh Khí','UTILITY','Cửa hàng khinh khí cầu neo tại căn cứ, bán vật phẩm và trang bị đang sử dụng trong game. Giá tạm thời 1 bạc mỗi món.',1,0,1,1000);
--> statement-breakpoint
INSERT INTO item_templates(code,name,category,rarity,description,is_active) VALUES
('SAMPLE_HERO_EXP_100','Sách EXP Hero Sơ Cấp (+1.000)','DEVELOPMENT',2,'Dùng để thêm 1.000 EXP cho Hero.',true),
('SAMPLE_HERO_EXP_1000','Sách EXP Hero Trung Cấp (+100.000)','DEVELOPMENT',3,'Dùng để thêm 100.000 EXP cho Hero.',true),
('SAMPLE_HERO_EXP_10000','Sách EXP Hero Cao Cấp (+10.000.000)','DEVELOPMENT',4,'Dùng để thêm 10.000.000 EXP cho Hero.',true),
('SAMPLE_HERO_PROMOTION_SEAL','Ấn Thăng Bậc Hero','DEVELOPMENT',3,'Nguyên liệu đột phá giới hạn cấp Hero.',true),
('SAMPLE_HERO_AWAKENING_CORE','Lõi Thức Tỉnh Hero','DEVELOPMENT',4,'Nguyên liệu thức tỉnh Hero.',true),
('SAMPLE_HERO_SKILL_BOOK','Sách Kỹ Năng Hero','DEVELOPMENT',3,'Nguyên liệu nâng cấp kỹ năng Hero.',true)
ON CONFLICT(code) DO NOTHING;
--> statement-breakpoint
-- Temporary prototype catalogue: all active items, no daily/weekday restrictions.
INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
SELECT code,name,description,code,category,1,0,'{}',true,100 FROM item_templates
WHERE is_active=true AND code NOT LIKE 'SAMPLE_TRASH_%'
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,item_id=EXCLUDED.item_id,
category=EXCLUDED.category,price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;
--> statement-breakpoint
INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
SELECT code,name,'Trang bị sử dụng cho Hero.','' || code,'EQUIPMENT',1,0,'{}',true,200 FROM equipment_templates
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,category='EQUIPMENT',price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;
--> statement-breakpoint
INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
VALUES('SHOP_SCROLL_NORMAL','Thiên Thư thường','Dùng cho triệu hồi bằng Thiên Thư thường.','NORMAL','SCROLL',1,0,'{}',true,50)
ON CONFLICT(code) DO UPDATE SET price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;
--> statement-breakpoint
UPDATE shop_items SET is_active=false WHERE item_id='DIVINE_TEAR' OR item_id LIKE 'SAMPLE_TRASH_%';
