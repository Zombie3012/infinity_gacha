extends Control
## Expedition Battle & Scout Reports Modal (Chiến Báo Viễn Chinh).
## Reads GET /api/world/expeditions (last 20 expeditions) and displays detailed reports
## for SCOUT_REPORT, DUNGEON_REPORT, GARRISON_REPORT, RESCUE_REPORT, PVP_REPORT, BATTLE_REPORT.

signal focus_tile_requested(x: float, y: float)
signal closed

const MISSION_LABELS := {
	"SCOUT": "🔭 Trinh sát",
	"DUNGEON": "⚔️ Hầm Ngục",
	"GARRISON": "⛺ Tập kết",
	"RESCUE": "🚑 Cứu hộ",
	"ATTACK": "🔥 Tấn công",
}

var _reports: Array = []
var _filter := "ALL"
var _selected_id := ""

var _list_host: VBoxContainer
var _detail_host: VBoxContainer
var _filter_btns: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if has_node("/root/ApiClient"):
		_refresh()

func _make_btn_style(bg: Color, border: Color, radius := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _style_button(btn: Button, accent := Color(0.35, 0.65, 0.95), bg := Color(0.10, 0.14, 0.22)) -> void:
	btn.add_theme_stylebox_override("normal", _make_btn_style(bg, accent.darkened(0.22)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(bg.lightened(0.1), accent))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(bg.darkened(0.12), accent.lightened(0.15)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))

func _make_card_style(bg := Color(0.08, 0.105, 0.17, 0.96), border := Color(0.26, 0.36, 0.54, 0.72)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(12)
	return s

func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.02, 0.045, 0.84)
	add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 580)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.125, 0.98)
	style.border_color = Color(0.84, 0.68, 0.32, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	root.add_child(hdr)

	var title := Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text = "📜 CHIẾN BÁO VIỄN CHINH (EXPEDITION)"
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.96, 0.85, 0.48))
	hdr.add_child(title)

	var ref_btn := Button.new()
	ref_btn.text = "🔄 Tải lại"
	_style_button(ref_btn, Color(0.38, 0.72, 1.0))
	ref_btn.pressed.connect(_refresh)
	hdr.add_child(ref_btn)

	var close_btn := Button.new()
	close_btn.text = "✕ Đóng"
	_style_button(close_btn, Color(0.75, 0.35, 0.35), Color(0.16, 0.09, 0.11))
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	# Filter Tabs
	var f_row := HBoxContainer.new()
	f_row.add_theme_constant_override("separation", 8)
	root.add_child(f_row)
	var filters := [
		["ALL", "Tất cả"],
		["SCOUT", "🔭 Trinh sát"],
		["DUNGEON", "⚔️ Hầm ngục"],
		["SUPPORT", "⛺ Tập kết / Cứu hộ"],
	]
	for item in filters:
		var key := str(item[0])
		var btn := Button.new()
		btn.text = str(item[1])
		_style_button(btn)
		btn.pressed.connect(func():
			_filter = key
			_render_all()
		)
		f_row.add_child(btn)
		_filter_btns[key] = btn

	# Body 2 Columns
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)

	var left_card := PanelContainer.new()
	left_card.custom_minimum_size = Vector2(340, 0)
	left_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_card.add_theme_stylebox_override("panel", _make_card_style())
	cols.add_child(left_card)

	var l_scroll := ScrollContainer.new()
	l_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_card.add_child(l_scroll)

	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.add_theme_constant_override("separation", 6)
	l_scroll.add_child(_list_host)

	var right_card := PanelContainer.new()
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", _make_card_style(Color(0.075, 0.095, 0.155, 0.98), Color(0.45, 0.38, 0.22, 0.78)))
	cols.add_child(right_card)

	var r_scroll := ScrollContainer.new()
	r_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_card.add_child(r_scroll)

	_detail_host = VBoxContainer.new()
	_detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_host.add_theme_constant_override("separation", 8)
	r_scroll.add_child(_detail_host)

func apply_reports(list: Array) -> void:
	_reports = list
	if _selected_id.is_empty() and _reports.size() > 0:
		_selected_id = str(_reports[0].get("id", ""))
	_render_all()

func _refresh() -> void:
	var res: Dictionary = await ApiClient.get_req("/api/world/expeditions")
	if bool(res.get("ok", false)) and res.get("data", null) is Array:
		apply_reports(res.get("data", []))

