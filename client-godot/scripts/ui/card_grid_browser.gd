class_name CardGridBrowser
extends "res://scripts/ui/base_card_browser.gd"

## Specialized Hero Grid Browser Component for Godot 4 Client
## Inherits BaseCardBrowser and keeps full backwards-compatible API for Hero modals.

const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const UniversalItemCardScript = preload("res://scripts/ui/universal_item_card.gd")

enum BrowserType { HERO, ITEM }

@export var browser_type: BrowserType = BrowserType.HERO

var hero_context_mode: int = 0
var item_context_mode: int = 0

func _get_default_placeholder() -> String:
	return "🔍 Tìm kiếm Hero theo tên hoặc hệ phái..."

func _get_count_unit() -> String:
	return "Hero" if browser_type == BrowserType.HERO else "Món"

func _get_sort_labels() -> PackedStringArray:
	if hero_context_mode == 1: # RECOVERY
		return PackedStringArray(["HP Thấp Nhất", "Độ Hiếm ★", "Cấp Độ Lv", "Tên A-Z"])
	return PackedStringArray(["Lực Chiến", "Độ Hiếm ★", "Cấp Độ Lv", "Tên A-Z"])

func _matches_search(it: Dictionary, query: String) -> bool:
	var iname := str(it.get("name", it.get("targetName", ""))).to_lower()
	var iclass := str(it.get("classCode", it.get("heroClass", it.get("slot", "")))).to_lower()
	return query in iname or query in iclass

func _passes_pill_filter_text(it: Dictionary, pill_text: String) -> bool:
	# Recovery Center filters
	if "cần hồi phục" in pill_text:
		var cur_hp := float(it.get("hp", 100))
		var max_hp := maxf(1.0, float(it.get("maxHp", 100)))
		var is_injured := str(it.get("state", "")) == "INJURED"
		return (cur_hp / max_hp) < 0.999 or is_injured
	elif "đang hồi phục" in pill_text or "đang chữa" in pill_text:
		return bool(it.get("isTreating", false)) or bool(it.get("isQueued", false))
	elif "đã khỏe" in pill_text:
		var cur_hp := float(it.get("hp", 100))
		var max_hp := maxf(1.0, float(it.get("maxHp", 100)))
		return (cur_hp / max_hp) >= 0.999 and str(it.get("state", "")) != "INJURED"

	# Dormitory / Resting filters
	if "đang nghỉ" in pill_text:
		if it.has("_dorm_is_resting_here"):
			return bool(it.get("_dorm_is_resting_here", false))
		return bool(it.get("isResting", false)) or str(it.get("state", "")) == "RESTING"
	elif "mệt nặng" in pill_text:
		return float(it.get("fatigue", it.get("fatigueScore", 0))) > 50.0
	elif "khỏe mạnh" in pill_text:
		return float(it.get("fatigue", it.get("fatigueScore", 0))) < 10.0

	# Survival / Kitchen filters
	if "đang đói" in pill_text:
		var hun := float(it.get("hunger", it.get("hungerScore", 0)))
		return hun >= 40.0
	elif "đói lả" in pill_text or "đói nặng" in pill_text or "cần ăn" in pill_text:
		var hun := float(it.get("hunger", it.get("hungerScore", 0)))
		return hun >= 60.0
	elif "no nê" in pill_text:
		var hun := float(it.get("hunger", it.get("hungerScore", 0)))
		return hun < 40.0

	# Floor Manager & Roster filters
	if "đội" in pill_text or "party" in pill_text:
		return GameState.active_party_ids.has(str(it.get("id", "")))
	elif "phân công" in pill_text or "làm việc" in pill_text:
		var wmap: Dictionary = GameState.get_worker_assignment_map()
		return wmap.has(str(it.get("id", "")))
	elif "chưa xếp" in pill_text or "tự do" in pill_text:
		var hid := str(it.get("id", ""))
		var wmap: Dictionary = GameState.get_worker_assignment_map()
		return not GameState.active_party_ids.has(hid) and not wmap.has(hid)

	return true

