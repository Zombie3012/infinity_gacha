class_name AncientDungeonModal
extends Control

## Ancient Dungeon Exploration Modal (M08)
## Connects /api/dungeon/templates, /api/dungeon/floors, /api/dungeon/instance/active,
## /api/dungeon/floor/:floorNumber/enter, /api/dungeon/instance/:instanceId/explore & /retreat.

signal closed

var _busy: bool = false
var _templates: Array = []
var _floors: Array = []
var _selected_template: String = "QUIET_FOREST"
var _active_instance: Dictionary = {}
var _log_lines: PackedStringArray = []

var _template_opt: OptionButton
var _body_vbox: VBoxContainer
var _log_label: RichTextLabel
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

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(940, 640)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.09, 0.15, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.35, 0.78, 1.0, 0.88)
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
	title.text = "🕳️ HẦM NGỤC CỔ ĐẠI (ANCIENT DUNGEON)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	hdr.add_child(title)

	_template_opt = OptionButton.new()
	_template_opt.custom_minimum_size = Vector2(210, 32)
	_template_opt.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < _templates.size() and _templates[idx] is Dictionary:
			_selected_template = str(_templates[idx].get("code", "QUIET_FOREST"))
			await _load_floors()
			_render_body()
	)
	hdr.add_child(_template_opt)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_body_vbox)

	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(340, 0)
	var lps := StyleBoxFlat.new()
	lps.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	lps.border_width_left = 1; lps.border_width_top = 1; lps.border_width_right = 1; lps.border_width_bottom = 1
	lps.border_color = Color(0.24, 0.35, 0.52, 0.7)
	lps.corner_radius_top_left = 8; lps.corner_radius_top_right = 8
	lps.corner_radius_bottom_left = 8; lps.corner_radius_bottom_right = 8
	log_panel.add_theme_stylebox_override("panel", lps)
	split.add_child(log_panel)

	var lm := MarginContainer.new()
	lm.add_theme_constant_override("margin_left", 10); lm.add_theme_constant_override("margin_right", 10)
	lm.add_theme_constant_override("margin_top", 10); lm.add_theme_constant_override("margin_bottom", 10)
	log_panel.add_child(lm)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = false
	_log_label.text = "📜 Nhật ký thám hiểm hầm ngục...\n"
	lm.add_child(_log_label)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải dữ liệu hầm ngục..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func refresh_all() -> void:
	var t_res := await ApiClient.get_req("/api/dungeon/templates")
	if not is_instance_valid(self): return
	if t_res.get("ok", false) and t_res.get("data") is Array:
		_templates = t_res["data"]
		_template_opt.clear()
		for t in _templates:
			if t is Dictionary:
				_template_opt.add_item(str(t.get("name", t.get("code", "Dungeon"))))
		if not _templates.is_empty() and _templates[0] is Dictionary:
			_selected_template = str(_templates[0].get("code", "QUIET_FOREST"))

	await _load_floors()
	await _load_active_instance()
	_render_body()

func _load_floors() -> void:
	var f_res := await ApiClient.get_req("/api/dungeon/floors?template=%s" % _selected_template)
	if not is_instance_valid(self): return
	if f_res.get("ok", false):
		var fd = f_res.get("data")
		_floors = fd if fd is Array else (fd.get("floors", []) if fd is Dictionary else [])

func _load_active_instance() -> void:
	var a_res := await ApiClient.get_req("/api/dungeon/instance/active")
	if not is_instance_valid(self): return
	if a_res.get("ok", false) and a_res.get("data") is Dictionary:
		_active_instance = a_res["data"]
	else:
		_active_instance = {}

