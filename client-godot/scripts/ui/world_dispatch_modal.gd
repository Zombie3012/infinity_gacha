extends Control
## Dedicated 2-Column Expedition Dispatch Modal (Hộp Thoại Điều Quân: Chọn Tàu Bay & Lưới Thẻ Hero).
## Left Column: Visual Airship Cards (3 / 5 / 6 / 15 Hero capacity, HP, Speed, Power Buff, Live ETA)
## Right Column: Visual 2-Column Hero Card Grid (Class Filter, Power/Level Sort, Auto-pick, Total LC Preview)

signal dispatch_confirmed(payload: Dictionary)
signal closed

const SHIP_COLORS := {
	"SCOUT_SKIFF": Color(0.22, 0.78, 0.96),
	"RESCUE_CUTTER": Color(0.24, 0.86, 0.56),
	"WAR_DREADNOUGHT": Color(0.95, 0.50, 0.24),
	"TRANSPORT_CARRIER": Color(0.68, 0.44, 0.96),
}

const SIZE_LABELS := {
	"SMALL": "Nhỏ",
	"MEDIUM": "Trung bình",
	"LARGE": "Lớn",
}

const CLASS_NAMES := {
	"ALL": "Tất cả nghề",
	"WARRIOR": "Chiến binh",
	"THIEF": "Đạo tặc",
	"SPEARMAN": "Thương thủ",
	"ARCHER": "Cung thủ",
	"MAGE": "Pháp sư",
}

const MISSION_TITLES := {
	"SCOUT": "🔭 ĐIỀU QUÂN TRINH SÁT (MỞ SƯƠNG MÙ 1 GIỜ)",
	"GARRISON": "⛺ ĐIỀU QUÂN TẬP KẾT (ĐỒN TRÚ TIỀN PHƯƠNG)",
	"DUNGEON": "⚔️ ĐIỀU QUÂN THÁM HIỂM HẦM NGỤC NỔI",
	"RESCUE": "🚑 ĐIỀU TÀU CỨU HỘ KHẨN CẤP (SOS)",
	"ATTACK": "🔥 ĐIỀU QUÂN TẤN CÔNG",
}

var _tile: Dictionary = {}
var _mission := "SCOUT"
var _base_coord := Vector2i(100, 100)
var _docked_ships: Array = []
var _heroes: Array = []
var _busy_hero_ids: Dictionary = {}
var _rescue_target_id := ""

var _selected_ship_id := ""
var _selected_hero_ids: Array[String] = []
var _filter_class := "ALL"
var _sort_mode := "POWER"

var _title_lbl: Label
var _sub_lbl: Label
var _ship_list: VBoxContainer
var _hero_grid: GridContainer
var _crew_counter_lbl: Label
var _footer_summary_lbl: Label
var _launch_btn: Button

func configure(params: Dictionary) -> void:
	_tile = params.get("tile", {})
	_mission = str(params.get("mission", "SCOUT")).to_upper()
	_base_coord = params.get("baseCoord", Vector2i(100, 100))
	_docked_ships = params.get("dockedShips", [])
	_heroes = params.get("heroes", [])
	_busy_hero_ids = params.get("busyHeroIds", {})
	_rescue_target_id = str(params.get("rescueTargetId", ""))
	_selected_hero_ids.clear()

	# Auto-pick best matching ship for the mission
	_selected_ship_id = ""
	var preferred_bp := ""
	if _mission == "SCOUT": preferred_bp = "SCOUT_SKIFF"
	elif _mission == "RESCUE": preferred_bp = "RESCUE_CUTTER"
	elif _mission == "GARRISON": preferred_bp = "TRANSPORT_CARRIER"
	elif _mission == "DUNGEON":
		var dungeon = _tile.get("dungeon", null)
		if dungeon is Dictionary and int(dungeon.get("maxPartySize", 5)) > 5:
			preferred_bp = "TRANSPORT_CARRIER"
		else:
			preferred_bp = "WAR_DREADNOUGHT"

	for s in _docked_ships:
		if str(s.get("blueprintCode", "")) == preferred_bp:
			_selected_ship_id = str(s.get("id", ""))
			break
	if _selected_ship_id.is_empty() and _docked_ships.size() > 0:
		_selected_ship_id = str(_docked_ships[0].get("id", ""))

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_render_all()

func _make_btn_style(bg: Color, border: Color, radius := 7) -> StyleBoxFlat:
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

