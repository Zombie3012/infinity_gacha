class_name ForgeModal
extends Control

## Dedicated Clash-of-Clans style Forge & Smithy Modal
## Supports 3 tabs:
##   Tab 0: 🔨 Chế tạo trang bị (Crafting with Blueprint Recipes)
##   Tab 1: ✨ Cường hóa (+15) (Equipment Enhancement with Stones)
##   Tab 2: 🌟 Ghép thăng sao (Star Fusion using duplicate gear)

signal closed
signal craft_requested(recipe_code: String, target_name: String)
signal enhance_requested(item_id: String, item_name: String)
signal fuse_requested(template_code: String, star_level: int, item_name: String)

const UniversalItemCardScript = preload("res://scripts/ui/universal_item_card.gd")
const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")

var building_data: Dictionary = {}
var building_level: int = 1
var building_status: String = "READY"
var current_tab: int = 0

# UI Components
var _title_label: Label
var _status_pill: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_tween: Tween = null
var _mat_labels: Dictionary = {}
var _tab_buttons: Array[Button] = []
var _tab_containers: Array[Control] = []

# Tab 0: Crafting
var _craft_vbox: VBoxContainer
var _craft_search: LineEdit
var _craft_pills: HBoxContainer
var _craft_recipes_scroll: ScrollContainer
var _craft_recipes_container: VBoxContainer
var _craft_pill_idx: int = 0
var _craft_search_query: String = ""

# Tab 1: Enhancement
var _enh_browser: CardGridBrowser
var _selected_enh_item: Dictionary = {}
var _enh_detail_box: PanelContainer
var _enh_preview_label: Label
var _enh_rate_label: Label
var _enh_cost_label: Label
var _enh_confirm_btn: Button

# Tab 2: Star Fusion
var _fuse_scroll: ScrollContainer
var _fuse_container: VBoxContainer
var _fuse_pills: HBoxContainer
var _fuse_pill_idx: int = 0
var _is_ui_built: bool = false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	if not _is_ui_built:
		_build_ui()
	refresh_all()

func setup(b_data: Dictionary) -> void:
	building_data = b_data
	building_level = int(b_data.get("level", 1))
	building_status = str(b_data.get("status", "READY"))
	if not _is_ui_built:
		_build_ui()
	refresh_all()

func refresh_all() -> void:
	if not _is_ui_built:
		return
	_refresh_header_and_materials()
	match current_tab:
		0: _render_craft_tab()
		1: _render_enhance_tab()
		2: _render_fuse_tab()