func _filtered_reports() -> Array:
	var out: Array = []
	for r in _reports:
		if not (r is Dictionary): continue
		var m := str(r.get("mission", "")).to_upper()
		if _filter == "SCOUT" and m != "SCOUT": continue
		elif _filter == "DUNGEON" and m != "DUNGEON" and m != "ATTACK": continue
		elif _filter == "SUPPORT" and m != "GARRISON" and m != "RESCUE": continue
		out.append(r)
	return out

func _outcome_tag(r: Dictionary) -> String:
	var st := str(r.get("status", "")).to_upper()
	var res = r.get("result", {})
	if st == "TRAVELING": return "ĐANG BAY"
	if st == "GARRISONED": return "ĐỒN TRÚ"
	if st == "STRANDED": return "SOS!"
	if st == "RECALLED": return "ĐÃ RÚT"
	if res is Dictionary and not res.is_empty():
		var kind := str(res.get("kind", ""))
		if kind == "SCOUT_REPORT": return "ĐÃ QUÉT"
		if kind == "GARRISON_REPORT": return "ĐỒN TRÚ"
		if kind == "RESCUE_REPORT": return "CỨU THÀNH CÔNG" if bool(res.get("rescued", false)) else "KHÔNG TÌM THẤY"
		if res.has("won"):
			return "THẮNG" if bool(res.get("won", false)) else "THẤT BẠI"
	return st

func _render_all() -> void:
	for k in _filter_btns.keys():
		var b: Button = _filter_btns[k]
		if k == _filter:
			_style_button(b, Color(0.96, 0.80, 0.30), Color(0.20, 0.16, 0.09))
		else:
			_style_button(b, Color(0.32, 0.44, 0.64), Color(0.09, 0.12, 0.19))

	for c in _list_host.get_children(): c.queue_free()
	for c in _detail_host.get_children(): c.queue_free()

	var items := _filtered_reports()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "Chưa có chiến báo nào trong mục này."
		empty.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
		_list_host.add_child(empty)
		return

	var selected: Dictionary = {}
	for r in items:
		var rid := str(r.get("id", ""))
		if rid == _selected_id: selected = r
		var tile: Dictionary = r.get("tile", {}) if r.get("tile", null) is Dictionary else {}
		var m_lbl := str(MISSION_LABELS.get(str(r.get("mission", "")), str(r.get("mission", ""))))
		var tag := _outcome_tag(r)
		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.text = "%s  [%s]\nÔ (%d, %d) • %d Hero" % [
			m_lbl, tag, int(tile.get("x", 0)), int(tile.get("y", 0)), (r.get("heroes", []) as Array).size()
		]
		if rid == _selected_id:
			_style_button(btn, Color(0.96, 0.82, 0.34), Color(0.15, 0.18, 0.27))
		else:
			_style_button(btn, Color(0.28, 0.40, 0.58), Color(0.08, 0.11, 0.18))
		btn.pressed.connect(func():
			_selected_id = rid
			_render_all()
		)
		_list_host.add_child(btn)

	if selected.is_empty():
		selected = items[0]
		_selected_id = str(selected.get("id", ""))

	_render_detail(selected)

