class_name BuildingInfoPopup
extends Control

## Building Info Popup [i] - Clash of Clans Style
## Clean, player-oriented information dialog showing building art, lore, current stats,
## and safe demolition options away from accidental clicks.

signal closed
signal demolish_requested(building_data: Dictionary)
signal worker_remove_requested(building_id: String, hero_id: String, hero_name: String)

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

	if building_code in ["HOUSE", "PARTY_MANSION"]:
		var occ_title := Label.new()
		occ_title.text = "🛏️ DANH SÁCH HERO ĐANG Ở BÊN TRONG"
		occ_title.add_theme_font_size_override("font_size", 13)
		occ_title.add_theme_color_override("font_color", Color(0.55, 0.90, 1.0))
		vbox.add_child(occ_title)

		var occ_scroll := ScrollContainer.new()
		occ_scroll.custom_minimum_size = Vector2(0, 110)
		occ_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		vbox.add_child(occ_scroll)

		var occ_list := VBoxContainer.new()
		occ_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		occ_list.add_theme_constant_override("separation", 4)
		occ_scroll.add_child(occ_list)

		var resting_heroes := _get_resting_heroes()
		if resting_heroes.is_empty():
			var empty_lbl := Label.new()
			empty_lbl.text = "Hiện chưa có Hero nào đang nghỉ ngơi bên trong."
			empty_lbl.add_theme_font_size_override("font_size", 12)
			empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
			occ_list.add_child(empty_lbl)
		else:
			for h in resting_heroes:
				var h_lbl := Label.new()
				var rest_tag := "💤 Đang nghỉ" if (bool(h.get("isResting", false)) or str(h.get("state", "")) == "RESTING") else "Thức"
				h_lbl.text = "• %s (%d★ · Lv.%d) — %s · Mệt mỏi: %d%%" % [
					str(h.get("name", "Hero")),
					int(h.get("rarity", 1)),
					int(h.get("level", 1)),
					rest_tag,
					int(float(h.get("fatigue", 0)))
				]
				h_lbl.add_theme_font_size_override("font_size", 12)
				h_lbl.add_theme_color_override("font_color", Color(0.82, 0.94, 1.0))
				occ_list.add_child(h_lbl)

	var workers_val: Variant = building_data.get("workers", [])
	var workers_arr: Array = workers_val if workers_val is Array else []
	var max_w := int(building_data.get("maxWorkers", 0))
	if max_w > 0 or not workers_arr.is_empty():
		var w_title := Label.new()
		w_title.text = "👷 NHÂN CÔNG ĐANG LÀM VIỆC (%d / %d)" % [workers_arr.size(), maxi(max_w, workers_arr.size())]
		w_title.add_theme_font_size_override("font_size", 13)
		w_title.add_theme_color_override("font_color", Color(0.55, 0.96, 0.72))
		vbox.add_child(w_title)

		if workers_arr.is_empty():
			var no_w := Label.new()
			no_w.text = "Chưa có Hero nào được phân công."
			no_w.add_theme_font_size_override("font_size", 12)
			no_w.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
			vbox.add_child(no_w)
		else:
			var b_id := str(building_data.get("id", ""))
			for w in workers_arr:
				if not (w is Dictionary):
					continue
				var wid := str(w.get("heroInstanceId", w.get("heroId", "")))
				var wname := str(w.get("heroName", w.get("name", "Hero")))
				var w_row := HBoxContainer.new()
				w_row.add_theme_constant_override("separation", 8)
				vbox.add_child(w_row)
				var w_lbl := Label.new()
				w_lbl.text = "• %s" % wname
				w_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				w_lbl.add_theme_font_size_override("font_size", 12)
				w_lbl.add_theme_color_override("font_color", Color(0.88, 0.95, 1.0))
				w_row.add_child(w_lbl)
				var rem_btn := Button.new()
				rem_btn.text = "🚪 Giải phóng"
				rem_btn.custom_minimum_size = Vector2(110, 28)
				rem_btn.modulate = Color(1.0, 0.72, 0.55)
				rem_btn.pressed.connect(func():
					worker_remove_requested.emit(b_id, wid, wname)
					_close()
				)
				w_row.add_child(rem_btn)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	var hsep2 := HSeparator.new()
	vbox.add_child(hsep2)

	# --- Danger Zone (Demolish) ---
	var is_landmark: bool = bool(building_data.get("is_landmark", false))
	if not is_landmark:
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
		"MEDICAL", "INFIRMARY": return "✚"
		"FORGE": return "⚒️"
		"WAREHOUSE": return "📦"
		"HOUSE": return "🏠"
		"PARTY_MANSION": return "🏰"
		"TRAINING_CENTER": return "🎯"
		"HALL_OF_MAGIC": return "🔮"
		"LIBRARY": return "📚"
		"ALCHEMY_WORKSHOP": return "⚗️"
		"MAGIC_RESEARCH_LAB": return "✨"
		"SUMMON_ALTAR": return "✨"
		"BARRACKS": return "🛡️"
		"DUNGEON_PORTAL": return "⛩️"
		"FOUNTAIN", "BONFIRE": return "⛲"
		_: return "🏛️"

