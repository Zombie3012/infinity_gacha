extends Control
## Airship Port Modal (Bến Thiên Hành — Cảng Tàu Bay).
## 2 focused tabs (Tech Tree lives inside Hall of Magic -> Research tab):
##   1. Bãi Đậu Lưới & Hạm Đội: Custom-drawn unified Hangar Grid with Press-and-Hold Drag & Drop + R/Right-Click 90° rotate
##   2. Xưởng Chế Tạo Tàu: 4 ship classes with visual grid footprint diagrams

signal closed
signal open_rts_map_requested

const SHIP_COLORS := {
	"SCOUT_SKIFF": Color(0.18, 0.68, 0.88, 0.94),
	"RESCUE_CUTTER": Color(0.18, 0.74, 0.48, 0.94),
	"WAR_DREADNOUGHT": Color(0.86, 0.42, 0.20, 0.94),
	"TRANSPORT_CARRIER": Color(0.56, 0.34, 0.86, 0.94),
}

const SIZE_LABELS := {
	"SMALL": "Nhỏ",
	"MEDIUM": "Trung bình",
	"LARGE": "Lớn",
}

const HOLD_THRESHOLD_SEC := 0.16
const DRAG_DISTANCE_PX := 8.0

var _state: Dictionary = {}
var _active_tab := 0
var _selected_ship_id := ""

# Hangar grid canvas + Press-and-Hold drag state
var _grid_canvas: Control
var _cell_px := 56.0
var _grid_origin := Vector2(12.0, 12.0)

var _pressing := false
var _press_ship_id := ""
var _press_start_pos := Vector2.ZERO
var _press_elapsed := 0.0
var _press_grab_cell_offset := Vector2i.ZERO

var _dragging_ship_id := ""
var _drag_rot := 0
var _drag_grid_pos := Vector2i.ZERO
var _drag_valid := false

var _header_meta: Label
var _status_lbl: Label
var _tab_btns: Array[Button] = []
var _body_host: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	if get_tree() != null and has_node("/root/ApiClient"):
		_refresh()

func _make_btn_style(bg: Color, border: Color, radius := 7) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

func _style_button(btn: Button, accent := Color(0.28, 0.56, 0.86), bg := Color(0.11, 0.15, 0.24)) -> void:
	btn.add_theme_stylebox_override("normal", _make_btn_style(bg, accent.darkened(0.2)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(bg.lightened(0.1), accent))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(bg.darkened(0.12), accent.lightened(0.15)))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(Color(0.08, 0.09, 0.13, 0.7), Color(0.22, 0.24, 0.3, 0.5)))
	btn.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.48, 0.52, 0.6))

func _make_card_style(bg := Color(0.09, 0.11, 0.18, 0.96), border := Color(0.25, 0.34, 0.5, 0.75)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(12)
	return s

func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.02, 0.045, 0.86)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1100, 690)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.072, 0.12, 0.98)
	style.border_color = Color(0.82, 0.68, 0.32, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 12)
	root.add_child(hdr)

	var title := Label.new()
	title.text = "⚓ BẾN THIÊN HÀNH — CẢNG TÀU BAY"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.96, 0.84, 0.48))
	hdr.add_child(title)

	_header_meta = Label.new()
	_header_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_header_meta.add_theme_font_size_override("font_size", 13)
	_header_meta.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
	hdr.add_child(_header_meta)

	var close_btn := Button.new()
	close_btn.text = "✕ Đóng"
	_style_button(close_btn, Color(0.75, 0.35, 0.35), Color(0.16, 0.09, 0.11))
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	# Tab Bar (2 focused tabs — Tech Tree is in Hall of Magic -> Research)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	var tab_names := ["📐 Bãi Đậu Lưới & Hạm Đội", "🔨 Xưởng Chế Tạo Tàu"]
	for i in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.custom_minimum_size = Vector2(240, 38)
		_style_button(btn)
		var idx := i
		btn.pressed.connect(func():
			_active_tab = idx
			_render_body()
		)
		tabs.add_child(btn)
		_tab_btns.append(btn)

	var tech_hint := Label.new()
	tech_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tech_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tech_hint.text = "🔬 Nghiên cứu mở khóa mẫu tàu & mở rộng sàn đậu tại: Đại Sảnh Ma Thuật → tab Nghiên cứu"
	tech_hint.add_theme_font_size_override("font_size", 12)
	tech_hint.add_theme_color_override("font_color", Color(0.76, 0.68, 0.96))
	tabs.add_child(tech_hint)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải dữ liệu Cảng Tàu Bay..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.84, 0.9, 0.98))
	root.add_child(_status_lbl)

	_body_host = VBoxContainer.new()
	_body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_body_host)

