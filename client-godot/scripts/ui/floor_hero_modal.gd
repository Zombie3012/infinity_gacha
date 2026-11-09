class_name FloorHeroModal
extends Control

## Dedicated Floor Hero Manager Modal for Godot 4 Client
## Uses CardGridBrowser and UniversalHeroCard to assign up to 6 Heroes
## per lobby floor (Floor 1: Hạ Thành, Floor 2: Thượng Thành).

signal closed
signal floor_saved(floor_num: int, assigned_hero_ids: Array)

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")

const MAX_HEROES_PER_FLOOR := 6

var current_floor: int = 1
var max_floors: int = 2

var title_label: Label
var subtitle_label: Label
var floor_tabs_box: HBoxContainer
var status_ribbon_label: Label
var banner_label: Label
var browser
var reset_btn: Button
var save_btn: Button

var _floor_buttons: Array[Button] = []
var _editing_selections: Dictionary = {} # floor_num -> Array[String]

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	max_floors = maxi(1, GameState.unlocked_lobby_floors)
	_build_ui()
	_load_floor_selection(current_floor)

func setup(floor_num: int = 1) -> void:
	max_floors = maxi(1, GameState.unlocked_lobby_floors)
	current_floor = clampi(floor_num, 1, max_floors)
	if is_inside_tree():
		_load_floor_selection(current_floor)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Translucent Backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.07, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# 2. Main Centered Window
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 680)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.35, 0.75, 1.0, 0.85) # Celestial Cyan Border
	p_style.corner_radius_top_left = 12
	p_style.corner_radius_top_right = 12
	p_style.corner_radius_bottom_left = 12
	p_style.corner_radius_bottom_right = 12
	p_style.shadow_size = 14
	p_style.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# 3. Header Row: Title & Close Button
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	title_label = Label.new()
	title_label.text = "👥 QUẢN LÝ HERO TỪNG TẦNG SẢNH CHỜ"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	title_box.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Chỉ định tối đa 6 Hero xuất hiện tại mỗi Tầng (Tối ưu hiệu năng & Giảm tải màn hình)"
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	title_box.add_child(subtitle_label)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_modal)
	header_row.add_child(close_btn)

	# 4. Floor Tabs Row
	floor_tabs_box = HBoxContainer.new()
	floor_tabs_box.add_theme_constant_override("separation", 8)
	floor_tabs_box.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(floor_tabs_box)
	_rebuild_floor_tabs()

	# 5. Status Ribbon & Quick Actions
	var ribbon := PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.10, 0.13, 0.19, 0.95)
	r_style.border_width_left = 1
	r_style.border_width_top = 1
	r_style.border_width_right = 1
	r_style.border_width_bottom = 1
	r_style.border_color = Color(0.24, 0.35, 0.48)
	r_style.corner_radius_top_left = 8
	r_style.corner_radius_top_right = 8
	r_style.corner_radius_bottom_left = 8
	r_style.corner_radius_bottom_right = 8
	ribbon.add_theme_stylebox_override("panel", r_style)
	root_vbox.add_child(ribbon)

	var r_margin := MarginContainer.new()
	r_margin.add_theme_constant_override("margin_left", 12)
	r_margin.add_theme_constant_override("margin_top", 8)
	r_margin.add_theme_constant_override("margin_right", 12)
	r_margin.add_theme_constant_override("margin_bottom", 8)
	ribbon.add_child(r_margin)

	var r_row := HBoxContainer.new()
	r_row.add_theme_constant_override("separation", 12)
	r_margin.add_child(r_row)

	status_ribbon_label = Label.new()
	status_ribbon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_ribbon_label.text = "⚪ Trạng thái: TỰ ĐỘNG PHÂN BỔ (Mặc định)"
	status_ribbon_label.add_theme_font_size_override("font_size", 13)
	status_ribbon_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	r_row.add_child(status_ribbon_label)

	reset_btn = Button.new()
	reset_btn.text = "🔄 Đặt Lại Tự Động"
	reset_btn.custom_minimum_size = Vector2(135, 34)
	reset_btn.modulate = Color(1.0, 0.85, 0.45)
	reset_btn.pressed.connect(_on_reset_to_auto_pressed)
	r_row.add_child(reset_btn)

	save_btn = Button.new()
	save_btn.text = "💾 Lưu & Áp Dụng"
	save_btn.custom_minimum_size = Vector2(135, 34)
	save_btn.modulate = Color(0.40, 1.0, 0.65)
	save_btn.pressed.connect(_on_save_pressed)
	r_row.add_child(save_btn)

	# 6. Status Toast Banner
	banner_label = Label.new()
	banner_label.text = "💡 Chọn tối đa 6 Hero bằng cách bấm vào thẻ bên dưới rồi nhấn 'Lưu & Áp Dụng'."
	banner_label.add_theme_font_size_override("font_size", 12)
	banner_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(banner_label)

	# 7. CardGridBrowser Component
	browser = CardGridBrowserScript.new()
	browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	browser.hero_context_mode = UniversalHeroCardScript.ContextMode.DEFAULT
	browser.grid_columns = 3
	browser.card_selectable = true
	browser.multi_select_enabled = true
	browser.max_selection = MAX_HEROES_PER_FLOOR
	root_vbox.add_child(browser)

	browser.configure_header("Danh sách Hero Lâu Đài", ["Tất cả", "Trong Đội PvE", "Đang phân công", "Chưa xếp"])
	browser.set_action_button("💾 Lưu Cấu Hình Tầng #%d" % current_floor, "Lưu")
	browser.selection_changed.connect(_on_selection_changed)
	browser.action_confirmed.connect(func(_items): _on_save_pressed())

