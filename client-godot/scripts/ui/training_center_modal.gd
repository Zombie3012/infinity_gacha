class_name TrainingCenterModal
extends Control

## Dedicated Clash-of-Clans style Training Center Modal
## Supports:
##   - Hero Grid Browser with Base Stats Context (STR / AGI / INT / STA)
##   - 4-Stat Individual Training Station (💪 STR, ⚡ AGI, 🔮 INT, 🛡️ STA)
##   - Hero Combat Skills Station (Unlock & Upgrade skills)

signal closed
signal stat_train_requested(hero_id: String, hero_name: String, stat_code: String)
signal skill_unlock_requested(hero_id: String, hero_name: String, skill_code: String, skill_name: String)
signal skill_upgrade_requested(hero_id: String, hero_name: String, skill_code: String, skill_name: String)

const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")

var building_data: Dictionary = {}
var building_level: int = 1
var building_status: String = "READY"
var selected_hero: Dictionary = {}

# UI Components
var _title_label: Label
var _capacity_label: Label
var _hero_browser: CardGridBrowser

# Right Training Panel
var _profile_panel: PanelContainer
var _profile_name_label: Label
var _profile_stats_label: Label
var _stat_buttons: Dictionary = {}
var _skills_vbox: VBoxContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()

func setup(b_data: Dictionary) -> void:
	building_data = b_data
	building_level = int(b_data.get("level", 1))
	building_status = str(b_data.get("status", "READY"))
	refresh_ui()

func refresh_ui() -> void:
	var cap_heroes := 3 if building_level <= 1 else (5 if building_level == 2 else 7)
	if _title_label != null:
		_title_label.text = "🥋 KHU HUẤN LUYỆN (TRAINING CENTER Lv.%d/3)" % building_level
	if _capacity_label != null:
		_capacity_label.text = "• Sức chứa huấn luyện: Tối đa %d Hero | Trạng thái: %s" % [
			cap_heroes, "SẴN SÀNG" if building_status == "READY" else building_status
		]
		_capacity_label.modulate = Color(0.4, 1.0, 0.6) if building_status == "READY" else Color(1.0, 0.75, 0.3)

	if _hero_browser != null:
		_hero_browser.set_items(GameState.heroes, true)

	if not selected_hero.is_empty():
		# Refresh selected hero data from GameState
		var hid := str(selected_hero.get("id", ""))
		for h in GameState.heroes:
			if h is Dictionary and str(h.get("id", "")) == hid:
				selected_hero = h
				break
		_update_workbench(selected_hero)
	elif not GameState.heroes.is_empty() and GameState.heroes[0] is Dictionary:
		selected_hero = GameState.heroes[0]
		_update_workbench(selected_hero)

