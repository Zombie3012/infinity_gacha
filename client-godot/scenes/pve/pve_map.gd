extends Control

const Ui := preload("res://scripts/ui/pve_ui.gd")
const PartyEditor := preload("res://scripts/ui/pve_party_editor.gd")
const UnitActor := preload("res://scenes/common/unit_actor_3d.tscn")
const SYMBOLS := {"CAMP": "⌂", "EMPTY": "·", "RESOURCE": "◆", "ENEMY": "⚔", "BOSS": "♛", "UNKNOWN": "?", "WALL": "▦", "ROCK": "▲"}
const TILE_NAMES := {"CAMP": "Điểm xuất phát", "EMPTY": "Đường đi", "RESOURCE": "Tài nguyên", "ENEMY": "Đội địch", "BOSS": "Boss tầng", "UNKNOWN": "Chưa khám phá", "WALL": "Tường", "ROCK": "Đá"}
const BASE_TILE_W := 46.0
const BASE_TILE_H := 44.0
const ZOOM_MIN := 0.65
const ZOOM_MAX := 1.50
const PAN_DRAG_THRESHOLD := 8.0

var _title: Label
var _status: Label
var _connection: Label
var _food: Label
var _enter: Button
var _retry: Button
var _party_picker: OptionButton
var _deploy: Button
var _edit: Button
var _create: Button
var _recall: Button
var _stone: Button
var _reset_tower: Button
var _auto: Button
var _items_btn: Button
var _squads: HBoxContainer
var _reports: VBoxContainer
var _more_reports: Button
var _history_cursor: String = ""
var _history_busy: bool = false
var _grid: GridContainer
var _breadcrumbs: HBoxContainer
var _portal_actions: HBoxContainer
var _nav_strip: Control
var _objective: Label
var _view_area_id: String = "floor"
var _follow_key: String = ""
var _map_width: int = 12
var _map_height: int = 12
var _map_hint: Label
var _tiles: Array[Button] = []
var _party_ids: Array = []
var _report_rows: Array = []
var _editor: Control
var _eta_elapsed: float = 0.0
var _portrait_views: Dictionary = {}

# Full-bleed Map Pan & Zoom + Collapsible Drawers
var _map_viewport: Control
var _map_canvas: Control
var _map_zoom: float = 1.0
var _map_offset: Vector2 = Vector2.ZERO
var _map_centered_once: bool = false
var _pan_pressing: bool = false
var _pan_dragging: bool = false
var _pan_start_pos: Vector2 = Vector2.ZERO
var _pan_last_pos: Vector2 = Vector2.ZERO
var _suppress_tile_press: bool = false
var _zoom_label: Label
var _party_drawer: Control
var _report_drawer: Control
var _legend_card: Control
var _party_drawer_btn: Button
var _report_drawer_btn: Button
var _stone_badge: Label
var _info_panel: Control

func _ready() -> void:
	_build_ui()
	_render_controls()
	PveState.snapshot_changed.connect(_render_state)
	PveState.command_changed.connect(_render_controls)
	PveState.message_changed.connect(_set_message)
	if not GameState.is_logged_in():
		_set_message("Hãy đăng nhập trước khi vào map chinh phạt.", true)
		return
	_set_message("Đang tải đội và bản đồ...", false)
	await GameState.refresh_heroes()
	if GameState.base_overview.is_empty():
		await GameState.refresh_base_overview()
	await PveState.activate()
	_render_state()
	await _load_reports()
	if not PveState.pending_command.is_empty():
		_set_message("Có lệnh chưa được xác nhận. Bấm Thử lại lệnh để kiểm tra an toàn.", true)

func _process(delta: float) -> void:
	_eta_elapsed += delta
	if _eta_elapsed >= 1.0:
		_eta_elapsed = 0.0
		_render_eta()

