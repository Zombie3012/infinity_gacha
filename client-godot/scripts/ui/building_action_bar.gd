class_name BuildingActionBar
extends Control

## Building Action Bar - Clash of Clans Style
## Floating bottom dock presenting circular / pill action buttons for the selected building:
## [i] Info, [⬆️] Upgrade, [Facility Action] (Cook / Heal / Forge / Warehouse / etc.),
## [👷] Workers, [🌾] Collect Harvest. Click outside the dock to dismiss it.

signal info_pressed(building_data: Dictionary)
signal upgrade_pressed(building_data: Dictionary)
signal facility_action_pressed(building_data: Dictionary, action_code: String)
signal workers_pressed(building_data: Dictionary)
signal collect_pressed(building_data: Dictionary)
signal build_pressed(plot_data: Dictionary)
signal expand_zone_pressed(zone_index: int)
signal closed

var current_data: Dictionary = {}
var is_plot_empty: bool = false
var is_plot_locked: bool = false
var plot_index: int = -1
var zone_index: int = 1

var main_panel: PanelContainer
var title_label: Label
var subtitle_label: Label
var buttons_container: HBoxContainer

func _init() -> void:
	# Bottom centered dock layout
	anchor_left = 0.5
	anchor_top = 1.0
	anchor_right = 0.5
	anchor_bottom = 1.0
	offset_left = -320
	offset_top = -140
	offset_right = 320
	offset_bottom = -15
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui_scaffolding()

func _build_ui_scaffolding() -> void:
	for c in get_children():
		c.queue_free()

	main_panel = PanelContainer.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.95, 0.78, 0.28, 0.9) # Gold border
	pstyle.corner_radius_top_left = 16
	pstyle.corner_radius_top_right = 16
	pstyle.corner_radius_bottom_left = 16
	pstyle.corner_radius_bottom_right = 16
	pstyle.shadow_size = 10
	pstyle.shadow_color = Color(0, 0, 0, 0.65)
	main_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(main_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	main_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	# --- Header: Title + Status Pill ---
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.add_theme_constant_override("separation", 10)
	vbox.add_child(header_row)

	title_label = Label.new()
	title_label.text = "Tên Công Trình"
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	header_row.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Trạng thái: Sẵn sàng"
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	header_row.add_child(subtitle_label)

	# --- Buttons Dock Row ---
	buttons_container = HBoxContainer.new()
	buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 12)
	vbox.add_child(buttons_container)

## Show action bar for constructed building
func show_building(data: Dictionary) -> void:
	current_data = data
	is_plot_empty = false
	is_plot_locked = false

	var b_code := str(data.get("buildingType", ""))
	var b_name := str(data.get("typeName", b_code))
	var b_lvl := int(data.get("level", 1))
	var max_lvl := int(data.get("maxLevel", 3))
	var status := str(data.get("status", "READY"))
	var stored := float(data.get("stored", 0.0))
	var res_type := str(data.get("resourceType", ""))
	var max_w := int(data.get("maxWorkers", 0))
	var workers: Array = data.get("workers", [])

	title_label.text = "%s %s (Cấp %d/%d)" % [_get_building_icon(b_code), b_name, b_lvl, max_lvl]
	subtitle_label.text = "• Trạng thái: %s" % ("SẴN SÀNG" if status == "READY" else status)
	subtitle_label.modulate = Color(0.4, 1.0, 0.6) if status == "READY" else Color(1.0, 0.85, 0.3)

	_clear_buttons()

	# 1. [ℹ️] Thông tin Button
	_add_action_button("ℹ️", "Thông tin", Color(0.3, 0.75, 1.0), func():
		info_pressed.emit(current_data)
	)

	# Upgrades complete immediately after the server accepts payment.
	if b_lvl < max_lvl:
		var upg_btn := _add_action_button("\u2b06\ufe0f", "N\u00e2ng c\u1ea5p", Color(0.95, 0.82, 0.35), func():
			upgrade_pressed.emit(current_data)
		)
		upg_btn.disabled = (status != "READY")
	else:
		var max_btn := _add_action_button("\u2b50", "C\u1ea5p T\u1ed1i \u0110a", Color(0.7, 0.7, 0.7), func(): pass)
		max_btn.disabled = true

	# 3. Primary Facility Action Button
	_add_facility_action_button(b_code, b_lvl)

	# 4. [👷] Nhân sự Button (if facility supports workers)
	if max_w > 0:
		var w_text := "Nhân sự (%d/%d)" % [workers.size(), max_w]
		var w_col := Color(0.45, 0.95, 0.65) if workers.size() < max_w else Color(0.5, 0.8, 1.0)
		_add_action_button("👷", w_text, w_col, func():
			workers_pressed.emit(current_data)
		)

	# 5. [🌾] Thu hoạch Button (if passive stored > 0)
	if stored >= 1.0 and res_type != "":
		_add_action_button("🌾", "Thu hoạch (+%d)" % int(floor(stored)), Color(1.0, 0.85, 0.35), func():
			collect_pressed.emit(current_data)
		)

	_animate_open()

