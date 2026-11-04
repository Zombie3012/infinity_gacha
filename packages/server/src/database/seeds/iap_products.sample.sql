-- P2 IAP package catalogue (sample prices; the prototype never contacts Apple/Google).
INSERT INTO iap_products (code, name, description, price_cents, currency, gems, silver, items, is_active, sort_order)
VALUES
  ('PKG_GEMS_TIER_1', 'Túi Ngọc Khởi Đầu', '1.000 Ngọc cho lần nạp đầu tiên.', 999, 'USD', 1000, 0, '[]'::jsonb, true, 10),
  ('PKG_GEMS_TIER_2', 'Túi Ngọc Chiến Binh', '2.500 Ngọc, tặng kèm 5.000 Xu Bạc.', 1999, 'USD', 2500, 5000, '[]'::jsonb, true, 20),
  ('PKG_STARTER', 'Gói Tân Thủ', '300 Ngọc, 10 lương khô và 2 dược liệu.', 499, 'USD', 300, 0,
   '[{"itemId":"FOOD","quantity":10},{"itemId":"MEDICINE","quantity":2}]'::jsonb, true, 30),
  ('PKG_MONTHLY_PASS', 'Thẻ Tháng', '500 Ngọc và 10 Đá Tăng Cường mỗi tháng.', 999, 'USD', 500, 0,
   '[{"itemId":"ENHANCEMENT_STONE","quantity":10}]'::jsonb, true, 40)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  description = EXCLUDED.description,
  price_cents = EXCLUDED.price_cents,
  currency = EXCLUDED.currency,
  gems = EXCLUDED.gems,
  silver = EXCLUDED.silver,
  items = EXCLUDED.items,
  is_active = EXCLUDED.is_active,
  sort_order = EXCLUDED.sort_order;
