class_name GameConstants

## Constants and Enums mapped directly from @infiniti-gacha/shared

enum HeroClass {
	UNCLASSIFIED,
	WARRIOR,
	THIEF,
	SPEARMAN,
	ARCHER,
	MAGE
}

enum StarRating {
	STAR_1 = 1,
	STAR_2 = 2,
	STAR_3 = 3,
	STAR_4 = 4,
	STAR_5 = 5,
	STAR_6 = 6,
	STAR_7 = 7
}

enum EquipmentSlot {
	MAIN_HAND,
	OFF_HAND,
	CHEST,
	HELMET,
	BOOTS,
	ACCESSORY
}

enum BannerType {
	STANDARD,
	SPECIAL,
	LIMITED,
	MAGE_SPECIAL
}

static func star_max_level(star: int) -> int:
	return star * 10

static func required_fodder_count(star: int) -> int:
	return star

static func star_promotion_cost(star: int) -> int:
	match star:
		1: return 10000
		2: return 25000
		3: return 50000
		4: return 100000
		_: return 200000