## Show action bar for empty plot
func show_empty_plot(plot_idx: int, zone_idx: int) -> void:
	plot_index = plot_idx
	zone_index = zone_idx
	is_plot_empty = true
	is_plot_locked = false

	title_label.text = "🟩 Ô Công Trình Trống #%d" % plot_idx
	subtitle_label.text = "• Vị trí: Tầng Sảnh Chờ #%d" % zone_idx
	subtitle_label.modulate = Color(0.65, 0.85, 1.0)

	_clear_buttons()

	_add_action_button("🔨", "Xây dựng", Color(0.4, 0.95, 0.6), func():
		build_pressed.emit({"plot_index": plot_index, "zone_index": zone_index})
	)

	_animate_open()

## Show action bar for locked zone plot
func show_locked_plot(plot_idx: int, zone_idx: int, cost: int, can_unlock: bool) -> void:
	plot_index = plot_idx
	zone_index = zone_idx
	is_plot_empty = false
	is_plot_locked = true

	title_label.text = "🔒 Ô Công Trình Chưa Mở #%d" % plot_idx
	subtitle_label.text = "• Thuộc Tầng Sảnh Chờ #%d" % zone_idx
	subtitle_label.modulate = Color(1.0, 0.65, 0.45)

	_clear_buttons()

	var unlock_btn := _add_action_button("🏗️", "Mở Tầng #%d (🪙 %d)" % [zone_idx, cost], Color(0.95, 0.82, 0.35), func():
		expand_zone_pressed.emit(zone_index)
	)
	unlock_btn.disabled = not can_unlock

	_animate_open()

func _add_facility_action_button(code: String, _lvl: int) -> void:
	match code:
		"SHOP_AIRSHIP":
			_add_action_button("🎈", "Cửa hàng", Color(0.95, 0.75, 0.35), func():
				facility_action_pressed.emit(current_data, "SHOP_AIRSHIP")
			)
		"HERO_CHRONICLE":
			_add_action_button("📖", "Sử Điện Anh Hùng", Color(0.9, 0.75, 0.35), func():
				facility_action_pressed.emit(current_data, "HERO_CHRONICLE")
			)
		"KITCHEN":
			_add_action_button("🍳", "Nấu ăn & Bữa tiệc", Color(1.0, 0.65, 0.3), func():
				facility_action_pressed.emit(current_data, "KITCHEN")
			)
		"MEDICAL":
			_add_action_button("🏥", "Hồi phục y tế", Color(0.4, 0.95, 0.7), func():
				facility_action_pressed.emit(current_data, "MEDICAL")
			)
		"WAREHOUSE":
			_add_action_button("📦", "Kho trang bị", Color(0.4, 0.8, 1.0), func():
				facility_action_pressed.emit(current_data, "WAREHOUSE")
			)
		"FORGE":
			_add_action_button("⚒️", "Xưởng rèn", Color(1.0, 0.55, 0.35), func():
				facility_action_pressed.emit(current_data, "FORGE")
			)
		"HOUSE", "PARTY_MANSION":
			_add_action_button("🛏️", "Nghỉ ngơi", Color(0.55, 0.85, 1.0), func():
				facility_action_pressed.emit(current_data, "DORMITORY")
			)
		"TRAINING_CENTER":
			_add_action_button("🎯", "Huấn luyện", Color(0.95, 0.45, 0.45), func():
				facility_action_pressed.emit(current_data, "TRAINING")
			)
		"HALL_OF_MAGIC":
			_add_action_button("🔮", "Đại sảnh ma thuật", Color(0.85, 0.65, 1.0), func():
				facility_action_pressed.emit(current_data, "HALL_OF_MAGIC")
			)