func _style_button(btn: Button, accent := Color(0.32, 0.62, 0.92), bg := Color(0.10, 0.14, 0.22)) -> void:
	btn.add_theme_stylebox_override("normal", _make_btn_style(bg, accent.darkened(0.22)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(bg.lightened(0.1), accent))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(bg.darkened(0.12), accent.lightened(0.15)))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(Color(0.07, 0.08, 0.12, 0.7), Color(0.2, 0.22, 0.28, 0.5)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.46, 0.5, 0.58))

func _make_card_style(bg := Color(0.08, 0.11, 0.17, 0.96), border := Color(0.25, 0.34, 0.5, 0.75)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(10)
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
	panel.custom_minimum_size = Vector2(980, 620)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.125, 0.98)
	style.border_color = Color(0.84, 0.68, 0.32, 0.88)
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
	hdr.add_theme_constant_override("separation", 10)
	root.add_child(hdr)

	var hdr_vb := VBoxContainer.new()
	hdr_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr_vb.add_theme_constant_override("separation", 2)
	hdr.add_child(hdr_vb)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 19)
	_title_lbl.add_theme_color_override("font_color", Color(0.96, 0.85, 0.48))
	hdr_vb.add_child(_title_lbl)

	_sub_lbl = Label.new()
	_sub_lbl.add_theme_font_size_override("font_size", 13)
	_sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	hdr_vb.add_child(_sub_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕ Đóng"
	_style_button(close_btn, Color(0.75, 0.35, 0.35), Color(0.16, 0.09, 0.11))
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	# Body: 2 Columns (Left: Airship Cards, Right: Hero Card Grid)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)

	# Left Column: Ship Selector
	var left_card := PanelContainer.new()
	left_card.custom_minimum_size = Vector2(340, 0)
	left_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_card.add_theme_stylebox_override("panel", _make_card_style())
	cols.add_child(left_card)

	var left_vb := VBoxContainer.new()
	left_vb.add_theme_constant_override("separation", 8)
	left_card.add_child(left_vb)

	var ship_hdr := Label.new()
	ship_hdr.text = "1. CHỌN TÀU BAY KHẢ DỤNG"
	ship_hdr.add_theme_font_size_override("font_size", 14)
	ship_hdr.add_theme_color_override("font_color", Color(0.62, 0.88, 1.0))
	left_vb.add_child(ship_hdr)

	var ship_scroll := ScrollContainer.new()
	ship_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ship_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_vb.add_child(ship_scroll)

	_ship_list = VBoxContainer.new()
	_ship_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_list.add_theme_constant_override("separation", 8)
	ship_scroll.add_child(_ship_list)

	# Right Column: Hero Card Grid
	var right_card := PanelContainer.new()
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_card.add_theme_stylebox_override("panel", _make_card_style())
	cols.add_child(right_card)

	var right_vb := VBoxContainer.new()
	right_vb.add_theme_constant_override("separation", 8)
	right_card.add_child(right_vb)

	var hero_bar := HBoxContainer.new()
	hero_bar.add_theme_constant_override("separation", 8)
	right_vb.add_child(hero_bar)

	_crew_counter_lbl = Label.new()
	_crew_counter_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crew_counter_lbl.add_theme_font_size_override("font_size", 14)
	_crew_counter_lbl.add_theme_color_override("font_color", Color(0.96, 0.86, 0.48))
	hero_bar.add_child(_crew_counter_lbl)

	var filter_opt := OptionButton.new()
	var filter_keys := ["ALL", "WARRIOR", "THIEF", "SPEARMAN", "ARCHER", "MAGE"]
	for i in range(filter_keys.size()):
		filter_opt.add_item(str(CLASS_NAMES.get(filter_keys[i], filter_keys[i])), i)
		filter_opt.set_item_metadata(i, filter_keys[i])
	filter_opt.item_selected.connect(func(idx: int):
		_filter_class = str(filter_opt.get_item_metadata(idx))
		_render_hero_grid()
	)
	hero_bar.add_child(filter_opt)

	var sort_opt := OptionButton.new()
	sort_opt.add_item("LC cao nhất", 0)
	sort_opt.add_item("Cấp cao nhất", 1)
	sort_opt.item_selected.connect(func(idx: int):
		_sort_mode = "POWER" if idx == 0 else "LEVEL"
		_render_hero_grid()
	)
	hero_bar.add_child(sort_opt)

	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	right_vb.add_child(quick_row)

	var auto_btn := Button.new()
	auto_btn.text = "⚡ Tự chọn mạnh nhất"
	_style_button(auto_btn, Color(0.28, 0.82, 1.0), Color(0.08, 0.16, 0.24))
	auto_btn.pressed.connect(_auto_pick_strongest)
	quick_row.add_child(auto_btn)

	var clear_btn := Button.new()
	clear_btn.text = "✕ Bỏ chọn hết"
	_style_button(clear_btn, Color(0.76, 0.36, 0.38), Color(0.16, 0.09, 0.11))
	clear_btn.pressed.connect(func():
		_selected_hero_ids.clear()
		_render_hero_grid()
		_update_footer()
	)
	quick_row.add_child(clear_btn)

	var hero_scroll := ScrollContainer.new()
	hero_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vb.add_child(hero_scroll)

	_hero_grid = GridContainer.new()
	_hero_grid.columns = 2
	_hero_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_grid.add_theme_constant_override("h_separation", 8)
	_hero_grid.add_theme_constant_override("v_separation", 8)
	hero_scroll.add_child(_hero_grid)

	# Footer
	var footer_panel := PanelContainer.new()
	footer_panel.add_theme_stylebox_override("panel", _make_card_style(Color(0.045, 0.06, 0.10, 0.98), Color(0.45, 0.38, 0.22, 0.7)))
	root.add_child(footer_panel)

	var footer_h := HBoxContainer.new()
	footer_h.add_theme_constant_override("separation", 12)
	footer_panel.add_child(footer_h)

	_footer_summary_lbl = Label.new()
	_footer_summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_summary_lbl.add_theme_font_size_override("font_size", 13)
	_footer_summary_lbl.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	footer_h.add_child(_footer_summary_lbl)

	var cancel_btn := Button.new()
	cancel_btn.text = "Hủy"
	cancel_btn.custom_minimum_size = Vector2(96, 40)
	_style_button(cancel_btn, Color(0.45, 0.5, 0.6))
	cancel_btn.pressed.connect(_close)
	footer_h.add_child(cancel_btn)

	_launch_btn = Button.new()
	_launch_btn.text = "🚀 XUẤT KÍCH"
	_launch_btn.custom_minimum_size = Vector2(180, 40)
	_style_button(_launch_btn, Color(0.96, 0.72, 0.24), Color(0.24, 0.16, 0.06))
	_launch_btn.pressed.connect(_confirm_dispatch)
	footer_h.add_child(_launch_btn)

func _selected_ship() -> Dictionary:
	for s in _docked_ships:
		if str(s.get("id", "")) == _selected_ship_id:
			return s
	return {}

func _max_heroes_allowed() -> int:
	var ship := _selected_ship()
	var cap := int(ship.get("maxHeroes", 5)) if not ship.is_empty() else 5
	if _mission == "DUNGEON":
		var dungeon = _tile.get("dungeon", null)
		if dungeon is Dictionary:
			cap = mini(cap, int(dungeon.get("maxPartySize", 5)))
	return maxi(1, cap)

func _estimate_eta_seconds(speed_mult: float) -> int:
	var tx := int(_tile.get("x", _base_coord.x))
	var ty := int(_tile.get("y", _base_coord.y))
	var dist := maxi(absi(tx - _base_coord.x), absi(ty - _base_coord.y))
	return maxi(15, int(round(float(dist * 30) / maxf(0.5, speed_mult))))

func _render_all() -> void:
	_title_lbl.text = str(MISSION_TITLES.get(_mission, "🚀 ĐIỀU QUÂN VIỄN CHINH"))
	var tx := int(_tile.get("x", 0))
	var ty := int(_tile.get("y", 0))
	var dungeon = _tile.get("dungeon", null)
	if _mission == "DUNGEON" and dungeon is Dictionary:
		_sub_lbl.text = "Mục tiêu: Ô (%d, %d) • Hầm Ngục [%s] %s (Boss: %s • Khuyến nghị LC %d • Tối đa %d Hero)" % [
			tx, ty, str(dungeon.get("rank", "D")), str(dungeon.get("name", "")),
			str(dungeon.get("bossName", "")), int(dungeon.get("recommendedPower", 0)), int(dungeon.get("maxPartySize", 5))
		]
	else:
		_sub_lbl.text = "Mục tiêu: Ô (%d, %d) — Địa hình: %s" % [tx, ty, str(_tile.get("terrain", "PLAINS"))]

	_render_ship_list()
	_render_hero_grid()
	_update_footer()

func _render_ship_list() -> void:
	for c in _ship_list.get_children():
		c.queue_free()

	if _docked_ships.is_empty():
		var lbl := Label.new()
		lbl.text = "⚠️ Không có tàu bay nào đang neo tại Cảng.\nHãy về Cảng Tàu Bay chế tạo hoặc chờ tàu trở về."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.35))
		_ship_list.add_child(lbl)
		return

	for s in _docked_ships:
		var sid := str(s.get("id", ""))
		var bp := str(s.get("blueprintCode", "SCOUT_SKIFF"))
		var is_sel := (sid == _selected_ship_id)
		var is_rescue_mismatch := (_mission == "RESCUE" and bp != "RESCUE_CUTTER")
		var accent: Color = SHIP_COLORS.get(bp, Color(0.4, 0.65, 0.9))
		var eta := _estimate_eta_seconds(float(s.get("speedMult", 1.0)))

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.disabled = is_rescue_mismatch
		var tag := ""
		if (_mission == "SCOUT" and bp == "SCOUT_SKIFF") or (_mission == "RESCUE" and bp == "RESCUE_CUTTER"):
			tag = " ★ Đề xuất"
		elif (_mission == "DUNGEON" or _mission == "GARRISON") and (bp == "WAR_DREADNOUGHT" or bp == "TRANSPORT_CARRIER"):
			tag = " ★ Đề xuất"

		btn.text = "%s%s%s\nHạng %s (%d×%d) • Chở %d Hero • ETA ~%ds\nHP %d/%d • Tốc %.2fx • Buff LC +%d%%" % [
			"▶ " if is_sel else "  ",
			str(s.get("name", bp)),
			tag,
			str(SIZE_LABELS.get(str(s.get("sizeClass", "SMALL")), "Nhỏ")),
			int(s.get("gridW", 2)), int(s.get("gridH", 2)),
			int(s.get("maxHeroes", 3)), eta,
			int(s.get("hp", 0)), int(s.get("maxHp", 100)),
			float(s.get("speedMult", 1.0)), int(s.get("powerBonusPct", 0)),
		]
		if is_sel:
			_style_button(btn, Color(0.98, 0.85, 0.34), Color(0.14, 0.19, 0.28))
		else:
			_style_button(btn, accent.darkened(0.25), Color(0.08, 0.105, 0.17))

		btn.pressed.connect(func():
			_selected_ship_id = sid
			var new_cap := _max_heroes_allowed()
			while _selected_hero_ids.size() > new_cap:
				_selected_hero_ids.pop_back()
			_render_ship_list()
			_render_hero_grid()
			_update_footer()
		)
		_ship_list.add_child(btn)

