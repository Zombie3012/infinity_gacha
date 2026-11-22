class_name BuildingUpgradePopup
extends Control

## Building Upgrade Popup [⬆️] - Clash of Clans Style
## Shows current level vs next level stats comparison, required materials (Silver, Wood, Stone),
## and immediate upgrade confirmation.

signal closed
signal upgrade_confirmed(building_data: Dictionary)

var building_data: Dictionary = {}
var building_code: String = ""
var building_name: String = ""
var building_level: int = 1
var max_level: int = 3
var target_level: int = 2

var req_silver: int = 0
var req_wood: int = 0
var req_stone: int = 0
var can_afford: bool = false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(data: Dictionary, blueprint_build_cost: int = 1000) -> void:
	building_data = data
	building_code = str(data.get("buildingType", ""))
	building_name = str(data.get("typeName", building_code))
	building_level = int(data.get("level", 1))
	max_level = int(data.get("maxLevel", 3))
	target_level = building_level + 1

	req_silver = int(round(float(blueprint_build_cost) * float(maxi(2, target_level)) * 0.75))
	req_wood = 10 * maxi(2, target_level)
	req_stone = 5 * maxi(2, target_level)

	var cur_silver: int = GameState.silver_coins
	var cur_wood: int = int(GameState.materials.get("WOOD", 0))
	var cur_stone: int = int(GameState.materials.get("STONE", 0))

	can_afford = (cur_silver >= req_silver and cur_wood >= req_wood and cur_stone >= req_stone)
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

	# 2. Centered Window
	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_wrap)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 490)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.35, 0.85, 1.0, 0.9) # Cyan/Blue accent border
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	pstyle.shadow_size = 12
	pstyle.shadow_color = Color(0, 0, 0, 0.6)
	panel.add_theme_stylebox_override("panel", pstyle)
	center_wrap.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# --- Header Row ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_vbox)

	var name_lbl := Label.new()
	name_lbl.text = "⬆️ NÂNG CẤP %s" % building_name.to_upper()
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_vbox.add_child(name_lbl)

	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 8)
	title_vbox.add_child(lvl_row)

	var cur_lvl_pill := _create_level_pill("Lv.%d" % building_level, Color(0.3, 0.4, 0.55))
	var arrow_lbl := Label.new()
	arrow_lbl.text = "➔"
	arrow_lbl.add_theme_font_size_override("font_size", 14)
	arrow_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	var next_lvl_pill := _create_level_pill("Lv.%d" % target_level, Color(0.2, 0.65, 0.4))

	lvl_row.add_child(cur_lvl_pill)
	lvl_row.add_child(arrow_lbl)
	lvl_row.add_child(next_lvl_pill)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var hsep1 := HSeparator.new()
	vbox.add_child(hsep1)

	# --- Stats Comparison Table ---
	var comp_title := Label.new()
	comp_title.text = "📈 THAY ĐỔI CHỈ SỐ KHI NÂNG CẤP"
	comp_title.add_theme_font_size_override("font_size", 13)
	comp_title.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	vbox.add_child(comp_title)

	var comp_box := PanelContainer.new()
	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.04, 0.06, 0.10, 0.9)
	cstyle.corner_radius_top_left = 8
	cstyle.corner_radius_top_right = 8
	cstyle.corner_radius_bottom_left = 8
	cstyle.corner_radius_bottom_right = 8
	comp_box.add_theme_stylebox_override("panel", cstyle)
	vbox.add_child(comp_box)

	var comp_margin := MarginContainer.new()
	comp_margin.add_theme_constant_override("margin_left", 14)
	comp_margin.add_theme_constant_override("margin_right", 14)
	comp_margin.add_theme_constant_override("margin_top", 10)
	comp_margin.add_theme_constant_override("margin_bottom", 10)
	comp_box.add_child(comp_margin)

	var comp_vbox := VBoxContainer.new()
	comp_vbox.add_theme_constant_override("separation", 8)
	comp_margin.add_child(comp_vbox)

	var comparisons := _get_upgrade_comparisons(building_code, building_level, target_level)
	for comp in comparisons:
		var row := HBoxContainer.new()
		var l_lbl := Label.new()
		l_lbl.text = str(comp.get("label", ""))
		l_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l_lbl.add_theme_font_size_override("font_size", 12)
		l_lbl.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
		row.add_child(l_lbl)

		var cur_val_lbl := Label.new()
		cur_val_lbl.text = str(comp.get("cur", ""))
		cur_val_lbl.add_theme_font_size_override("font_size", 12)
		cur_val_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		row.add_child(cur_val_lbl)

		var arr := Label.new()
		arr.text = " ➔ "
		arr.add_theme_font_size_override("font_size", 12)
		arr.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
		row.add_child(arr)

		var nxt_val_lbl := Label.new()
		nxt_val_lbl.text = str(comp.get("next", ""))
		nxt_val_lbl.add_theme_font_size_override("font_size", 12)
		nxt_val_lbl.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
		row.add_child(nxt_val_lbl)
		comp_vbox.add_child(row)

	# --- Required Materials Section ---
	var cost_title := Label.new()
	cost_title.text = "🪵 NGUYÊN LIỆU YÊU CẦU"
	cost_title.add_theme_font_size_override("font_size", 13)
	cost_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	vbox.add_child(cost_title)

	var cost_row := HBoxContainer.new()
	cost_row.add_theme_constant_override("separation", 10)
	vbox.add_child(cost_row)

	var cur_silver := GameState.silver_coins
	var cur_wood := int(GameState.materials.get("WOOD", 0))
	var cur_stone := int(GameState.materials.get("STONE", 0))

	cost_row.add_child(_create_cost_pill("🪙 Bạc", cur_silver, req_silver))
	cost_row.add_child(_create_cost_pill("🪵 Gỗ", cur_wood, req_wood))
	cost_row.add_child(_create_cost_pill("🪨 Đá", cur_stone, req_stone))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var hsep2 := HSeparator.new()
	vbox.add_child(hsep2)

	# --- Upgrade Confirm Button ---
	var confirm_btn := Button.new()
	confirm_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_btn.custom_minimum_size = Vector2(0, 42)
	confirm_btn.text = "⬆️ NÂNG CẤP LÊN CẤP %d" % target_level if can_afford else "❌ THIẾU NGUYÊN LIỆU NÂNG CẤP"
	confirm_btn.disabled = not can_afford
	if can_afford:
		confirm_btn.modulate = Color(0.4, 1.0, 0.6)
	else:
		confirm_btn.modulate = Color(0.85, 0.85, 0.85)

	confirm_btn.pressed.connect(func():
		upgrade_confirmed.emit(building_data)
		_close()
	)
	vbox.add_child(confirm_btn)

