-- Temporary airship catalogue: all implemented items and equipment cost 1 Silver.
INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
SELECT code,name,description,code,category,1,0,'{}',true,100 FROM item_templates
WHERE is_active=true AND code NOT LIKE 'SAMPLE_TRASH_%' AND code NOT IN ('DIVINE_TEAR','STAMINA_POTION')
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,description=EXCLUDED.description,item_id=EXCLUDED.item_id,
category=EXCLUDED.category,price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;

INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
SELECT code,name,'Trang bị sử dụng cho Hero.',code,'EQUIPMENT',1,0,'{}',true,200 FROM equipment_templates
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,item_id=EXCLUDED.item_id,category='EQUIPMENT',
price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;

INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
VALUES('SHOP_SCROLL_NORMAL','Thiên Thư thường','Dùng cho triệu hồi bằng Thiên Thư thường.','NORMAL','SCROLL',1,0,'{}',true,50)
ON CONFLICT(code) DO UPDATE SET price_silver=1,daily_limit=0,rotation_days='{}',is_active=true;

UPDATE shop_items SET is_active=false WHERE item_id IN ('DIVINE_TEAR','STAMINA_POTION') OR item_id LIKE 'SAMPLE_TRASH_%';
