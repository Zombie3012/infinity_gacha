class_name EventsQuestsModal
extends Control

## Events, Quests & Achievements Modal (M06)
## 3 tabs: Sự Kiện LiveOps (/api/events), Nhiệm Vụ (/api/quests), Thành Tựu (/api/achievements/:code/claim)

signal closed

var _active_tab: int = 0
var _busy: bool = false
var _events_data: Array = []
var _quests_data: Array = []
var _achievements_data: Array = []

var _tab_buttons: Array[Button] = []
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
	_tab_buttons.clear()

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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 620)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.95, 0.82, 0.35, 0.88)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "📜 SỰ KIỆN, NHIỆM VỤ & THÀNH TỰU"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	hdr.add_child(title)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	for i in range(3):
		var names := ["🎉 Sự Kiện Đang Mở", "📋 Nhiệm Vụ", "🏅 Thành Tựu"]
		var btn := Button.new()
		btn.text = names[i]
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func(): _switch_tab(idx))
		tabs.add_child(btn)
		_tab_buttons.append(btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_body_vbox)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải dữ liệu sự kiện & nhiệm vụ..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func refresh_all() -> void:
	if _status_lbl != null:
		_status_lbl.text = "⏳ Đang đồng bộ..."
	var ev_res := await ApiClient.get_req("/api/events")
	if not is_instance_valid(self): return
	if ev_res.get("ok", false):
		var d = ev_res.get("data")
		_events_data = d if d is Array else (d.get("events", []) if d is Dictionary else [])

	var q_res := await ApiClient.get_req("/api/quests")
	if not is_instance_valid(self): return
	if q_res.get("ok", false) and q_res.get("data") is Dictionary:
		var qd: Dictionary = q_res["data"]
		_quests_data = qd.get("quests", []) if qd.get("quests") is Array else []
		_achievements_data = qd.get("achievements", []) if qd.get("achievements") is Array else []

	if _status_lbl != null:
		_status_lbl.text = "✅ Đã cập nhật dữ liệu mới nhất."
	_render_tab()

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	_render_tab()

func _render_tab() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].modulate = Color(1.0, 0.90, 0.42) if i == _active_tab else Color(0.76, 0.84, 0.92)
	if _body_vbox == null:
		return
	for c in _body_vbox.get_children():
		c.queue_free()

	match _active_tab:
		0: _render_events()
		1: _render_quests()
		2: _render_achievements()

func _make_row_card(title_txt: String, desc_txt: String, btn_txt: String, btn_disabled: bool, on_press: Callable) -> void:
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.13, 0.20, 0.95)
	cs.border_width_left = 1; cs.border_width_top = 1; cs.border_width_right = 1; cs.border_width_bottom = 1
	cs.border_color = Color(0.28, 0.38, 0.55, 0.7)
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", cs)
	_body_vbox.add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12); m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8); m.add_theme_constant_override("margin_bottom", 8)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	m.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var t := Label.new()
	t.text = title_txt
	t.add_theme_font_size_override("font_size", 14)
	t.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	info.add_child(t)

	var d := Label.new()
	d.text = desc_txt
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.add_theme_font_size_override("font_size", 12)
	d.add_theme_color_override("font_color", Color(0.80, 0.88, 0.96))
	info.add_child(d)

	if not btn_txt.is_empty():
		var b := Button.new()
		b.text = btn_txt
		b.custom_minimum_size = Vector2(130, 34)
		b.disabled = _busy or btn_disabled
		b.pressed.connect(on_press)
		row.add_child(b)