func _close() -> void:
	closed.emit()
	queue_free()

func _create_level_pill(text: String, bg_col: Color) -> PanelContainer:
	var pill := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = bg_col
	ps.corner_radius_top_left = 4
	ps.corner_radius_top_right = 4
	ps.corner_radius_bottom_left = 4
	ps.corner_radius_bottom_right = 4
	pill.add_theme_stylebox_override("panel", ps)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 2)
	m.add_theme_constant_override("margin_bottom", 2)
	pill.add_child(m)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	m.add_child(l)
	return pill

func _create_cost_pill(item_name: String, current: int, required: int) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_enough := current >= required
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.12, 0.08, 0.95) if is_enough else Color(0.16, 0.06, 0.06, 0.95)
	ps.border_width_left = 1
	ps.border_width_top = 1
	ps.border_width_right = 1
	ps.border_width_bottom = 1
	ps.border_color = Color(0.3, 0.8, 0.4, 0.8) if is_enough else Color(0.9, 0.3, 0.3, 0.8)
	ps.corner_radius_top_left = 6
	ps.corner_radius_top_right = 6
	ps.corner_radius_bottom_left = 6
	ps.corner_radius_bottom_right = 6
	pill.add_theme_stylebox_override("panel", ps)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 6)
	m.add_theme_constant_override("margin_bottom", 6)
	pill.add_child(m)

	var vb := VBoxContainer.new()
	m.add_child(vb)

	var tlbl := Label.new()
	tlbl.text = item_name
	tlbl.add_theme_font_size_override("font_size", 11)
	tlbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98))
	vb.add_child(tlbl)

	var vlbl := Label.new()
	vlbl.text = "%d / %d" % [current, required]
	vlbl.add_theme_font_size_override("font_size", 11)
	vlbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55) if is_enough else Color(1.0, 0.45, 0.45))
	vb.add_child(vlbl)

	return pill

