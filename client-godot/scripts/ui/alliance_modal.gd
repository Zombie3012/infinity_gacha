class_name AllianceModal
extends Control

## Alliance Hall Modal (M10)
## Manages Alliance creation, search, join/cancel request, leave/disband,
## member management, and internal notice. (No Tech Upgrade / Alliance Wars).

signal closed

var _busy: bool = false
var _alliance_data: Dictionary = {}
var _search_results: Array = []

var _body_vbox: VBoxContainer
var _status_lbl: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	await refresh_all()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.85)
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vp := get_viewport_rect().size
	var pw := clampf(vp.x * 0.82, 660.0, 900.0) if vp.x > 0 else 900.0
	var ph := clampf(vp.y * 0.85, 460.0, 620.0) if vp.y > 0 else 620.0
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(pw, ph)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.15, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.45, 0.78, 1.0, 0.9)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18); margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16); margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "🏳️ ĐẠI SẢNH LIÊN MINH (ALLIANCE HALL)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	hdr.add_child(title)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_body_vbox)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải thông tin Liên Minh..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func refresh_all() -> void:
	var res := await ApiClient.get_req("/api/alliance")
	if not is_instance_valid(self): return
	if res.get("ok", false) and res.get("data") is Dictionary:
		_alliance_data = res["data"]
	else:
		_alliance_data = {}
	_render_body()

func _render_body() -> void:
	if _body_vbox == null: return
	for c in _body_vbox.get_children():
		c.queue_free()

	var my_alliance: Variant = _alliance_data.get("alliance")
	if my_alliance is Dictionary and not (my_alliance as Dictionary).is_empty():
		_render_my_alliance(my_alliance as Dictionary)
	else:
		_render_no_alliance()