func _add_action_button(icon_text: String, label_text: String, accent_color: Color, on_click: Callable) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(85, 68)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.10, 0.14, 0.20, 0.92)
	btn_style.border_width_left = 1
	btn_style.border_width_top = 1
	btn_style.border_width_right = 1
	btn_style.border_width_bottom = 1
	btn_style.border_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.55)
	btn_style.corner_radius_top_left = 10
	btn_style.corner_radius_top_right = 10
	btn_style.corner_radius_bottom_left = 10
	btn_style.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.15, 0.22, 0.32, 0.98)
	btn_hover.border_width_left = 2
	btn_hover.border_width_top = 2
	btn_hover.border_width_right = 2
	btn_hover.border_width_bottom = 2
	btn_hover.border_color = accent_color
	btn_hover.corner_radius_top_left = 10
	btn_hover.corner_radius_top_right = 10
	btn_hover.corner_radius_bottom_left = 10
	btn_hover.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("hover", btn_hover)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vb)

	var icon_lbl := Label.new()
	icon_lbl.text = icon_text
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 20)
	vb.add_child(icon_lbl)

	var sub_lbl := Label.new()
	sub_lbl.text = label_text
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 10)
	sub_lbl.add_theme_color_override("font_color", accent_color)
	vb.add_child(sub_lbl)

	btn.pressed.connect(on_click)
	buttons_container.add_child(btn)
	return btn

## Show action bar for major landmarks (Summon Altar, Barracks/Strategic House, Infirmary/Recovery Center, Fountain, East Gate)
func show_landmark(code: String, title: String, subtitle: String, actions: Array = []) -> void:
	current_data = {"landmark_code": code, "typeName": title, "buildingType": code, "is_landmark": true}
	is_plot_empty = false
	is_plot_locked = false

	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.modulate = Color(0.65, 0.9, 1.0)

	_clear_buttons()

	for act in actions:
		var a_icon: String = str(act.get("icon", "⚡"))
		var a_label: String = str(act.get("label", "Hành động"))
		var a_col: Color = act.get("color", Color(0.3, 0.75, 1.0))
		var a_call: Callable = act.get("callback", func(): pass)
		var a_dis: bool = bool(act.get("disabled", false))
		var btn := _add_action_button(a_icon, a_label, a_col, a_call)
		btn.disabled = a_dis

	_animate_open()

func _clear_buttons() -> void:
	if buttons_container != null:
		for c in buttons_container.get_children():
			c.queue_free()

func _animate_open() -> void:
	visible = true
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.18)

func _close() -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.12)
	tw.tween_callback(func():
		visible = false
		closed.emit()
	)

func _get_building_icon(code: String) -> String:
	match code:
		"SHOP_AIRSHIP": return "🎈"
		"KITCHEN": return "🍖"
		"MEDICAL": return "✚"
		"FORGE": return "⚒️"
		"WAREHOUSE": return "📦"
		"HOUSE": return "🏠"
		"PARTY_MANSION": return "🏰"
		"TRAINING_CENTER": return "🎯"
		"HALL_OF_MAGIC": return "🔮"
		"LIBRARY": return "📚"
		"ALCHEMY_WORKSHOP": return "⚗️"
		"MAGIC_RESEARCH_LAB": return "✨"
		_: return "🏛️"