func _process(delta: float) -> void:
	if _pressing and _dragging_ship_id.is_empty():
		_press_elapsed += delta
		if _press_elapsed >= HOLD_THRESHOLD_SEC:
			_begin_drag(_press_ship_id)

func _unhandled_key_input(event: InputEvent) -> void:
	if _dragging_ship_id.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_drag_rot = 90 if _drag_rot == 0 else 0
		_drag_valid = _validate_drag_pos(_dragging_ship_id, _drag_grid_pos, _drag_rot)
		if _grid_canvas != null:
			_grid_canvas.queue_redraw()
		get_viewport().set_input_as_handled()

func apply_state(data: Dictionary) -> void:
	_state = data
	var dock: Dictionary = _state.get("dock", {})
	var lvl := int(_state.get("portLevel", 0))
	var silver := int(_state.get("silverCoins", 0))
	var floor_num := int(_state.get("clearedFloor", 1))
	var ships: Array = _state.get("airships", [])
	_header_meta.text = "Cảng Lv.%d  •  Sàn %d×%d  •  %d Tàu  •  %d Bạc  •  Tháp Tầng %d" % [
		lvl, int(dock.get("width", 0)), int(dock.get("height", 0)), ships.size(), silver, floor_num
	]
	if _selected_ship_id.is_empty() and ships.size() > 0:
		_selected_ship_id = str(ships[0].get("id", ""))
	_render_body()

func _refresh() -> void:
	var res: Dictionary = await ApiClient.get_req("/api/base/airships")
	if not bool(res.get("ok", false)):
		_status_lbl.text = "⚠️ Lỗi tải Cảng Tàu Bay: %s" % str(res.get("error", "Không rõ"))
		return
	var data = res.get("data", {})
	if data is Dictionary:
		_status_lbl.text = "💡 Nhấn giữ chuột vào tàu bay trên lưới để kéo thả vị trí neo (nhấn R hoặc chuột phải khi đang giữ để xoay 90°)."
		apply_state(data)

func _render_body() -> void:
	for c in _body_host.get_children():
		c.queue_free()
	_grid_canvas = null
	_pressing = false
	_dragging_ship_id = ""

	for i in range(_tab_btns.size()):
		if i == _active_tab:
			_style_button(_tab_btns[i], Color(0.95, 0.78, 0.35), Color(0.18, 0.16, 0.11))
		else:
			_style_button(_tab_btns[i], Color(0.32, 0.44, 0.64), Color(0.09, 0.12, 0.19))

	if not bool(_state.get("unlockedByFloor", false)):
		var lock_card := PanelContainer.new()
		lock_card.add_theme_stylebox_override("panel", _make_card_style(Color(0.14, 0.09, 0.08), Color(0.85, 0.45, 0.25)))
		_body_host.add_child(lock_card)
		var lock_lbl := Label.new()
		lock_lbl.text = "🔒 Bến Thiên Hành mở khóa khi vượt Tháp tầng %d (hiện tại: Tầng %d)." % [
			int(_state.get("requiredFloor", 25)), int(_state.get("clearedFloor", 1))
		]
		lock_lbl.add_theme_font_size_override("font_size", 16)
		lock_lbl.add_theme_color_override("font_color", Color(1.0, 0.74, 0.42))
		lock_card.add_child(lock_lbl)
		return

	if _active_tab == 0:
		_render_dock_tab()
	else:
		_render_shipyard_tab()