func _build_ui() -> void:
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
	win_style.border_color = Color(0.45, 0.95, 0.65, 0.8)
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
	_title_label.text = "🥋 KHU HUẤN LUYỆN (TRAINING CENTER Lv.%d/3)" % building_level
	_title_label.add_theme_font_size_override("font_size", 18)
	_title_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))
	header_row.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	_capacity_label = Label.new()
	_capacity_label.text = "• Sức chứa: 3 Hero"
	_capacity_label.add_theme_font_size_override("font_size", 12)
	_capacity_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	header_row.add_child(_capacity_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_btn.pressed.connect(_on_close_pressed)
	header_row.add_child(close_btn)

	# Main Body: Split Left (Hero Grid Browser) & Right (Training Workbench)
	var body_hbox := HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 12)
	body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	# Left: Hero Browser
	_hero_browser = CardGridBrowserScript.new()
	_hero_browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	_hero_browser.grid_columns = 3
	_hero_browser.card_selectable = true
	_hero_browser.multi_select_enabled = false
	_hero_browser.hero_context_mode = UniversalHeroCardScript.ContextMode.TRAINING
	_hero_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_hero_browser.configure_header("Chọn Hero Để Huấn Luyện", [
		"Tất cả", "Đội hình PVE", "Chiến binh", "Đỡ đòn", "Pháp sư", "Xạ thủ"
	])
	_hero_browser.item_selected.connect(_on_hero_selected)
	body_hbox.add_child(_hero_browser)

	# Right: Workbench Panel
	_profile_panel = PanelContainer.new()
	_profile_panel.custom_minimum_size = Vector2(330, 0)
	var pb_style := StyleBoxFlat.new()
	pb_style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	pb_style.border_width_left = 1
	pb_style.border_width_top = 1
	pb_style.border_width_right = 1
	pb_style.border_width_bottom = 1
	pb_style.border_color = Color(0.3, 0.5, 0.4, 0.6)
	pb_style.corner_radius_top_left = 8
	pb_style.corner_radius_top_right = 8
	pb_style.corner_radius_bottom_left = 8
	pb_style.corner_radius_bottom_right = 8
	_profile_panel.add_theme_stylebox_override("panel", pb_style)
	body_hbox.add_child(_profile_panel)

	var pb_m := MarginContainer.new()
	pb_m.add_theme_constant_override("margin_left", 14)
	pb_m.add_theme_constant_override("margin_right", 14)
	pb_m.add_theme_constant_override("margin_top", 14)
	pb_m.add_theme_constant_override("margin_bottom", 14)
	_profile_panel.add_child(pb_m)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pb_m.add_child(scroll)

	var work_vbox := VBoxContainer.new()
	work_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(work_vbox)

	var wb_title := Label.new()
	wb_title.text = "🎯 BÀN HUẤN LUYỆN CHỈ SỐ"
	wb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wb_title.add_theme_font_size_override("font_size", 14)
	wb_title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))
	work_vbox.add_child(wb_title)

	var sep1 := HSeparator.new()
	work_vbox.add_child(sep1)

	_profile_name_label = Label.new()
	_profile_name_label.text = "Hero: Chưa chọn"
	_profile_name_label.add_theme_font_size_override("font_size", 14)
	_profile_name_label.add_theme_color_override("font_color", Color.WHITE)
	work_vbox.add_child(_profile_name_label)

	_profile_stats_label = Label.new()
	_profile_stats_label.text = "💪 STR: 0 | ⚡ AGI: 0\n🔮 INT: 0 | 🛡️ STA: 0"
	_profile_stats_label.add_theme_font_size_override("font_size", 12)
	_profile_stats_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	work_vbox.add_child(_profile_stats_label)

	var stat_title := Label.new()
	stat_title.text = "Rèn luyện 4 chỉ số cơ bản (+1 điểm):"
	stat_title.add_theme_font_size_override("font_size", 12)
	stat_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	work_vbox.add_child(stat_title)

	# 2x2 Grid of Stat Training Buttons
	var stat_grid := GridContainer.new()
	stat_grid.columns = 2
	stat_grid.add_theme_constant_override("h_separation", 6)
	stat_grid.add_theme_constant_override("v_separation", 6)
	stat_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_vbox.add_child(stat_grid)

	var stat_keys := [
		{"code": "str", "icon": "💪", "name": "STR"},
		{"code": "agi", "icon": "⚡", "name": "AGI"},
		{"code": "int", "icon": "🔮", "name": "INT"},
		{"code": "sta", "icon": "🛡️", "name": "STA"}
	]
	for sk in stat_keys:
		var scode := str(sk["code"])
		var btn := Button.new()
		btn.text = "%s %s (+1)" % [sk["icon"], sk["name"]]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func(): _on_train_stat_pressed(scode))
		stat_grid.add_child(btn)
		_stat_buttons[scode] = btn

	var sep2 := HSeparator.new()
	work_vbox.add_child(sep2)

	var skill_header := Label.new()
	skill_header.text = "⚔️ KỸ NĂNG THỰC CHIẾN:"
	skill_header.add_theme_font_size_override("font_size", 13)
	skill_header.add_theme_color_override("font_color", Color(0.65, 0.9, 1.0))
	work_vbox.add_child(skill_header)

	_skills_vbox = VBoxContainer.new()
	_skills_vbox.add_theme_constant_override("separation", 6)
	_skills_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work_vbox.add_child(_skills_vbox)

func _on_hero_selected(hero: Dictionary) -> void:
	selected_hero = hero
	_update_workbench(hero)

