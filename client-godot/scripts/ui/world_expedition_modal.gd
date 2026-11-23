class_name WorldExpeditionModal
extends Control

## World Expedition Modal (M09)
## Connects /api/world/global/unlock, /api/world/global/map, /api/world/expeditions,
## /api/world/expeditions/:id/recall, and /api/world/heroes/away.

signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")

var _busy: bool = false
var _world_unlocked: bool = false
var _tiles: Array = []
var _expeditions: Array = []

var _tile_opt: OptionButton
var _mission_opt: OptionButton
var _browser: CardGridBrowser
var _exp_vbox: VBoxContainer
var _unlock_btn: Button
var _dispatch_btn: Button
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
	panel.custom_minimum_size = Vector2(980, 660)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.10, 0.12, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.42, 0.92, 0.68, 0.88)
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
	title.text = "🧭 VIỄN CHINH THẾ GIỚI (WORLD EXPEDITION)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.45, 0.95, 0.72))
	hdr.add_child(title)

	_unlock_btn = Button.new()
	_unlock_btn.text = "🌍 Mở Khóa Thế Giới"
	_unlock_btn.custom_minimum_size = Vector2(160, 32)
	_unlock_btn.visible = false
	_unlock_btn.pressed.connect(unlock_world)
	hdr.add_child(_unlock_btn)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var cfg_row := HBoxContainer.new()
	cfg_row.add_theme_constant_override("separation", 10)
	root.add_child(cfg_row)

	_tile_opt = OptionButton.new()
	_tile_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cfg_row.add_child(_tile_opt)

	_mission_opt = OptionButton.new()
	_mission_opt.custom_minimum_size = Vector2(180, 34)
	_mission_opt.add_item("🧭 Trinh Sát (SCOUT)")
	_mission_opt.add_item("⚔️ Tập Kích (ATTACK)")
	cfg_row.add_child(_mission_opt)

	_dispatch_btn = Button.new()
	_dispatch_btn.text = "🚀 Cử Đoàn Viễn Chinh"
	_dispatch_btn.custom_minimum_size = Vector2(180, 34)
	_dispatch_btn.modulate = Color(0.55, 1.0, 0.72)
	_dispatch_btn.pressed.connect(dispatch_selected)
	cfg_row.add_child(_dispatch_btn)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_browser = CardGridBrowserScript.new()
	_browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	_browser.grid_columns = 3
	_browser.card_selectable = true
	_browser.multi_select_enabled = true
	_browser.max_selection = 5
	_browser.show_action_bar = false
	_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_browser.configure_header("Chọn 1–5 Tướng rảnh", ["Tất cả", "Chưa xếp"])
	split.add_child(_browser)

	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(340, 0)
	var rps := StyleBoxFlat.new()
	rps.bg_color = Color(0.05, 0.07, 0.11, 0.95)
	rps.border_width_left = 1; rps.border_width_top = 1; rps.border_width_right = 1; rps.border_width_bottom = 1
	rps.border_color = Color(0.28, 0.45, 0.40, 0.7)
	rps.corner_radius_top_left = 8; rps.corner_radius_top_right = 8
	rps.corner_radius_bottom_left = 8; rps.corner_radius_bottom_right = 8
	right_panel.add_theme_stylebox_override("panel", rps)
	split.add_child(right_panel)

	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 10); rm.add_theme_constant_override("margin_right", 10)
	rm.add_theme_constant_override("margin_top", 10); rm.add_theme_constant_override("margin_bottom", 10)
	right_panel.add_child(rm)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rm.add_child(scroll)

	_exp_vbox = VBoxContainer.new()
	_exp_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_exp_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_exp_vbox)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải dữ liệu Viễn Chinh..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.92, 0.85))
	root.add_child(_status_lbl)