func _render_dock_tab() -> void:
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 16)
	_body_host.add_child(hbox)

	var dock: Dictionary = _state.get("dock", {})
	var dock_w := maxi(1, int(dock.get("width", 4)))
	var dock_h := maxi(1, int(dock.get("height", 4)))
	var ships: Array = _state.get("airships", [])

	# Left: Unified Custom-Drawn Hangar Grid Card
	var left_card := PanelContainer.new()
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_card.add_theme_stylebox_override("panel", _make_card_style())
	hbox.add_child(left_card)

	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 8)
	left_card.add_child(left_vb)

	var grid_hdr := Label.new()
	grid_hdr.text = "📐 SÀN BÃI ĐẬU (%d×%d = %d ô) — Nhấn giữ tàu để kéo thả • Phím R / Chuột phải để xoay 90°" % [dock_w, dock_h, dock_w * dock_h]
	grid_hdr.add_theme_font_size_override("font_size", 13)
	grid_hdr.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98))
	left_vb.add_child(grid_hdr)

	_cell_px = clampf(floorf(460.0 / float(maxi(dock_w, dock_h))), 42.0, 76.0)
	_grid_canvas = Control.new()
	_grid_canvas.custom_minimum_size = Vector2(dock_w * _cell_px + 28.0, dock_h * _cell_px + 28.0)
	_grid_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_canvas.draw.connect(_draw_hangar_grid)
	_grid_canvas.gui_input.connect(_on_hangar_gui_input)
	left_vb.add_child(_grid_canvas)

	# Right: Selected Ship Inspector Card
	var right_card := PanelContainer.new()
	right_card.custom_minimum_size = Vector2(375, 0)
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", _make_card_style(Color(0.08, 0.105, 0.17, 0.98), Color(0.45, 0.38, 0.22, 0.85)))
	hbox.add_child(right_card)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right_card.add_child(right)

	var sel := _find_ship(_selected_ship_id)
	if sel.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Chưa có tàu bay nào trong bãi đậu.\n\n1. Vào [Đại Sảnh Ma Thuật → Nghiên cứu] để mở khóa mẫu tàu.\n2. Sang tab [Xưởng Chế Tạo Tàu] để đóng tàu đầu tiên!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.76, 0.82, 0.92))
		right.add_child(empty_lbl)
		return

	var name_lbl := Label.new()
	name_lbl.text = "🛸 %s  •  Lv.%d" % [str(sel.get("name", "")), int(sel.get("level", 1))]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.48))
	right.add_child(name_lbl)

	# HP Bar
	var hp := int(sel.get("hp", 0))
	var max_hp := maxi(1, int(sel.get("maxHp", 100)))
	var hp_bar := ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_bar.custom_minimum_size.y = 20
	right.add_child(hp_bar)

	var size_str := str(SIZE_LABELS.get(str(sel.get("sizeClass", "SMALL")), "Nhỏ"))
	var info := Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", Color(0.86, 0.9, 0.97))
	info.text = (
		"Hạng kích cỡ: %s (%d×%d ô • Xoay %d°)\n" +
		"Vị trí neo: Ô (%d, %d) • Trạng thái: %s\n" +
		"Độ bền (HP): %d / %d\n" +
		"Sức chở tổ đội: Tối đa %d Hero\n" +
		"Tốc độ bay: %.2fx  •  Tầm Radar: +%d ô\n" +
		"Buff Lực chiến: +%d%%\n\n%s"
	) % [
		size_str, int(sel.get("footprintW", 1)), int(sel.get("footprintH", 1)), int(sel.get("rotation", 0)),
		int(sel.get("dockX", 0)), int(sel.get("dockY", 0)), str(sel.get("status", "DOCKED")),
		hp, max_hp,
		int(sel.get("maxHeroes", 3)),
		float(sel.get("speedMult", 1.0)), int(sel.get("radarRadius", 1)),
		int(sel.get("powerBonusPct", 0)),
		str(sel.get("roleSummary", "")),
	]
	right.add_child(info)

	var is_docked := str(sel.get("status", "")) == "DOCKED"

	var rot_btn := Button.new()
	rot_btn.text = "↻ Xoay 90° tại chỗ"
	rot_btn.disabled = not is_docked
	_style_button(rot_btn, Color(0.35, 0.72, 0.95))
	rot_btn.pressed.connect(func():
		var next_rot := 90 if int(sel.get("rotation", 0)) == 0 else 0
		_move_ship(_selected_ship_id, int(sel.get("dockX", 0)), int(sel.get("dockY", 0)), next_rot)
	)
	right.add_child(rot_btn)

	var upg_cost = sel.get("upgradeCostSilver", null)
	if upg_cost != null:
		var upg_btn := Button.new()
		upg_btn.text = "⬆️ Nâng Cấp Tàu (%d Bạc)" % int(upg_cost)
		upg_btn.disabled = not is_docked
		_style_button(upg_btn, Color(0.95, 0.76, 0.28), Color(0.17, 0.14, 0.08))
		upg_btn.pressed.connect(func(): _upgrade_ship(_selected_ship_id))
		right.add_child(upg_btn)

	if hp < max_hp:
		var rep_btn := Button.new()
		rep_btn.text = "🔧 Sửa Chữa (%d Bạc)" % int(sel.get("repairCostSilver", 0))
		rep_btn.disabled = not is_docked
		_style_button(rep_btn, Color(0.28, 0.86, 0.56), Color(0.08, 0.16, 0.12))
		rep_btn.pressed.connect(func(): _repair_ship(_selected_ship_id))
		right.add_child(rep_btn)

	var dis_btn := Button.new()
	dis_btn.text = "🗑️ Tháo Dỡ (Hoàn 40% Bạc)"
	dis_btn.disabled = not is_docked
	_style_button(dis_btn, Color(0.85, 0.32, 0.32), Color(0.16, 0.08, 0.09))
	dis_btn.pressed.connect(func(): _dismantle_ship(_selected_ship_id))
	right.add_child(dis_btn)

