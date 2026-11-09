class_name CardGridBrowser
extends VBoxContainer

const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const UniversalItemCardScript = preload("res://scripts/ui/universal_item_card.gd")

## Reusable Card Grid Browser Component for Godot 4 Client
## Provides Header, Search Bar, Filter Pills, Sort Options, Multi-select,
## Auto-select, and Bottom Action Bar for any Facility or Inventory UI.

signal item_selected(item: Dictionary)
signal item_deselected(item: Dictionary)
signal selection_changed(selected_items: Array)
signal action_confirmed(selected_items: Array)
signal quick_action_requested(action_code: String, selected_items: Array)

enum BrowserType { HERO, ITEM }

@export var browser_type: BrowserType = BrowserType.HERO
@export var grid_columns: int = 3
@export var card_selectable: bool = true
@export var multi_select_enabled: bool = true
@export var max_selection: int = 6

var all_items: Array = []
var filtered_items: Array = []
var selected_item_ids: Array = []

# Filter & Sort states
var current_search_query: String = ""
var current_filter_pill_idx: int = 0
var current_sort_mode: int = 0
var sort_ascending: bool = false
var filter_pills: Array = []

# Context for hero cards (int representing ContextMode enum)
var hero_context_mode: int = 0
var item_context_mode: int = 0

# UI Node References
var header_title_label: Label
var header_count_label: Label
var search_input: LineEdit
var filter_btn: Button
var pills_row: HBoxContainer
var grid_container: GridContainer
var empty_label: Label
var selection_count_label: Label
var action_badge_label: Label
var confirm_action_btn: Button
var extra_action_box: HBoxContainer
var _pill_buttons: Array[Button] = []
var _card_nodes: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

func _ready() -> void:
	_build_component_layout()

# ==============================================================================
# CONFIGURATION & INITIALIZATION API
# ==============================================================================

func configure_header(title: String, pills: Array = []) -> void:
	if header_title_label != null:
		header_title_label.text = title
	filter_pills.clear()
	for p in pills:
		filter_pills.append(str(p))
	_rebuild_filter_pills()

func set_items(items: Array, preserve_selection: bool = false) -> void:
	all_items = items
	if not preserve_selection:
		selected_item_ids.clear()
	apply_filter_and_sort()

func set_action_button(label_text: String, badge_prefix: String = "Hành động") -> void:
	if confirm_action_btn != null:
		confirm_action_btn.text = label_text
	_update_action_bar()

func add_extra_action_button(title: String, action_code: String, btn_color: Color = Color.WHITE) -> Button:
	var btn := Button.new()
	btn.text = title
	btn.custom_minimum_size = Vector2(0, 36)
	btn.modulate = btn_color
	btn.pressed.connect(func():
		var sel_items := get_selected_items()
		quick_action_requested.emit(action_code, sel_items)
	)
	if extra_action_box != null:
		extra_action_box.add_child(btn)
	return btn

func get_selected_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for it in all_items:
		if it is Dictionary:
			var iid := str(it.get("id", ""))
			if selected_item_ids.has(iid):
				result.append(it)
	return result

func clear_selection() -> void:
	selected_item_ids.clear()
	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

func select_item_by_id(item_id: String) -> void:
	if not selected_item_ids.has(item_id):
		if not multi_select_enabled:
			selected_item_ids.clear()
		selected_item_ids.append(item_id)
		_update_card_selection_visuals()
		_update_action_bar()
		selection_changed.emit(get_selected_items())

func select_items_by_ids(ids: Array) -> void:
	selected_item_ids.clear()
	for id in ids:
		var sid := str(id)
		if selected_item_ids.size() < max_selection and not selected_item_ids.has(sid):
			selected_item_ids.append(sid)
	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

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

	# Sort by lowest HP first, then highest rarity/level
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


# ==============================================================================
# COMPONENT LAYOUT BUILDER
# ==============================================================================

