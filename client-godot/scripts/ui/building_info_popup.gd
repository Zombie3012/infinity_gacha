class_name BuildingInfoPopup
extends Control

## Building Info Popup [i] - Clash of Clans Style
## Clean, player-oriented information dialog showing building art, lore, current stats,
## and safe demolition options away from accidental clicks.

signal closed
signal demolish_requested(building_data: Dictionary)

var building_data: Dictionary = {}
var building_code: String = ""
var building_name: String = ""
var building_level: int = 1
var max_level: int = 3

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(data: Dictionary) -> void:
	building_data = data
	building_code = str(data.get("buildingType", ""))
	building_name = str(data.get("typeName", building_code))
	building_level = int(data.get("level", 1))
	max_level = int(data.get("maxLevel", 3))
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
	panel.custom_minimum_size = Vector2(460, 480)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.08, 0.10, 0.15, 0.98)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.95, 0.78, 0.28, 0.9) # Gold border
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	pstyle.shadow_size = 12
	pstyle.shadow_color = Color(0, 0, 0, 0.6)
	panel.add_theme_stylebox_override("panel", pstyle)
	center_wrap.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# --- Header Row ---
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var icon_lbl := Label.new()
	icon_lbl.text = _get_building_icon(building_code)
	icon_lbl.add_theme_font_size_override("font_size", 28)
	header.add_child(icon_lbl)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_vbox)

	var name_lbl := Label.new()
	name_lbl.text = "%s" % building_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_vbox.add_child(name_lbl)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Cấp độ: Cấp %d / %d" % [building_level, max_level]
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	title_vbox.add_child(lvl_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	var hsep1 := HSeparator.new()
	vbox.add_child(hsep1)

	# --- Lore / Description Card ---
	var desc_box := PanelContainer.new()
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.04, 0.06, 0.10, 0.85)
	dstyle.corner_radius_top_left = 8
	dstyle.corner_radius_top_right = 8
	dstyle.corner_radius_bottom_left = 8
	dstyle.corner_radius_bottom_right = 8
	desc_box.add_theme_stylebox_override("panel", dstyle)
	vbox.add_child(desc_box)

	var desc_margin := MarginContainer.new()
	desc_margin.add_theme_constant_override("margin_left", 14)
	desc_margin.add_theme_constant_override("margin_right", 14)
	desc_margin.add_theme_constant_override("margin_top", 10)
	desc_margin.add_theme_constant_override("margin_bottom", 10)
	desc_box.add_child(desc_margin)

	var desc_lbl := Label.new()
	desc_lbl.text = _get_player_lore_description(building_code)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
	desc_margin.add_child(desc_lbl)

	# --- Current Stats Section ---
	var stats_title := Label.new()
	stats_title.text = "📊 CHỈ SỐ CÔNG TRÌNH HIỆN TẠI"
	stats_title.add_theme_font_size_override("font_size", 13)
	stats_title.add_theme_color_override("font_color", Color(0.95, 0.80, 0.35))
	vbox.add_child(stats_title)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 6)
	vbox.add_child(stats_vbox)

	var stats := _get_building_stats_display(building_code, building_level)
	for s in stats:
		var row := HBoxContainer.new()
		var s_lbl := Label.new()
		s_lbl.text = str(s.get("label", ""))
		s_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s_lbl.add_theme_font_size_override("font_size", 12)
		s_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
		row.add_child(s_lbl)

		var v_lbl := Label.new()
		v_lbl.text = str(s.get("val", ""))
		v_lbl.add_theme_font_size_override("font_size", 12)
		v_lbl.add_theme_color_override("font_color", s.get("col", Color(0.4, 0.95, 0.6)))
		row.add_child(v_lbl)
		stats_vbox.add_child(row)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var hsep2 := HSeparator.new()
	vbox.add_child(hsep2)

	# --- Danger Zone (Demolish) ---
	var demo_row := HBoxContainer.new()
	vbox.add_child(demo_row)

	var demo_btn := Button.new()
	demo_btn.text = "🏚️ Phá Dỡ Công Trình (Hoàn 50% Bạc)"
	demo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	demo_btn.custom_minimum_size = Vector2(0, 36)
	demo_btn.modulate = Color(1.0, 0.55, 0.55)
	demo_btn.pressed.connect(func():
		demolish_requested.emit(building_data)
		_close()
	)
	demo_row.add_child(demo_btn)

func _close() -> void:
	closed.emit()
	queue_free()

func _get_building_icon(code: String) -> String:
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

