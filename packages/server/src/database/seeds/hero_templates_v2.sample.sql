-- Combat v2 conversion for the sample Hero templates.
-- Level-1 budgets: 1★ 100, 2★ 130, 3★ 170, 4★ 220, 5★ 280 (6★ 350 / 7★ 430).
-- 1-2 star templates stay Unclassified; 3-5 star templates carry their class
-- options so the summon roll keeps the template's identity.
WITH base AS (
  SELECT
    id,
    CASE default_rarity
      WHEN 1 THEN 100 WHEN 2 THEN 130 WHEN 3 THEN 170 WHEN 4 THEN 220
      WHEN 5 THEN 280 WHEN 6 THEN 350 WHEN 7 THEN 430 ELSE 100
    END AS budget,
    CASE hero_class
      WHEN 'WARRIOR' THEN 0.35 WHEN 'ARCHER' THEN 0.30 WHEN 'ASSASSIN' THEN 0.25
      WHEN 'MAGE' THEN 0.15 WHEN 'TANK' THEN 0.30 WHEN 'SUPPORT' THEN 0.15 ELSE 0.25
    END AS w_str,
    CASE hero_class
      WHEN 'WARRIOR' THEN 0.15 WHEN 'ARCHER' THEN 0.15 WHEN 'ASSASSIN' THEN 0.15
      WHEN 'MAGE' THEN 0.45 WHEN 'TANK' THEN 0.10 WHEN 'SUPPORT' THEN 0.35 ELSE 0.25
    END AS w_int,
    CASE hero_class
      WHEN 'WARRIOR' THEN 0.30 WHEN 'ARCHER' THEN 0.20 WHEN 'ASSASSIN' THEN 0.20
      WHEN 'MAGE' THEN 0.20 WHEN 'TANK' THEN 0.45 WHEN 'SUPPORT' THEN 0.30 ELSE 0.25
    END AS w_sta,
    CASE hero_class
      WHEN 'WARRIOR' THEN 0.20 WHEN 'ARCHER' THEN 0.35 WHEN 'ASSASSIN' THEN 0.40
      WHEN 'MAGE' THEN 0.20 WHEN 'TANK' THEN 0.15 WHEN 'SUPPORT' THEN 0.20 ELSE 0.25
    END AS w_agi
  FROM hero_templates
), sized AS (
  SELECT
    id,
    round(budget * w_str)::int AS s_str,
    round(budget * w_int)::int AS s_int,
    round(budget * w_sta)::int AS s_sta,
    budget - round(budget * w_str)::int - round(budget * w_int)::int - round(budget * w_sta)::int AS s_agi
  FROM base
)
UPDATE hero_templates t SET
  base_str = sized.s_str,
  base_int = sized.s_int,
  base_sta = sized.s_sta,
  base_agi = sized.s_agi,
  archetype_weights = jsonb_build_object(
    'str', base.w_str, 'int', base.w_int, 'sta', base.w_sta, 'agi', base.w_agi
  ),
  class_code = CASE
    WHEN t.default_rarity <= 2 THEN 'UNCLASSIFIED'
    WHEN t.hero_class = 'WARRIOR' THEN 'WARRIOR'
    WHEN t.hero_class = 'ARCHER' THEN 'ARCHER'
    WHEN t.hero_class = 'ASSASSIN' THEN 'THIEF'
    WHEN t.hero_class = 'MAGE' THEN 'MAGE'
    WHEN t.hero_class = 'TANK' THEN 'WARRIOR'
    WHEN t.hero_class = 'SUPPORT' THEN 'MAGE'
    ELSE 'UNCLASSIFIED'
  END,
  combat_role = CASE t.hero_class
    WHEN 'TANK' THEN 'TANK'
    WHEN 'SUPPORT' THEN 'SUPPORT'
    WHEN 'ASSASSIN' THEN 'ASSASSIN'
    WHEN 'MAGE' THEN 'MAGIC_DPS'
    ELSE 'PHYSICAL_DPS'
  END,
  class_options = CASE
    WHEN t.default_rarity <= 2 THEN NULL
    WHEN t.hero_class = 'WARRIOR' THEN '["WARRIOR", "SPEARMAN"]'::jsonb
    WHEN t.hero_class = 'ARCHER' THEN '["ARCHER", "SPEARMAN"]'::jsonb
    WHEN t.hero_class = 'ASSASSIN' THEN '["THIEF", "ARCHER"]'::jsonb
    WHEN t.hero_class = 'MAGE' THEN '["MAGE"]'::jsonb
    WHEN t.hero_class = 'TANK' THEN '["WARRIOR"]'::jsonb
    WHEN t.hero_class = 'SUPPORT' THEN '["MAGE"]'::jsonb
    ELSE NULL
  END,
  is_enabled = true
FROM sized
JOIN base ON base.id = sized.id
WHERE t.id = sized.id;

-- Legacy columns are mirrored from the derived stats until the v2 engine ships.
UPDATE hero_templates SET
  base_hp = 200 + 20 * base_sta,
  base_atk = round(2.5 * base_str + 0.5 * base_agi)::int,
  base_def = 15 + round(0.5 * base_sta)::int,
  base_spd = 60 + base_agi;