func _render_no_alliance() -> void:
	var create_hdr := Label.new()
	create_hdr.text = "✨ Thành Lập Liên Minh Mới"
	create_hdr.add_theme_font_size_override("font_size", 16)
	create_hdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_body_vbox.add_child(create_hdr)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(row)

	var name_in := LineEdit.new()
	name_in.placeholder_text = "Tên Liên Minh..."
	name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_in)

	var tag_in := LineEdit.new()
	tag_in.placeholder_text = "Tag (VD: SKY)"
	tag_in.custom_minimum_size = Vector2(120, 0)
	row.add_child(tag_in)

	var c_btn := Button.new()
	c_btn.text = "Lập Liên Minh"
	c_btn.custom_minimum_size = Vector2(140, 34)
	c_btn.pressed.connect(func():
		await create_alliance(name_in.text.strip_edges(), tag_in.text.strip_edges())
	)
	row.add_child(c_btn)

	_body_vbox.add_child(HSeparator.new())

	var s_row := HBoxContainer.new()
	s_row.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(s_row)

	var s_in := LineEdit.new()
	s_in.placeholder_text = "Tìm kiếm Liên Minh theo tên..."
	s_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s_row.add_child(s_in)

	var s_btn := Button.new()
	s_btn.text = "🔍 Tìm Kiếm"
	s_btn.custom_minimum_size = Vector2(120, 34)
	s_btn.pressed.connect(func(): await search_alliances(s_in.text.strip_edges()))
	s_row.add_child(s_btn)

	for al in _search_results:
		if not (al is Dictionary): continue
		var aid := str(al.get("id", ""))
		var a_row := HBoxContainer.new()
		_body_vbox.add_child(a_row)
		var lbl := Label.new()
		lbl.text = "🏳️ [%s] %s (Lv.%d)" % [str(al.get("tag", "")), str(al.get("name", "")), int(al.get("level", 1))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		a_row.add_child(lbl)
		var j_btn := Button.new()
		j_btn.text = "Xin Gia Nhập"
		j_btn.pressed.connect(func(): await join_alliance(aid))
		a_row.add_child(j_btn)

func _render_my_alliance(al: Dictionary) -> void:
	var hdr := Label.new()
	hdr.text = "🏳️ [%s] %s  •  Cấp %d" % [str(al.get("tag", "")), str(al.get("name", "")), int(al.get("allianceLevel", al.get("level", 1)))]
	hdr.add_theme_font_size_override("font_size", 17)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_body_vbox.add_child(hdr)

	var notice_row := HBoxContainer.new()
	notice_row.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(notice_row)

	var notice_in := LineEdit.new()
	notice_in.text = str(al.get("noticeBoard", al.get("notice", "")))
	notice_in.placeholder_text = "Thông báo nội bộ Liên Minh..."
	notice_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice_row.add_child(notice_in)

	var save_n_btn := Button.new()
	save_n_btn.text = "💾 Lưu Thông Báo"
	save_n_btn.pressed.connect(func(): await update_notice(notice_in.text.strip_edges()))
	notice_row.add_child(save_n_btn)

	var members: Array = _alliance_data.get("members", []) if _alliance_data.get("members") is Array else []
	var m_hdr := Label.new()
	m_hdr.text = "👥 Thành Viên (%d)" % members.size()
	m_hdr.add_theme_font_size_override("font_size", 14)
	_body_vbox.add_child(m_hdr)

	for mem in members:
		if not (mem is Dictionary): continue
		var mem_id := str(mem.get("masterId", ""))
		var mem_name := str(mem.get("masterName", mem_id if not mem_id.is_empty() else "Thành viên"))
		var mem_row := HBoxContainer.new()
		mem_row.add_theme_constant_override("separation", 8)
		_body_vbox.add_child(mem_row)

		var mlbl := Label.new()
		mlbl.text = "• %s [%s]" % [mem_name, str(mem.get("role", "MEMBER"))]
		mlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mem_row.add_child(mlbl)

		if not mem_id.is_empty() and mem_id != GameState.master_id:
			var add_f_btn := Button.new()
			add_f_btn.text = "➕ Kết Bạn"
			add_f_btn.custom_minimum_size = Vector2(104, 28)
			add_f_btn.pressed.connect(func():
				var res := await ApiClient.post_req("/api/friends/requests", {"targetMasterId": mem_id})
				if is_instance_valid(self) and _status_lbl != null:
					_status_lbl.text = "📨 Đã gửi lời mời kết bạn tới %s!" % mem_name if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
			)
			mem_row.add_child(add_f_btn)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	_body_vbox.add_child(act_row)

	var leave_btn := Button.new()
	leave_btn.text = "🚪 Rời Liên Minh"
	leave_btn.modulate = Color(1.0, 0.72, 0.65)
	leave_btn.pressed.connect(leave_alliance)
	act_row.add_child(leave_btn)

	var disband_btn := Button.new()
	disband_btn.text = "🗑️ Giải Tán Liên Minh"
	disband_btn.modulate = Color(1.0, 0.50, 0.50)
	disband_btn.pressed.connect(disband_alliance)
	act_row.add_child(disband_btn)

func create_alliance(a_name: String, a_tag: String) -> Dictionary:
	if _busy: return {}
	_busy = true
	var res := await ApiClient.post_req("/api/alliance", {"name": a_name, "tag": a_tag})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🏳️ Đã thành lập Liên Minh!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func search_alliances(query: String) -> void:
	var res := await ApiClient.get_req("/api/alliance/search?query=%s" % query.uri_encode())
	if not is_instance_valid(self): return
	if res.get("ok", false):
		var d = res.get("data")
		_search_results = d if d is Array else (d.get("alliances", []) if d is Dictionary else [])
		_render_body()

func join_alliance(aid: String) -> void:
	if _busy or aid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/alliance/join", {"allianceId": aid})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "📨 Đã gửi đơn gia nhập!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()

func update_notice(notice_txt: String) -> Dictionary:
	if _busy: return {}
	_busy = true
	var res := await ApiClient.patch_req("/api/alliance/notice", {"notice": notice_txt})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "💾 Đã cập nhật thông báo!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func leave_alliance() -> void:
	if _busy: return
	_busy = true
	var res := await ApiClient.post_req("/api/alliance/leave", {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🚪 Đã rời Liên Minh." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()

func disband_alliance() -> Dictionary:
	if _busy: return {}
	_busy = true
	var res := await ApiClient.delete_req("/api/alliance")
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🗑️ Đã giải tán Liên Minh." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func _close() -> void:
	closed.emit()
	queue_free()