func _render_body() -> void:
	if _body_vbox == null: return
	for c in _body_vbox.get_children():
		c.queue_free()

	if not _active_instance.is_empty() and not str(_active_instance.get("id", "")).is_empty():
		var iid := str(_active_instance.get("id", ""))
		var fnum := int(_active_instance.get("floorNumber", 1))
		var room_idx := int(_active_instance.get("currentRoomIndex", _active_instance.get("exploredRooms", 0)))
		var active_lbl := Label.new()
		active_lbl.text = "🔥 Đang thám hiểm Tầng %d (Phòng #%d)" % [fnum, room_idx]
		active_lbl.add_theme_font_size_override("font_size", 16)
		active_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
		_body_vbox.add_child(active_lbl)

		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 10)
		_body_vbox.add_child(btn_row)

		var exp_btn := Button.new()
		exp_btn.text = "🧭 Thám Hiểm Bước Tiếp"
		exp_btn.custom_minimum_size = Vector2(200, 40)
		exp_btn.disabled = _busy
		exp_btn.pressed.connect(func(): await explore_active(iid))
		btn_row.add_child(exp_btn)

		var ret_btn := Button.new()
		ret_btn.text = "🏃 Rút Lui Bảo Toàn"
		ret_btn.custom_minimum_size = Vector2(180, 40)
		ret_btn.modulate = Color(1.0, 0.72, 0.65)
		ret_btn.disabled = _busy
		ret_btn.pressed.connect(func(): await retreat_active(iid))
		btn_row.add_child(ret_btn)
		return

	if _floors.is_empty():
		var e_lbl := Label.new()
		e_lbl.text = "Chưa có tầng hầm ngục nào khả dụng."
		_body_vbox.add_child(e_lbl)
		return

	for fl in _floors:
		if not (fl is Dictionary): continue
		var fnum := int(fl.get("floorNumber", 1))
		var unlocked := bool(fl.get("unlocked", fnum == 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_body_vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = "🕳️ Tầng %d — %s" % [fnum, str(fl.get("name", "Hầm Ngục Cổ Đại"))]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_color_override("font_color", Color.WHITE if unlocked else Color(0.55, 0.6, 0.7))
		row.add_child(lbl)

		var enter_btn := Button.new()
		enter_btn.text = "Tiến Vào" if unlocked else "🔒 Khóa"
		enter_btn.custom_minimum_size = Vector2(110, 32)
		enter_btn.disabled = _busy or not unlocked
		enter_btn.pressed.connect(func(): await enter_floor(fnum))
		row.add_child(enter_btn)

func enter_floor(floor_num: int) -> void:
	if _busy: return
	_busy = true
	var res := await ApiClient.post_req("/api/dungeon/floor/%d/enter" % floor_num, {"template": _selected_template})
	_busy = false
	if not is_instance_valid(self): return
	if res.get("ok", false) and res.get("data") is Dictionary:
		_active_instance = res["data"]
		_append_log("🚪 Đã tiến vào Tầng %d (%s)." % [floor_num, _selected_template])
		_status_lbl.text = "✅ Đã mở phiên thám hiểm Tầng %d." % floor_num
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Không thể vào tầng"))
	_render_body()

func explore_active(iid: String) -> void:
	if _busy or iid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/dungeon/instance/%s/explore" % iid, {})
	_busy = false
	if not is_instance_valid(self): return
	if res.get("ok", false):
		_append_log("🧭 Thám hiểm phòng: " + str(res.get("data", {})))
		_status_lbl.text = "🧭 Đã khám phá phòng tiếp theo."
		await _load_active_instance()
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Lỗi thám hiểm"))
	_render_body()

func retreat_active(iid: String) -> void:
	if _busy or iid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/dungeon/instance/%s/retreat" % iid, {})
	_busy = false
	if not is_instance_valid(self): return
	if res.get("ok", false):
		_append_log("🏃 Đã rút lui an toàn khỏi hầm ngục.")
		_status_lbl.text = "🏃 Đã rút lui bảo toàn."
		_active_instance = {}
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Lỗi rút lui"))
	_render_body()

func _append_log(line: String) -> void:
	_log_lines.append(line)
	if _log_label != null:
		_log_label.text = "\n".join(_log_lines)

func _close() -> void:
	closed.emit()
	queue_free()