func _get_upgrade_comparisons(code: String, cur_lvl: int, nxt_lvl: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	match code:
		"KITCHEN":
			var cur_rate := 20 if cur_lvl <= 1 else (40 if cur_lvl == 2 else 80)
			var nxt_rate := 20 if nxt_lvl <= 1 else (40 if nxt_lvl == 2 else 80)
			list.append({"label": "Tốc độ sản xuất lương thực", "cur": "+%d FOOD/h" % cur_rate, "next": "+%d FOOD/h" % nxt_rate})
			list.append({"label": "Sức chứa kho lương thực", "cur": "%d" % (cur_rate * 10), "next": "%d" % (nxt_rate * 10)})
			list.append({"label": "Số Hero làm việc tối đa", "cur": "%d người" % cur_lvl, "next": "%d người" % nxt_lvl})
		"MEDICAL":
			list.append({"label": "Số giường chữa trị mở", "cur": "%d giường" % (cur_lvl * 2), "next": "%d giường" % (nxt_lvl * 2)})
		"WAREHOUSE":
			list.append({"label": "Số ô chứa trang bị mở thêm", "cur": "+%d ô" % (cur_lvl * 100), "next": "+%d ô" % (nxt_lvl * 100)})
		"HOUSE":
			var cur_c := 5 if cur_lvl <= 1 else (7 if cur_lvl == 2 else 10)
			var nxt_c := 5 if nxt_lvl <= 1 else (7 if nxt_lvl == 2 else 10)
			var cur_m := 1.0 if cur_lvl <= 1 else (1.5 if cur_lvl == 2 else 2.0)
			var nxt_m := 1.0 if nxt_lvl <= 1 else (1.5 if nxt_lvl == 2 else 2.0)
			list.append({"label": "Sức chứa phòng cư trú", "cur": "%d người" % cur_c, "next": "%d người" % nxt_c})
			list.append({"label": "Tốc độ hồi phục thể lực", "cur": "%.1fx" % cur_m, "next": "%.1fx" % nxt_m})
		"TRAINING_CENTER":
			var cur_s := 3 if cur_lvl <= 1 else (5 if cur_lvl == 2 else 7)
			var nxt_s := 3 if nxt_lvl <= 1 else (5 if nxt_lvl == 2 else 7)
			list.append({"label": "Số vị trí huấn luyện", "cur": "%d Hero" % cur_s, "next": "%d Hero" % nxt_s})
		"FORGE":
			list.append({"label": "Thợ rèn phụ trách", "cur": "%d Hero" % cur_lvl, "next": "%d Hero" % nxt_lvl})
		"LIBRARY":
			var cur_r := 100 if cur_lvl <= 1 else (50 if cur_lvl == 2 else 15)
			var nxt_r := 100 if nxt_lvl <= 1 else (50 if nxt_lvl == 2 else 15)
			list.append({"label": "Sản xuất Sách EXP", "cur": "+%d/h" % cur_r, "next": "+%d/h" % nxt_r})
		"ALCHEMY_WORKSHOP":
			var cur_r := 15 if cur_lvl <= 1 else (30 if cur_lvl == 2 else 60)
			var nxt_r := 15 if nxt_lvl <= 1 else (30 if nxt_lvl == 2 else 60)
			list.append({"label": "Sản xuất Đá Cường Hóa", "cur": "+%d/h" % cur_r, "next": "+%d/h" % nxt_r})
		_:
			list.append({"label": "Cấp độ công trình", "cur": "Cấp %d" % cur_lvl, "next": "Cấp %d" % nxt_lvl})
	return list
