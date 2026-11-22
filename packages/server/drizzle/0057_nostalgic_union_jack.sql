CREATE TABLE "alchemy_research" (
	"master_id" varchar(36) NOT NULL,
	"code" varchar(60) NOT NULL,
	"researched_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "uq_alchemy_research" UNIQUE("master_id","code")
);
--> statement-breakpoint
CREATE TABLE "hero_consumables" (
	"hero_id" varchar(36) PRIMARY KEY NOT NULL,
	"master_id" varchar(36) NOT NULL,
	"config" jsonb NOT NULL,
	"squad_id" varchar(36),
	"strength_ready" boolean DEFAULT false NOT NULL
);
--> statement-breakpoint
ALTER TABLE "alchemy_research" ADD CONSTRAINT "alchemy_research_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_consumables" ADD CONSTRAINT "hero_consumables_hero_id_heroes_id_fk" FOREIGN KEY ("hero_id") REFERENCES "public"."heroes"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "hero_consumables" ADD CONSTRAINT "hero_consumables_master_id_masters_id_fk" FOREIGN KEY ("master_id") REFERENCES "public"."masters"("id") ON DELETE cascade ON UPDATE no action;
--> statement-breakpoint
INSERT INTO item_templates(code,name,category,rarity,description,is_active)
SELECT 'ALCHEMY_HERB_' || star, 'Dược liệu ' || star || '★', 'MATERIAL', star, 'Dược liệu giả kim. Bản đầu chỉ thu thập dược liệu 1★ trong PvE.', true FROM generate_series(1,7) star
ON CONFLICT(code) DO NOTHING;
--> statement-breakpoint
INSERT INTO item_templates(code,name,category,rarity,description,is_active) VALUES
('MANA_POTION','Thuốc ma lực','CONSUMABLE',2,'Hồi 50% MP tối đa cho Hero sử dụng.',true),
('STRENGTH_POTION','Thuốc cường lực','CONSUMABLE',3,'Tăng 20% ATK của Hero trong một trận PvE. Không cộng dồn.',true)
ON CONFLICT(code) DO NOTHING;