func _build_ui() -> void:
	if _is_ui_built:
		return
	_is_ui_built = true
	# 1. Dark Backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.04, 0.07, 0.88)
	bg.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			_on_close_pressed()
	)
	add_child(bg)

	# 2. Main Centered Window
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var win := PanelContainer.new()
	win.custom_minimum_size = Vector2(1040, 680)
	var win_style := StyleBoxFlat.new()
	win_style.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	win_style.border_width_left = 2
	win_style.border_width_top = 2
	win_style.border_width_right = 2
	win_style.border_width_bottom = 2
	win_style.border_color = Color(1.0, 0.65, 0.35, 0.8)
	win_style.corner_radius_top_left = 12
	win_style.corner_radius_top_right = 12
	win_style.corner_radius_bottom_left = 12
	win_style.corner_radius_bottom_right = 12
	win_style.shadow_size = 18
	win_style.shadow_color = Color(0, 0, 0, 0.65)
	win.add_theme_stylebox_override("panel", win_style)
	center.add_child(win)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	win.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# Top Header Row: Icon + Title + Status + Close [✕]
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	_title_label = Label.new()
	_title_label.text = "⚒️ XƯỞNG RÈN TRANG BỊ (FORGE Lv.%d/3)" % building_level
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	header_row.add_child(_title_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(header_spacer)

	_status_pill = Label.new()
	_status_pill.text = "SẴN SÀNG"
	_status_pill.add_theme_font_size_override("font_size", 12)
	_status_pill.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	header_row.add_child(_status_pill)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_on_close_pressed)
	header_row.add_child(close_btn)

	# Toast Notification Banner
	_toast_panel = PanelContainer.new()
	_toast_panel.visible = false
	var tp_style := StyleBoxFlat.new()
	tp_style.bg_color = Color(0.10, 0.38, 0.20, 0.95)
	tp_style.border_width_left = 1
	tp_style.border_width_top = 1
	tp_style.border_width_right = 1
	tp_style.border_width_bottom = 1
	tp_style.border_color = Color(0.35, 1.0, 0.55)
	tp_style.corner_radius_top_left = 6
	tp_style.corner_radius_top_right = 6
	tp_style.corner_radius_bottom_left = 6
	tp_style.corner_radius_bottom_right = 6
	_toast_panel.add_theme_stylebox_override("panel", tp_style)
	root_vbox.add_child(_toast_panel)

	var t_m := MarginContainer.new()
	t_m.add_theme_constant_override("margin_left", 12)
	t_m.add_theme_constant_override("margin_right", 12)
	t_m.add_theme_constant_override("margin_top", 6)
	t_m.add_theme_constant_override("margin_bottom", 6)
	_toast_panel.add_child(t_m)

	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_font_size_override("font_size", 13)
	_toast_label.add_theme_color_override("font_color", Color.WHITE)
	t_m.add_child(_toast_label)

	# Materials Dashboard Bar
	var mat_panel := PanelContainer.new()
	var mp_style := StyleBoxFlat.new()
	mp_style.bg_color = Color(0.045, 0.06, 0.09, 0.95)
	mp_style.border_width_bottom = 1
	mp_style.border_color = Color(0.3, 0.38, 0.5, 0.4)
	mp_style.corner_radius_top_left = 6
	mp_style.corner_radius_top_right = 6
	mp_style.corner_radius_bottom_left = 6
	mp_style.corner_radius_bottom_right = 6
	mat_panel.add_theme_stylebox_override("panel", mp_style)
	root_vbox.add_child(mat_panel)

	var mat_m := MarginContainer.new()
	mat_m.add_theme_constant_override("margin_left", 12)
	mat_m.add_theme_constant_override("margin_right", 12)
	mat_m.add_theme_constant_override("margin_top", 6)
	mat_m.add_theme_constant_override("margin_bottom", 6)
	mat_panel.add_child(mat_m)

	var mat_row := HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 18)
	mat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mat_m.add_child(mat_row)

	var mat_types := [
		{"key": "IRON", "icon": "⛓️", "name": "Sắt", "col": Color(0.85, 0.88, 0.95)},
		{"key": "WOOD", "icon": "🪵", "name": "Gỗ", "col": Color(0.88, 0.72, 0.50)},
		{"key": "STONE", "icon": "🪨", "name": "Đá", "col": Color(0.75, 0.80, 0.85)},
		{"key": "ENHANCEMENT_STONE", "icon": "💎", "name": "Đá Cường Hóa", "col": Color(0.45, 0.92, 1.0)},
		{"key": "SILVER", "icon": "🪙", "name": "Bạc", "col": Color(1.0, 0.85, 0.35)}
	]
	for m in mat_types:
		var lbl := Label.new()
		lbl.text = "%s %s: 0" % [m["icon"], m["name"]]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", m["col"])
		mat_row.add_child(lbl)
		_mat_labels[m["key"]] = lbl

	# Tab Bar
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	root_vbox.add_child(tab_bar)

	var tab_defs := [
		{"label": "🔨 Rèn Trang Bị", "icon": "🔨"},
		{"label": "✨ Cường Hóa (+15)", "icon": "✨"},
		{"label": "🌟 Ghép Thăng Sao", "icon": "🌟"}
	]
	for i in range(tab_defs.size()):
		var t_btn := Button.new()
		t_btn.text = tab_defs[i]["label"]
		t_btn.custom_minimum_size = Vector2(170, 38)
		t_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		t_btn.pressed.connect(func(): _switch_tab(idx))
		tab_bar.add_child(t_btn)
		_tab_buttons.append(t_btn)

	var tab_spacer := Control.new()
	tab_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_bar.add_child(tab_spacer)

	# Content Area: Containers for 3 tabs
	var content_deck := Control.new()
	content_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_deck.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(content_deck)

	_build_craft_tab_ui(content_deck)
	_build_enhance_tab_ui(content_deck)
	_build_fuse_tab_ui(content_deck)

	_switch_tab(0)

func _switch_tab(tab_idx: int) -> void:
	current_tab = clampi(tab_idx, 0, 2)
	for i in range(_tab_buttons.size()):
		var is_act := (i == current_tab)
		_tab_buttons[i].modulate = Color(1.0, 0.85, 0.4) if is_act else Color(0.7, 0.75, 0.85)
		_tab_containers[i].visible = is_act

	refresh_all()

func _refresh_header_and_materials() -> void:
	if _title_label != null:
		_title_label.text = "⚒️ XƯỞNG RÈN TRANG BỊ (FORGE Lv.%d/3)" % building_level
	if _status_pill != null:
		_status_pill.text = "• Trạng thái: %s" % ("SẴN SÀNG" if building_status == "READY" else building_status)
		_status_pill.modulate = Color(0.4, 1.0, 0.6) if building_status == "READY" else Color(1.0, 0.75, 0.3)

	if _mat_labels.has("IRON"):
		_mat_labels["IRON"].text = "⛓️ Sắt: %s" % _format_num(int(GameState.materials.get("IRON", 0)))
	if _mat_labels.has("WOOD"):
		_mat_labels["WOOD"].text = "🪵 Gỗ: %s" % _format_num(int(GameState.materials.get("WOOD", 0)))
	if _mat_labels.has("STONE"):
		_mat_labels["STONE"].text = "🪨 Đá: %s" % _format_num(int(GameState.materials.get("STONE", 0)))
	if _mat_labels.has("ENHANCEMENT_STONE"):
		_mat_labels["ENHANCEMENT_STONE"].text = "💎 Đá Cường Hóa: %s" % _format_num(int(GameState.materials.get("ENHANCEMENT_STONE", 0)))
	if _mat_labels.has("SILVER"):
		_mat_labels["SILVER"].text = "🪙 Bạc: %s" % _format_num(GameState.silver_coins)