func _get_player_lore_description(code: String) -> String:
	match code:
		"KITCHEN":
			return "Nhà Bếp tự động nấu nướng và lưu trữ lương thực quân lương cho toàn bộ căn cứ. Bếp hoạt động liên tục đảm bảo anh hùng không bị suy giảm thể lực khi xuất trận."
		"MEDICAL":
			return "Trung tâm y tế cao cấp với các giường điều trị chuyên dụng, tiếp nhận và chữa trị dứt điểm mọi chấn thương nặng nề của anh hùng sau các chuyến thám hiểm."
		"FORGE":
			return "Xưởng rèn ma thuật nơi tinh luyện kim loại, chế tác vũ khí và áo giáp uy lực, hỗ trợ cường hóa chỉ số và ghép sao trang bị đỉnh cao."
		"WAREHOUSE":
			return "Kho lưu trữ vật tư và quân trang an toàn của căn cứ. Nâng cấp nhà kho để mở rộng thêm nhiều ô chứa trang bị và bảo quản chiến lợi phẩm."
		"HOUSE":
			return "Khu ký túc xá ấm cúng cho các anh hùng nghỉ dưỡng, phục hồi thể lực và xóa tan mệt mỏi sau những trận chiến cam go."
		"PARTY_MANSION":
			return "Biệt thự sang trọng độc lập dành riêng cho tổ đội chủ lực, tăng tốc độ phục hồi thể lực và tinh thần lên mức tối đa."
		"TRAINING_CENTER":
			return "Khu huấn luyện thực chiến chuyên sâu, giúp các anh hùng rèn luyện cơ bắp và gia tăng các chỉ số gốc STR, AGI, INT, STA."
		"LIBRARY":
			return "Thư viện lưu giữ cổ thư ma đạo. Các Pháp Sư (Mage) nghiên cứu tại đây sẽ tự động in ấn Sách Kinh Nghiệm và đột phá cấp độ nhanh chóng."
		"ALCHEMY_WORKSHOP":
			return "Xưởng giả kim chuyên điều chế Đá Cường Hóa ma thuật, chưng cất dược phẩm hồi phục và tinh chế nguyên liệu quý hiếm."
		"MAGIC_RESEARCH_LAB":
			return "Phòng nghiên cứu cấm thuật cao cấp, đảm nhiệm các nghi thức Chuyển Chức và Thức Tỉnh sức mạnh tiềm ẩn của các anh hùng."
		"HALL_OF_MAGIC":
			return "Đại sảnh ma thuật tối thượng kết nối Thư Viện, Xưởng Giả Kim và Phòng Nghiên Cứu dưới một mái vòm kỳ vĩ."
		_:
			return "Công trình chức năng trong Lâu Đài Sảnh Chờ của Master."

func _get_building_stats_display(code: String, lvl: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	match code:
		"KITCHEN":
			var rate := 20 if lvl <= 1 else (40 if lvl == 2 else 80)
			var cap := rate * 10
			list.append({"label": "Tốc độ sản xuất lương thực:", "val": "+%d FOOD / giờ" % rate, "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Sức chứa kho lương thực:", "val": "%d FOOD" % cap, "col": Color(1.0, 0.85, 0.4)})
			list.append({"label": "Số Hero đầu bếp tối đa:", "val": "%d Hero" % clampi(lvl, 1, 3), "col": Color(0.65, 0.85, 1.0)})
		"MEDICAL":
			var beds := lvl * 2
			list.append({"label": "Số giường chữa trị mở:", "val": "%d Giường" % beds, "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Bác sĩ phụ trách:", "val": "1 Hero", "col": Color(0.65, 0.85, 1.0)})
		"WAREHOUSE":
			var slots := lvl * 100
			list.append({"label": "Không gian kho mở thêm:", "val": "+%d Ô trang bị" % slots, "col": Color(0.4, 0.95, 0.6)})
		"HOUSE":
			var cap := 5 if lvl <= 1 else (7 if lvl == 2 else 10)
			var mult := 1.0 if lvl <= 1 else (1.5 if lvl == 2 else 2.0)
			list.append({"label": "Sức chứa cư trú:", "val": "%d Người" % cap, "col": Color(0.65, 0.85, 1.0)})
			list.append({"label": "Tốc độ hồi phục thể lực:", "val": "%.1fx (-%.1f Mệt mỏi/giờ)" % [mult, 15.0 * mult], "col": Color(0.4, 0.95, 0.6)})
		"PARTY_MANSION":
			list.append({"label": "Sức chứa tổ đội:", "val": "5 Người (Cố định)", "col": Color(0.65, 0.85, 1.0)})
			list.append({"label": "Tốc độ hồi phục thể lực:", "val": "4.0x (-60 Mệt mỏi/giờ)", "col": Color(0.4, 0.95, 0.6)})
		"FORGE":
			list.append({"label": "Cấp độ lò rèn:", "val": "Cấp %d / 3" % lvl, "col": Color(1.0, 0.85, 0.4)})
			list.append({"label": "Thợ rèn phụ trách:", "val": "%d Hero" % clampi(lvl, 1, 3), "col": Color(0.65, 0.85, 1.0)})
		"TRAINING_CENTER":
			var slots := 3 if lvl <= 1 else (5 if lvl == 2 else 7)
			list.append({"label": "Số vị trí huấn luyện:", "val": "%d Hero" % slots, "col": Color(0.4, 0.95, 0.6)})
		"LIBRARY":
			var rate := 100 if lvl <= 1 else (50 if lvl == 2 else 15)
			var bname := "Sơ cấp" if lvl <= 1 else ("Trung cấp" if lvl == 2 else "Cao cấp")
			list.append({"label": "Sản xuất Sách EXP (%s):" % bname, "val": "+%d Cuốn / giờ" % rate, "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Pháp sư phụ trách (MAGE):", "val": "Tối đa 2 Hero", "col": Color(0.65, 0.85, 1.0)})
		"ALCHEMY_WORKSHOP":
			var rate := 15 if lvl <= 1 else (30 if lvl == 2 else 60)
			list.append({"label": "Sản xuất Đá Cường Hóa:", "val": "+%d Viên / giờ" % rate, "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Dược sĩ phụ trách:", "val": "Tối đa 2 Hero", "col": Color(0.65, 0.85, 1.0)})
		_:
			list.append({"label": "Cấp công trình:", "val": "Cấp %d" % lvl, "col": Color(0.4, 0.95, 0.6)})
	return list