func _find_ship(ship_id: String) -> Dictionary:
	for s in _state.get("airships", []):
		if str(s.get("id", "")) == ship_id:
			return s
	return {}

func _screen_to_grid(local_pos: Vector2) -> Vector2i:
	var rel := local_pos - _grid_origin
	return Vector2i(int(floorf(rel.x / _cell_px)), int(floorf(rel.y / _cell_px)))

func _ship_at_cell(cell: Vector2i) -> Dictionary:
	for s in _state.get("airships", []):
		var sx := int(s.get("dockX", 0))
		var sy := int(s.get("dockY", 0))
		var fw := int(s.get("footprintW", s.get("gridW", 1)))
		var fh := int(s.get("footprintH", s.get("gridH", 1)))
		if cell.x >= sx and cell.x < sx + fw and cell.y >= sy and cell.y < sy + fh:
			return s
	return {}

func _begin_drag(ship_id: String) -> void:
	var s := _find_ship(ship_id)
	if s.is_empty():
		return
	var st := str(s.get("status", ""))
	if st == "DEPLOYED" or st == "STRANDED":
		_status_lbl.text = "⚠️ Không thể di chuyển vị trí neo khi tàu đang bay ngoài bản đồ."
		_pressing = false
		return
	_dragging_ship_id = ship_id
	_selected_ship_id = ship_id
	_drag_rot = int(s.get("rotation", 0))
	_drag_grid_pos = Vector2i(int(s.get("dockX", 0)), int(s.get("dockY", 0)))
	_drag_valid = true
	_status_lbl.text = "✋ Đang giữ kéo [%s] — Kéo đến ô mong muốn rồi thả chuột (R hoặc chuột phải để xoay 90°)." % str(s.get("name", ""))
	if _grid_canvas != null:
		_grid_canvas.queue_redraw()