func _build_component_layout() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Top Header Row: Title & Total Count (e.g. 12 / 120 Hero)
	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(top_row)

	header_title_label = Label.new()
	header_title_label.text = "Chọn Hero"
	header_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title_label.add_theme_font_size_override("font_size", 16)
	header_title_label.add_theme_color_override("font_color", Color.WHITE)
	top_row.add_child(header_title_label)

	header_count_label = Label.new()
	header_count_label.text = "0 / 0 Hero"
	header_count_label.add_theme_font_size_override("font_size", 13)
	header_count_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	top_row.add_child(header_count_label)

	# 2. Search & Filter Bar
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	add_child(search_row)

	search_input = LineEdit.new()
	search_input.placeholder_text = "🔍 Tìm kiếm theo tên hoặc hệ phái..."
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 38)
	search_input.clear_button_enabled = true
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	s_style.border_width_left = 1
	s_style.border_width_top = 1
	s_style.border_width_right = 1
	s_style.border_width_bottom = 1
	s_style.border_color = Color(0.24, 0.32, 0.45)
	s_style.corner_radius_top_left = 6
	s_style.corner_radius_top_right = 6
	s_style.corner_radius_bottom_left = 6
	s_style.corner_radius_bottom_right = 6
	search_input.add_theme_stylebox_override("normal", s_style)
	search_input.text_changed.connect(_on_search_text_changed)
	search_row.add_child(search_input)

	filter_btn = Button.new()
	filter_btn.text = "Filter 🎚️"
	filter_btn.custom_minimum_size = Vector2(85, 38)
	filter_btn.pressed.connect(_on_sort_toggle_pressed)
	search_row.add_child(filter_btn)

	# 3. Filter Pills Row (e.g. [Cần hồi phục] [Đang hồi phục] [Đã khỏe])
	pills_row = HBoxContainer.new()
	pills_row.add_theme_constant_override("separation", 6)
	add_child(pills_row)
	_rebuild_filter_pills()

	# 4. Scroll Container with Hero/Item Cards Grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 2)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(margin)

	grid_container = GridContainer.new()
	grid_container.columns = grid_columns
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 10)
	grid_container.add_theme_constant_override("v_separation", 10)
	margin.add_child(grid_container)

	empty_label = Label.new()
	empty_label.text = "Không tìm thấy kết quả nào phù hợp."
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 14)
	empty_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.visible = false
	margin.add_child(empty_label)

	# 5. Bottom Action Bar (Selection Counter, Action Badges, Extra Actions, Confirm Button)
	var sep := HSeparator.new()
	add_child(sep)

	var bottom_info_row := HBoxContainer.new()
	bottom_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom_info_row)

	selection_count_label = Label.new()
	selection_count_label.text = "Đã chọn 0 Hero"
	selection_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_count_label.add_theme_font_size_override("font_size", 13)
	selection_count_label.add_theme_color_override("font_color", Color.WHITE)
	bottom_info_row.add_child(selection_count_label)

	action_badge_label = Label.new()
	action_badge_label.text = ""
	action_badge_label.add_theme_font_size_override("font_size", 13)
	action_badge_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	bottom_info_row.add_child(action_badge_label)

	extra_action_box = HBoxContainer.new()
	extra_action_box.add_theme_constant_override("separation", 6)
	add_child(extra_action_box)

	confirm_action_btn = Button.new()
	confirm_action_btn.text = "Xác nhận hành động"
	confirm_action_btn.custom_minimum_size = Vector2(0, 42)
	confirm_action_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_action_btn.disabled = true
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.12, 0.38, 0.22, 0.95)
	c_style.corner_radius_top_left = 6
	c_style.corner_radius_top_right = 6
	c_style.corner_radius_bottom_left = 6
	c_style.corner_radius_bottom_right = 6
	confirm_action_btn.add_theme_stylebox_override("normal", c_style)
	confirm_action_btn.pressed.connect(func():
		action_confirmed.emit(get_selected_items())
	)
	add_child(confirm_action_btn)

func _rebuild_filter_pills() -> void:
	if pills_row == null:
		return
	for c in pills_row.get_children():
		c.queue_free()
	_pill_buttons.clear()

	if filter_pills.is_empty():
		pills_row.visible = false
		return
	pills_row.visible = true

	for i in range(filter_pills.size()):
		var pill_text: String = str(filter_pills[i])
		var pbtn := Button.new()
		pbtn.text = pill_text
		pbtn.custom_minimum_size = Vector2(0, 30)
		var target_idx := i
		pbtn.pressed.connect(func():
			current_filter_pill_idx = target_idx
			_update_pill_styles()
			apply_filter_and_sort()
		)
		pills_row.add_child(pbtn)
		_pill_buttons.append(pbtn)

	_update_pill_styles()

func _update_pill_styles() -> void:
	for i in range(_pill_buttons.size()):
		var btn: Button = _pill_buttons[i]
		if i == current_filter_pill_idx:
			btn.modulate = Color(0.4, 1.0, 0.6)
		else:
			btn.modulate = Color(0.8, 0.85, 0.92)

# ==============================================================================
# FILTERING & SORTING LOGIC
# ==============================================================================

func apply_filter_and_sort() -> void:
	filtered_items.clear()
	var q := current_search_query.strip_edges().to_lower()

	for it in all_items:
		if not (it is Dictionary):
			continue
		var iname := str(it.get("name", it.get("targetName", ""))).to_lower()
		var iclass := str(it.get("classCode", it.get("heroClass", it.get("slot", "")))).to_lower()

		if q != "" and not (q in iname or q in iclass):
			continue

		if not _passes_pill_filter(it):
			continue

		filtered_items.append(it)

	_sort_filtered_items()
	_render_cards()
	_update_action_bar()