# ==============================================================================
# TAB 0: CRAFTING (CHẾ TẠO TRANG BỊ)
# ==============================================================================

func _build_craft_tab_ui(deck: Control) -> void:
	_craft_vbox = VBoxContainer.new()
	_craft_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_craft_vbox.add_theme_constant_override("separation", 8)
	deck.add_child(_craft_vbox)
	_tab_containers.append(_craft_vbox)

	# Search & Filter Row
	var top_filter_row := HBoxContainer.new()
	top_filter_row.add_theme_constant_override("separation", 10)
	_craft_vbox.add_child(top_filter_row)

	_craft_search = LineEdit.new()
	_craft_search.placeholder_text = "🔍 Tìm bản vẽ rèn theo tên..."
	_craft_search.custom_minimum_size = Vector2(240, 34)
	_craft_search.text_changed.connect(func(new_text):
		_craft_search_query = new_text.strip_edges().to_lower()
		_render_craft_tab()
	)
	top_filter_row.add_child(_craft_search)

	_craft_pills = HBoxContainer.new()
	_craft_pills.add_theme_constant_override("separation", 6)
	top_filter_row.add_child(_craft_pills)

	var pills := ["Tất cả", "Vũ khí", "Áo giáp", "Trang sức", "Đủ nguyên liệu"]
	for i in range(pills.size()):
		var p_btn := Button.new()
		p_btn.text = pills[i]
		p_btn.custom_minimum_size = Vector2(0, 32)
		p_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		p_btn.pressed.connect(func():
			_craft_pill_idx = idx
			_update_craft_pills()
			_render_craft_tab()
		)
		_craft_pills.add_child(p_btn)
	_update_craft_pills()

	# Scrollable Recipes List
	_craft_recipes_scroll = ScrollContainer.new()
	_craft_recipes_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_recipes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_craft_vbox.add_child(_craft_recipes_scroll)

	_craft_recipes_container = VBoxContainer.new()
	_craft_recipes_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_recipes_container.add_theme_constant_override("separation", 8)
	_craft_recipes_scroll.add_child(_craft_recipes_container)

func _update_craft_pills() -> void:
	for i in range(_craft_pills.get_child_count()):
		var btn = _craft_pills.get_child(i) as Button
		if btn != null:
			var is_sel := (i == _craft_pill_idx)
			btn.modulate = Color(1.0, 0.85, 0.35) if is_sel else Color(0.7, 0.75, 0.85)

func _render_craft_tab() -> void:
	if _craft_recipes_container == null:
		return
	for c in _craft_recipes_container.get_children():
		c.queue_free()

	var recipes: Array = GameState.crafting_overview.get("recipes", [])
	if recipes.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "ℹ️ Đang tải hoặc chưa có Bản vẽ rèn khả dụng."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		_craft_recipes_container.add_child(empty_lbl)
		return

	var rendered_count: int = 0
	for rec in recipes:
		if not (rec is Dictionary):
			continue
		var rcode := str(rec.get("code", ""))
		var rname := str(rec.get("targetName", rcode))
		var rslot := str(rec.get("slot", "WEAPON")).to_upper()
		var rfee := int(rec.get("craftFeeSilver", 500))
		var req_b_lvl := int(rec.get("requiredForgeLevel", 1))
		var mats: Array = rec.get("materials", [])
		var val: Dictionary = rec.get("validation", {})
		var ok_craft := bool(val.get("ok", false))
		var reason := str(val.get("reason", ""))

		# Filter search
		if _craft_search_query != "" and not (_craft_search_query in rname.to_lower() or _craft_search_query in rslot.to_lower()):
			continue

		# Filter pills
		match _craft_pill_idx:
			1: # Vũ khí
				if not (rslot in ["WEAPON", "SWORD", "BOW", "STAFF", "DAGGER"]): continue
			2: # Áo giáp
				if not (rslot in ["ARMOR", "HELMET", "CHEST", "PANTS", "BOOTS", "SHIELD"]): continue
			3: # Trang sức
				if not (rslot in ["RING", "AMULET", "NECKLACE"]): continue
			4: # Đủ nguyên liệu
				if not ok_craft: continue

		rendered_count += 1
		var card := _create_recipe_row(rec, rcode, rname, rslot, req_b_lvl, mats, rfee, ok_craft, reason)
		_craft_recipes_container.add_child(card)

	if rendered_count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Không tìm thấy Bản vẽ rèn nào phù hợp với bộ lọc."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
		_craft_recipes_container.add_child(empty_lbl)

