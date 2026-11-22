INSERT INTO shop_items(code,name,description,item_id,category,price_silver,daily_limit,rotation_days,is_active,sort_order)
SELECT code,name,description,code,category,1,0,'{}',true,100 FROM item_templates
WHERE code IN ('MANA_POTION','STRENGTH_POTION') OR code LIKE 'ALCHEMY_HERB_%'
ON CONFLICT(code) DO NOTHING;
