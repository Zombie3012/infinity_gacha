class_name DormitoryModal
extends Control

## Dedicated Clash-of-Clans style Dormitory & Party Mansion Modal
## Supports both:
##   - HOUSE: Standard Dormitory (1.0x / 1.5x / 2.0x fatigue recovery, 5/7/10 slots)
##   - PARTY_MANSION: Luxury Villa (4.0x fatigue recovery, 5 slots)

signal closed
signal hero_rest_toggled(hero_id: String, hero_name: String, is_currently_resting: bool)
signal squad_rest_requested(is_resting: bool)
signal feed_hero_requested(hero_id: String, hero_name: String)

const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")

var building_data: Dictionary = {}
var is_mansion: bool = false
var building_level: int = 1
var max_capacity: int = 5
var mult_by_lvl: float = 1.0
var fat_per_hr: float = 15.0

# UI References
var _title_label: Label
var _capacity_label: Label
var _rate_label: Label
var _ration_label: Label
var _hero_browser: CardGridBrowser
var _is_ui_built: bool = false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	if not _is_ui_built:
		_build_ui()
	EventBus.heroes_updated.connect(func(_heroes: Array): refresh_ui())
	refresh_ui()

func setup(b_data: Dictionary) -> void:
	building_data = b_data
	var b_code := str(b_data.get("buildingType", "HOUSE"))
	is_mansion = (b_code == "PARTY_MANSION")
	building_level = int(b_data.get("level", 1))

	if is_mansion:
		max_capacity = 5
		mult_by_lvl = 4.0
		fat_per_hr = 60.0
	else:
		max_capacity = 5 if building_level <= 1 else (7 if building_level == 2 else 10)
		mult_by_lvl = 1.0 if building_level <= 1 else (1.5 if building_level == 2 else 2.0)
		fat_per_hr = 15.0 * mult_by_lvl

	if not _is_ui_built:
		_build_ui()
	refresh_ui()

