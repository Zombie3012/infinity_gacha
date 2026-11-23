class_name ItemGridBrowser
extends "res://scripts/ui/base_card_browser.gd"

## Specialized Item Grid Browser Component for Godot 4 Client
## Handles UniversalItemCard rendering, auto-fit grid columns (92x92),
## item search (name/code/slot/description), item sorting, and category/gear filtering.

const UniversalItemCardScript = preload("res://scripts/ui/universal_item_card.gd")

var item_context_mode: int = 0

func _init() -> void:
	super._init()
	show_action_bar = false
	card_selectable = false

func _get_default_placeholder() -> String:
	return "🔍 Tìm kiếm vật phẩm theo tên, loại hoặc mô tả..."

func _get_count_unit() -> String:
	return "Món"

func _get_sort_labels() -> PackedStringArray:
	return PackedStringArray(["Độ Hiếm ★", "Số Lượng", "Tên A-Z", "Cường Hóa +"])

func _matches_search(it: Dictionary, query: String) -> bool:
	var iname := str(it.get("name", it.get("targetName", ""))).to_lower()
	var icode := str(it.get("itemId", it.get("code", ""))).to_lower()
	var islot := str(it.get("slot", it.get("itemType", ""))).to_lower()
	var idesc := str(it.get("description", "")).to_lower()
	return query in iname or query in icode or query in islot or query in idesc

func _passes_pill_filter_text(it: Dictionary, pill_text: String) -> bool:
	var item_cat := str(it.get("_warehouse_cat", it.get("category", ""))).to_upper()
	var item_code := str(it.get("itemId", it.get("code", it.get("id", "")))).to_upper()
	var item_name_l := str(it.get("name", "")).to_lower()
	var slot: String = str(it.get("slot", it.get("itemType", ""))).to_upper()

	# Warehouse top-level category pills
	if pill_text == "trang bị":
		return item_cat == "EQUIPMENT" or (slot in ["WEAPON", "MAIN_HAND", "OFF_HAND", "SWORD", "BOW", "STAFF", "DAGGER", "ARMOR", "HELMET", "CHEST", "PANTS", "BOOTS", "BELT", "SHIELD", "RING", "AMULET", "NECKLACE", "EARRING"])
	elif pill_text == "tiêu hao":
		return item_cat == "CONSUMABLE"
	elif pill_text == "nguyên liệu":
		return item_cat == "MATERIAL"
	elif pill_text == "phát triển":
		return item_cat == "DEVELOPMENT"
	elif "lương thực & vé" in pill_text:
		return item_cat == "MISC" or item_cat == "TICKET"

	# Equipment & Forge filters
	if "chưa đạt +15" in pill_text:
		return int(it.get("enhanceLevel", 0)) < 15
	elif "đạt +15" in pill_text:
		return int(it.get("enhanceLevel", 0)) >= 15
	elif "vũ khí" in pill_text or "weapon" in pill_text:
		return slot in ["WEAPON", "MAIN_HAND", "OFF_HAND", "SWORD", "BOW", "STAFF", "DAGGER"]
	elif "giáp" in pill_text or "armor" in pill_text:
		return slot in ["ARMOR", "HELMET", "CHEST", "PANTS", "BOOTS", "BELT", "SHIELD"]
	elif "trang sức" in pill_text or "jewelry" in pill_text:
		return slot in ["RING", "AMULET", "NECKLACE", "EARRING"]
	elif "chưa trang bị" in pill_text or "lưu kho" in pill_text or "chưa mặc" in pill_text:
		return str(it.get("equippedHeroId", "")).is_empty()
	elif "đang mặc" in pill_text or "đã mặc" in pill_text or "trên hero" in pill_text:
		return not str(it.get("equippedHeroId", "")).is_empty()

	# Warehouse per-category filters
	elif "thuốc hồi phục" in pill_text:
		return "POTION" in item_code or "HEAL" in item_code or "RESURRECTION" in item_code or "REVIVE" in item_code or "STAMINA" in item_code or "thuốc" in item_name_l or "hồi" in item_name_l
	elif "dược phẩm" in pill_text or "hỗ trợ" in pill_text:
		return not ("POTION" in item_code or "HEAL" in item_code or "RESURRECTION" in item_code or "REVIVE" in item_code or "STAMINA" in item_code or "thuốc" in item_name_l or "hồi" in item_name_l)
	elif "gỗ & đá & sắt" in pill_text or "tài nguyên thô" in pill_text:
		return item_code in ["WOOD", "STONE", "IRON", "IRON_ORE", "ORE", "COPPER", "SILVER_ORE"] or "gỗ" in item_name_l or "đá" == item_name_l or "quặng" in item_name_l
	elif "nguyên liệu chế tạo" in pill_text:
		return not (item_code in ["WOOD", "STONE", "IRON", "IRON_ORE", "ORE", "COPPER", "SILVER_ORE"] or "gỗ" in item_name_l or "quặng" in item_name_l)
	elif "sách exp" in pill_text:
		return "EXP" in item_code or "exp" in item_name_l
	elif "đột phá & thức tỉnh" in pill_text:
		return not ("EXP" in item_code or "exp" in item_name_l)
	elif "lương thực" in pill_text:
		return item_code in ["FOOD", "RATION", "FOOD_RAW", "RAW_FOOD"] or "lương thực" in item_name_l or "thịt" in item_name_l
	elif "thiên thư & vé" in pill_text:
		return item_cat == "TICKET" or "SCROLL" in item_code or "SUMMON" in item_code or "thiên thư" in item_name_l or "vé" in item_name_l

	return true

func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	match current_sort_mode:
		0: # Rarity / Stars
			var star_a := int(a.get("starLevel", a.get("rarity", 1)))
			var star_b := int(b.get("starLevel", b.get("rarity", 1)))
			if star_a != star_b:
				return star_a > star_b if not sort_ascending else star_a < star_b
		1: # Quantity
			var qty_a := int(a.get("quantity", 1))
			var qty_b := int(b.get("quantity", 1))
			if qty_a != qty_b:
				return qty_a > qty_b if not sort_ascending else qty_a < qty_b
		2: # Name A-Z
			var name_cmp := str(a.get("name", a.get("targetName", ""))).nocasecmp_to(str(b.get("name", b.get("targetName", ""))))
			if name_cmp != 0:
				return name_cmp < 0 if not sort_ascending else name_cmp > 0
		3: # Enhance level
			var enh_a := int(a.get("enhanceLevel", 0))
			var enh_b := int(b.get("enhanceLevel", 0))
			if enh_a != enh_b:
				return enh_a > enh_b if not sort_ascending else enh_a < enh_b
	return str(a.get("id", "")) < str(b.get("id", ""))

func _update_responsive_columns(scroll_node: ScrollContainer) -> void:
	if grid_container == null or scroll_node == null:
		return
	var avail := scroll_node.size.x - 24.0
	if avail > 90.0:
		grid_container.columns = maxi(1, int((avail + 10.0) / 102.0))
	else:
		grid_container.columns = grid_columns

func _create_card_node(it: Dictionary, is_sel: bool) -> Control:
	var icard = UniversalItemCardScript.new()
	icard.setup(it, item_context_mode, card_selectable)
	icard.set_selected(is_sel)
	icard.selection_toggled.connect(_on_card_selection_toggled)
	icard.item_clicked.connect(func(data): item_selected.emit(data))
	icard.item_action_requested.connect(func(code: String, data: Dictionary, qty: int):
		item_action_requested.emit(code, data, qty)
	)
	return icard