func _validate_drag_pos(ship_id: String, pos: Vector2i, rot: int) -> bool:
	var s := _find_ship(ship_id)
	if s.is_empty():
		return false
	var dock: Dictionary = _state.get("dock", {})
	var dock_w := int(dock.get("width", 4))
	var dock_h := int(dock.get("height", 4))
	var gw := int(s.get("gridW", 1))
	var gh := int(s.get("gridH", 1))
	var fw := gh if rot == 90 else gw
	var fh := gw if rot == 90 else gh
	if pos.x < 0 or pos.y < 0 or pos.x + fw > dock_w or pos.y + fh > dock_h:
		return false
	for other in _state.get("airships", []):
		if str(other.get("id", "")) == ship_id:
			continue
		var ox := int(other.get("dockX", 0))
		var oy := int(other.get("dockY", 0))
		var ow := int(other.get("footprintW", other.get("gridW", 1)))
		var oh := int(other.get("footprintH", other.get("gridH", 1)))
		if pos.x < ox + ow and pos.x + fw > ox and pos.y < oy + oh and pos.y + fh > oy:
			return false
	return true

func _on_hangar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _dragging_ship_id.is_empty():
			_drag_rot = 90 if _drag_rot == 0 else 0
			_drag_valid = _validate_drag_pos(_dragging_ship_id, _drag_grid_pos, _drag_rot)
			_grid_canvas.queue_redraw()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var cell := _screen_to_grid(mb.position)
				var hit := _ship_at_cell(cell)
				if not hit.is_empty():
					_pressing = true
					_press_ship_id = str(hit.get("id", ""))
					_press_start_pos = mb.position
					_press_elapsed = 0.0
					_press_grab_cell_offset = cell - Vector2i(int(hit.get("dockX", 0)), int(hit.get("dockY", 0)))
			else:
				if not _dragging_ship_id.is_empty():
					var ship_id := _dragging_ship_id
					var target := _drag_grid_pos
					var rot := _drag_rot
					var valid := _drag_valid
					_dragging_ship_id = ""
					_pressing = false
					if valid:
						_move_ship(ship_id, target.x, target.y, rot)
					else:
						_status_lbl.text = "⚠️ Vị trí thả không hợp lệ — đã trả tàu về chỗ cũ."
						_grid_canvas.queue_redraw()
				elif _pressing:
					_selected_ship_id = _press_ship_id
					_pressing = false
					_render_body()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressing and _dragging_ship_id.is_empty():
			if mm.position.distance_to(_press_start_pos) >= DRAG_DISTANCE_PX:
				_begin_drag(_press_ship_id)
		if not _dragging_ship_id.is_empty():
			var cell := _screen_to_grid(mm.position) - _press_grab_cell_offset
			var dock: Dictionary = _state.get("dock", {})
			var s := _find_ship(_dragging_ship_id)
			var gw := int(s.get("gridW", 1))
			var gh := int(s.get("gridH", 1))
			var fw := gh if _drag_rot == 90 else gw
			var fh := gw if _drag_rot == 90 else gh
			cell.x = clampi(cell.x, 0, maxi(0, int(dock.get("width", 4)) - fw))
			cell.y = clampi(cell.y, 0, maxi(0, int(dock.get("height", 4)) - fh))
			_drag_grid_pos = cell
			_drag_valid = _validate_drag_pos(_dragging_ship_id, _drag_grid_pos, _drag_rot)
			_grid_canvas.queue_redraw()