func _get_player_lore_description(code: String) -> String:
	match code:
		"SUMMON_ALTAR":
			return "Đài Triệu Hồi Linh Hồn Cổ Xưa. Nơi triệu thỉnh Anh Hùng theo tỉ lệ thuần (không Pity) với 2 loại Banner: Banner Thường (1★–3★ bằng Thiên Thư) và Banner Đặc Biệt (2★–5★ với 100 Gem/lần)."
		"BARRACKS":
			return "Nhà Chiến Lược & Doanh Trại Quân Sự. Trung tâm chỉ huy, điều động quân lực, lập đội hình xuất kích và thăng hoa sao cho các Anh Hùng."
		"INFIRMARY":
			return "Trung Tâm Hồi Phục Y Tế Hoàng Gia. Nơi các Y Sĩ chuyên trách điều trị vết thương sau chiến trận, hồi máu cấp tốc và duy trì thể trạng sung mãn."
		"DUNGEON_PORTAL":
			return "Cổng Tháp Thử Thách Vô Tận. Con đường tiến vào các tầng tháp hiểm nguy để thu thập tài nguyên, chiến lợi phẩm và chứng minh sức mạnh."
		"FOUNTAIN", "BONFIRE":
			return "Đài Phun Nước Trung Tâm Thành Phố. Trái tim của vương quốc, nơi điều hòa khí hậu và tập trung nguồn sinh lực dồi dào."
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
			var resting_cnt := _get_resting_heroes().size()
			list.append({"label": "Đang nghỉ ngơi bên trong:", "val": "%d / %d Người" % [resting_cnt, cap], "col": Color(0.55, 0.90, 1.0)})
			list.append({"label": "Sức chứa cư trú:", "val": "%d Người (Lv.1: 5 · Lv.2: 7 · Lv.3: 10)" % cap, "col": Color(0.65, 0.85, 1.0)})
			list.append({"label": "Tốc độ hồi phục thể lực:", "val": "%.1fx (-%.1f Mệt mỏi/giờ)" % [mult, 15.0 * mult], "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Chức năng:", "val": "Giảm mệt mỏi & phục hồi sức bền", "col": Color(1.0, 0.88, 0.45)})
		"PARTY_MANSION":
			var resting_cnt := _get_resting_heroes().size()
			list.append({"label": "Đang nghỉ ngơi bên trong:", "val": "%d / 5 Người" % resting_cnt, "col": Color(0.55, 0.90, 1.0)})
			list.append({"label": "Sức chứa tổ đội:", "val": "5 Người (Cố định)", "col": Color(0.65, 0.85, 1.0)})
			list.append({"label": "Tốc độ hồi phục thể lực:", "val": "4.0x (-60.0 Mệt mỏi/giờ)", "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Chức năng:", "val": "Biệt thự cao cấp hồi phục siêu tốc cho tổ đội", "col": Color(1.0, 0.88, 0.45)})
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
		"SUMMON_ALTAR":
			list.append({"label": "Thiên thư hiện có:", "val": "%s Cuốn" % _format_num(GameState.normal_scrolls), "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Đá Quý (Gems) hiện có:", "val": "%s Gem" % _format_num(GameState.gem_stones), "col": Color(0.55, 0.88, 1.0)})
			list.append({"label": "Bạc hiện có:", "val": "%s Bạc" % _format_num(GameState.silver_coins), "col": Color(1.0, 0.85, 0.4)})
		"BARRACKS":
			list.append({"label": "Tổng số Hero sở hữu:", "val": "%d Hero" % GameState.owned_hero_count(), "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Đội hình PVE xuất trận:", "val": "%d / 5 Hero" % GameState.active_party_ids.size(), "col": Color(1.0, 0.85, 0.4)})
		"INFIRMARY":
			list.append({"label": "Số giường chữa trị:", "val": "%d Giường" % (lvl * 2), "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Y sĩ phụ trách:", "val": "1 Hero", "col": Color(0.65, 0.85, 1.0)})
		"DUNGEON_PORTAL":
			list.append({"label": "Tầng tháp hiện tại:", "val": "Tầng %d" % GameState.current_floor, "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "World Level:", "val": "Level %d" % GameState.world_level, "col": Color(1.0, 0.85, 0.4)})
		"FOUNTAIN", "BONFIRE":
			list.append({"label": "Khẩu phần dự trữ:", "val": "%d FOOD" % int(GameState.materials.get("RATION", 0)), "col": Color(0.4, 0.95, 0.6)})
			list.append({"label": "Lương thực thô:", "val": "%d RAW_FOOD" % int(GameState.materials.get("RAW_FOOD", 0)), "col": Color(1.0, 0.85, 0.4)})
		_:
			list.append({"label": "Cấp công trình:", "val": "Cấp %d" % lvl, "col": Color(0.4, 0.95, 0.6)})
	return list

func _get_resting_heroes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var b_id := str(building_data.get("id", ""))
	for h in GameState.heroes:
		if not (h is Dictionary) or not GameState.is_hero_alive(h):
			continue
		var hid_building := str(h.get("housingBuildingId", "")) if h.get("housingBuildingId") != null else ""
		if not b_id.is_empty():
			if hid_building == b_id:
				result.append(h)
		elif bool(h.get("isResting", false)) or str(h.get("state", "")) == "RESTING":
			result.append(h)
	return result

func _format_num(val: int) -> String:
	if val >= 1_000_000:
		return "%.1fM" % (float(val) / 1_000_000.0)
	elif val >= 10_000:
		return "%.1fK" % (float(val) / 1000.0)
	return str(val)