func show_toast(msg: String, is_success: bool = true) -> void:
	if _toast_panel == null or _toast_label == null:
		return
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	_toast_label.text = msg
	var tp_style = _toast_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if tp_style != null:
		if is_success:
			tp_style.bg_color = Color(0.10, 0.38, 0.20, 0.95)
			tp_style.border_color = Color(0.35, 1.0, 0.55)
		else:
			tp_style.bg_color = Color(0.45, 0.15, 0.15, 0.95)
			tp_style.border_color = Color(1.0, 0.45, 0.45)

	_toast_panel.visible = true
	_toast_panel.modulate.a = 0.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(3.0)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func(): _toast_panel.visible = false)

func _format_craft_reason(reason: String, req_lvl: int) -> String:
	match reason:
		"ERR_CRAFT_FORGE_LEVEL":
			return "Yêu cầu cấp độ Lò Rèn đạt Cấp %d mới có thể chế tạo!" % req_lvl
		"ERR_INSUFFICIENT_MATERIALS":
			return "Chưa đủ số lượng nguyên liệu chế tạo!"
		"ERR_INSUFFICIENT_SILVER":
			return "Không đủ Bạc để trả phí rèn!"
		"ERR_FORGE_BUSY", "BUSY":
			return "Lò Rèn đang trong trạng thái bận hoặc nâng cấp!"
		_:
			return reason

func _create_recipe_row(_rec: Dictionary, rcode: String, rname: String, rslot: String, req_lvl: int, mats: Array, fee: int, ok_craft: bool, reason: String) -> PanelContainer:
	var row := PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	r_style.border_width_left = 1
	r_style.border_width_top = 1
	r_style.border_width_right = 1
	r_style.border_width_bottom = 1
	r_style.border_color = Color(0.25, 0.35, 0.45, 0.7) if ok_craft else Color(0.4, 0.2, 0.2, 0.6)
	r_style.corner_radius_top_left = 8
	r_style.corner_radius_top_right = 8
	r_style.corner_radius_bottom_left = 8
	r_style.corner_radius_bottom_right = 8
	row.add_theme_stylebox_override("panel", r_style)

	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 12)
	rm.add_theme_constant_override("margin_right", 12)
	rm.add_theme_constant_override("margin_top", 10)
	rm.add_theme_constant_override("margin_bottom", 10)
	row.add_child(rm)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rm.add_child(hbox)

	# Slot Icon Avatar
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(50, 50)
	var ib_style := StyleBoxFlat.new()
	ib_style.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	ib_style.corner_radius_top_left = 6
	ib_style.corner_radius_top_right = 6
	ib_style.corner_radius_bottom_left = 6
	ib_style.corner_radius_bottom_right = 6
	icon_box.add_theme_stylebox_override("panel", ib_style)
	var icon_lbl := Label.new()
	icon_lbl.text = _get_slot_icon(rslot)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_box.add_child(icon_lbl)
	hbox.add_child(icon_box)

	# Middle Info Column
	var mid_vbox := VBoxContainer.new()
	mid_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(mid_vbox)

	var title_h := HBoxContainer.new()
	title_h.add_theme_constant_override("separation", 8)
	mid_vbox.add_child(title_h)

	var name_lbl := Label.new()
	name_lbl.text = rname
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	title_h.add_child(name_lbl)

	var slot_badge := _create_mini_badge(rslot, Color(0.2, 0.35, 0.55))
	title_h.add_child(slot_badge)

	if req_lvl > building_level:
		var lvl_warn := _create_mini_badge("⚠️ Cần Lò Rèn Lv.%d" % req_lvl, Color(0.7, 0.25, 0.25))
		title_h.add_child(lvl_warn)

	# Materials row with Pills
	var mat_row := HBoxContainer.new()
	mat_row.add_theme_constant_override("separation", 8)
	mid_vbox.add_child(mat_row)

	for m in mats:
		if m is Dictionary:
			var mcode := str(m.get("code", ""))
			var mqty := int(m.get("quantity", 0))
			var player_qty := int(GameState.materials.get(mcode, 0))
			var has_enough := player_qty >= mqty
			var pill_col := Color(0.18, 0.42, 0.25) if has_enough else Color(0.45, 0.2, 0.2)
			var mat_pill := _create_mini_badge("%s %d/%d" % [mcode, player_qty, mqty], pill_col, Color.WHITE if has_enough else Color(1.0, 0.6, 0.6))
			mat_row.add_child(mat_pill)

	# Silver Fee Pill
	var fee_pill := _create_mini_badge("🪙 Phí: %d Bạc" % fee, Color(0.45, 0.38, 0.15))
	mat_row.add_child(fee_pill)

	if not ok_craft and reason != "":
		var reason_lbl := Label.new()
		reason_lbl.text = "⚠️ " + _format_craft_reason(reason, req_lvl)
		reason_lbl.add_theme_font_size_override("font_size", 11)
		reason_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
		mid_vbox.add_child(reason_lbl)

	# Right Action: Craft Button
	var craft_btn := Button.new()
	craft_btn.text = "🔨 Rèn Ngay"
	craft_btn.custom_minimum_size = Vector2(120, 42)
	craft_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var can_craft := ok_craft and building_status == "READY"
	craft_btn.disabled = not can_craft
	craft_btn.modulate = Color(0.4, 1.0, 0.6) if can_craft else Color(0.6, 0.6, 0.6)
	craft_btn.pressed.connect(func():
		craft_requested.emit(rcode, rname)
	)
	hbox.add_child(craft_btn)

	return row