func _draw_hangar_grid() -> void:
	if _grid_canvas == null:
		return
	var dock: Dictionary = _state.get("dock", {})
	var dock_w := maxi(1, int(dock.get("width", 4)))
	var dock_h := maxi(1, int(dock.get("height", 4)))
	var font := ThemeDB.fallback_font

	# 1. Draw floor grid cells
	for y in range(dock_h):
		for x in range(dock_w):
			var r := Rect2(_grid_origin + Vector2(x * _cell_px, y * _cell_px), Vector2(_cell_px - 3.0, _cell_px - 3.0))
			_grid_canvas.draw_rect(r, Color(0.06, 0.085, 0.14, 0.95), true)
			_grid_canvas.draw_rect(r, Color(0.18, 0.26, 0.38, 0.65), false, 1.0)

	# 2. Draw each ship as ONE unified multi-cell block
	for s in _state.get("airships", []):
		var sid := str(s.get("id", ""))
		var is_dragging_this := (sid == _dragging_ship_id)
		var sx := int(s.get("dockX", 0))
		var sy := int(s.get("dockY", 0))
		var fw := int(s.get("footprintW", s.get("gridW", 1)))
		var fh := int(s.get("footprintH", s.get("gridH", 1)))
		var rect := Rect2(_grid_origin + Vector2(sx * _cell_px + 2.0, sy * _cell_px + 2.0), Vector2(fw * _cell_px - 7.0, fh * _cell_px - 7.0))
		var bp := str(s.get("blueprintCode", "SCOUT_SKIFF"))
		var col: Color = SHIP_COLORS.get(bp, Color(0.35, 0.55, 0.8))
		if is_dragging_this:
			col.a = 0.28

		_grid_canvas.draw_rect(rect, col, true)
		var border_col := Color(1.0, 0.92, 0.36) if sid == _selected_ship_id else Color(0.85, 0.92, 1.0, 0.55)
		_grid_canvas.draw_rect(rect, border_col, false, 3.0 if sid == _selected_ship_id else 1.5)

		# Ship label + footprint + HP mini-bar
		var title_txt := str(s.get("name", bp))
		if title_txt.length() > 14:
			title_txt = title_txt.substr(0, 13) + "…"
		_grid_canvas.draw_string(font, rect.position + Vector2(8, 20), title_txt, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 12, Color(1, 1, 1))
		_grid_canvas.draw_string(font, rect.position + Vector2(8, 36), "Lv.%d • %d×%d • %s" % [int(s.get("level", 1)), fw, fh, str(s.get("status", ""))], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 10, Color(0.95, 0.95, 0.82))

		var hp_ratio := clampf(float(s.get("hp", 0)) / maxf(1.0, float(s.get("maxHp", 100))), 0.0, 1.0)
		var bar_bg := Rect2(rect.position + Vector2(8, rect.size.y - 12), Vector2(maxf(12.0, rect.size.x - 16), 5))
		_grid_canvas.draw_rect(bar_bg, Color(0.05, 0.06, 0.1, 0.8), true)
		_grid_canvas.draw_rect(Rect2(bar_bg.position, Vector2(bar_bg.size.x * hp_ratio, bar_bg.size.y)), Color(0.32, 0.92, 0.52), true)

	# 3. Draw live Drag Ghost Preview
	if not _dragging_ship_id.is_empty():
		var ds := _find_ship(_dragging_ship_id)
		var gw := int(ds.get("gridW", 1))
		var gh := int(ds.get("gridH", 1))
		var fw := gh if _drag_rot == 90 else gw
		var fh := gw if _drag_rot == 90 else gh
		var grect := Rect2(_grid_origin + Vector2(_drag_grid_pos.x * _cell_px + 2.0, _drag_grid_pos.y * _cell_px + 2.0), Vector2(fw * _cell_px - 7.0, fh * _cell_px - 7.0))
		var gcol := Color(0.22, 0.92, 0.52, 0.45) if _drag_valid else Color(0.96, 0.25, 0.28, 0.48)
		var gborder := Color(0.35, 1.0, 0.62) if _drag_valid else Color(1.0, 0.35, 0.38)
		_grid_canvas.draw_rect(grect, gcol, true)
		_grid_canvas.draw_rect(grect, gborder, false, 3.0)
		_grid_canvas.draw_string(font, grect.position + Vector2(8, 22), "Thả để neo (%d×%d)" % [fw, fh], HORIZONTAL_ALIGNMENT_LEFT, grect.size.x - 12, 12, Color(1, 1, 1))