func _render_events() -> void:
	if _events_data.is_empty():
		_make_row_card("Chưa có sự kiện đang mở", "Hiện không có sự kiện LiveOps nào đang diễn ra.", "", true, Callable())
		return
	for ev in _events_data:
		if not (ev is Dictionary): continue
		var ev_title := str(ev.get("title", ev.get("name", "Sự Kiện")))
		var missions: Array = ev.get("missions", []) if ev.get("missions") is Array else []
		if missions.is_empty():
			_make_row_card("🎉 " + ev_title, str(ev.get("description", "Sự kiện đang diễn ra.")), "", true, Callable())
		for ms in missions:
			if not (ms is Dictionary): continue
			var mid := str(ms.get("id", ""))
			var mname := str(ms.get("title", ms.get("description", "Nhiệm vụ sự kiện")))
			var prog := int(ms.get("progress", 0))
			var target := maxi(1, int(ms.get("targetValue", ms.get("targetCount", 1))))
			var claimed := bool(ms.get("claimed", false))
			var can_claim := (not claimed) and prog >= target
			var lbl := "Đã nhận" if claimed else ("Nhận thưởng" if can_claim else "%d/%d" % [prog, target])
			_make_row_card("🎉 [%s] %s" % [ev_title, mname], "Tiến độ: %d / %d" % [prog, target], lbl, not can_claim, func():
				await _claim_event_mission(mid)
			)

func _render_quests() -> void:
	if _quests_data.is_empty():
		_make_row_card("Không có nhiệm vụ", "Tất cả nhiệm vụ đã hoàn thành.", "", true, Callable())
		return
	for q in _quests_data:
		if not (q is Dictionary): continue
		var code := str(q.get("code", ""))
		var qname := str(q.get("title", q.get("name", code)))
		var status := str(q.get("status", "AVAILABLE")).to_upper()
		var prog := int(q.get("progress", 0))
		var target := maxi(1, int(q.get("targetValue", q.get("targetCount", 1))))
		var btn_txt := "Nhận NV"
		var disabled := false
		if status == "CLAIMED":
			btn_txt = "Đã nhận"
			disabled = true
		elif status == "COMPLETED" or (status == "ACTIVE" and prog >= target):
			btn_txt = "Nhận thưởng"
		elif status == "ACTIVE":
			btn_txt = "%d/%d" % [prog, target]
			disabled = true
		_make_row_card("📋 %s" % qname, "Trạng thái: %s • Tiến độ: %d / %d" % [status, prog, target], btn_txt, disabled, func():
			if status == "AVAILABLE":
				await _accept_quest(code)
			else:
				await _claim_quest(code)
		)

func _render_achievements() -> void:
	if _achievements_data.is_empty():
		_make_row_card("Chưa có thành tựu", "Hãy tiếp tục khám phá Tháp PvE và xây dựng Lâu đài.", "", true, Callable())
		return
	for a in _achievements_data:
		if not (a is Dictionary): continue
		var code := str(a.get("code", ""))
		var aname := str(a.get("title", a.get("name", code)))
		var prog := int(a.get("progress", 0))
		var target := maxi(1, int(a.get("targetValue", a.get("targetCount", 1))))
		var claimed := bool(a.get("claimed", false))
		var can_claim := (not claimed) and prog >= target
		var btn_txt := "Đã nhận" if claimed else ("Nhận thưởng" if can_claim else "%d/%d" % [prog, target])
		_make_row_card("🏅 %s" % aname, "Tiến độ: %d / %d" % [prog, target], btn_txt, not can_claim, func():
			await _claim_achievement(code)
		)

func _claim_event_mission(mid: String) -> void:
	if _busy or mid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/events/missions/%s/claim" % mid, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🎁 Đã nhận thưởng sự kiện!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await GameState.refresh_profile()
	await refresh_all()

func _accept_quest(code: String) -> void:
	if _busy or code.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/quests/%s/accept" % code, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "📋 Đã nhận nhiệm vụ!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()

func _claim_quest(code: String) -> void:
	if _busy or code.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/quests/%s/claim" % code, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🎁 Đã nhận thưởng nhiệm vụ!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await GameState.refresh_profile()
	await refresh_all()

func _claim_achievement(code: String) -> void:
	if _busy or code.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/achievements/%s/claim" % code, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🏅 Đã nhận thưởng thành tựu!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await GameState.refresh_profile()
	await refresh_all()

func _close() -> void:
	closed.emit()
	queue_free()