func _hero_power(h: Dictionary) -> int:
	var p := int(h.get("combatPower", 0))
	if p > 0: return p
	return int(h.get("attack", 0)) * 3 + int(h.get("defense", 0)) * 2 + int(h.get("maxHp", 0)) / 5

func _is_hero_alive(h: Dictionary) -> bool:
	if h.is_empty():
		return false
	var st := str(h.get("state", "ALIVE")).to_upper()
	if st in ["DEAD", "DISABLED"]:
		return false
	if h.has("hp") and float(h.get("hp", 1)) <= 0.0:
		return false
	return true

func _is_hero_pve_deployed(h: Dictionary) -> bool:
	var dep: Variant = h.get("pveDeployment", null)
	return dep is Dictionary and not dep.is_empty()

func _filtered_sorted_heroes() -> Array:
	var list: Array = []
	for h in _heroes:
		if not (h is Dictionary) or not _is_hero_alive(h):
			continue
		var cls := str(h.get("classCode", h.get("heroClass", ""))).to_upper()
		if _filter_class != "ALL" and cls != _filter_class:
			continue
		list.append(h)
	list.sort_custom(func(a, b):
		if _sort_mode == "LEVEL":
			return int(a.get("level", 1)) > int(b.get("level", 1))
		return _hero_power(a) > _hero_power(b)
	)
	return list

