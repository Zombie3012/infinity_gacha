-- P3 global world map (12x12 outer-rim grid, sample yields).
INSERT INTO world_tiles (id, x, y, terrain, resource_type, base_yield_per_hour, required_power, is_outer_rim)
SELECT
  'tile-' || x || '-' || y,
  100 + x,
  100 + y,
  (ARRAY['PLAINS','FOREST','HILLS','MOUNTAIN','MARSH','RUINS'])[1 + ((x + y) % 6)],
  (ARRAY['WOOD','STONE','IRON','FOOD_RAW','HERB','STONE'])[1 + ((x * 2 + y) % 6)],
  20 + ((x * 7 + y * 3) % 5) * 10,
  (x + y) * 400,
  true
FROM generate_series(0, 11) AS x
CROSS JOIN generate_series(0, 11) AS y
ON CONFLICT (x, y) DO UPDATE SET
  terrain = EXCLUDED.terrain,
  resource_type = EXCLUDED.resource_type,
  base_yield_per_hour = EXCLUDED.base_yield_per_hour,
  required_power = EXCLUDED.required_power,
  is_outer_rim = EXCLUDED.is_outer_rim;

-- Central Imperial Wonder at the map centre (500, 500). It is not part of the
-- outer-rim spawn pool; MOD-13-07 sieges it during the last 3 days of a season.
INSERT INTO world_tiles (id, x, y, terrain, resource_type, base_yield_per_hour, required_power, is_outer_rim)
VALUES ('tile-wonder-500-500', 500, 500, 'WONDER', 'WONDER', 0, 25000, false)
ON CONFLICT (x, y) DO UPDATE SET
  terrain = EXCLUDED.terrain,
  resource_type = EXCLUDED.resource_type,
  required_power = EXCLUDED.required_power,
  is_outer_rim = EXCLUDED.is_outer_rim;