# ==============================================================================
# TAB 1: ENHANCEMENT (+15)
# ==============================================================================

func _build_enhance_tab_ui(deck: Control) -> void:
	var enh_hbox := HBoxContainer.new()
	enh_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	enh_hbox.add_theme_constant_override("separation", 12)
	deck.add_child(enh_hbox)
	_tab_containers.append(enh_hbox)

	# Left / Center Area: CardGridBrowser for Equipment Items
	_enh_browser = CardGridBrowserScript.new()
	_enh_browser.browser_type = CardGridBrowserScript.BrowserType.ITEM
	_enh_browser.grid_columns = 3
	_enh_browser.card_selectable = true
	_enh_browser.multi_select_enabled = false
	_enh_browser.item_context_mode = UniversalItemCardScript.ContextMode.FORGE_ENHANCE
	_enh_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enh_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_enh_browser.configure_header("Danh sách Trang Bị Có Thể Cường Hóa", [
		"Tất cả", "Vũ khí", "Áo giáp", "Trang sức", "Chưa đạt +15", "Đạt +15"
	])
	_enh_browser.item_selected.connect(_on_enhance_item_selected)
	enh_hbox.add_child(_enh_browser)

	# Right Area: Enhancement Workbench Preview Panel
	_enh_detail_box = PanelContainer.new()
	_enh_detail_box.custom_minimum_size = Vector2(300, 0)
	var db_style := StyleBoxFlat.new()
	db_style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	db_style.border_width_left = 1
	db_style.border_width_top = 1
	db_style.border_width_right = 1
	db_style.border_width_bottom = 1
	db_style.border_color = Color(0.3, 0.45, 0.65, 0.5)
	db_style.corner_radius_top_left = 8
	db_style.corner_radius_top_right = 8
	db_style.corner_radius_bottom_left = 8
	db_style.corner_radius_bottom_right = 8
	_enh_detail_box.add_theme_stylebox_override("panel", db_style)
	enh_hbox.add_child(_enh_detail_box)

	var db_m := MarginContainer.new()
	db_m.add_theme_constant_override("margin_left", 14)
	db_m.add_theme_constant_override("margin_right", 14)
	db_m.add_theme_constant_override("margin_top", 14)
	db_m.add_theme_constant_override("margin_bottom", 14)
	_enh_detail_box.add_child(db_m)

	var db_vbox := VBoxContainer.new()
	db_vbox.add_theme_constant_override("separation", 10)
	db_m.add_child(db_vbox)

	var dt_title := Label.new()
	dt_title.text = "✨ BÀN RÈN CƯỜNG HÓA"
	dt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dt_title.add_theme_font_size_override("font_size", 14)
	dt_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	db_vbox.add_child(dt_title)

	var sep := HSeparator.new()
	db_vbox.add_child(sep)

	_enh_preview_label = Label.new()
	_enh_preview_label.text = "Chọn 1 trang bị ở danh sách bên trái để xem chi tiết cường hóa."
	_enh_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_enh_preview_label.add_theme_font_size_override("font_size", 12)
	_enh_preview_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
	db_vbox.add_child(_enh_preview_label)

	_enh_rate_label = Label.new()
	_enh_rate_label.text = ""
	_enh_rate_label.add_theme_font_size_override("font_size", 12)
	_enh_rate_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.65))
	db_vbox.add_child(_enh_rate_label)

	_enh_cost_label = Label.new()
	_enh_cost_label.text = ""
	_enh_cost_label.add_theme_font_size_override("font_size", 12)
	_enh_cost_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	db_vbox.add_child(_enh_cost_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	db_vbox.add_child(spacer)

	_enh_confirm_btn = Button.new()
	_enh_confirm_btn.text = "✨ Cường Hóa Ngay"
	_enh_confirm_btn.custom_minimum_size = Vector2(0, 44)
	_enh_confirm_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enh_confirm_btn.disabled = true
	_enh_confirm_btn.pressed.connect(_on_enhance_confirm_pressed)
	db_vbox.add_child(_enh_confirm_btn)

func _render_enhance_tab() -> void:
	if _enh_browser == null:
		return
	var equips: Array = _get_all_equipment()
	_enh_browser.set_items(equips, true)
	if not _selected_enh_item.is_empty():
		_update_enhance_preview(_selected_enh_item)
	else:
		_enh_preview_label.text = "Chọn 1 trang bị ở danh sách bên trái để bắt đầu cường hóa."
		_enh_rate_label.text = ""
		_enh_cost_label.text = ""
		_enh_confirm_btn.disabled = true

func _on_enhance_item_selected(item: Dictionary) -> void:
	_selected_enh_item = item
	_update_enhance_preview(item)

func _update_enhance_preview(item: Dictionary) -> void:
	var cur_enh := int(item.get("enhanceLevel", 0))
	var iname := str(item.get("name", "Trang bị"))
	var islot := str(item.get("slot", "WEAPON"))
	var atk := int(item.get("atkBonus", item.get("attack", 0)))
	var def := int(item.get("defBonus", item.get("defense", 0)))
	var hp := int(item.get("hpBonus", item.get("hp", 0)))

	var next_enh := cur_enh + 1
	var enh_stones_owned := int(GameState.materials.get("ENHANCEMENT_STONE", 0))
	var stones_needed := 1 if cur_enh < 5 else (2 if cur_enh < 10 else 3)
	var silver_needed := 500 * (cur_enh + 1)
	var can_afford := enh_stones_owned >= stones_needed and GameState.silver_coins >= silver_needed

	if cur_enh >= 15:
		_enh_preview_label.text = "✅ [%s] đã đạt cấp cường hóa tối đa (+15)!\n\n• Chỉ số hiện tại: ATK +%d | DEF +%d | HP +%d" % [
			iname, atk, def, hp
		]
		_enh_rate_label.text = "⭐ CẤP TRẦN ĐẠT ĐỈNH"
		_enh_cost_label.text = ""
		_enh_confirm_btn.disabled = true
		_enh_confirm_btn.text = "✅ Đã Đạt Cấp Trần (+15)"
		return

	# Success rate approximation
	var rate_text: String
	if next_enh <= 3:
		rate_text = "Tỉ lệ thành công: 100% (An toàn tuyệt đối)"
	elif next_enh <= 6:
		rate_text = "Tỉ lệ thành công: 85% (Rất cao)"
	elif next_enh <= 9:
		rate_text = "Tỉ lệ thành công: 65% (Khá)"
	elif next_enh <= 12:
		rate_text = "Tỉ lệ thành công: 45% (Trung bình)"
	else:
		rate_text = "Tỉ lệ thành công: 25% (Thử thách)"

	_enh_preview_label.text = (
		"• [%s] (%s)\n" % [iname, islot] +
		"• Cấp hiện tại: +%d ➔ Mục tiêu: +%d\n" % [cur_enh, next_enh] +
		"• Tăng trưởng chỉ số dự kiến: +8%% chỉ số cơ bản\n" +
		"• Cơ chế: Thất bại không vỡ đồ (Chỉ giữ nguyên cấp)."
	)
	_enh_rate_label.text = "🎯 " + rate_text
	_enh_cost_label.text = (
		"Chi phí:\n" +
		"• 💎 Đá Cường Hóa: %d/%d %s\n" % [enh_stones_owned, stones_needed, "✅" if enh_stones_owned >= stones_needed else "❌"] +
		"• 🪙 Bạc: %d/%d %s" % [GameState.silver_coins, silver_needed, "✅" if GameState.silver_coins >= silver_needed else "❌"]
	)

	var can_enh := can_afford and building_status == "READY"
	_enh_confirm_btn.disabled = not can_enh
	_enh_confirm_btn.text = "✨ Nâng Lên +%d (🪙 %d)" % [next_enh, silver_needed]
	_enh_confirm_btn.modulate = Color(0.4, 1.0, 0.6) if can_enh else Color(0.7, 0.7, 0.7)

func _on_enhance_confirm_pressed() -> void:
	if _selected_enh_item.is_empty():
		return
	var eid := str(_selected_enh_item.get("id", ""))
	var ename := str(_selected_enh_item.get("name", "Trang bị"))
	enhance_requested.emit(eid, ename)

# ==============================================================================
# TAB 2: STAR FUSION (GHÉP THĂNG SAO)
# ==============================================================================

func _build_fuse_tab_ui(deck: Control) -> void:
	var fuse_vbox := VBoxContainer.new()
	fuse_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	fuse_vbox.add_theme_constant_override("separation", 8)
	deck.add_child(fuse_vbox)
	_tab_containers.append(fuse_vbox)

	# Header / Guide Banner
	var guide_panel := PanelContainer.new()
	var gp_style := StyleBoxFlat.new()
	gp_style.bg_color = Color(0.09, 0.12, 0.18, 0.9)
	gp_style.corner_radius_top_left = 6
	gp_style.corner_radius_top_right = 6
	gp_style.corner_radius_bottom_left = 6
	gp_style.corner_radius_bottom_right = 6
	guide_panel.add_theme_stylebox_override("panel", gp_style)
	fuse_vbox.add_child(guide_panel)

	var gm := MarginContainer.new()
	gm.add_theme_constant_override("margin_left", 12)
	gm.add_theme_constant_override("margin_right", 12)
	gm.add_theme_constant_override("margin_top", 6)
	gm.add_theme_constant_override("margin_bottom", 6)
	guide_panel.add_child(gm)

	var guide_lbl := Label.new()
	guide_lbl.text = "🌟 Quy tắc: Gom 2 Trang Bị cùng loại & cùng cấp Sao (chưa mặc) để đột phá lên cấp Sao kế tiếp (Tối đa 6★)."
	guide_lbl.add_theme_font_size_override("font_size", 12)
	guide_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	gm.add_child(guide_lbl)

	# Filter pills
	_fuse_pills = HBoxContainer.new()
	_fuse_pills.add_theme_constant_override("separation", 6)
	fuse_vbox.add_child(_fuse_pills)

	var fpills := ["Tất cả", "Sẵn sàng ghép (≥2)", "1★", "2★", "3★", "4★", "5★"]
	for i in range(fpills.size()):
		var p_btn := Button.new()
		p_btn.text = fpills[i]
		p_btn.custom_minimum_size = Vector2(0, 32)
		p_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx := i
		p_btn.pressed.connect(func():
			_fuse_pill_idx = idx
			_update_fuse_pills()
			_render_fuse_tab()
		)
		_fuse_pills.add_child(p_btn)
	_update_fuse_pills()

	# Scrollable grid of fusion cards
	_fuse_scroll = ScrollContainer.new()
	_fuse_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuse_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fuse_vbox.add_child(_fuse_scroll)

	_fuse_container = VBoxContainer.new()
	_fuse_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fuse_container.add_theme_constant_override("separation", 8)
	_fuse_scroll.add_child(_fuse_container)

func _update_fuse_pills() -> void:
	for i in range(_fuse_pills.get_child_count()):
		var btn = _fuse_pills.get_child(i) as Button
		if btn != null:
			var is_sel := (i == _fuse_pill_idx)
			btn.modulate = Color(1.0, 0.85, 0.35) if is_sel else Color(0.7, 0.75, 0.85)

func _render_fuse_tab() -> void:
	if _fuse_container == null:
		return
	for c in _fuse_container.get_children():
		c.queue_free()

	var equips: Array = _get_all_equipment()
	var groups: Dictionary = {}
	for eq_item in equips:
		if not (eq_item is Dictionary):
			continue
		var eq_hero_id := str(eq_item.get("equippedHeroId", ""))
		if eq_hero_id != "":
			continue
		var tcode := str(eq_item.get("templateCode", ""))
		var s_lvl := int(eq_item.get("starLevel", 1))
		if tcode == "" or s_lvl >= 6:
			continue

		var gkey := "%s__%d" % [tcode, s_lvl]
		if not groups.has(gkey):
			groups[gkey] = {
				"templateCode": tcode,
				"name": str(eq_item.get("name", tcode)),
				"starLevel": s_lvl,
				"slot": str(eq_item.get("slot", "WEAPON")),
				"atkBonus": int(eq_item.get("atkBonus", 0)),
				"defBonus": int(eq_item.get("defBonus", 0)),
				"hpBonus": int(eq_item.get("hpBonus", 0)),
				"count": 0
			}
		groups[gkey]["count"] = int(groups[gkey]["count"]) + 1

	var count_rendered: int = 0
	for gkey in groups.keys():
		var g: Dictionary = groups[gkey]
		var cnt := int(g["count"])
		var slvl := int(g["starLevel"])

		# Pill filters
		match _fuse_pill_idx:
			1: # Sẵn sàng ghép (>= 2)
				if cnt < 2: continue
			2, 3, 4, 5, 6: # 1★ .. 5★
				if slvl != (_fuse_pill_idx - 1): continue

		count_rendered += 1
		var row := _create_fuse_row(g)
		_fuse_container.add_child(row)

	if count_rendered == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Chưa có trang bị rảnh rỗi nào trong kho đủ điều kiện ghép Sao với bộ lọc hiện tại."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		_fuse_container.add_child(empty_lbl)

func _create_fuse_row(g: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.10, 0.15, 0.95)
	r_style.border_width_left = 1
	r_style.border_width_top = 1
	r_style.border_width_right = 1
	r_style.border_width_bottom = 1
	r_style.border_color = Color(0.3, 0.4, 0.55, 0.6)
	r_style.corner_radius_top_left = 8
	r_style.corner_radius_top_right = 8
	r_style.corner_radius_bottom_left = 8
	r_style.corner_radius_bottom_right = 8
	row.add_theme_stylebox_override("panel", r_style)

	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 12)
	rm.add_theme_constant_override("margin_right", 12)
	rm.add_theme_constant_override("margin_top", 10)
	rm.add_theme_constant_override("margin_bottom", 10)
	row.add_child(rm)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rm.add_child(hbox)

	var gname := str(g.get("name", "Trang bị"))
	var slvl := int(g.get("starLevel", 1))
	var cnt := int(g.get("count", 1))
	var tcode := str(g.get("templateCode", ""))
	var slot := str(g.get("slot", "WEAPON"))
	var can_fuse := cnt >= 2 and building_status == "READY"

	# Slot Icon
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(50, 50)
	var ib_style := StyleBoxFlat.new()
	ib_style.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	ib_style.corner_radius_top_left = 6
	ib_style.corner_radius_top_right = 6
	ib_style.corner_radius_bottom_left = 6
	ib_style.corner_radius_bottom_right = 6
	icon_box.add_theme_stylebox_override("panel", ib_style)
	var icon_lbl := Label.new()
	icon_lbl.text = _get_slot_icon(slot)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_box.add_child(icon_lbl)
	hbox.add_child(icon_box)

	# Info Column
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 3)
	hbox.add_child(info_vbox)

	var h_title := HBoxContainer.new()
	h_title.add_theme_constant_override("separation", 8)
	info_vbox.add_child(h_title)

	var name_lbl := Label.new()
	name_lbl.text = gname
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	h_title.add_child(name_lbl)

	var star_badge := _create_mini_badge("★".repeat(slvl), Color(0.55, 0.42, 0.12), Color(1.0, 0.9, 0.3))
	h_title.add_child(star_badge)

	var next_star_badge := _create_mini_badge("➔ %d★" % (slvl + 1), Color(0.18, 0.42, 0.25))
	h_title.add_child(next_star_badge)

	var status_text := "Đủ điều kiện ghép (Có %d/2 món)" % cnt if cnt >= 2 else "Còn thiếu %d món nữa (Có %d/2 món)" % [2 - cnt, cnt]
	var status_lbl := Label.new()
	status_lbl.text = status_text
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.65) if cnt >= 2 else Color(0.8, 0.8, 0.85))
	info_vbox.add_child(status_lbl)

	# Right Action Button
	var fuse_btn := Button.new()
	fuse_btn.text = "🌟 Đột Phá Lên %d★" % (slvl + 1) if can_fuse else "Thiếu 1 Món (%d/2)" % cnt
	fuse_btn.custom_minimum_size = Vector2(160, 42)
	fuse_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	fuse_btn.disabled = not can_fuse
	fuse_btn.modulate = Color(0.4, 1.0, 0.6) if can_fuse else Color(0.65, 0.65, 0.65)
	fuse_btn.pressed.connect(func():
		fuse_requested.emit(tcode, slvl, gname)
	)
	hbox.add_child(fuse_btn)

	return row