func _render_hero_grid() -> void:
	for c in _hero_grid.get_children():
		c.queue_free()

	var cap := _max_heroes_allowed()
	_crew_counter_lbl.text = "2. CHỌN TỔ ĐỘI HERO (%d / %d)" % [_selected_hero_ids.size(), cap]

	var list := _filtered_sorted_heroes()
	if list.is_empty():
		var lbl := Label.new()
		lbl.text = "Không có Hero còn sống phù hợp bộ lọc."
		_hero_grid.add_child(lbl)
		return

	for h in list:
		var hid := str(h.get("id", ""))
		var is_busy := _busy_hero_ids.has(hid)
		var is_pve := _is_hero_pve_deployed(h)
		var is_picked := _selected_hero_ids.has(hid)
		var cls := str(h.get("classCode", h.get("heroClass", "")))
		var stars := int(h.get("rarity", h.get("starRating", 1)))
		var lvl := int(h.get("level", 1))
		var pwr := _hero_power(h)

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = is_busy or is_pve
		var badge := "✓ " if is_picked else ("✈️ " if is_busy else ("⚔️ " if is_pve else "☐ "))
		var st_note := " • Đang bay" if is_busy else (" • Bận PvE" if is_pve else "")
		btn.text = "%s%s (%d★)%s\n%s • Lv.%d • LC %d" % [
			badge, str(h.get("name", "Hero")), stars, st_note,
			str(CLASS_NAMES.get(cls.to_upper(), cls)), lvl, pwr
		]
		if is_picked:
			_style_button(btn, Color(0.28, 0.94, 0.56), Color(0.09, 0.21, 0.15))
		else:
			_style_button(btn, Color(0.28, 0.38, 0.55), Color(0.08, 0.11, 0.18))
		btn.pressed.connect(func(): toggle_hero(hid))
		_hero_grid.add_child(btn)