func _render_detail(r: Dictionary) -> void:
	var tile: Dictionary = r.get("tile", {}) if r.get("tile", null) is Dictionary else {}
	var res: Dictionary = r.get("result", {}) if r.get("result", null) is Dictionary else {}
	var heroes_arr: Array = r.get("heroes", []) if r.get("heroes", null) is Array else []
	var m_lbl := str(MISSION_LABELS.get(str(r.get("mission", "")), str(r.get("mission", ""))))

	var hdr := Label.new()
	hdr.text = "%s — %s" % [m_lbl, _outcome_tag(r)]
	hdr.add_theme_font_size_override("font_size", 18)
	hdr.add_theme_color_override("font_color", Color(0.96, 0.86, 0.48))
	_detail_host.add_child(hdr)

	var coord_x := float(tile.get("x", 100))
	var coord_y := float(tile.get("y", 100))
	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", 10)
	_detail_host.add_child(loc_row)

	var loc_lbl := Label.new()
	loc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_lbl.text = "📍 Tọa độ: (%d, %d) • Địa hình: %s" % [int(coord_x), int(coord_y), str(tile.get("terrain", ""))]
	loc_lbl.add_theme_color_override("font_color", Color(0.76, 0.88, 1.0))
	loc_row.add_child(loc_lbl)

	var jump_btn := Button.new()
	jump_btn.text = "🎯 Xem trên bản đồ"
	_style_button(jump_btn, Color(0.35, 0.82, 1.0))
	jump_btn.pressed.connect(func():
		focus_tile_requested.emit(coord_x, coord_y)
		_close()
	)
	loc_row.add_child(jump_btn)

	# Squad list
	var names := PackedStringArray()
	for h in heroes_arr:
		if h is Dictionary: names.append(str(h.get("name", "Hero")))
	var sq_lbl := Label.new()
	sq_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sq_lbl.text = "👥 Tổ đội (%d): %s" % [names.size(), ", ".join(names) if names.size() > 0 else "—"]
	_detail_host.add_child(sq_lbl)

	# Result breakdown
	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	var kind := str(res.get("kind", ""))
	if kind == "SCOUT_REPORT":
		var df = res.get("dungeonFound", null)
		var d_txt := "Không phát hiện Hầm Ngục Nổi tại ô này."
		if df is Dictionary:
			d_txt = "⚔️ Phát hiện Hầm Ngục Nổi [Hạng %s]: %s\nBoss: %s • LC khuyến nghị: %d • Tối đa: %d Hero" % [
				str(df.get("rank", "D")), str(df.get("name", "")), str(df.get("bossName", "")),
				int(df.get("recommendedPower", 0)), int(df.get("maxPartySize", 5))
			]
		body.text = "🔭 BÁO CÁO TRINH SÁT\n• Tuyến đường đã được lưu tầm nhìn trong %d phút.\n• %s" % [
			int(int(res.get("visionDurationSeconds", 3600)) / 60), d_txt
		]
	elif kind == "DUNGEON_REPORT":
		var won := bool(res.get("won", false))
		body.text = "⚔️ BÁO CÁO THÁM HIỂM HẦM NGỤC [%s] %s\n• Kết quả: %s\n• Boss: %s\n• Lực chiến tổ đội: %d / Khuyến nghị: %d\n• Phần thưởng: %s" % [
			str(res.get("rank", "D")), str(res.get("dungeonName", "")),
			"CHIẾN THẮNG!" if won else ("MẮC KẸT (SOS) — CẦN TÀU CỨU HỘ!" if bool(res.get("stranded", false)) else "THẤT BẠI"),
			str(res.get("bossName", "")),
			int(res.get("partyPower", 0)), int(res.get("recommendedPower", 0)),
			("+%d Bạc" % int(res.get("silverReward", 0))) if won else "0 Bạc",
		]
	elif kind == "GARRISON_REPORT":
		body.text = "⛺ BÁO CÁO TẬP KẾT (ĐỒN TRÚ)\n• Hạm đội đã đóng quân tiền phương an toàn tại (%d, %d) với %d Hero.\n• Duy trì tầm nhìn sáng quanh khu vực và sẵn sàng xuất kích tiếp." % [
			int(coord_x), int(coord_y), int(res.get("heroCount", names.size()))
		]
	elif kind == "RESCUE_REPORT":
		body.text = "🚑 BÁO CÁO CỨU HỘ\n• Trạng thái: %s" % (
			"Đã giải cứu thành công tổ đội mắc kẹt và hộ tống về Cảng!" if bool(res.get("rescued", false)) else "Không còn tổ đội mắc kẹt tại hiện trường."
		)
	elif kind == "PVP_REPORT" or kind == "BATTLE_REPORT":
		body.text = "🔥 BÁO CÁO GIAO TRANH\n• Kết quả: %s\n• Lực chiến tổ đội: %d • Phòng thủ: %d" % [
			"CHIẾN THẮNG" if bool(res.get("won", false)) else "THẤT BẠI",
			int(res.get("partyPower", 0)), int(res.get("defenderPower", res.get("guardianPower", 0)))
		]
	else:
		body.text = "Trạng thái hiện tại: %s\nThời gian còn lại: %ds" % [str(r.get("status", "")), int(r.get("secondsRemaining", 0))]
	_detail_host.add_child(body)

func _close() -> void:
	closed.emit()
	queue_free()