func _rebuild_floor_tabs() -> void:
	if floor_tabs_box == null:
		return
	for c in floor_tabs_box.get_children():
		c.queue_free()
	_floor_buttons.clear()

	for f in range(1, max_floors + 1):
		var btn := Button.new()
		var floor_tag := " (Hạ Thành)" if f == 1 else (" (Thượng Thành)" if f == 2 else "")
		btn.text = "🏰 Tầng %d%s" % [f, floor_tag]
		btn.custom_minimum_size = Vector2(160, 34)
		var target_f := f
		btn.pressed.connect(func():
			_load_floor_selection(target_f)
		)
		floor_tabs_box.add_child(btn)
		_floor_buttons.append(btn)

	_update_floor_tab_styles()

func _update_floor_tab_styles() -> void:
	for i in range(_floor_buttons.size()):
		var f := i + 1
		var btn: Button = _floor_buttons[i]
		if f == current_floor:
			btn.modulate = Color(1.0, 0.88, 0.38)
		else:
			btn.modulate = Color(0.80, 0.85, 0.95)

func _load_floor_selection(floor_num: int) -> void:
	current_floor = floor_num
	_update_floor_tab_styles()

	if not _editing_selections.has(floor_num):
		var assigned: Array = GameState.get_assigned_heroes_for_floor(floor_num).duplicate()
		_editing_selections[floor_num] = assigned

	var cur_selected: Array = _editing_selections[floor_num]
	if browser != null:
		browser.set_items(GameState.heroes, true)
		browser.select_items_by_ids(cur_selected)
		browser.set_action_button("💾 Lưu Cấu Hình Tầng #%d" % current_floor, "Lưu")

	_update_status_display()
	banner_label.text = "💡 Đang cấu hình Tầng #%d. Chọn tối đa 6 Hero rồi nhấn 'Lưu & Áp Dụng'." % floor_num

func _update_status_display() -> void:
	var cur_selected: Array = _editing_selections.get(current_floor, [])
	var has_custom: bool = not GameState.get_assigned_heroes_for_floor(current_floor).is_empty()

	if cur_selected.is_empty() and not has_custom:
		status_ribbon_label.text = "⚪ Trạng thái Tầng #%d: TỰ ĐỘNG PHÂN BỔ (Mặc định)" % current_floor
		status_ribbon_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	else:
		status_ribbon_label.text = "🟢 Trạng thái Tầng #%d: ĐÃ CHỌN %d / %d HERO" % [
			current_floor, cur_selected.size(), MAX_HEROES_PER_FLOOR
		]
		status_ribbon_label.add_theme_color_override("font_color", Color(0.40, 1.0, 0.65))

func _on_selection_changed(selected_items: Array) -> void:
	var ids: Array = []
	for it in selected_items:
		if it is Dictionary:
			ids.append(str(it.get("id", "")))
	_editing_selections[current_floor] = ids
	_update_status_display()

func _on_save_pressed() -> void:
	var ids: Array = _editing_selections.get(current_floor, [])
	GameState.set_assigned_heroes_for_floor(current_floor, ids)
	floor_saved.emit(current_floor, ids)
	banner_label.text = "✅ Đã lưu cấu hình %d Hero xuất hiện tại Tầng #%d thành công!" % [ids.size(), current_floor]
	_update_status_display()

func _on_reset_to_auto_pressed() -> void:
	_editing_selections[current_floor] = []
	GameState.clear_assigned_heroes_for_floor(current_floor)
	if browser != null:
		browser.clear_selection()
	floor_saved.emit(current_floor, [])
	banner_label.text = "🔄 Đã đưa Tầng #%d về chế độ tự động phân bổ Hero mặc định!" % current_floor
	_update_status_display()

func close_modal() -> void:
	closed.emit()
	queue_free()
