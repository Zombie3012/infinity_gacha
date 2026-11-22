-- This legacy potion has no use handler yet. Keep it out of the usable catalogue.
UPDATE shop_items SET is_active=false WHERE item_id='STAMINA_POTION';