func toggle_hero(hero_id: String) -> void:
	var idx := _selected_hero_ids.find(hero_id)
	if idx >= 0:
		_selected_hero_ids.remove_at(idx)
	elif _selected_hero_ids.size() < _max_heroes_allowed():
		_selected_hero_ids.append(hero_id)
	_render_hero_grid()
	_update_footer()

func _auto_pick_strongest() -> void:
	_selected_hero_ids.clear()
	var cap := _max_heroes_allowed()
	for h in _filtered_sorted_heroes():
		if _selected_hero_ids.size() >= cap:
			break
		var hid := str(h.get("id", ""))
		if _is_hero_alive(h) and not _busy_hero_ids.has(hid) and not _is_hero_pve_deployed(h):
			_selected_hero_ids.append(hid)
	_render_hero_grid()
	_update_footer()

func _update_footer() -> void:
	var ship := _selected_ship()
	var cap := _max_heroes_allowed()
	var base_power := 0
	for h in _heroes:
		if _selected_hero_ids.has(str(h.get("id", ""))):
			base_power += _hero_power(h)
	var bonus_pct := int(ship.get("powerBonusPct", 0)) if not ship.is_empty() else 0
	var total_power := int(round(float(base_power) * (1.0 + float(bonus_pct) / 100.0)))
	var eta := _estimate_eta_seconds(float(ship.get("speedMult", 1.0))) if not ship.is_empty() else 30

	var ship_name := str(ship.get("name", "Chưa chọn tàu")) if not ship.is_empty() else "Chưa chọn tàu"
	var extra := ""
	var dungeon = _tile.get("dungeon", null)
	if _mission == "DUNGEON" and dungeon is Dictionary:
		var rec := int(dungeon.get("recommendedPower", 0))
		extra = "  •  Mục tiêu LC %d (%s)" % [rec, "Đủ sức" if total_power >= int(rec * 0.95) else "Nguy hiểm!"]

	_footer_summary_lbl.text = "🛸 %s  •  👥 %d/%d Hero  •  🔥 Tổng LC: %d (+%d%%)  •  ⏱️ ETA ~%ds%s" % [
		ship_name, _selected_hero_ids.size(), cap, total_power, bonus_pct, eta, extra
	]
	_launch_btn.disabled = _selected_ship_id.is_empty() or _selected_hero_ids.is_empty()

func _confirm_dispatch() -> void:
	var payload := {
		"tileId": str(_tile.get("id", "")),
		"mission": _mission,
		"heroIds": _selected_hero_ids.duplicate(),
		"airshipId": _selected_ship_id,
	}
	var dungeon = _tile.get("dungeon", null)
	if _mission == "DUNGEON" and dungeon is Dictionary:
		payload["dungeonId"] = str(dungeon.get("id", ""))
	if _mission == "RESCUE" and not _rescue_target_id.is_empty():
		payload["rescueTargetExpeditionId"] = _rescue_target_id
	dispatch_confirmed.emit(payload)
	queue_free()

func _close() -> void:
	closed.emit()
	queue_free()
