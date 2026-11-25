class_name BuildingConstructionModal
extends Control

## Building Construction Modal - Clash of Clans Style
## Shows available building blueprints with clean cards, cost, requirements,
## and 1-click construction confirmation.

signal closed
signal construction_requested(building_code: String, plot_index: int)

var plot_index: int = -1
var zone_index: int = 1

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(p_idx: int, z_idx: int) -> void:
	plot_index = p_idx
	zone_index = z_idx
	_build_ui()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.06, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	# 2. Main Centered Window
	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_wrap)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 520)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.95, 0.78, 0.28, 0.9)
	pstyle.corner_radius_top_left = 14
	pstyle.corner_radius_top_right = 14
	pstyle.corner_radius_bottom_left = 14
	pstyle.corner_radius_bottom_right = 14
	pstyle.shadow_size = 14
	pstyle.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", pstyle)
	center_wrap.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# --- Header Row ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "🔨 DANH MỤC XÂY DỰNG CÔNG TRÌNH"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "Ô #%d (Tầng %d) • 🪙 %s Bạc" % [plot_index, zone_index, _format_number(GameState.silver_coins)]
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	header.add_child(subtitle_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var hsep := HSeparator.new()
	vbox.add_child(hsep)

	# --- Blueprints Scroll Grid ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	var b_types: Array = GameState.base_overview.get("buildingTypes", [])
	for bt in b_types:
		if not (bt is Dictionary):
			continue
		var card := _create_blueprint_card(bt)
		grid.add_child(card)

func _create_blueprint_card(bt: Dictionary) -> PanelContainer:
	var code := str(bt.get("code", ""))
	var bname := str(bt.get("name", code))
	var desc_txt := str(bt.get("description", ""))
	var cost := int(bt.get("buildCostSilver", 1000))
	var req_floor := int(bt.get("requiredTowerFloor", 0))
	var unlocked := bool(bt.get("unlocked", true))
	var max_w := int(bt.get("maxWorkers", 0))

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(340, 130)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.05, 0.07, 0.10, 0.95)
	cstyle.border_width_left = 1
	cstyle.border_width_top = 1
	cstyle.border_width_right = 1
	cstyle.border_width_bottom = 1
	cstyle.border_color = Color(0.95, 0.78, 0.28, 0.4) if unlocked else Color(0.4, 0.4, 0.4, 0.3)
	cstyle.corner_radius_top_left = 8
	cstyle.corner_radius_top_right = 8
	cstyle.corner_radius_bottom_left = 8
	cstyle.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", cstyle)

	var cm := MarginContainer.new()
	cm.add_theme_constant_override("margin_left", 12)
	cm.add_theme_constant_override("margin_right", 12)
	cm.add_theme_constant_override("margin_top", 10)
	cm.add_theme_constant_override("margin_bottom", 10)
	card.add_child(cm)

	var cvb := VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 4)
	cm.add_child(cvb)

	var top_row := HBoxContainer.new()
	cvb.add_child(top_row)

	var icon_lbl := Label.new()
	icon_lbl.text = _get_icon(code)
	icon_lbl.add_theme_font_size_override("font_size", 20)
	top_row.add_child(icon_lbl)

	var title_lbl := Label.new()
	title_lbl.text = bname
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6) if unlocked else Color(0.65, 0.65, 0.65))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = "🪙 %s Bạc" % _format_number(cost)
	cost_lbl.add_theme_font_size_override("font_size", 12)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35) if GameState.silver_coins >= cost else Color(1.0, 0.4, 0.4))
	top_row.add_child(cost_lbl)

	var d_lbl := Label.new()
	d_lbl.text = desc_txt
	d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d_lbl.add_theme_font_size_override("font_size", 10)
	d_lbl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	d_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cvb.add_child(d_lbl)

	var action_row := HBoxContainer.new()
	cvb.add_child(action_row)

	var req_lbl := Label.new()
	req_lbl.text = "Vượt Tháp tầng %d | %d Hero" % [req_floor, max_w] if req_floor > 0 else "Mở từ đầu | %d Hero" % max_w
	req_lbl.add_theme_font_size_override("font_size", 10)
	req_lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	req_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(req_lbl)

	var can_build := unlocked and (GameState.silver_coins >= cost)
	var build_btn := Button.new()
	build_btn.custom_minimum_size = Vector2(90, 28)
	build_btn.text = "Xây Ngay" if can_build else ("Chưa mở" if not unlocked else "Thiếu Bạc")
	build_btn.disabled = not can_build
	build_btn.modulate = Color(0.4, 1.0, 0.6) if can_build else Color(0.7, 0.7, 0.7)
	build_btn.pressed.connect(func():
		construction_requested.emit(code, plot_index)
		_close()
	)
	action_row.add_child(build_btn)

	return card

func _close() -> void:
	closed.emit()
	queue_free()

func _format_number(val: int) -> String:
	if val >= 1_000_000:
		return "%.1fM" % (float(val) / 1_000_000.0)
	elif val >= 10_000:
		return "%.1fK" % (float(val) / 1000.0)
	return str(val)

func _get_icon(code: String) -> String:
	match code:
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
