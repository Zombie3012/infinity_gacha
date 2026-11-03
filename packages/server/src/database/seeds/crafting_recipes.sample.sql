-- DM-10 crafting recipes (sample prototype costs).
INSERT INTO crafting_recipes (code, name, target_template_code, required_forge_level, required_materials, craft_fee_silver, is_active)
VALUES
  ('RECIPE_IRON_SWORD', 'Kiếm Sắt Thô', 'SAMPLE_IRON_SWORD', 1, '[{"itemId":"IRON","quantity":10},{"itemId":"WOOD","quantity":5}]'::jsonb, 1000, true),
  ('RECIPE_LEATHER_CHEST', 'Giáp Da', 'SAMPLE_LEATHER_CHEST', 1, '[{"itemId":"STONE","quantity":5},{"itemId":"IRON","quantity":3}]'::jsonb, 800, true),
  ('RECIPE_SWIFT_CHARM', 'Bùa Nhanh Nhẹn', 'SAMPLE_SWIFT_CHARM', 2, '[{"itemId":"IRON","quantity":5},{"itemId":"STONE","quantity":5}]'::jsonb, 1500, true)
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  target_template_code = EXCLUDED.target_template_code,
  required_forge_level = EXCLUDED.required_forge_level,
  required_materials = EXCLUDED.required_materials,
  craft_fee_silver = EXCLUDED.craft_fee_silver,
  is_active = EXCLUDED.is_active;