func refresh_ui() -> void:
	if not _is_ui_built:
		return
	var resting_count := 0
	for h in GameState.heroes:
		if h is Dictionary and str(h.get("state", "")) == "RESTING":
			resting_count += 1

	if _title_label != null:
		if is_mansion:
			_title_label.text = "🏰 BIỆT THỰ TỔ ĐỘI – PARTY MANSION (Lv.%d/3)" % building_level
		else:
			_title_label.text = "🏠 DORMITORY – KHU CƯ TRÚ (Lv.%d/3)" % building_level

	if _capacity_label != null:
		_capacity_label.text = "🛌 Đang nghỉ ngơi: %d / %d Hero" % [resting_count, max_capacity]
		_capacity_label.modulate = Color(0.4, 0.95, 0.65) if resting_count < max_capacity else Color(1.0, 0.75, 0.3)

	if _rate_label != null:
		_rate_label.text = "⚡ Tốc độ hồi phục: %.1fx (-%.1f Mệt mỏi/giờ)" % [mult_by_lvl, fat_per_hr]

	if _ration_label != null:
		var rations := int(GameState.materials.get("RATION", 0))
		_ration_label.text = "🍖 Lương thực: %d" % rations

	if _hero_browser != null:
		_hero_browser.set_items(GameState.heroes.filter(func(hero): return hero is Dictionary and GameState.is_hero_available(hero)), true)

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

	# 2. Centered Modal Window
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
	win_style.border_color = Color(0.55, 0.85, 1.0, 0.8)
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

	# Top Header Row: Title + Close Button
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	_title_label = Label.new()
	_title_label.text = "🏠 DORMITORY – KHU CƯ TRÚ (Lv.1/3)"
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.75, 0.92, 1.0))
	header_row.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_on_close_pressed)
	header_row.add_child(close_btn)

	# Summary Bar: Capacity + Recovery Multiplier + Rations
	var summary_panel := PanelContainer.new()
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color(0.045, 0.065, 0.10, 0.95)
	sp_style.border_width_bottom = 1
	sp_style.border_color = Color(0.3, 0.45, 0.6, 0.4)
	sp_style.corner_radius_top_left = 6
	sp_style.corner_radius_top_right = 6
	sp_style.corner_radius_bottom_left = 6
	sp_style.corner_radius_bottom_right = 6
	summary_panel.add_theme_stylebox_override("panel", sp_style)
	root_vbox.add_child(summary_panel)

	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 12)
	sm.add_theme_constant_override("margin_right", 12)
	sm.add_theme_constant_override("margin_top", 8)
	sm.add_theme_constant_override("margin_bottom", 8)
	summary_panel.add_child(sm)

	var sm_row := HBoxContainer.new()
	sm_row.add_theme_constant_override("separation", 24)
	sm_row.alignment = BoxContainer.ALIGNMENT_CENTER
	sm.add_child(sm_row)

	_capacity_label = Label.new()
	_capacity_label.text = "🛌 Đang nghỉ ngơi: 0 / 5 Hero"
	_capacity_label.add_theme_font_size_override("font_size", 13)
	_capacity_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.65))
	sm_row.add_child(_capacity_label)

	_rate_label = Label.new()
	_rate_label.text = "⚡ Tốc độ hồi phục: 1.0x (-15.0 Mệt mỏi/giờ)"
	_rate_label.add_theme_font_size_override("font_size", 13)
	_rate_label.add_theme_color_override("font_color", Color(0.7, 0.88, 1.0))
	sm_row.add_child(_rate_label)

	_ration_label = Label.new()
	_ration_label.text = "🍖 Lương thực: 0"
	_ration_label.add_theme_font_size_override("font_size", 13)
	_ration_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	sm_row.add_child(_ration_label)

	# Main Hero Browser
	_hero_browser = CardGridBrowserScript.new()
	_hero_browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	_hero_browser.grid_columns = 4
	_hero_browser.card_selectable = true
	_hero_browser.multi_select_enabled = true
	_hero_browser.max_selection = 10
	_hero_browser.hero_context_mode = UniversalHeroCardScript.ContextMode.DORMITORY
	_hero_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_hero_browser.configure_header("Danh sách Hero Cần Nghỉ Ngơi & Hồi Phục", [
		"Tất cả", "Đang nghỉ ngơi", "Mệt nặng (>50%)", "Đội hình PVE", "Khỏe mạnh (<10%)"
	])
	_hero_browser.set_action_button("🛏️ Đổi Trạng Thái Nghỉ Cho Hero Đã Chọn")

	# Quick squad buttons on browser action bar
	_hero_browser.add_extra_action_button("🛏️ Cho Cả Đội PVE Nghỉ", "REST_PVE", Color(0.45, 0.85, 1.0))
	_hero_browser.add_extra_action_button("🌅 Đánh Thức Tất Cả", "WAKE_ALL", Color(1.0, 0.85, 0.4))
	_hero_browser.add_extra_action_button("🍖 Cho Ăn Tiếp Tế", "FEED_SELECTED", Color(1.0, 0.65, 0.35))

	_hero_browser.action_confirmed.connect(_on_browser_action_confirmed)
	_hero_browser.quick_action_requested.connect(_on_quick_action_requested)
	_hero_browser.item_selected.connect(_on_card_clicked)

	root_vbox.add_child(_hero_browser)

func _on_card_clicked(hero: Dictionary) -> void:
	var hid := str(hero.get("id", ""))
	var hname := str(hero.get("name", "Hero"))
	var is_resting := str(hero.get("state", "")) == "RESTING"
	hero_rest_toggled.emit(hid, hname, is_resting)

func _on_browser_action_confirmed(selected_heroes: Array) -> void:
	for h in selected_heroes:
		if h is Dictionary:
			var hid := str(h.get("id", ""))
			var hname := str(h.get("name", "Hero"))
			var is_resting := str(h.get("state", "")) == "RESTING"
			hero_rest_toggled.emit(hid, hname, is_resting)

func _on_quick_action_requested(action_code: String, selected_heroes: Array) -> void:
	match action_code:
		"REST_PVE":
			squad_rest_requested.emit(true)
		"WAKE_ALL":
			squad_rest_requested.emit(false)
		"FEED_SELECTED":
			for h in selected_heroes:
				if h is Dictionary:
					var hid := str(h.get("id", ""))
					var hname := str(h.get("name", "Hero"))
					feed_hero_requested.emit(hid, hname)

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