func _passes_pill_filter(it: Dictionary) -> bool:
	if filter_pills.is_empty() or current_filter_pill_idx == 0:
		return true

	var pill_text: String = str(filter_pills[current_filter_pill_idx]).to_lower()

	# Specialized logic for Recovery Center filters
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

	# General item/gear filters
	if "vũ khí" in pill_text or "weapon" in pill_text:
		var slot: String = str(it.get("slot", it.get("itemType", ""))).to_upper()
		return slot in ["WEAPON", "MAIN_HAND", "OFF_HAND", "SWORD", "BOW", "STAFF", "DAGGER"]
	elif "giáp" in pill_text or "armor" in pill_text:
		var slot: String = str(it.get("slot", it.get("itemType", ""))).to_upper()
		return slot in ["ARMOR", "HELMET", "CHEST", "PANTS", "BOOTS", "BELT", "SHIELD"]
	elif "trang sức" in pill_text or "jewelry" in pill_text:
		var slot: String = str(it.get("slot", it.get("itemType", ""))).to_upper()
		return slot in ["RING", "AMULET", "NECKLACE", "EARRING"]
	elif "chưa trang bị" in pill_text or "lưu kho" in pill_text or "chưa mặc" in pill_text:
		return str(it.get("equippedHeroId", "")).is_empty()
	elif "đang mặc" in pill_text or "đã mặc" in pill_text or "trên hero" in pill_text:
		return not str(it.get("equippedHeroId", "")).is_empty()

	return true

func _sort_filtered_items() -> void:
	filtered_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
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
	)

func _render_cards() -> void:
	if grid_container == null:
		return
	for c in grid_container.get_children():
		c.queue_free()
	_card_nodes.clear()

	header_count_label.text = "%d / %d %s" % [
		filtered_items.size(),
		all_items.size(),
		"Hero" if browser_type == BrowserType.HERO else "Món"
	]

	if filtered_items.is_empty():
		empty_label.visible = true
		return
	empty_label.visible = false

	for it in filtered_items:
		var iid := str(it.get("id", ""))
		var is_sel := selected_item_ids.has(iid)

		if browser_type == BrowserType.HERO:
			var hcard = UniversalHeroCardScript.new()
			hcard.setup(it, hero_context_mode, card_selectable)
			hcard.set_selected(is_sel)
			hcard.selection_toggled.connect(_on_card_selection_toggled)
			hcard.card_clicked.connect(func(data): item_selected.emit(data))
			grid_container.add_child(hcard)
			_card_nodes[iid] = hcard
		else:
			var icard = UniversalItemCardScript.new()
			icard.setup(it, item_context_mode, card_selectable)
			icard.set_selected(is_sel)
			icard.selection_toggled.connect(_on_card_selection_toggled)
			icard.item_clicked.connect(func(data): item_selected.emit(data))
			grid_container.add_child(icard)
			_card_nodes[iid] = icard

func _update_card_selection_visuals() -> void:
	for iid in _card_nodes.keys():
		var node = _card_nodes[iid]
		if is_instance_valid(node) and node.has_method("set_selected"):
			node.set_selected(selected_item_ids.has(iid))

func _update_action_bar() -> void:
	var count := selected_item_ids.size()
	if selection_count_label != null:
		selection_count_label.text = "Đã chọn %d %s" % [count, "Hero" if browser_type == BrowserType.HERO else "Món"]

	if confirm_action_btn != null:
		confirm_action_btn.disabled = count == 0
		if count > 0:
			confirm_action_btn.modulate = Color(0.4, 1.0, 0.6)
		else:
			confirm_action_btn.modulate = Color(0.8, 0.8, 0.8)

	if action_badge_label != null:
		if count > 0:
			action_badge_label.text = "Thực hiện x%d" % count
			action_badge_label.visible = true
		else:
			action_badge_label.visible = false

func _on_card_selection_toggled(data: Dictionary, is_sel: bool) -> void:
	var iid := str(data.get("id", ""))
	if is_sel:
		if not multi_select_enabled:
			selected_item_ids.clear()
		if selected_item_ids.size() < max_selection:
			if not selected_item_ids.has(iid):
				selected_item_ids.append(iid)
		else:
			# Revert selection if cap exceeded
			if _card_nodes.has(iid):
				_card_nodes[iid].set_selected(false)
			return
	else:
		selected_item_ids.erase(iid)

	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

func _on_search_text_changed(new_text: String) -> void:
	current_search_query = new_text
	apply_filter_and_sort()

func _on_sort_toggle_pressed() -> void:
	current_sort_mode = (current_sort_mode + 1) % 4
	var sort_names := ["Lực Chiến", "Độ Hiếm ★", "Cấp Độ Lv", "Tên A-Z"]
	if hero_context_mode == 1: # RECOVERY
		sort_names[0] = "HP Thấp Nhất"
	filter_btn.text = "%s 🎚️" % sort_names[current_sort_mode]
	apply_filter_and_sort()