func _input(event: InputEvent) -> void:
	if _map_viewport == null or not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed and _is_point_in_map(mb.global_position):
			_set_map_zoom(_map_zoom + 0.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed and _is_point_in_map(mb.global_position):
			_set_map_zoom(_map_zoom - 0.12)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _is_point_in_map(mb.global_position) and not _is_pointer_over_hud(mb.global_position):
				_pan_pressing = true
				_pan_dragging = false
				_suppress_tile_press = false
				_pan_start_pos = mb.global_position
				_pan_last_pos = mb.global_position
			elif not mb.pressed and _pan_pressing:
				_pan_pressing = false
				if _pan_dragging:
					_suppress_tile_press = true
					call_deferred("_clear_tile_suppress")
				_pan_dragging = false
	elif event is InputEventMouseMotion and _pan_pressing:
		var mm := event as InputEventMouseMotion
		if not _pan_dragging and mm.global_position.distance_to(_pan_start_pos) >= PAN_DRAG_THRESHOLD:
			_pan_dragging = true
			_suppress_tile_press = true
		if _pan_dragging:
			var delta := mm.global_position - _pan_last_pos
			_pan_last_pos = mm.global_position
			_map_offset += delta
			_apply_map_transform()

func _clear_tile_suppress() -> void:
	_suppress_tile_press = false

func _is_point_in_map(pos: Vector2) -> bool:
	return _map_viewport != null and _map_viewport.get_global_rect().has_point(pos)

func _is_pointer_over_hud(pos: Vector2) -> bool:
	for panel_node in [_party_drawer, _report_drawer, _legend_card, _info_panel]:
		if panel_node != null and panel_node.visible and panel_node.get_global_rect().has_point(pos):
			return true
	return false

func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Ui.INK
	add_child(background)

	# Layer 1: Full-Bleed Pannable & Zoomable Tactical Map
	_map_viewport = Control.new()
	_map_viewport.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_viewport.clip_contents = true
	_map_viewport.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_map_viewport)

	_map_canvas = Control.new()
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_map_viewport.add_child(_map_canvas)

	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	_map_canvas.add_child(_grid)
	_ensure_grid(12, 12)

	# Layer 2: Floating HUD Overlay
	var hud_margin := MarginContainer.new()
	hud_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		hud_margin.add_theme_constant_override("margin_" + edge, 12)
	add_child(hud_margin)

	var hud_col := VBoxContainer.new()
	hud_col.add_theme_constant_override("separation", 8)
	hud_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_margin.add_child(hud_col)

	# Top Floating Header Bar
	var top_box := Ui.glass_panel(hud_col, Ui.BORDER, 12, 14, 8)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	top_box.add_child(header)

	_title = Ui.label(header, "CHINH PHẠT · TẦNG 1", 19, Ui.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_connection = Ui.label(header, "● Đang kết nối", 12, Ui.MUTED)
	_enter = Ui.button(header, "Bắt đầu khám phá", _enter_map, true, "gold")
	_retry = Ui.button(header, "Thử lại lệnh", func(): await PveState.retry_pending(), true, "danger")
	_retry.visible = false
	_reset_tower = Ui.button(header, "DEV · Reset", _confirm_reset_tower, false, "danger")
	_reset_tower.visible = false
	Ui.button(header, "Tải lại", func(): await PveState.refresh(), false, "ghost")
	Ui.button(header, "🗼 Ngoài Tháp", _back_to_tower, false, "ghost")
	Ui.button(header, "Về căn cứ", _back_to_base, false, "ghost")

	# Sub-top Strip: Area Breadcrumbs & Portals
	var sub_strip := HBoxContainer.new()
	sub_strip.add_theme_constant_override("separation", 10)
	sub_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_col.add_child(sub_strip)

	var nav_card := Ui.glass_panel(sub_strip, Ui.BORDER_SOFT, 10, 10, 6)
	_nav_strip = nav_card.get_parent()
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 6)
	nav_card.add_child(nav_row)
	_breadcrumbs = HBoxContainer.new()
	_breadcrumbs.add_theme_constant_override("separation", 4)
	nav_row.add_child(_breadcrumbs)
	_portal_actions = HBoxContainer.new()
	_portal_actions.add_theme_constant_override("separation", 4)
	nav_row.add_child(_portal_actions)

	# Middle Layer: Collapsible Left Drawer (Party) + Center Viewport + Right Controls & Report Drawer
	var mid_row := HBoxContainer.new()
	mid_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_row.add_theme_constant_override("separation", 10)
	mid_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_col.add_child(mid_row)

	var party_col := Ui.glass_panel(mid_row, Ui.GOLD, 12, 12, 10)
	_party_drawer = party_col.get_parent()
	_party_drawer.custom_minimum_size.x = 274
	_party_drawer.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var p_hdr := HBoxContainer.new()
	party_col.add_child(p_hdr)
	var p_title := Ui.label(p_hdr, "QUẢN LÝ ĐỘI", 15, Ui.GOLD)
	p_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.button(p_hdr, "✕", func(): _toggle_party_drawer(false), false, "ghost").custom_minimum_size = Vector2(30, 28)
	_party_picker = OptionButton.new()
	_party_picker.custom_minimum_size = Vector2(244, 34)
	_party_picker.item_selected.connect(func(index: int):
		if index >= 0 and index < _party_ids.size():
			PveState.selected_party_id = str(_party_ids[index])
			_render_controls()
	)
	party_col.add_child(_party_picker)
	_deploy = Ui.button(party_col, "Triển khai đội lên Map", _deploy_party, true, "gold")
	_edit = Ui.button(party_col, "Đội hình & chiến thuật", _edit_party)
	_create = Ui.button(party_col, "+ Tạo đội mới", func(): _open_editor({}), true)

	var mid_spacer := Control.new()
	mid_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid_row.add_child(mid_spacer)

	var right_stack := VBoxContainer.new()
	right_stack.add_theme_constant_override("separation", 8)
	right_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid_row.add_child(right_stack)

	# Right Top Map Controls: Zoom + Center + Legend Toggle
	var zoom_row_wrap := HBoxContainer.new()
	zoom_row_wrap.alignment = BoxContainer.ALIGNMENT_END
	zoom_row_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_stack.add_child(zoom_row_wrap)
	var zoom_col := Ui.glass_panel(zoom_row_wrap, Ui.BORDER_SOFT, 10, 8, 6)
	var zoom_bar := HBoxContainer.new()
	zoom_bar.add_theme_constant_override("separation", 4)
	zoom_col.add_child(zoom_bar)
	var z_out := Ui.button(zoom_bar, "−", func(): _set_map_zoom(_map_zoom - 0.15), false, "ghost")
	z_out.custom_minimum_size = Vector2(32, 30)
	_zoom_label = Ui.label(zoom_bar, "100%", 12, Ui.TEXT)
	_zoom_label.custom_minimum_size.x = 42
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var z_in := Ui.button(zoom_bar, "+", func(): _set_map_zoom(_map_zoom + 0.15), false, "ghost")
	z_in.custom_minimum_size = Vector2(32, 30)
	var z_center := Ui.button(zoom_bar, "🎯", _center_map_on_selected, false, "accent")
	z_center.custom_minimum_size = Vector2(34, 30)
	z_center.tooltip_text = "Căn giữa vào đội đang chọn"
	var legend_btn := Ui.button(zoom_bar, "?", func(): _legend_card.visible = not _legend_card.visible, false, "ghost")
	legend_btn.custom_minimum_size = Vector2(30, 30)
	legend_btn.tooltip_text = "Bật/tắt Chú giải bản đồ"

	var legend_col := Ui.glass_panel(right_stack, Ui.BORDER_SOFT, 10, 12, 8)
	_legend_card = legend_col.get_parent()
	_legend_card.visible = false
	Ui.label(legend_col, "CHÚ GIẢI BẢN ĐỒ", 12, Ui.GOLD)
	var legend_lbl := Ui.label(legend_col, "⌂ Căn cứ   ◆ Tài nguyên   ⚔ Địch   ♛ Boss\n⟲ Điểm dịch chuyển   🎒 Đồ rơi   ✓ Đã dọn\n• Kéo-vuốt để di chuyển map · Cuộn để Zoom", 12, Ui.MUTED)
	legend_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Right Info Panel: Objective & Rations
	var info_col := Ui.glass_panel(right_stack, Ui.GOLD, 12, 12, 10)
	_info_panel = info_col.get_parent()
	_info_panel.custom_minimum_size.x = 282
	Ui.label(info_col, "🎯 MỤC TIÊU & KHẨU PHẦN", 13, Ui.GOLD)
	_objective = Ui.label(info_col, "Mục tiêu: Hạ boss được chỉ định", 13, Ui.TEXT)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 8)
	info_col.add_child(res_row)
	var food_pill := Ui.badge(res_row, "🍖 Khẩu phần: 0", Color("1c3330"), Ui.TEAL, Ui.TEAL, 12)
	_food = food_pill.get_child(0) as Label
	var stone_pill := Ui.badge(res_row, "💎 Đá: 0", Color("232e47"), Ui.BORDER, Ui.TEXT, 12)
	_stone_badge = stone_pill.get_child(0) as Label
	_map_hint = Ui.label(info_col, "Đã khám phá: 0/144 ô", 12, Ui.MUTED)
	_status = Ui.label(info_col, "", 12, Ui.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false

	# Right Collapsible Report Drawer
	var rep_col := Ui.glass_panel(right_stack, Ui.BORDER, 12, 12, 10)
	_report_drawer = rep_col.get_parent()
	_report_drawer.custom_minimum_size.x = 282
	_report_drawer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report_drawer.visible = false
	var r_hdr := HBoxContainer.new()
	rep_col.add_child(r_hdr)
	var r_title := Ui.label(r_hdr, "CHIẾN BÁO & TRẬN ĐẤU", 15, Ui.GOLD)
	r_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.button(r_hdr, "✕", func(): _toggle_report_drawer(false), false, "ghost").custom_minimum_size = Vector2(30, 28)
	Ui.label(rep_col, "Mở trận thủ công để điều khiển trực tiếp.", 12, Ui.MUTED)
	var report_scroll := ScrollContainer.new()
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rep_col.add_child(report_scroll)
	_reports = VBoxContainer.new()
	_reports.custom_minimum_size.x = 250
	_reports.add_theme_constant_override("separation", 6)
	_reports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.add_child(_reports)
	_more_reports = Ui.button(rep_col, "Tải chiến báo cũ hơn", func(): await _load_reports(true), false, "ghost")
	_more_reports.visible = false

	# Bottom Floating Dock: Squad Cards + Quick Command Bar
	var dock_col := Ui.glass_panel(hud_col, Ui.BORDER, 14, 12, 10)
	var dock_row := HBoxContainer.new()
	dock_row.add_theme_constant_override("separation", 12)
	dock_col.add_child(dock_row)

	var squads_wrap := VBoxContainer.new()
	squads_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squads_wrap.add_theme_constant_override("separation", 4)
	dock_row.add_child(squads_wrap)
	Ui.label(squads_wrap, "ĐỘI TRÊN MAP (TỐI ĐA 3)", 11, Ui.MUTED)
	_squads = HBoxContainer.new()
	_squads.add_theme_constant_override("separation", 8)
	squads_wrap.add_child(_squads)

	var actions_col := VBoxContainer.new()
	actions_col.add_theme_constant_override("separation", 6)
	dock_row.add_child(actions_col)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	actions_col.add_child(row1)
	_auto = Ui.button(row1, "Bật tự khám phá", _toggle_auto, true)
	_recall = Ui.button(row1, "Thu hồi", _recall_squad)
	_stone = Ui.button(row1, "Đá dịch chuyển ×0", _place_recall_point)
	_items_btn = Ui.button(row1, "🎒 Vật phẩm", func():
		if PveState.selected_squad_id.is_empty(): return
		var modal = preload("res://scripts/ui/pve_field_items_modal.gd").new()
		modal.squad_id = PveState.selected_squad_id
		add_child(modal)
	)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	row2.alignment = BoxContainer.ALIGNMENT_END
	actions_col.add_child(row2)
	_party_drawer_btn = Ui.button(row2, "👥 Quản lý & Triển khai Đội", func(): _toggle_party_drawer(not _party_drawer.visible), false, "gold")
	_report_drawer_btn = Ui.button(row2, "📜 Chiến báo (0)", func(): _toggle_report_drawer(not _report_drawer.visible), false, "ghost")

func _toggle_party_drawer(show_drawer: bool) -> void:
	if _party_drawer != null:
		_party_drawer.visible = show_drawer

func _toggle_report_drawer(show_drawer: bool) -> void:
	if _report_drawer != null:
		_report_drawer.visible = show_drawer

func _set_map_zoom(next_zoom: float) -> void:
	_map_zoom = clampf(next_zoom, ZOOM_MIN, ZOOM_MAX)
	if _zoom_label != null:
		_zoom_label.text = "%d%%" % int(round(_map_zoom * 100.0))
	var tw := roundi(BASE_TILE_W * _map_zoom)
	var th := roundi(BASE_TILE_H * _map_zoom)
	for button in _tiles:
		button.custom_minimum_size = Vector2(tw, th)
		button.add_theme_font_size_override("font_size", maxi(11, roundi(15.0 * _map_zoom)))
		var portraits := button.get_children().filter(func(c): return c.has_meta("pve_portrait"))
		for idx in range(portraits.size()):
			var p: Control = portraits[idx]
			p.position = Vector2(float(idx) * float(tw - 4) / maxf(1.0, float(portraits.size())), 2)
			p.size = Vector2(float(tw - 4) / maxf(1.0, float(portraits.size())), float(th - 4))
	_apply_map_transform()

func _center_map_on_selected() -> void:
	if _map_viewport == null or _grid == null:
		return
	var vp_size := _map_viewport.size
	if vp_size.x <= 1.0 or vp_size.y <= 1.0:
		vp_size = Vector2(1280, 720)
	var tw := BASE_TILE_W * _map_zoom + 3.0
	var th := BASE_TILE_H * _map_zoom + 3.0
	var grid_w := float(_map_width) * tw
	var grid_h := float(_map_height) * th
	var selected: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	if not selected.is_empty() and str(selected.get("areaId", "floor")) == _view_area_id:
		var sx := (float(int(selected.get("x", 0))) + 0.5) * tw
		var sy := (float(int(selected.get("y", 0))) + 0.5) * th
		_map_offset = vp_size * 0.5 - Vector2(sx, sy) - Vector2(0, 18)
	else:
		_map_offset = Vector2((vp_size.x - grid_w) * 0.5, (vp_size.y - grid_h) * 0.5 - 18.0)
	_apply_map_transform()

func _apply_map_transform() -> void:
	if _map_canvas == null or _map_viewport == null:
		return
	var tw := BASE_TILE_W * _map_zoom + 3.0
	var th := BASE_TILE_H * _map_zoom + 3.0
	var grid_w := float(_map_width) * tw
	var grid_h := float(_map_height) * th
	var vp_size := _map_viewport.size
	if vp_size.x > 10.0 and vp_size.y > 10.0:
		var margin_x := maxf(240.0, vp_size.x * 0.45)
		var margin_y := maxf(220.0, vp_size.y * 0.45)
		_map_offset.x = clampf(_map_offset.x, vp_size.x - grid_w - margin_x, margin_x)
		_map_offset.y = clampf(_map_offset.y, vp_size.y - grid_h - margin_y, margin_y)
	_map_canvas.position = _map_offset

func _render_state() -> void:
	var data: Dictionary = PveState.snapshot
	var map_value: Variant = data.get("map")
	var map_data: Dictionary = map_value if map_value is Dictionary else {}
	_title.text = "CHINH PHẠT · TẦNG %d" % int(map_data.get("floor", data.get("currentFloor", GameState.current_floor)))
	_food.text = "🍖 Khẩu phần: %d" % int(data.get("food", 0))
	if _stone_badge != null:
		_stone_badge.text = "💎 Đá: %d" % int(PveState.snapshot.get("teleportStones", 0))
	_enter.text = "Tiến vào tầng tiếp theo" if str(map_data.get("status", "")) == "CLEARED" else "Bắt đầu khám phá"

	Ui.clear(_squads)
	var active: Array = PveState.active_squads()
	if active.is_empty():
		Ui.label(_squads, "Chưa triển khai đội nào (10 FOOD/Hero). Mở «Quản lý & Triển khai Đội» để xuất kích.", 12, Ui.MUTED)
		PveState.selected_squad_id = ""
	elif not active.any(func(squad): return str(squad.get("id", "")) == PveState.selected_squad_id):
		PveState.selected_squad_id = str(active[0].get("id", ""))

	for index in range(active.size()):
		var squad: Dictionary = active[index]
		var squad_id := str(squad.get("id", ""))
		var is_selected := (squad_id == PveState.selected_squad_id)
		var state_val := str(squad.get("status", ""))
		var tone := "danger" if state_val == "FIGHTING" else ("accent" if is_selected else "default")
		var row := Ui.button(_squads, "", func():
			PveState.selected_squad_id = squad_id
			_follow_key = ""
			_render_state()
			_center_map_on_selected()
		, is_selected, tone)
		row.custom_minimum_size = Vector2(215, 62)
		row.clip_text = true
		row.set_meta("squad_id", squad_id)
		row.set_meta("ordinal", index + 1)
	_render_eta()

	_party_ids.clear()
	_party_picker.clear()
	for party in data.get("parties", []):
		_party_ids.append(str(party.get("id", "")))
		_party_picker.add_item("%s · %d Hero" % [str(party.get("name", "Đội")), party.get("members", []).size()])
	if not _party_ids.has(PveState.selected_party_id) and not _party_ids.is_empty():
		PveState.selected_party_id = str(_party_ids[0])
	var selected_index: int = _party_ids.find(PveState.selected_party_id)
	if selected_index >= 0:
		_party_picker.select(selected_index)

	var selected_squad: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	var follow_key := "%s:%s" % [PveState.selected_squad_id, selected_squad.get("areaId", "floor")]
	if follow_key != _follow_key:
		_view_area_id = str(selected_squad.get("areaId", "floor"))
		_follow_key = follow_key
	var area_data: Dictionary = map_data
	for candidate in data.get("areas", []):
		if str(candidate.get("id", "")) == _view_area_id:
			area_data = candidate.duplicate(true)
			area_data["status"] = map_data.get("status", "")
	_ensure_grid(int(area_data.get("width", 12)), int(area_data.get("height", 12)))
	if not _map_centered_once:
		_map_centered_once = true
		call_deferred("_center_map_on_selected")
	_render_navigation(area_data, selected_squad)

	var objective: Dictionary = data.get("objective", {})
	_objective.text = "Mục tiêu: Hạ boss · %d/%d%s" % [int(objective.get("progress", 0)), int(objective.get("required", 1)), " · Hoàn tất" if str(objective.get("status", "")) == "COMPLETED" else ""]
	if str(map_data.get("recallPolicy", "FREE")) == "UNTIL_COMPLETE" and str(map_data.get("status", "")) == "ACTIVE":
		_objective.text += " · 🔒 Cấm thu hồi"
	_render_tiles(area_data, active)

	var existing_ids: Array = _report_rows.map(func(row): return str(row.get("battleId", "")))
	for event_value in data.get("events", []):
		if str(event_value.get("kind", "")) == "SQUAD_DETECTED":
			_set_message("Một đội đã bị quái phát hiện! Tìm vật cản để cắt tầm nhìn.", true)
		elif str(event_value.get("kind", "")) == "SQUAD_LOST":
			_set_message("Quái mất dấu, đang tìm tại vị trí cuối nhìn thấy.", false)
		if str(event_value.get("kind", "")) == "BATTLE_COMPLETED":
			var details: Dictionary = event_value.get("data", {})
			if bool(details.get("ambush", false)):
				_set_message("Đội bị phục kích! Quái có pha đánh mở màn.", true)
			if not existing_ids.has(str(details.get("battleId", ""))):
				_report_rows.push_front(details)
			else:
				for row in _report_rows:
					if row.get("battleId") == details.get("battleId"): row.merge(details, true)
	for squad in data.get("squads", []):
		var battle_id: String = PveState.optional_id(squad.get("lastBattleId"))
		if not battle_id.is_empty() and not _report_rows.any(func(row): return str(row.get("battleId", "")) == battle_id):
			_report_rows.append({"battleId": battle_id, "squadId": squad.get("id", ""), "name": squad.get("name", "Đội")})

	Ui.clear(_reports)
	var has_live_fight := false
	for result in _report_rows:
		var winner := str(result.get("winner", ""))
		var label := "Thắng" if winner == "HERO" else "Thất bại" if winner == "ENEMY" else "Hòa" if winner == "DRAW" else "Chiến báo"
		var report_id := str(result.get("battleId", ""))
		var is_fighting := false
		var squad_name := str(result.get("name", "Đội"))
		for squad in data.get("squads", []):
			if squad.get("lastBattleId") == report_id and squad.get("status") == "FIGHTING":
				is_fighting = true
				has_live_fight = true
				squad_name = str(squad.get("name", "Đội"))
		var rep_card := Ui.card(_reports, Ui.CARD, Ui.DANGER if is_fighting else (Ui.SUCCESS if winner == "HERO" else Ui.BORDER))
		var rep_btn := Ui.button(rep_card, ("⚔️ Điều khiển • " + squad_name) if is_fighting else ("Tầng %d · %s · Xem lại" % [int(result.get("floor", 1)), label]), func(): _watch_report(report_id), is_fighting, "danger" if is_fighting else ("accent" if winner == "HERO" else "default"))
		rep_btn.tooltip_text = "Báo cáo trận đấu và phần thưởng đã lưu"
		if result.has("silverReward"):
			Ui.label(rep_card, "+%d Silver · +%d EXP/Hero" % [int(result.get("silverReward", 0)), int(result.get("heroExpReward", 0))], 11, Ui.GOLD)
	if _report_rows.is_empty():
		Ui.label(_reports, "Chưa có trận đấu.\nDi chuyển đội đến ô có địch.", 12, Ui.MUTED)
	if _report_drawer_btn != null:
		_report_drawer_btn.text = ("⚔️ Điều khiển trận (%d)" if has_live_fight else "📜 Chiến báo (%d)") % _report_rows.size()
	_render_controls()

func _load_reports(more: bool = false) -> void:
	if _history_busy or not GameState.is_logged_in():
		return
	_history_busy = true
	_more_reports.disabled = true
	var endpoint := "/api/pve/battles?limit=30"
	if more and not _history_cursor.is_empty():
		endpoint += "&before=" + _history_cursor.uri_encode()
	var response: Dictionary = await ApiClient.get_req(endpoint)
	_history_busy = false
	if not is_inside_tree():
		return
	if response.get("ok", false) and response.get("data") is Dictionary:
		var data: Dictionary = response["data"]
		for entry in data.get("battles", []):
			var report_id := str(entry.get("id", ""))
			var detail: Dictionary = entry.get("settlement", {}).duplicate(true)
			detail["battleId"] = report_id
			detail["winner"] = str(entry.get("winner", ""))
			detail["name"] = str(entry.get("name", "Đội"))
			var matched := false
			for index in range(_report_rows.size()):
				if str(_report_rows[index].get("battleId", "")) == report_id:
					_report_rows[index] = detail
					matched = true
					break
			if not matched:
				_report_rows.append(detail)
		_history_cursor = PveState.optional_id(data.get("nextCursor"))
		_more_reports.visible = not _history_cursor.is_empty()
		_render_state()
	_more_reports.disabled = false

func _ensure_grid(width: int, height: int) -> void:
	if _tiles.size() == width * height and _map_width == width:
		return
	for button in _tiles:
		_grid.remove_child(button)
		button.queue_free()
	_tiles.clear()
	_map_width = width
	_map_height = height
	_grid.columns = width
	var tw := roundi(BASE_TILE_W * _map_zoom)
	var th := roundi(BASE_TILE_H * _map_zoom)
	for index in range(width * height):
		var button := Button.new()
		button.custom_minimum_size = Vector2(tw, th)
		button.add_theme_font_size_override("font_size", maxi(11, roundi(15.0 * _map_zoom)))
		button.pressed.connect(func():
			if _suppress_tile_press:
				return
			_move_selected(index % width, index / width)
		)
		_grid.add_child(button)
		_tiles.append(button)

func _render_navigation(area: Dictionary, selected: Dictionary) -> void:
	Ui.clear(_breadcrumbs)
	Ui.clear(_portal_actions)
	var chain: Array = [area]
	var parent_id: String = PveState.optional_id(area.get("parentAreaId"))
	while not parent_id.is_empty():
		var found := false
		for candidate in PveState.snapshot.get("areas", []):
			if str(candidate.get("id", "")) == parent_id:
				chain.push_front(candidate)
				parent_id = PveState.optional_id(candidate.get("parentAreaId"))
				found = true
				break
		if not found:
			break
	for entry in chain:
		var area_id := str(entry.get("id", "floor"))
		Ui.button(_breadcrumbs, str(entry.get("name", "Tầng")), func():
			_view_area_id = area_id
			_render_state()
			_center_map_on_selected()
		, area_id == _view_area_id)
	for portal in area.get("portals", []):
		if str(selected.get("areaId", "floor")) != _view_area_id or int(portal.get("x", -1)) != int(selected.get("x", -2)) or int(portal.get("y", -1)) != int(selected.get("y", -2)):
			continue
		var portal_id := str(portal.get("id", ""))
		var action := Ui.button(_portal_actions, str(portal.get("label", "Qua cửa")), func():
			await PveState.send_command("/api/pve/squads/%s/portal" % PveState.selected_squad_id, {"areaId": _view_area_id, "portalId": portal_id})
		, true, "gold")
		action.disabled = not _can_command() or str(selected.get("status", "")) == "FIGHTING"
	if _nav_strip != null:
		_nav_strip.visible = _breadcrumbs.get_child_count() > 0 or _portal_actions.get_child_count() > 0

func _render_tiles(map_data: Dictionary, active: Array) -> void:
	var known_count := 0
	var nodes: Array = map_data.get("tiles", [])
	var selected: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	var tw := BASE_TILE_W * _map_zoom
	var th := BASE_TILE_H * _map_zoom
	for index in range(_tiles.size()):
		var button: Button = _tiles[index]
		var node: Dictionary = nodes[index] if index < nodes.size() else {}
		var kind := str(node.get("kind", "UNKNOWN"))
		var consumed := bool(node.get("collected", false)) or bool(node.get("cleared", false))
		var caption := str(SYMBOLS.get(kind, "?"))
		var is_recall_point := false
		var floor_map: Dictionary = PveState.snapshot.get("map", {}) if PveState.snapshot.get("map") is Dictionary else {}
		for point in floor_map.get("recallPoints", []):
			if str(point.get("areaId", "floor")) == _view_area_id and int(point.get("x", -1)) == index % _map_width and int(point.get("y", -1)) == index / _map_width:
				is_recall_point = true
		for portal in map_data.get("portals", []):
			if int(portal.get("x", -1)) == index % _map_width and int(portal.get("y", -1)) == index / _map_width:
				if str(map_data.get("level", "")) != "FLOOR":
					caption = "↪"
		for building in map_data.get("buildings", []):
			if str(map_data.get("level", "")) == "FLOOR" and int(building.get("parentTileId", -1)) == index:
				caption = "⌂+"
		for enemy in map_data.get("enemies", []):
			if int(enemy.get("x", -1)) == index % _map_width and int(enemy.get("y", -1)) == index / _map_width:
				caption = "♛" if bool(enemy.get("boss", false)) else "⚔"
		var background := Color("182b32") if kind != "UNKNOWN" else Color("101a29")
		if is_recall_point:
			caption = "⟲"
		var radar := false
		for enemy in map_data.get("enemies", []):
			if enemy.get("radarTileIds", []).has(index) and kind != "UNKNOWN":
				radar = true
		if radar:
			background = background.lerp(Color("70383d"), 0.45)
		var border := Color("29454d") if kind != "UNKNOWN" else Color("1d2a3d")
		if kind != "UNKNOWN":
			known_count += 1
		if consumed:
			caption = "✓"
		elif kind in ["ENEMY", "BOSS"]:
			background = Color("56313a") if kind == "ENEMY" else Color("60402f")
		elif kind == "RESOURCE":
			background = Color("254b3d")
		elif kind == "CAMP":
			background = Color("34506a")
		for drop in map_data.get("drops", []):
			if int(drop.get("x", -1)) == index % _map_width and int(drop.get("y", -1)) == index / _map_width:
				caption = "🎒"
		for step in selected.get("route", []) if str(selected.get("areaId", "floor")) == _view_area_id else []:
			if int(step.get("x", -1)) == index % _map_width and int(step.get("y", -1)) == index / _map_width:
				border = Ui.GOLD
		for child in button.get_children():
			if child.has_meta("pve_portrait"):
				button.remove_child(child)
				child.queue_free()
		var occupants: Array = []
		for ordinal in range(active.size()):
			var squad: Dictionary = active[ordinal]
			if str(squad.get("areaId", "floor")) != _view_area_id:
				continue
			if int(squad.get("x", -1)) == index % _map_width and int(squad.get("y", -1)) == index / _map_width:
				occupants.append({"squad": squad, "ordinal": ordinal + 1})
				if str(squad.get("id", "")) == PveState.selected_squad_id:
					background = Color("38677a")
					border = Ui.TEAL
		button.text = "" if not occupants.is_empty() else caption
		for position in range(occupants.size()):
			var occupant: Dictionary = occupants[position]
			var squad: Dictionary = occupant["squad"]
			var hero_id := PveState.optional_id(squad.get("leaderHeroId"))
			var hero: Dictionary = GameState.get_hero_by_id(hero_id)
			var portrait := TextureRect.new()
			portrait.set_meta("pve_portrait", true)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.position = Vector2(float(position) * (tw - 4.0) / occupants.size(), 2)
			portrait.size = Vector2((tw - 4.0) / occupants.size(), th - 4.0)
			portrait.texture = _leader_portrait(hero_id, hero)
			portrait.tooltip_text = str(hero.get("name", "Đội trưởng"))
			button.add_child(portrait)
		button.add_theme_stylebox_override("normal", Ui.style(background, border, 5, 2, 2))
		button.add_theme_stylebox_override("hover", Ui.style(background.lightened(0.15), Ui.GOLD, 5, 2, 2))
		button.add_theme_stylebox_override("disabled", Ui.style(background, border, 5, 2, 2))
		button.tooltip_text = "(%d, %d) · %s" % [index % _map_width, index / _map_width, str(TILE_NAMES.get(kind, kind))]
		if is_recall_point:
			button.tooltip_text += "\nĐiểm dịch chuyển · Các đội đứng tại đây có thể thu hồi"
		for building in map_data.get("buildings", []):
			if str(map_data.get("level", "")) == "FLOOR" and int(building.get("parentTileId", -1)) == index:
				button.tooltip_text += "\n" + str(building.get("name", "Công trình"))
		for occupant in occupants:
			var leader: Dictionary = GameState.get_hero_by_id(PveState.optional_id(occupant["squad"].get("leaderHeroId")))
			button.tooltip_text += "\nĐội %d · %s · Đội trưởng: %s" % [occupant["ordinal"], occupant["squad"].get("name", "Đội"), leader.get("name", "Hero")]
		if node.get("resource") is Dictionary and not consumed:
			button.tooltip_text += "\n%s ×%d" % [str(node["resource"].get("itemId", "")), int(node["resource"].get("quantity", 0))]
		button.disabled = not _can_command() or selected.is_empty() or str(map_data.get("status", "")) != "ACTIVE"
	_map_hint.text = "%d/%d ô · %dm/ô" % [known_count, _tiles.size(), int(map_data.get("metersPerTile", 1000))]

func _leader_portrait(hero_id: String, hero: Dictionary) -> Texture2D:
	if hero_id.is_empty() or hero.is_empty():
		return null
	if _portrait_views.has(hero_id) and is_instance_valid(_portrait_views[hero_id]):
		return _portrait_views[hero_id].get_texture()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var actor: UnitActor3D = UnitActor.instantiate()
	viewport.add_child(actor)
	actor.setup_combat_unit(hero)
	actor.name_label.visible = false
	actor.hp_label.visible = false
	actor.speech_label.visible = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	viewport.add_child(camera)
	camera.position = Vector3(2, 2.2, 3)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	_portrait_views[hero_id] = viewport
	return viewport.get_texture()

func _render_eta() -> void:
	var statuses := {"IDLE": "Sẵn sàng", "MOVING": "Hành quân", "FIGHTING": "Giao chiến"}
	for child in _squads.get_children():
		if not (child is Button):
			continue
		var squad: Dictionary = PveState.squad_by_id(str(child.get_meta("squad_id", "")))
		var eta: int = maxi(0, int(ceil(PveState.parse_time(str(squad.get("nextStepAt", ""))) - PveState.server_now())))
		var state_value := str(squad.get("status", ""))
		child.text = "#%d %s\n(%d, %d) · %s%s" % [int(child.get_meta("ordinal", 0)), str(squad.get("name", "Đội")),
			int(squad.get("x", 0)), int(squad.get("y", 0)), str(statuses.get(state_value, state_value)), " (%ds)" % eta if state_value == "MOVING" else ""]

func _can_command() -> bool:
	return PveState.connected and not PveState.command_busy and PveState.pending_command.is_empty()

func _render_controls() -> void:
	if _enter == null:
		return
	var map_value: Variant = PveState.snapshot.get("map")
	var active_map := map_value is Dictionary and str(map_value.get("status", "")) == "ACTIVE"
	_connection.text = "● Kết nối · %d/3 đội" % PveState.active_squads().size() if PveState.connected else "● Mất kết nối"
	if bool(PveState.snapshot.get("catchupPending", false)):
		_connection.text = "● Đang đồng bộ tiến độ…"
	_connection.modulate = Ui.TEAL if PveState.connected else Color("ffad82")
	_enter.disabled = not _can_command() or active_map
	_retry.visible = not PveState.pending_command.is_empty()
	_retry.disabled = PveState.command_busy
	var party_deployed: bool = PveState.active_squads().any(func(squad): return str(squad.get("partyId", "")) == PveState.selected_party_id)
	_deploy.disabled = not _can_command() or not active_map or party_deployed or PveState.active_squads().size() >= 3 or PveState.selected_party_id.is_empty()
	_edit.disabled = not _can_command() or party_deployed or PveState.selected_party_id.is_empty()
	_create.disabled = not _can_command()
	if is_instance_valid(_editor):
		_editor.set_busy(PveState.command_busy or not PveState.pending_command.is_empty())
	var selected: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	_recall.disabled = not _can_command() or selected.is_empty() or str(selected.get("status", "")) not in ["IDLE", "MOVING"]
	_auto.disabled = _recall.disabled
	_recall.disabled = _recall.disabled or bool(selected.get("pursued", false))
	if selected.has("canRecall"):
		_recall.disabled = not _can_command() or not bool(selected.get("canRecall", false))
	_recall.text = "Thu hồi tại điểm dịch chuyển" if bool(selected.get("atRecallPoint", false)) else "Thu hồi đội"
	var recall_reason: String = PveState.optional_id(selected.get("recallBlockReason"))
	_recall.tooltip_text = PveState.error_message(recall_reason) if not recall_reason.is_empty() else "Đưa đội về căn cứ"
	_stone.text = "Đá dịch chuyển ×%d" % int(PveState.snapshot.get("teleportStones", 0))
	var recall_locked := active_map and str(map_value.get("recallPolicy", "FREE")) == "UNTIL_COMPLETE"
	_stone.disabled = not _can_command() or not active_map or recall_locked or selected.is_empty() or str(selected.get("status", "")) != "IDLE" or bool(selected.get("atRecallPoint", false)) or int(PveState.snapshot.get("teleportStones", 0)) < 1
	_stone.tooltip_text = "Tầng này cấm dùng Đá dịch chuyển." if recall_locked else "Tiêu hao 1 đá để tạo điểm thu hồi dùng chung tới hết tầng."
	_reset_tower.visible = OS.is_debug_build() and bool(PveState.snapshot.get("devToolsEnabled", false))
	_reset_tower.disabled = not _can_command()
	_auto.text = "Dừng tự khám phá" if bool(selected.get("autoExplore", false)) else "Bật tự khám phá"
	if _items_btn != null:
		_items_btn.disabled = selected.is_empty()
	for button in _tiles:
		button.disabled = not _can_command() or not active_map or selected.is_empty() or str(selected.get("status", "")) == "FIGHTING" or str(selected.get("areaId", "floor")) != _view_area_id

func _enter_map() -> void:
	await PveState.send_command("/api/pve/enter")

func _deploy_party() -> void:
	var result: Dictionary = await PveState.send_command("/api/pve/parties/%s/deploy" % PveState.selected_party_id)
	if result.get("ok", false):
		PveState.selected_squad_id = str(result.get("data", {}).get("squadId", ""))
		_toggle_party_drawer(false)
		_render_state()
		_center_map_on_selected()
		return
	var err_code := str(result.get("error", ""))
	if err_code in ["ERR_PVE_HERO_BUSY", "ERR_PVE_HERO_RESTING"]:
		_confirm_force_deploy_party(PveState.selected_party_id)

func _confirm_force_deploy_party(party_id: String) -> void:
	if GameState.base_overview.is_empty():
		await GameState.refresh_base_overview()
	var busy_lines: PackedStringArray = []
	var assigned_map := GameState.get_worker_assignment_map()
	for party in PveState.snapshot.get("parties", []):
		if str(party.get("id", "")) != party_id:
			continue
		for member in party.get("members", []):
			var hid := str(member.get("heroId", ""))
			if hid.is_empty():
				continue
			var hero := GameState.get_hero_by_id(hid)
			var hname := str(hero.get("name", hid))
			if assigned_map.has(hid):
				var b_info: Dictionary = assigned_map[hid].get("building", {})
				var b_name := str(b_info.get("typeName", b_info.get("buildingType", "Công trình")))
				busy_lines.append("• %s — Đang làm việc tại [%s]" % [hname, b_name])
			elif bool(hero.get("isResting", false)) or str(hero.get("state", "")) == "RESTING":
				busy_lines.append("• %s — Đang nghỉ ngơi tại Dormitory / Biệt Thự" % hname)
	var detail_txt := "\n".join(busy_lines) if not busy_lines.is_empty() else "• Có Hero trong đội đang bận làm việc hoặc nghỉ ngơi tại căn cứ."

	var dialog := ConfirmationDialog.new()
	dialog.title = "Xác nhận triệu hồi Hero"
	dialog.dialog_text = "Các Hero sau đang bận:\n%s\n\nBạn có muốn gọi các Hero này rời công việc/nghỉ ngơi để xuất kích ngay không?\n(Vẫn yêu cầu Mệt mỏi & Đói < 60%%)" % detail_txt
	dialog.ok_button_text = "Có, gọi đi"
	dialog.cancel_button_text = "Không"
	dialog.confirmed.connect(func():
		var force_res: Dictionary = await PveState.send_command("/api/pve/parties/%s/deploy" % party_id, {"forceRecall": true})
		if force_res.get("ok", false):
			PveState.selected_squad_id = str(force_res.get("data", {}).get("squadId", ""))
			_toggle_party_drawer(false)
			await GameState.refresh_heroes()
			_render_state()
			_center_map_on_selected()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _recall_squad() -> void:
	await PveState.send_command("/api/pve/squads/%s/recall" % PveState.selected_squad_id)

func _place_recall_point() -> void:
	var squad: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	if not squad.is_empty():
		await PveState.send_command("/api/pve/squads/%s/recall-point" % PveState.selected_squad_id, {"areaId": squad.get("areaId", "floor"), "x": squad.get("x", 0), "y": squad.get("y", 0)})

func _confirm_reset_tower() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "DEV · Reset tháp về tầng 1"
	dialog.dialog_text = "Dừng lượt tháp hiện tại, thu hồi mọi đội và quay về tầng 1.\nGiữ Hero, vật phẩm và chiến báo cũ."
	dialog.confirmed.connect(func():
		var result: Dictionary = await PveState.send_command("/api/pve/dev/reset-tower", {"confirm": true})
		if result.get("ok", false):
			PveState.selected_squad_id = ""
			_view_area_id = "floor"
			_follow_key = ""
			GameState.current_floor = 1
			_render_state()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _toggle_auto() -> void:
	var squad := PveState.squad_by_id(PveState.selected_squad_id)
	if not squad.is_empty():
		await PveState.send_command("/api/pve/squads/%s/auto" % PveState.selected_squad_id, {"enabled": not bool(squad.get("autoExplore", false))})

func _move_selected(x: int, y: int) -> void:
	if _can_command() and not PveState.selected_squad_id.is_empty():
		await PveState.send_command("/api/pve/squads/%s/move" % PveState.selected_squad_id, {"x": x, "y": y, "areaId": _view_area_id})

func _edit_party() -> void:
	for party in PveState.snapshot.get("parties", []):
		if str(party.get("id", "")) == PveState.selected_party_id:
			_open_editor(party)
			return

func _open_editor(party: Dictionary) -> void:
	if is_instance_valid(_editor):
		return
	_editor = PartyEditor.new()
	_editor.configure(party)
	_editor.saved.connect(_save_party)
	_editor.retry_requested.connect(_retry_party_save)
	add_child(_editor)

func _save_party(party_id: String, payload: Dictionary) -> void:
	var endpoint := "/api/pve/parties" if party_id.is_empty() else "/api/pve/parties/" + party_id
	var method := HTTPClient.METHOD_POST if party_id.is_empty() else HTTPClient.METHOD_PUT
	var result: Dictionary = await PveState.send_command(endpoint, payload, method)
	_finish_party_save(result)

func _retry_party_save() -> void:
	var result: Dictionary = await PveState.retry_pending()
	_finish_party_save(result)

func _finish_party_save(result: Dictionary) -> void:
	if result.get("ok", false):
		PveState.selected_party_id = str(result.get("data", {}).get("partyId", ""))
		if is_instance_valid(_editor):
			_editor.queue_free()
		_render_state()
	else:
		if is_instance_valid(_editor):
			_editor.show_error(PveState.error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), not PveState.pending_command.is_empty())
		_set_message(PveState.error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), true)

func _watch_report(battle_id: String) -> void:
	PveState.selected_battle_id = battle_id
	get_tree().change_scene_to_file("res://scenes/pve/isometric_pve_arena_3d.tscn")

func _set_message(message: String, is_error: bool) -> void:
	_status.text = message
	_status.visible = is_error and not message.is_empty()
	_status.modulate = Color("ffb49a") if is_error else Ui.TEXT

func _back_to_tower() -> void:
	PveState.polling_enabled = false
	get_tree().change_scene_to_file("res://scenes/pve/pve_tower.tscn")

func _back_to_base() -> void:
	PveState.polling_enabled = false
	get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")
