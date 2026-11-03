-- Illustrative Hero templates for local development.
-- These values are starter samples, not approved production balance data.
-- This seed intentionally does not create a banner or summon pool.

INSERT INTO hero_templates
    (id, code, name, default_rarity, hero_class, element, base_hp, base_atk, base_def, base_spd)
VALUES
    -- ========================================
    -- 1 STAR HEROES
    -- ========================================
    ('hero-1s-001', 'HERO_1S_BLADE', 'Iron Blade', 1, 'WARRIOR', 'EARTH', 520, 54, 28, 92),
    ('hero-1s-002', 'HERO_1S_ARCHER', 'Forest Archer', 1, 'ARCHER', 'WIND', 500, 62, 24, 105),
    ('hero-1s-003', 'HERO_1S_MAGE', 'Apprentice Mage', 1, 'MAGE', 'WATER', 480, 68, 22, 96),
    ('hero-1s-004', 'HERO_1S_GUARD', 'Stone Guard', 1, 'TANK', 'EARTH', 650, 38, 42, 82),
    ('hero-1s-005', 'HERO_1S_FLAME', 'Flame Rookie', 1, 'MAGE', 'FIRE', 490, 65, 23, 94),
    ('hero-1s-006', 'HERO_1S_WIND', 'Swift Runner', 1, 'ARCHER', 'WIND', 510, 58, 25, 112),
    ('hero-1s-007', 'HERO_1S_LIGHT', 'Light Novice', 1, 'SUPPORT', 'LIGHT', 530, 45, 30, 98),
    ('hero-1s-008', 'HERO_1S_SHADOW', 'Shadow Thief', 1, 'ASSASSIN', 'DARK', 470, 72, 20, 115),
    ('hero-1s-009', 'HERO_1S_WATER', 'River Healer', 1, 'SUPPORT', 'WATER', 540, 42, 32, 90),
    ('hero-1s-010', 'HERO_1S_THUNDER', 'Thunder Cadet', 1, 'WARRIOR', 'LIGHTNING', 550, 60, 27, 100),

    -- ========================================
    -- 2 STAR HEROES
    -- ========================================
    ('hero-2s-001', 'HERO_2S_BLADE', 'Steel Knight', 2, 'WARRIOR', 'EARTH', 650, 68, 36, 98),
    ('hero-2s-002', 'HERO_2S_ARCHER', 'Wind Ranger', 2, 'ARCHER', 'WIND', 620, 78, 30, 112),
    ('hero-2s-003', 'HERO_2S_MAGE', 'Frost Sorcerer', 2, 'MAGE', 'WATER', 590, 85, 28, 102),
    ('hero-2s-004', 'HERO_2S_GUARD', 'Iron Defender', 2, 'TANK', 'EARTH', 820, 50, 55, 88),
    ('hero-2s-005', 'HERO_2S_FLAME', 'Fire Dancer', 2, 'MAGE', 'FIRE', 610, 82, 29, 100),
    ('hero-2s-006', 'HERO_2S_WIND', 'Sky Hunter', 2, 'ARCHER', 'WIND', 630, 76, 31, 118),
    ('hero-2s-007', 'HERO_2S_LIGHT', 'Dawn Priest', 2, 'SUPPORT', 'LIGHT', 680, 55, 38, 104),
    ('hero-2s-008', 'HERO_2S_SHADOW', 'Night Stalker', 2, 'ASSASSIN', 'DARK', 570, 92, 25, 122),
    ('hero-2s-009', 'HERO_2S_WATER', 'Tide Healer', 2, 'SUPPORT', 'WATER', 690, 52, 40, 96),
    ('hero-2s-010', 'HERO_2S_THUNDER', 'Storm Fighter', 2, 'WARRIOR', 'LIGHTNING', 700, 80, 34, 108),

    -- ========================================
    -- 3 STAR HEROES
    -- ========================================
    ('hero-3s-001', 'HERO_3S_BLADE', 'Earthbreaker', 3, 'WARRIOR', 'EARTH', 820, 88, 48, 105),
    ('hero-3s-002', 'HERO_3S_ARCHER', 'Tempest Archer', 3, 'ARCHER', 'WIND', 780, 102, 40, 120),
    ('hero-3s-003', 'HERO_3S_MAGE', 'Abyssal Mage', 3, 'MAGE', 'WATER', 750, 112, 38, 110),
    ('hero-3s-004', 'HERO_3S_GUARD', 'Granite Colossus', 3, 'TANK', 'EARTH', 1050, 65, 72, 95),
    ('hero-3s-005', 'HERO_3S_FLAME', 'Inferno Witch', 3, 'MAGE', 'FIRE', 770, 108, 39, 108),
    ('hero-3S-006', 'HERO_3S_WIND', 'Stormblade', 3, 'ASSASSIN', 'WIND', 790, 105, 37, 125),
    ('hero-3s-007', 'HERO_3S_LIGHT', 'Celestial Priest', 3, 'SUPPORT', 'LIGHT', 850, 70, 52, 112),
    ('hero-3s-008', 'HERO_3S_SHADOW', 'Dusk Reaper', 3, 'ASSASSIN', 'DARK', 720, 120, 34, 130),
    ('hero-3s-009', 'HERO_3S_WATER', 'Ocean Oracle', 3, 'SUPPORT', 'WATER', 880, 68, 55, 104),
    ('hero-3s-010', 'HERO_3S_THUNDER', 'Thunder Champion', 3, 'WARRIOR', 'LIGHTNING', 900, 105, 46, 115),

    -- ========================================
    -- 4 STAR HEROES
    -- ========================================
    ('hero-4s-001', 'HERO_4S_BLADE', 'Dragon Slayer', 4, 'WARRIOR', 'EARTH', 1040, 112, 62, 112),
    ('hero-4s-002', 'HERO_4S_ARCHER', 'Phantom Ranger', 4, 'ARCHER', 'WIND', 990, 130, 52, 128),
    ('hero-4s-003', 'HERO_4S_MAGE', 'Glacial Empress', 4, 'MAGE', 'WATER', 960, 142, 50, 118),
    ('hero-4s-004', 'HERO_4S_GUARD', 'Mountain Fortress', 4, 'TANK', 'EARTH', 1350, 82, 95, 102),
    ('hero-4s-005', 'HERO_4S_FLAME', 'Phoenix Sorceress', 4, 'MAGE', 'FIRE', 980, 138, 51, 116),
    ('hero-4s-006', 'HERO_4S_WIND', 'Skyblade Assassin', 4, 'ASSASSIN', 'WIND', 1000, 135, 48, 135),
    ('hero-4s-007', 'HERO_4S_LIGHT', 'Archangel Healer', 4, 'SUPPORT', 'LIGHT', 1100, 90, 70, 120),
    ('hero-4s-008', 'HERO_4S_SHADOW', 'Void Executioner', 4, 'ASSASSIN', 'DARK', 920, 155, 45, 140),
    ('hero-4s-009', 'HERO_4S_WATER', 'Tidal Guardian', 4, 'TANK', 'WATER', 1400, 85, 100, 105),
    ('hero-4s-010', 'HERO_4S_THUNDER', 'Storm Lord', 4, 'WARRIOR', 'LIGHTNING', 1150, 145, 65, 125),

    -- ========================================
    -- 5 STAR HEROES
    -- ========================================
    ('hero-5s-001', 'HERO_5S_BLADE', 'Worldbreaker', 5, 'WARRIOR', 'EARTH', 1320, 145, 78, 120),
    ('hero-5s-002', 'HERO_5S_ARCHER', 'Celestial Sniper', 5, 'ARCHER', 'WIND', 1250, 168, 65, 138),
    ('hero-5s-003', 'HERO_5S_MAGE', 'Ocean Sovereign', 5, 'MAGE', 'WATER', 1220, 185, 62, 128),
    ('hero-5s-004', 'HERO_5S_GUARD', 'Titan King', 5, 'TANK', 'EARTH', 1750, 110, 125, 110),
    ('hero-5s-005', 'HERO_5S_FLAME', 'Eternal Phoenix', 5, 'MAGE', 'FIRE', 1280, 180, 64, 126),
    ('hero-5s-006', 'HERO_5S_WIND', 'Heavenly Assassin', 5, 'ASSASSIN', 'WIND', 1300, 178, 60, 145),
    ('hero-5s-007', 'HERO_5S_LIGHT', 'Divine Archon', 5, 'SUPPORT', 'LIGHT', 1450, 115, 90, 132),
    ('hero-5s-008', 'HERO_5S_SHADOW', 'Abyss Overlord', 5, 'ASSASSIN', 'DARK', 1180, 195, 58, 150),
    ('hero-5s-009', 'HERO_5S_WATER', 'Leviathan Guardian', 5, 'TANK', 'WATER', 1850, 105, 135, 115),
    ('hero-5s-010', 'HERO_5S_THUNDER', 'Thunder Emperor', 5, 'WARRIOR', 'LIGHTNING', 1500, 190, 82, 138)

ON CONFLICT (code) DO NOTHING;