func refresh_all() -> void:
	await GameState.refresh_heroes()
	await GameState.refresh_away_heroes()
	if not is_instance_valid(self): return

	var map_res := await ApiClient.get_req("/api/world/global/map")
	if not is_instance_valid(self): return
	if map_res.get("ok", false):
		_world_unlocked = true
		_unlock_btn.visible = false
		var d = map_res.get("data")
		_tiles = d if d is Array else (d.get("tiles", []) if d is Dictionary else [])
		_tile_opt.clear()
		for t in _tiles:
			if t is Dictionary:
				_tile_opt.add_item("Ô (%s,%s) — %s" % [str(t.get("x", 0)), str(t.get("y", 0)), str(t.get("tileType", t.get("terrain", "Vùng đất")))])
	else:
		_world_unlocked = false
		_unlock_btn.visible = true

	var exp_res := await ApiClient.get_req("/api/world/expeditions")
	if not is_instance_valid(self): return
	if exp_res.get("ok", false):
		var ed = exp_res.get("data")
		_expeditions = ed if ed is Array else (ed.get("expeditions", []) if ed is Dictionary else [])

	var avail: Array = []
	for h in GameState.heroes:
		if h is Dictionary and GameState.is_hero_available(h):
			avail.append(h)
	_browser.set_items(avail, false)
	_render_expeditions()
	_status_lbl.text = "✅ Sẵn sàng (%d Tướng rảnh, %d đoàn viễn chinh)." % [avail.size(), _expeditions.size()]

func _render_expeditions() -> void:
	for c in _exp_vbox.get_children():
		c.queue_free()
	var hdr := Label.new()
	hdr.text = "📜 CÁC ĐOÀN VIỄN CHINH (%d)" % _expeditions.size()
	hdr.add_theme_font_size_override("font_size", 14)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_exp_vbox.add_child(hdr)

	if _expeditions.is_empty():
		var e := Label.new()
		e.text = "Chưa có đoàn viễn chinh nào."
		_exp_vbox.add_child(e)
		return

	for ex in _expeditions:
		if not (ex is Dictionary): continue
		var eid := str(ex.get("id", ex.get("expeditionId", "")))
		var status := str(ex.get("status", "TRAVELING")).to_upper()
		var mission := str(ex.get("mission", "SCOUT"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_exp_vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = "• [%s] %s" % [mission, status]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		if status == "TRAVELING":
			var rbtn := Button.new()
			rbtn.text = "Thu hồi"
			rbtn.custom_minimum_size = Vector2(84, 28)
			rbtn.disabled = _busy
			rbtn.pressed.connect(func(): await recall_expedition(eid))
			row.add_child(rbtn)

func unlock_world() -> void:
	if _busy: return
	_busy = true
	var res := await ApiClient.post_req("/api/world/global/unlock", {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🌍 Đã mở khóa Bản đồ Thế giới!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()

func dispatch_selected() -> void:
	if _busy or _tiles.is_empty(): return
	var sel := _browser.get_selected_items()
	if sel.is_empty():
		_status_lbl.text = "⚠️ Hãy chọn ít nhất 1 Tướng để cử đi viễn chinh."
		return
	var tile_idx := maxi(0, _tile_opt.selected)
	var tile_id := str(_tiles[tile_idx].get("id", ""))
	var mission := "SCOUT" if _mission_opt.selected == 0 else "ATTACK"
	var hero_ids: Array = []
	for h in sel:
		hero_ids.append(str(h.get("id", "")))
	await dispatch_expedition(tile_id, mission, hero_ids)

func dispatch_expedition(tile_id: String, mission: String, hero_ids: Array) -> Dictionary:
	if _busy: return {}
	_busy = true
	var res := await ApiClient.post_req("/api/world/expeditions", {
		"tileId": tile_id,
		"mission": mission,
		"heroIds": hero_ids,
	})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🚀 Đã cử đoàn Viễn chinh!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func recall_expedition(eid: String) -> void:
	if _busy or eid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/world/expeditions/%s/recall" % eid, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "↩️ Đã thu hồi đoàn Viễn chinh!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()

func _close() -> void:
	closed.emit()
	queue_free()