func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	var prio_a := bool(a.get("_worker_priority", false))
	var prio_b := bool(b.get("_worker_priority", false))
	if prio_a != prio_b:
		return prio_a

	if browser_type == BrowserType.HERO:
		match current_sort_mode:
			0: # Mode 0: If Recovery Center, HP%. Otherwise Combat Power (CP)
				if hero_context_mode == 1: # RECOVERY
					var hp_a: float = float(a.get("hp", 100)) / maxf(1.0, float(a.get("maxHp", 100)))
					var hp_b: float = float(b.get("hp", 100)) / maxf(1.0, float(b.get("maxHp", 100)))
					if hp_a != hp_b:
						return hp_a < hp_b if not sort_ascending else hp_a > hp_b
				else:
					var cp_a := int(a.get("combatPower", 0))
					var cp_b := int(b.get("combatPower", 0))
					if cp_a != cp_b:
						return cp_a > cp_b if not sort_ascending else cp_a < cp_b
			1: # Stars / Rarity
				var s_a := int(a.get("rarity", 1))
				var s_b := int(b.get("rarity", 1))
				if s_a != s_b:
					return s_a > s_b if not sort_ascending else s_a < s_b
			2: # Level
				var l_a := int(a.get("level", 1))
				var l_b := int(b.get("level", 1))
				if l_a != l_b:
					return l_a > l_b if not sort_ascending else l_a < l_b
			3: # Name A-Z
				return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	else:
		var star_a := int(a.get("starLevel", a.get("rarity", 1)))
		var star_b := int(b.get("starLevel", b.get("rarity", 1)))
		if star_a != star_b:
			return star_a > star_b if not sort_ascending else star_a < star_b

	return str(a.get("id", "")) < str(b.get("id", ""))

func _create_card_node(it: Dictionary, is_sel: bool) -> Control:
	if browser_type == BrowserType.HERO:
		var hcard = UniversalHeroCardScript.new()
		hcard.setup(it, hero_context_mode, card_selectable)
		hcard.set_selected(is_sel)
		hcard.selection_toggled.connect(_on_card_selection_toggled)
		hcard.card_clicked.connect(func(data): item_selected.emit(data))
		return hcard

	var icard = UniversalItemCardScript.new()
	icard.setup(it, item_context_mode, card_selectable)
	icard.set_selected(is_sel)
	icard.selection_toggled.connect(_on_card_selection_toggled)
	icard.item_clicked.connect(func(data): item_selected.emit(data))
	icard.item_action_requested.connect(func(code: String, data: Dictionary, qty: int):
		item_action_requested.emit(code, data, qty)
	)
	return icard

func auto_select_recovery_candidates(max_count: int) -> int:
	var eligible: Array[Dictionary] = []
	for it in all_items:
		if not (it is Dictionary):
			continue
		var is_treating := bool(it.get("isTreating", false))
		var is_queued := bool(it.get("isQueued", false))
		if is_treating or is_queued:
			continue
		var cur_hp := float(it.get("hp", 100))
		var max_hp := maxf(1.0, float(it.get("maxHp", 100)))
		var is_injured := str(it.get("state", "")) == "INJURED"
		if (cur_hp / max_hp) < 0.999 or is_injured:
			eligible.append(it)

	eligible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var hp_a: float = float(a.get("hp", 100)) / maxf(1.0, float(a.get("maxHp", 100)))
		var hp_b: float = float(b.get("hp", 100)) / maxf(1.0, float(b.get("maxHp", 100)))
		if absf(hp_a - hp_b) > 0.001:
			return hp_a < hp_b
		var r_a := int(a.get("rarity", 1))
		var r_b := int(b.get("rarity", 1))
		if r_a != r_b:
			return r_a > r_b
		return int(a.get("level", 1)) > int(b.get("level", 1))
	)

	var to_select: Array = []
	var limit := mini(max_count, max_selection)
	for i in range(mini(limit, eligible.size())):
		to_select.append(str(eligible[i].get("id", "")))

	select_items_by_ids(to_select)
	return to_select.size()