func _render_shipyard_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_host.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)

	for bp in _state.get("blueprints", []):
		var code := str(bp.get("code", ""))
		var accent: Color = SHIP_COLORS.get(code, Color(0.4, 0.55, 0.75))
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _make_card_style(Color(0.085, 0.11, 0.18, 0.96), accent))
		grid.add_child(card)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		card.add_child(hbox)

		# Mini visual footprint preview (WxH)
		var gw := int(bp.get("gridW", 2))
		var gh := int(bp.get("gridH", 2))
		var mini := Control.new()
		mini.custom_minimum_size = Vector2(74, 86)
		mini.draw.connect(func():
			var csz := 13.0
			for gy in range(gh):
				for gx in range(gw):
					var mr := Rect2(Vector2(6 + gx * csz, 8 + gy * csz), Vector2(csz - 2, csz - 2))
					mini.draw_rect(mr, accent, true)
		)
		hbox.add_child(mini)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 6)
		hbox.add_child(vb)

		var title := Label.new()
		title.text = "%s — Hạng %s (%d×%d ô)" % [
			str(bp.get("name", "")),
			str(SIZE_LABELS.get(str(bp.get("sizeClass", "SMALL")), "Nhỏ")),
			gw, gh,
		]
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color(0.96, 0.88, 0.52))
		vb.add_child(title)

		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.84, 0.89, 0.96))
		desc.text = "Sức chở: %d Hero • Tốc độ: %.2fx • Radar: +%d ô • HP: %d\n%s" % [
			int(bp.get("maxHeroes", 3)), float(bp.get("baseSpeedMult", 1.0)),
			int(bp.get("radarRadius", 1)), int(bp.get("baseMaxHp", 100)),
			str(bp.get("roleSummary", "")),
		]
		vb.add_child(desc)

		var unlocked := bool(bp.get("unlocked", false))
		var btn := Button.new()
		if unlocked:
			btn.text = "🔨 Chế Tạo (%d Bạc • %ds)" % [int(bp.get("craftCostSilver", 0)), int(bp.get("craftSeconds", 30))]
			_style_button(btn, accent, Color(0.11, 0.16, 0.25))
			btn.pressed.connect(func(): _craft_ship(code))
		else:
			btn.text = "🔒 Mở khóa tại Đại Sảnh Ma Thuật → Nghiên cứu"
			btn.disabled = true
			_style_button(btn)
		vb.add_child(btn)

func _craft_ship(blueprint_code: String) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/base/airships/craft", {"blueprintCode": blueprint_code})
	if bool(res.get("ok", false)):
		_status_lbl.text = "🔨 Đã bắt đầu chế tạo tàu bay!"
		_active_tab = 0
		await _refresh()
	else:
		_status_lbl.text = "⚠️ %s" % str(res.get("error", "Không thể chế tạo"))

func _move_ship(ship_id: String, dock_x: int, dock_y: int, rotation_deg: int) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/base/airships/%s/move" % ship_id, {
		"dockX": dock_x, "dockY": dock_y, "rotation": rotation_deg,
	})
	if bool(res.get("ok", false)):
		_status_lbl.text = "✅ Đã di chuyển tàu đến ô (%d, %d)!" % [dock_x, dock_y]
		await _refresh()
	else:
		_status_lbl.text = "⚠️ %s" % str(res.get("error", "Không thể di chuyển vị trí neo"))
		if _grid_canvas != null:
			_grid_canvas.queue_redraw()

func _upgrade_ship(ship_id: String) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/base/airships/%s/upgrade" % ship_id, {})
	if bool(res.get("ok", false)):
		_status_lbl.text = "⬆️ Đã nâng cấp tàu bay!"
		await _refresh()
	else:
		_status_lbl.text = "⚠️ %s" % str(res.get("error", "Không thể nâng cấp"))

func _repair_ship(ship_id: String) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/base/airships/%s/repair" % ship_id, {})
	if bool(res.get("ok", false)):
		_status_lbl.text = "🔧 Đã bắt đầu sửa chữa tàu bay!"
		await _refresh()
	else:
		_status_lbl.text = "⚠️ %s" % str(res.get("error", "Không thể sửa chữa"))

func _dismantle_ship(ship_id: String) -> void:
	var res: Dictionary = await ApiClient.delete_req("/api/base/airships/%s" % ship_id)
	if bool(res.get("ok", false)):
		_selected_ship_id = ""
		_status_lbl.text = "🗑️ Đã tháo dỡ tàu bay và hoàn trả 40% Bạc."
		await _refresh()
	else:
		_status_lbl.text = "⚠️ %s" % str(res.get("error", "Không thể tháo dỡ"))

func _close() -> void:
	closed.emit()
	queue_free()