func _update_workbench(hero: Dictionary) -> void:
	if hero.is_empty():
		return
	var hname := str(hero.get("name", "Hero"))
	var hlvl := int(hero.get("level", 1))
	var hclass := str(hero.get("classCode", hero.get("heroClass", "WARRIOR")))
	var str_val := int(hero.get("str", 10))
	var agi_val := int(hero.get("agi", 10))
	var int_val := int(hero.get("int", 10))
	var sta_val := int(hero.get("sta", 10))

	_profile_name_label.text = "Hero: [%s] (%s Lv.%d)" % [hname, hclass, hlvl]
	_profile_stats_label.text = "💪 STR: %d | ⚡ AGI: %d\n🔮 INT: %d | 🛡️ STA: %d" % [
		str_val, agi_val, int_val, sta_val
	]

	var can_train := building_status == "READY"
	if _stat_buttons.has("str"):
		_stat_buttons["str"].text = "💪 STR (%d→%d)" % [str_val, str_val + 1]
		_stat_buttons["str"].disabled = not can_train
	if _stat_buttons.has("agi"):
		_stat_buttons["agi"].text = "⚡ AGI (%d→%d)" % [agi_val, agi_val + 1]
		_stat_buttons["agi"].disabled = not can_train
	if _stat_buttons.has("int"):
		_stat_buttons["int"].text = "🔮 INT (%d→%d)" % [int_val, int_val + 1]
		_stat_buttons["int"].disabled = not can_train
	if _stat_buttons.has("sta"):
		_stat_buttons["sta"].text = "🛡️ STA (%d→%d)" % [sta_val, sta_val + 1]
		_stat_buttons["sta"].disabled = not can_train

	# Skills list
	for c in _skills_vbox.get_children():
		c.queue_free()

	var skills: Array = hero.get("skills", [])
	if skills.is_empty():
		var empty_sk := Label.new()
		empty_sk.text = "Hero chưa có kỹ năng chiến đấu riêng."
		empty_sk.add_theme_font_size_override("font_size", 11)
		empty_sk.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		_skills_vbox.add_child(empty_sk)
		return

	for sk in skills:
		if not (sk is Dictionary):
			continue
		var sk_code := str(sk.get("code", ""))
		var sk_name := str(sk.get("name", sk_code))
		var sk_lvl := int(sk.get("level", 0))
		var sk_max := int(sk.get("maxLevel", 5))
		var unlocked := bool(sk.get("unlocked", sk_lvl > 0))

		var sk_row := PanelContainer.new()
		var skr_style := StyleBoxFlat.new()
		skr_style.bg_color = Color(0.10, 0.14, 0.20, 0.9)
		skr_style.corner_radius_top_left = 6
		skr_style.corner_radius_top_right = 6
		skr_style.corner_radius_bottom_left = 6
		skr_style.corner_radius_bottom_right = 6
		sk_row.add_theme_stylebox_override("panel", skr_style)

		var sk_m := MarginContainer.new()
		sk_m.add_theme_constant_override("margin_left", 8)
		sk_m.add_theme_constant_override("margin_right", 8)
		sk_m.add_theme_constant_override("margin_top", 6)
		sk_m.add_theme_constant_override("margin_bottom", 6)
		sk_row.add_child(sk_m)

		var sk_h := HBoxContainer.new()
		sk_h.add_theme_constant_override("separation", 8)
		sk_m.add_child(sk_h)

		var sk_info := Label.new()
		sk_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sk_info.text = "%s (Lv.%d/%d)" % [sk_name, sk_lvl, sk_max]
		sk_info.add_theme_font_size_override("font_size", 12)
		sk_info.add_theme_color_override("font_color", Color.WHITE if unlocked else Color(0.65, 0.7, 0.8))
		sk_h.add_child(sk_info)

		var act_btn := Button.new()
		act_btn.custom_minimum_size = Vector2(80, 28)
		act_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if not unlocked:
			act_btn.text = "🔓 Mở"
			act_btn.modulate = Color(0.4, 0.95, 0.65)
			act_btn.disabled = not can_train
			act_btn.pressed.connect(func():
				var hid := str(hero.get("id", ""))
				skill_unlock_requested.emit(hid, hname, sk_code, sk_name)
			)
		else:
			var maxed := sk_lvl >= sk_max
			act_btn.text = "MAX" if maxed else "⬆️ Nâng"
			act_btn.disabled = maxed or not can_train
			act_btn.modulate = Color(1.0, 0.85, 0.4) if not maxed else Color(0.7, 0.7, 0.7)
			act_btn.pressed.connect(func():
				var hid := str(hero.get("id", ""))
				skill_upgrade_requested.emit(hid, hname, sk_code, sk_name)
			)
		sk_h.add_child(act_btn)

		_skills_vbox.add_child(sk_row)

func _on_train_stat_pressed(stat_code: String) -> void:
	if selected_hero.is_empty():
		return
	var hid := str(selected_hero.get("id", ""))
	var hname := str(selected_hero.get("name", "Hero"))
	stat_train_requested.emit(hid, hname, stat_code)

func _on_close_pressed() -> void:
	closed.emit()
	queue_free()