# ==============================================================================
# HELPERS
# ==============================================================================

func _get_all_equipment() -> Array:
	return GameState.inventory_items.filter(func(it):
		if not (it is Dictionary):
			return false
		var cat := str(it.get("category", it.get("itemType", ""))).to_upper()
		var slot := str(it.get("slot", "")).to_upper()
		return cat == "EQUIPMENT" or slot in ["WEAPON", "ARMOR", "HELMET", "CHEST", "PANTS", "BOOTS", "RING", "AMULET", "SHIELD"]
	)

func _create_mini_badge(text: String, bg_col: Color, fg_col: Color = Color.WHITE) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = bg_col
	pstyle.corner_radius_top_left = 4
	pstyle.corner_radius_top_right = 4
	pstyle.corner_radius_bottom_left = 4
	pstyle.corner_radius_bottom_right = 4
	pill.add_theme_stylebox_override("panel", pstyle)

	var pm := MarginContainer.new()
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_theme_constant_override("margin_left", 6)
	pm.add_theme_constant_override("margin_right", 6)
	pm.add_theme_constant_override("margin_top", 2)
	pm.add_theme_constant_override("margin_bottom", 2)
	pill.add_child(pm)

	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", fg_col)
	pm.add_child(lbl)
	return pill

func _get_slot_icon(slot: String) -> String:
	match slot.to_upper():
		"WEAPON", "SWORD": return "⚔️"
		"BOW": return "🏹"
		"STAFF": return "🔮"
		"DAGGER": return "🗡️"
		"ARMOR", "CHEST": return "🛡️"
		"HELMET": return "🪖"
		"PANTS", "BOOTS": return "👢"
		"RING": return "💍"
		"AMULET", "NECKLACE": return "📿"
		_: return "📦"

func _format_num(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (float(n) / 1_000_000.0)
	elif n >= 10_000:
		return "%.1fK" % (float(n) / 1000.0)
	return str(n)

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
