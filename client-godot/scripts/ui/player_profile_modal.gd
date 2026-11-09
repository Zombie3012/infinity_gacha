extends Control
class_name PlayerProfileModal

## Player Profile, Settings, Giftcode & Support Modal
## Occult Dark Fantasy styled multi-tab modal window

signal closed()
signal weather_changed(preset: String)

var _active_tab: int = 0
var _is_ui_built: bool = false

var _dimmer: ColorRect
var _main_panel: PanelContainer
var _tabs_container: VBoxContainer
var _tab_buttons: Array[Button] = []
var _content_panel: PanelContainer
var _toast_banner: PanelContainer
var _toast_label: Label
var _toast_tween: Tween

var _audio_bus_master_idx: int = -1
var _audio_bus_bgm_idx: int = -1
var _audio_bus_sfx_idx: int = -1

var _center_box: CenterContainer = null

# Avatar selector sub-modal
var _avatar_picker_wrap: Control = null
var _avatar_picker_panel: PanelContainer = null

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	if not _is_ui_built:
		_build_ui()
	_init_audio_buses()
	_switch_tab(_active_tab)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_update_fullscreen_layout()

func _on_viewport_size_changed() -> void:
	_update_fullscreen_layout()

func _update_fullscreen_layout() -> void:
	var vp_size := get_viewport_rect().size
	if vp_size.x > 0 and vp_size.y > 0:
		size = vp_size
		if _dimmer != null:
			_dimmer.size = vp_size
		if _center_box != null:
			_center_box.size = vp_size

func _init_audio_buses() -> void:
	_audio_bus_master_idx = AudioServer.get_bus_index("Master")
	_audio_bus_bgm_idx = AudioServer.get_bus_index("Music")
	if _audio_bus_bgm_idx == -1:
		_audio_bus_bgm_idx = AudioServer.get_bus_index("BGM")
	_audio_bus_sfx_idx = AudioServer.get_bus_index("SFX")

func setup(initial_tab: int = 0) -> void:
	_active_tab = initial_tab
	if not _is_ui_built:
		_build_ui()
	_update_fullscreen_layout()
	_switch_tab(_active_tab)

func refresh_all() -> void:
	if _is_ui_built:
		_render_active_tab()

func _build_ui() -> void:
	_is_ui_built = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp_size := get_viewport_rect().size
	if vp_size.x > 0 and vp_size.y > 0:
		size = vp_size

	# 1. Dimmer Background
	_dimmer = ColorRect.new()
	_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dimmer.anchor_right = 1.0
	_dimmer.anchor_bottom = 1.0
	_dimmer.offset_left = 0.0
	_dimmer.offset_top = 0.0
	_dimmer.offset_right = 0.0
	_dimmer.offset_bottom = 0.0
	_dimmer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dimmer.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dimmer.color = Color(0.02, 0.03, 0.06, 0.82)
	_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_dimmer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close_modal()
	)
	add_child(_dimmer)

	# 2. Main Window Center Container
	_center_box = CenterContainer.new()
	_center_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_center_box.anchor_right = 1.0
	_center_box.anchor_bottom = 1.0
	_center_box.offset_left = 0.0
	_center_box.offset_top = 0.0
	_center_box.offset_right = 0.0
	_center_box.offset_bottom = 0.0
	_center_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center_box)

	_main_panel = PanelContainer.new()
	_main_panel.custom_minimum_size = Vector2(920, 580)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.12, 0.98)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.24, 0.38, 0.58, 0.85)
	panel_style.corner_radius_top_left = 10
	panel_style.corner_radius_top_right = 10
	panel_style.corner_radius_bottom_left = 10
	panel_style.corner_radius_bottom_right = 10
	panel_style.shadow_color = Color(0, 0, 0, 0.75)
	panel_style.shadow_size = 24
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	_center_box.add_child(_main_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 20)
	outer_margin.add_theme_constant_override("margin_top", 16)
	outer_margin.add_theme_constant_override("margin_right", 20)
	outer_margin.add_theme_constant_override("margin_bottom", 16)
	_main_panel.add_child(outer_margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	outer_margin.add_child(main_vbox)

	# Header Row
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header_row)

	var title_vbox := VBoxContainer.new()
	title_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	title_vbox.add_theme_constant_override("separation", 2)
	header_row.add_child(title_vbox)

	var title_lbl := Label.new()
	title_lbl.text = "👑 HỒ SƠ MASTER & THIẾT LẬP"
	title_lbl.add_theme_font_size_override("font_size", 17)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_vbox.add_child(title_lbl)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "Thông tin định danh, cấu hình trải nghiệm, đổi mã quà tặng & hỗ trợ kỹ thuật"
	subtitle_lbl.add_theme_font_size_override("font_size", 11)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	title_vbox.add_child(subtitle_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.focus_mode = FOCUS_NONE
	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.18, 0.22, 0.32, 0.8)
	close_style.corner_radius_top_left = 6
	close_style.corner_radius_top_right = 6
	close_style.corner_radius_bottom_left = 6
	close_style.corner_radius_bottom_right = 6
	close_btn.add_theme_stylebox_override("normal", close_style)
	close_btn.pressed.connect(_close_modal)
	header_row.add_child(close_btn)

	# Divider line
	var div := HSeparator.new()
	var div_style := StyleBoxLine.new()
	div_style.color = Color(0.2, 0.3, 0.45, 0.5)
	div.add_theme_stylebox_override("separator", div_style)
	main_vbox.add_child(div)

	# Body: 2 Columns (Left Tabs, Right Content)
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(body_hbox)

	# Left Column: Tabs
	_tabs_container = VBoxContainer.new()
	_tabs_container.custom_minimum_size = Vector2(175, 0)
	_tabs_container.add_theme_constant_override("separation", 8)
	body_hbox.add_child(_tabs_container)

	_create_tab_buttons()

	# Right Column: Content Box
	_content_panel = PanelContainer.new()
	_content_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	_content_panel.size_flags_vertical = SIZE_EXPAND_FILL
	var content_style := StyleBoxFlat.new()
	content_style.bg_color = Color(0.04, 0.05, 0.08, 0.75)
	content_style.border_width_left = 1
	content_style.border_width_top = 1
	content_style.border_width_right = 1
	content_style.border_width_bottom = 1
	content_style.border_color = Color(0.16, 0.24, 0.36, 0.6)
	content_style.corner_radius_top_left = 8
	content_style.corner_radius_top_right = 8
	content_style.corner_radius_bottom_left = 8
	content_style.corner_radius_bottom_right = 8
	_content_panel.add_theme_stylebox_override("panel", content_style)
	body_hbox.add_child(_content_panel)

	# Toast Overlay inside modal
	_build_toast_overlay()

func _create_tab_buttons() -> void:
	_tab_buttons.clear()
	var tab_defs := [
		{"icon": "👤", "title": "Hồ Sơ Master", "tab": 0},
		{"icon": "⚙️", "title": "Cài Đặt", "tab": 1},
		{"icon": "🎁", "title": "Mã Quà Tặng", "tab": 2},
		{"icon": "🛟", "title": "Hỗ Trợ", "tab": 3},
	]

	for item in tab_defs:
		var btn := Button.new()
		btn.text = "%s  %s" % [item["icon"], item["title"]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 42)
		btn.focus_mode = FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)

		var t_idx: int = int(item["tab"])
		btn.pressed.connect(func():
			_switch_tab(t_idx)
		)
		_tabs_container.add_child(btn)
		_tab_buttons.append(btn)

func _switch_tab(tab_idx: int) -> void:
	_active_tab = tab_idx
	for i in range(_tab_buttons.size()):
		var btn: Button = _tab_buttons[i]
		var is_active := (i == _active_tab)
		var style := StyleBoxFlat.new()
		if is_active:
			style.bg_color = Color(0.15, 0.25, 0.42, 0.95)
			style.border_width_left = 3
			style.border_color = Color(0.45, 0.75, 1.0)
			btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		else:
			style.bg_color = Color(0.08, 0.11, 0.17, 0.7)
			style.border_width_left = 0
			btn.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.content_margin_left = 12
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
		btn.add_theme_stylebox_override("pressed", style)

	_render_active_tab()

func _render_active_tab() -> void:
	# Clear previous content children
	for child in _content_panel.get_children():
		child.queue_free()

	match _active_tab:
		0:
			_render_profile_tab()
		1:
			_render_settings_tab()
		2:
			_render_giftcode_tab()
		3:
			_render_support_tab()

# ==============================================================================
# TAB 0: HỒ SƠ MASTER
# ==============================================================================
func _render_profile_tab() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_content_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(root_vbox)

	# 1. Master Identity Card (Avatar + Name + UID + EXP Bar)
	var id_card := PanelContainer.new()
	var id_style := StyleBoxFlat.new()
	id_style.bg_color = Color(0.08, 0.11, 0.18, 0.85)
	id_style.border_width_left = 1
	id_style.border_width_top = 1
	id_style.border_width_right = 1
	id_style.border_width_bottom = 1
	id_style.border_color = Color(0.22, 0.35, 0.55, 0.6)
	id_style.corner_radius_top_left = 8
	id_style.corner_radius_top_right = 8
	id_style.corner_radius_bottom_left = 8
	id_style.corner_radius_bottom_right = 8
	id_card.add_theme_stylebox_override("panel", id_style)
	root_vbox.add_child(id_card)

	var id_margin := MarginContainer.new()
	id_margin.add_theme_constant_override("margin_left", 14)
	id_margin.add_theme_constant_override("margin_top", 12)
	id_margin.add_theme_constant_override("margin_right", 14)
	id_margin.add_theme_constant_override("margin_bottom", 12)
	id_card.add_child(id_margin)

	var id_hbox := HBoxContainer.new()
	id_hbox.add_theme_constant_override("separation", 16)
	id_margin.add_child(id_hbox)

	# Avatar Box with Level Badge & Change Button
	var av_vbox := VBoxContainer.new()
	av_vbox.add_theme_constant_override("separation", 4)
	id_hbox.add_child(av_vbox)

	var av_box := PanelContainer.new()
	av_box.custom_minimum_size = Vector2(72, 72)
	var av_style := StyleBoxFlat.new()
	av_style.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	av_style.border_width_left = 2
	av_style.border_width_top = 2
	av_style.border_width_right = 2
	av_style.border_width_bottom = 2
	av_style.border_color = Color(0.9, 0.72, 0.25, 0.85) # Gold
	av_style.corner_radius_top_left = 8
	av_style.corner_radius_top_right = 8
	av_style.corner_radius_bottom_left = 8
	av_style.corner_radius_bottom_right = 8
	av_box.add_theme_stylebox_override("panel", av_style)
	av_vbox.add_child(av_box)

	var av_icon_lbl := Label.new()
	av_icon_lbl.text = _get_avatar_icon()
	av_icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	av_icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	av_icon_lbl.add_theme_font_size_override("font_size", 32)
	av_box.add_child(av_icon_lbl)

	# Level badge inside avatar
	var lvl_badge := Label.new()
	lvl_badge.text = "Lv.%d" % GameState.master_level
	lvl_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lvl_badge.add_theme_font_size_override("font_size", 10)
	lvl_badge.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	av_box.add_child(lvl_badge)

	var change_av_btn := Button.new()
	change_av_btn.text = "🔄 Đổi Avatar"
	change_av_btn.custom_minimum_size = Vector2(72, 22)
	change_av_btn.add_theme_font_size_override("font_size", 9)
	change_av_btn.focus_mode = FOCUS_NONE
	change_av_btn.pressed.connect(_open_avatar_picker)
	av_vbox.add_child(change_av_btn)

	# Master Info Column
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 6)
	id_hbox.add_child(info_vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	info_vbox.add_child(name_row)

	var name_lbl := Label.new()
	name_lbl.text = GameState.master_name if GameState.master_name != "" else "Demo Master"
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	name_row.add_child(name_lbl)

	var rank_badge := Label.new()
	rank_badge.text = "👑 Đại Trưởng Lão (Rank S)"
	rank_badge.add_theme_font_size_override("font_size", 11)
	rank_badge.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	name_row.add_child(rank_badge)

	# UID Row + Copy Button
	var uid_row := HBoxContainer.new()
	uid_row.add_theme_constant_override("separation", 6)
	info_vbox.add_child(uid_row)

	var display_uid := GameState.master_id if GameState.master_id != "" else (GameState.account_id if GameState.account_id != "" else "UID-8888-9999")
	var uid_lbl := Label.new()
	uid_lbl.text = "UID: %s" % display_uid
	uid_lbl.add_theme_font_size_override("font_size", 11)
	uid_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	uid_row.add_child(uid_lbl)

	var copy_btn := Button.new()
	copy_btn.text = "📋 Sao chép"
	copy_btn.custom_minimum_size = Vector2(70, 20)
	copy_btn.add_theme_font_size_override("font_size", 10)
	copy_btn.focus_mode = FOCUS_NONE
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(display_uid)
		show_toast("📋 Đã sao chép UID: %s" % display_uid, true)
	)
	uid_row.add_child(copy_btn)

	# EXP Bar
	var cur_exp: int = GameState.master_exp
	var max_exp: int = GameState.get_master_max_exp()
	var exp_pct: float = clampf(float(cur_exp) / float(maxi(1, max_exp)), 0.0, 1.0) * 100.0

	var exp_vbox := VBoxContainer.new()
	exp_vbox.add_theme_constant_override("separation", 2)
	info_vbox.add_child(exp_vbox)

	var exp_row := HBoxContainer.new()
	exp_vbox.add_child(exp_row)

	var exp_title := Label.new()
	exp_title.text = "Kinh Nghiệm Master:"
	exp_title.add_theme_font_size_override("font_size", 11)
	exp_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	exp_title.size_flags_horizontal = SIZE_EXPAND_FILL
	exp_row.add_child(exp_title)

	var exp_val := Label.new()
	exp_val.text = "%s / %s (%d%%)" % [_format_number(cur_exp), _format_number(max_exp), int(exp_pct)]
	exp_val.add_theme_font_size_override("font_size", 11)
	exp_val.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	exp_row.add_child(exp_val)

	var exp_pb := ProgressBar.new()
	exp_pb.custom_minimum_size = Vector2(0, 8)
	exp_pb.show_percentage = false
	exp_pb.value = exp_pct
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0.08, 0.12, 0.18, 0.9)
	pb_bg.corner_radius_top_left = 4
	pb_bg.corner_radius_top_right = 4
	pb_bg.corner_radius_bottom_left = 4
	pb_bg.corner_radius_bottom_right = 4
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.2, 0.65, 0.95)
	pb_fill.corner_radius_top_left = 4
	pb_fill.corner_radius_top_right = 4
	pb_fill.corner_radius_bottom_left = 4
	pb_fill.corner_radius_bottom_right = 4
	exp_pb.add_theme_stylebox_override("background", pb_bg)
	exp_pb.add_theme_stylebox_override("fill", pb_fill)
	exp_vbox.add_child(exp_pb)

	# 2. Overview Stats (3 cards, No Building Count as requested)
	var stats_title := Label.new()
	stats_title.text = "📊 TỔNG QUAN TIẾN ĐỘ"
	stats_title.add_theme_font_size_override("font_size", 13)
	stats_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	root_vbox.add_child(stats_title)

	var stats_grid := HBoxContainer.new()
	stats_grid.add_theme_constant_override("separation", 10)
	root_vbox.add_child(stats_grid)

	var party_cp := GameState.get_party_combat_power()
	var total_heroes := GameState.heroes.size()
	var cur_flr := GameState.current_floor
	var w_lvl := GameState.world_level

	_create_stat_card(stats_grid, "⚔️ Tổng Lực Chiến", _format_number(party_cp), "Đội hình xuất kích chính", Color(1.0, 0.75, 0.3))
	_create_stat_card(stats_grid, "🦸 Anh Hùng Đang Sở Hữu", "%d Tướng" % total_heroes, _get_hero_rarity_summary(), Color(0.4, 0.9, 0.6))
	_create_stat_card(stats_grid, "🗼 Tháp Thử Thách", "Tầng %d" % cur_flr, "Cấp Thế Giới: WL.%d" % w_lvl, Color(0.45, 0.8, 1.0))

	# 3. Active Party Showcase (5 heroes)
	var party_title := Label.new()
	party_title.text = "⚔️ ĐỘI HÌNH XUẤT KÍCH TIÊU BIỂU (5 TƯỚNG)"
	party_title.add_theme_font_size_override("font_size", 13)
	party_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	root_vbox.add_child(party_title)

	var party_hbox := HBoxContainer.new()
	party_hbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(party_hbox)

	var party_heroes := _get_active_or_top_party_heroes()
	for i in range(5):
		var slot_card := PanelContainer.new()
		slot_card.custom_minimum_size = Vector2(120, 110)
		slot_card.size_flags_horizontal = SIZE_EXPAND_FILL

		var sc_style := StyleBoxFlat.new()
		sc_style.bg_color = Color(0.06, 0.08, 0.14, 0.85)
		sc_style.border_width_left = 1
		sc_style.border_width_top = 1
		sc_style.border_width_right = 1
		sc_style.border_width_bottom = 1
		sc_style.border_color = Color(0.2, 0.3, 0.45, 0.6)
		sc_style.corner_radius_top_left = 6
		sc_style.corner_radius_top_right = 6
		sc_style.corner_radius_bottom_left = 6
		sc_style.corner_radius_bottom_right = 6
		slot_card.add_theme_stylebox_override("panel", sc_style)
		party_hbox.add_child(slot_card)

		var sc_margin := MarginContainer.new()
		sc_margin.add_theme_constant_override("margin_left", 6)
		sc_margin.add_theme_constant_override("margin_top", 6)
		sc_margin.add_theme_constant_override("margin_right", 6)
		sc_margin.add_theme_constant_override("margin_bottom", 6)
		slot_card.add_child(sc_margin)

		var sc_vbox := VBoxContainer.new()
		sc_vbox.add_theme_constant_override("separation", 2)
		sc_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		sc_margin.add_child(sc_vbox)

		if i < party_heroes.size():
			var h: Dictionary = party_heroes[i]
			var h_name: String = str(h.get("name", "Anh Hùng"))
			var h_lvl: int = int(h.get("level", 1))
			var h_star: int = int(h.get("star", 1))
			var h_rarity: String = str(h.get("rarity", "SR")).to_upper()
			var h_elem: String = str(h.get("element", "NEUTRAL")).to_upper()
			var h_cp: int = GameStateSingleton.calculate_hero_cp(h)

			var rarity_col := _get_rarity_color(h_rarity)
			sc_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.65)

			var star_lbl := Label.new()
			star_lbl.text = "★".repeat(clampi(h_star, 1, 7))
			star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			star_lbl.add_theme_font_size_override("font_size", 10)
			star_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			sc_vbox.add_child(star_lbl)

			var h_icon := Label.new()
			h_icon.text = _get_element_emoji(h_elem)
			h_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h_icon.add_theme_font_size_override("font_size", 20)
			sc_vbox.add_child(h_icon)

			var hn_lbl := Label.new()
			hn_lbl.text = h_name
			hn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hn_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			hn_lbl.add_theme_font_size_override("font_size", 11)
			hn_lbl.add_theme_color_override("font_color", rarity_col)
			sc_vbox.add_child(hn_lbl)

			var hlvl_lbl := Label.new()
			hlvl_lbl.text = "Lv.%d · LC: %s" % [h_lvl, _format_number(h_cp)]
			hlvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hlvl_lbl.add_theme_font_size_override("font_size", 9)
			hlvl_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.95))
			sc_vbox.add_child(hlvl_lbl)
		else:
			var empty_lbl := Label.new()
			empty_lbl.text = "➕\nTrống"
			empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty_lbl.add_theme_font_size_override("font_size", 12)
			empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.55))
			sc_vbox.add_child(empty_lbl)

func _create_stat_card(parent: Control, title: String, main_val: String, sub_val: String, accent_col: Color) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.17, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(accent_col.r, accent_col.g, accent_col.b, 0.45)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_bottom", 10)
	card.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	m.add_child(v)

	var t_lbl := Label.new()
	t_lbl.text = title
	t_lbl.add_theme_font_size_override("font_size", 11)
	t_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	v.add_child(t_lbl)

	var v_lbl := Label.new()
	v_lbl.text = main_val
	v_lbl.add_theme_font_size_override("font_size", 15)
	v_lbl.add_theme_color_override("font_color", accent_col)
	v.add_child(v_lbl)

	var s_lbl := Label.new()
	s_lbl.text = sub_val
	s_lbl.add_theme_font_size_override("font_size", 10)
	s_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	v.add_child(s_lbl)

func _get_active_or_top_party_heroes() -> Array:
	var result: Array = []
	if GameState.active_party_ids.size() > 0:
		for hid in GameState.active_party_ids:
			for h in GameState.heroes:
				if h is Dictionary and str(h.get("id", "")) == str(hid):
					result.append(h)
					break
	if result.size() == 0:
		var sorted := GameState.heroes.duplicate()
		sorted.sort_custom(func(a, b):
			return GameStateSingleton.calculate_hero_cp(a) > GameStateSingleton.calculate_hero_cp(b)
		)
		for i in range(mini(5, sorted.size())):
			result.append(sorted[i])
	return result

func _get_hero_rarity_summary() -> String:
	var ssr := 0
	var sr := 0
	var r := 0
	for h in GameState.heroes:
		if h is Dictionary:
			var rar := str(h.get("rarity", "SR")).to_upper()
			if rar.contains("SSR") or rar.contains("UR"):
				ssr += 1
			elif rar.contains("SR"):
				sr += 1
			else:
				r += 1
	return "%d SSR · %d SR · %d R" % [ssr, sr, r]

func _get_avatar_icon() -> String:
	if GameState.selected_avatar_hero_id != "":
		for h in GameState.heroes:
			if h is Dictionary and str(h.get("id", "")) == GameState.selected_avatar_hero_id:
				return _get_element_emoji(str(h.get("element", "NEUTRAL")))
	return "🧙‍♂️"

# ==============================================================================
# TAB 1: CÀI ĐẶT (SETTINGS)
# ==============================================================================
func _render_settings_tab() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_content_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(root_vbox)

	# --- 1. SECTION: ÂM THANH ---
	var audio_sec := _create_settings_section(root_vbox, "🔊 ÂM THANH & HIỆU ỨNG")
	
	# BGM Slider
	var bgm_val: float = _get_bus_volume_percent(_audio_bus_bgm_idx)
	_create_slider_row(audio_sec, "Nhạc Nền (BGM):", bgm_val, func(val: float):
		_set_bus_volume_percent(_audio_bus_bgm_idx, val)
	)

	# SFX Slider
	var sfx_val: float = _get_bus_volume_percent(_audio_bus_sfx_idx)
	_create_slider_row(audio_sec, "Hiệu Ứng Âm Thanh (SFX):", sfx_val, func(val: float):
		_set_bus_volume_percent(_audio_bus_sfx_idx, val)
	)

	# Mute All Checkbox
	var is_muted := AudioServer.is_bus_mute(_audio_bus_master_idx) if _audio_bus_master_idx != -1 else false
	var mute_cb := CheckBox.new()
	mute_cb.text = " 🔇 Tắt Toàn Bộ Âm Thanh (Mute All)"
	mute_cb.button_pressed = is_muted
	mute_cb.focus_mode = FOCUS_NONE
	mute_cb.toggled.connect(func(pressed: bool):
		if _audio_bus_master_idx != -1:
			AudioServer.set_bus_mute(_audio_bus_master_idx, pressed)
		show_toast("🔊 Đã %s âm thanh!" % ("TẮT" if pressed else "BẬT"), true)
	)
	audio_sec.add_child(mute_cb)

	# --- 2. SECTION: ĐỒ HỌA & HIỂN THỊ (FPS 30/60/120/240 as requested) ---
	var gfx_sec := _create_settings_section(root_vbox, "🖥️ ĐỒ HỌA & HIỂN THỊ")

	# FPS Selector: 30 / 60 / 120 / 240
	var fps_row := HBoxContainer.new()
	fps_row.add_theme_constant_override("separation", 12)
	gfx_sec.add_child(fps_row)

	var fps_lbl := Label.new()
	fps_lbl.text = "Giới hạn Tốc độ Khung hình (FPS):"
	fps_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	fps_lbl.add_theme_font_size_override("font_size", 12)
	fps_row.add_child(fps_lbl)

	var fps_opt := OptionButton.new()
	fps_opt.custom_minimum_size = Vector2(130, 30)
	fps_opt.focus_mode = FOCUS_NONE
	fps_opt.add_item("30 FPS", 30)
	fps_opt.add_item("60 FPS (Chuẩn)", 60)
	fps_opt.add_item("120 FPS (Mượt)", 120)
	fps_opt.add_item("240 FPS (Tối đa)", 240)

	var cur_fps := Engine.max_fps
	var sel_idx := 1 # Default 60
	if cur_fps == 30: sel_idx = 0
	elif cur_fps == 60: sel_idx = 1
	elif cur_fps == 120: sel_idx = 2
	elif cur_fps == 240: sel_idx = 3
	fps_opt.selected = sel_idx

	fps_opt.item_selected.connect(func(idx: int):
		var target_fps: int = int(fps_opt.get_item_id(idx))
		Engine.max_fps = target_fps
		show_toast("🖥️ Đã đặt giới hạn khung hình: %d FPS" % target_fps, true)
	)
	fps_row.add_child(fps_opt)

	# Screen mode
	var screen_row := HBoxContainer.new()
	screen_row.add_theme_constant_override("separation", 12)
	gfx_sec.add_child(screen_row)

	var screen_lbl := Label.new()
	screen_lbl.text = "Chế độ Toàn Màn Hình (Fullscreen):"
	screen_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	screen_lbl.add_theme_font_size_override("font_size", 12)
	screen_row.add_child(screen_lbl)

	var full_check := CheckButton.new()
	full_check.focus_mode = FOCUS_NONE
	var cur_mode := DisplayServer.window_get_mode()
	full_check.button_pressed = (cur_mode == DisplayServer.WINDOW_MODE_FULLSCREEN or cur_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	full_check.toggled.connect(func(is_full: bool):
		if is_full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		show_toast("🖥️ Chế độ màn hình: %s" % ("Toàn màn hình" if is_full else "Cửa sổ"), true)
	)
	screen_row.add_child(full_check)

	# Weather Selection inside Settings
	var weather_row := HBoxContainer.new()
	weather_row.add_theme_constant_override("separation", 12)
	gfx_sec.add_child(weather_row)

	var w_lbl := Label.new()
	w_lbl.text = "Thời tiết & Ánh sáng Lâu Đài:"
	w_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	w_lbl.add_theme_font_size_override("font_size", 12)
	weather_row.add_child(w_lbl)

	var w_opt := OptionButton.new()
	w_opt.custom_minimum_size = Vector2(130, 30)
	w_opt.focus_mode = FOCUS_NONE
	w_opt.add_item("🌤️ Ban Ngày", 0)
	w_opt.add_item("🌅 Hoàng Hôn", 1)
	w_opt.add_item("🌙 Ban Đêm", 2)
	w_opt.item_selected.connect(func(idx: int):
		var p_name := "day"
		if idx == 1: p_name = "sunset"
		elif idx == 2: p_name = "night"
		weather_changed.emit(p_name)
		show_toast("🌤️ Đã đổi thời tiết sang: %s" % w_opt.get_item_text(idx), true)
	)
	weather_row.add_child(w_opt)

	# --- 3. SECTION: TÀI KHOẢN ---
	var acc_sec := _create_settings_section(root_vbox, "👤 TÀI KHOẢN & PHIÊN ĐĂNG NHẬP")

	var acc_row := HBoxContainer.new()
	acc_row.add_theme_constant_override("separation", 12)
	acc_sec.add_child(acc_row)

	var acc_lbl := Label.new()
	acc_lbl.text = "Tài khoản hiện tại: [b]%s[/b] (Máy chủ: Infiniti Alpha 2026)" % (GameState.DEFAULT_DEMO_USERNAME)
	acc_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	acc_lbl.add_theme_font_size_override("font_size", 12)
	acc_row.add_child(acc_lbl)

	var logout_btn := Button.new()
	logout_btn.text = "🚪 Đăng Xuất"
	logout_btn.custom_minimum_size = Vector2(110, 30)
	logout_btn.focus_mode = FOCUS_NONE
	var l_style := StyleBoxFlat.new()
	l_style.bg_color = Color(0.38, 0.12, 0.12, 0.85)
	l_style.corner_radius_top_left = 6
	l_style.corner_radius_top_right = 6
	l_style.corner_radius_bottom_left = 6
	l_style.corner_radius_bottom_right = 6
	logout_btn.add_theme_stylebox_override("normal", l_style)
	logout_btn.pressed.connect(func():
		show_toast("ℹ️ Bạn đang chạy phiên bản Demo Local, phiên đăng nhập được duy trì.", false)
	)
	acc_row.add_child(logout_btn)

func _create_settings_section(parent: Control, header: String) -> VBoxContainer:
	var sec_panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.11, 0.17, 0.8)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.2, 0.3, 0.45, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	sec_panel.add_theme_stylebox_override("panel", style)
	parent.add_child(sec_panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_bottom", 12)
	sec_panel.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var h_lbl := Label.new()
	h_lbl.text = header
	h_lbl.add_theme_font_size_override("font_size", 12)
	h_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	v.add_child(h_lbl)

	return v

func _create_slider_row(parent: Control, title: String, init_val: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d%%" % int(init_val * 100.0)
	val_lbl.custom_minimum_size = Vector2(45, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))

	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(160, 20)
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = init_val
	slider.focus_mode = FOCUS_NONE
	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%d%%" % int(v * 100.0)
		on_change.call(v)
	)

	row.add_child(slider)
	row.add_child(val_lbl)

func _get_bus_volume_percent(bus_idx: int) -> float:
	if bus_idx == -1: return 1.0
	var db_val := AudioServer.get_bus_volume_db(bus_idx)
	return db_to_linear(db_val)

func _set_bus_volume_percent(bus_idx: int, pct: float) -> void:
	if bus_idx == -1: return
	var db_val := linear_to_db(clampf(pct, 0.001, 1.0))
	AudioServer.set_bus_volume_db(bus_idx, db_val)

# ==============================================================================
# TAB 2: MÃ QUÀ TẶNG (GIFTCODE)
# ==============================================================================
func _render_giftcode_tab() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_content_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(root_vbox)

	# Banner
	var banner := PanelContainer.new()
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.12, 0.16, 0.25, 0.9)
	b_style.border_width_left = 1
	b_style.border_width_top = 1
	b_style.border_width_right = 1
	b_style.border_width_bottom = 1
	b_style.border_color = Color(0.85, 0.65, 0.25, 0.75)
	b_style.corner_radius_top_left = 8
	b_style.corner_radius_top_right = 8
	b_style.corner_radius_bottom_left = 8
	b_style.corner_radius_bottom_right = 8
	banner.add_theme_stylebox_override("panel", b_style)
	root_vbox.add_child(banner)

	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 14)
	bm.add_theme_constant_override("margin_top", 12)
	bm.add_theme_constant_override("margin_right", 14)
	bm.add_theme_constant_override("margin_bottom", 12)
	banner.add_child(bm)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 4)
	bm.add_child(bv)

	var b_title := Label.new()
	b_title.text = "🎁 TRUNG TÂM KÍCH HOẠT MÃ QUÀ TẶNG"
	b_title.add_theme_font_size_override("font_size", 14)
	b_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.45))
	bv.add_child(b_title)

	var b_desc := Label.new()
	b_desc.text = "Nhập mã quà tặng nhận từ sự kiện hoặc mã hỗ trợ thử nghiệm để nhận Đá Quý, Vàng, Khẩu Phần và Thiên Thư."
	b_desc.add_theme_font_size_override("font_size", 11)
	b_desc.add_theme_color_override("font_color", Color(0.8, 0.88, 0.98))
	bv.add_child(b_desc)

	# Input Row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(input_row)

	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "Nhập mã quà tặng (VD: FULL, VIP999, INFINITI2026)..."
	line_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	line_edit.custom_minimum_size = Vector2(0, 42)
	line_edit.add_theme_font_size_override("font_size", 13)
	input_row.add_child(line_edit)

	line_edit.text_changed.connect(func(new_text: String):
		var upper := new_text.to_upper()
		if upper != new_text:
			var car := line_edit.caret_column
			line_edit.text = upper
			line_edit.caret_column = car
	)

	var redeem_btn := Button.new()
	redeem_btn.text = "🎁 Nhận Quà"
	redeem_btn.custom_minimum_size = Vector2(130, 42)
	redeem_btn.focus_mode = FOCUS_NONE
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.85, 0.55, 0.15, 0.95)
	r_style.corner_radius_top_left = 6
	r_style.corner_radius_top_right = 6
	r_style.corner_radius_bottom_left = 6
	r_style.corner_radius_bottom_right = 6
	redeem_btn.add_theme_stylebox_override("normal", r_style)
	redeem_btn.add_theme_font_size_override("font_size", 13)
	input_row.add_child(redeem_btn)

	# Quick Test Pills
	var quick_title := Label.new()
	quick_title.text = "⚡ MÃ NHANH THỬ NGHIỆM (Click để tự động nhập):"
	quick_title.add_theme_font_size_override("font_size", 11)
	quick_title.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
	root_vbox.add_child(quick_title)

	var quick_hbox := HBoxContainer.new()
	quick_hbox.add_theme_constant_override("separation", 8)
	root_vbox.add_child(quick_hbox)

	var test_codes := [
		{"code": "FULL", "label": "⚡ Mã FULL (Max Tài Nguyên)", "col": Color(0.9, 0.4, 0.2)},
		{"code": "VIP999", "label": "👑 VIP999 (Tân Thủ VIP)", "col": Color(0.3, 0.6, 0.9)},
		{"code": "INFINITI2026", "label": "🎉 INFINITI2026", "col": Color(0.2, 0.7, 0.5)},
		{"code": "FREESUMMON", "label": "📜 FREESUMMON (30 Vé)", "col": Color(0.7, 0.4, 0.9)},
	]

	for tc in test_codes:
		var qb := Button.new()
		qb.text = tc["label"]
		qb.custom_minimum_size = Vector2(0, 32)
		qb.focus_mode = FOCUS_NONE
		qb.add_theme_font_size_override("font_size", 11)
		var q_style := StyleBoxFlat.new()
		var col: Color = tc["col"]
		q_style.bg_color = Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.85)
		q_style.border_width_left = 1
		q_style.border_width_top = 1
		q_style.border_width_right = 1
		q_style.border_width_bottom = 1
		q_style.border_color = col
		q_style.corner_radius_top_left = 6
		q_style.corner_radius_top_right = 6
		q_style.corner_radius_bottom_left = 6
		q_style.corner_radius_bottom_right = 6
		qb.add_theme_stylebox_override("normal", q_style)
		var c_str: String = tc["code"]
		qb.pressed.connect(func():
			line_edit.text = c_str
			_execute_redeem(c_str, line_edit)
		)
		quick_hbox.add_child(qb)

	# Reward Result Container
	var result_panel := PanelContainer.new()
	result_panel.name = "ResultPanel"
	result_panel.visible = false
	var rp_style := StyleBoxFlat.new()
	rp_style.bg_color = Color(0.06, 0.1, 0.16, 0.95)
	rp_style.border_width_left = 1
	rp_style.border_width_top = 1
	rp_style.border_width_right = 1
	rp_style.border_width_bottom = 1
	rp_style.border_color = Color(0.3, 0.75, 0.45, 0.8)
	rp_style.corner_radius_top_left = 8
	rp_style.corner_radius_top_right = 8
	rp_style.corner_radius_bottom_left = 8
	rp_style.corner_radius_bottom_right = 8
	result_panel.add_theme_stylebox_override("panel", rp_style)
	root_vbox.add_child(result_panel)

	redeem_btn.pressed.connect(func():
		var code := line_edit.text.strip_edges().to_upper()
		if code == "":
			show_toast("⚠️ Vui lòng nhập mã quà tặng trước khi nhận!", false)
			return
		_execute_redeem(code, line_edit)
	)

func _execute_redeem(code: String, line_edit: LineEdit) -> void:
	line_edit.editable = false
	var res = await GameState.redeem_giftcode(code)
	line_edit.editable = true

	if res.get("ok", false):
		var data: Dictionary = res.get("data", {})
		var title: String = str(data.get("title", "Mã Quà Tặng Hợp Lệ"))
		var msg: String = str(data.get("message", "Đã nhận quà thành công!"))
		show_toast("🎉 %s: %s" % [title, msg], true)
		_show_gift_rewards(data.get("rewards", {}))
		line_edit.text = ""
	else:
		var err_msg: String = str(res.get("error", "Mã quà tặng không hợp lệ hoặc đã hết hạn."))
		show_toast("❌ %s" % err_msg, false)

func _show_gift_rewards(rewards: Dictionary) -> void:
	var result_panel: PanelContainer = _content_panel.find_child("ResultPanel", true, false)
	if result_panel == null: return
	
	result_panel.visible = true
	for child in result_panel.get_children():
		child.queue_free()

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_bottom", 12)
	result_panel.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	m.add_child(v)

	var r_lbl := Label.new()
	r_lbl.text = "✨ PHẦN THƯỞNG ĐÃ ĐƯỢC CỘNG VÀO TÚI ĐỒ & TOP HUD:"
	r_lbl.add_theme_font_size_override("font_size", 12)
	r_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	v.add_child(r_lbl)

	var r_hbox := HBoxContainer.new()
	r_hbox.add_theme_constant_override("separation", 10)
	v.add_child(r_hbox)

	var gems := int(rewards.get("gems", 0))
	var silver := int(rewards.get("silver", 0))
	var food := int(rewards.get("food", 0))
	var scrolls := int(rewards.get("scrolls", 0))

	if gems > 0:
		_create_reward_badge(r_hbox, "💎 +%s Đá Quý" % _format_number(gems), Color(0.45, 0.85, 1.0))
	if silver > 0:
		_create_reward_badge(r_hbox, "🪙 +%s Vàng" % _format_number(silver), Color(1.0, 0.85, 0.35))
	if food > 0:
		_create_reward_badge(r_hbox, "🍖 +%s Khẩu Phần" % _format_number(food), Color(1.0, 0.6, 0.4))
	if scrolls > 0:
		_create_reward_badge(r_hbox, "📜 +%s Thiên Thư" % _format_number(scrolls), Color(0.6, 0.95, 0.6))

func _create_reward_badge(parent: Control, text: String, col: Color) -> void:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.85)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = col
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	pill.add_theme_stylebox_override("panel", style)
	parent.add_child(pill)

	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 8)
	pm.add_theme_constant_override("margin_top", 4)
	pm.add_theme_constant_override("margin_right", 8)
	pm.add_theme_constant_override("margin_bottom", 4)
	pill.add_child(pm)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	pm.add_child(lbl)

# ==============================================================================
# TAB 3: HỖ TRỢ & BÁO LỖI (SUPPORT)
# ==============================================================================
func _render_support_tab() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	_content_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(root_vbox)

	var header_lbl := Label.new()
	header_lbl.text = "🛟 GỬI PHIẾU HỖ TRỢ & BÁO CÁO LỖI"
	header_lbl.add_theme_font_size_override("font_size", 13)
	header_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	root_vbox.add_child(header_lbl)

	# Category dropdown
	var cat_row := HBoxContainer.new()
	cat_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(cat_row)

	var cat_lbl := Label.new()
	cat_lbl.text = "Danh mục hỗ trợ:"
	cat_lbl.custom_minimum_size = Vector2(120, 0)
	cat_lbl.add_theme_font_size_override("font_size", 12)
	cat_row.add_child(cat_lbl)

	var cat_opt := OptionButton.new()
	cat_opt.custom_minimum_size = Vector2(220, 32)
	cat_opt.focus_mode = FOCUS_NONE
	cat_opt.add_item("🐛 Báo lỗi Game (Bug Report)", 0)
	cat_opt.add_item("💡 Góp ý tính năng (Feedback)", 1)
	cat_opt.add_item("🔑 Hỗ trợ tài khoản (Account)", 2)
	cat_row.add_child(cat_opt)

	# Subject
	var sub_row := HBoxContainer.new()
	sub_row.add_theme_constant_override("separation", 10)
	root_vbox.add_child(sub_row)

	var sub_lbl := Label.new()
	sub_lbl.text = "Tiêu đề phiếu:"
	sub_lbl.custom_minimum_size = Vector2(120, 0)
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_row.add_child(sub_lbl)

	var sub_input := LineEdit.new()
	sub_input.placeholder_text = "Nhập ngắn gọn vấn đề cần báo cáo..."
	sub_input.size_flags_horizontal = SIZE_EXPAND_FILL
	sub_input.custom_minimum_size = Vector2(0, 34)
	sub_input.add_theme_font_size_override("font_size", 12)
	sub_row.add_child(sub_input)

	# Body
	var body_lbl := Label.new()
	body_lbl.text = "Chi tiết nội dung sự cố / đề xuất:"
	body_lbl.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(body_lbl)

	var body_input := TextEdit.new()
	body_input.placeholder_text = "Mô tả chi tiết các bước xảy ra lỗi hoặc nội dung góp ý của bạn..."
	body_input.custom_minimum_size = Vector2(0, 90)
	body_input.size_flags_horizontal = SIZE_EXPAND_FILL
	body_input.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(body_input)

	var send_btn := Button.new()
	send_btn.text = "📨 Gửi Phiếu Hỗ Trợ"
	send_btn.custom_minimum_size = Vector2(160, 36)
	send_btn.focus_mode = FOCUS_NONE
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0.2, 0.45, 0.75, 0.9)
	sb_style.corner_radius_top_left = 6
	sb_style.corner_radius_top_right = 6
	sb_style.corner_radius_bottom_left = 6
	sb_style.corner_radius_bottom_right = 6
	send_btn.add_theme_stylebox_override("normal", sb_style)
	root_vbox.add_child(send_btn)

	send_btn.pressed.connect(func():
		var subject := sub_input.text.strip_edges()
		var body_text := body_input.text.strip_edges()
		if subject == "" or body_text == "":
			show_toast("⚠️ Vui lòng điền đủ tiêu đề và nội dung phiếu!", false)
			return

		var cat_name := "BUG_REPORT"
		if cat_opt.selected == 1: cat_name = "FEEDBACK"
		elif cat_opt.selected == 2: cat_name = "ACCOUNT"

		send_btn.disabled = true
		var payload := {
			"subject": subject,
			"body": body_text,
			"category": cat_name
		}
		var res = await ApiClient.post_req("/api/support/tickets", payload)
		send_btn.disabled = false

		if res.get("ok", false):
			show_toast("📨 Đã gửi phiếu hỗ trợ thành công!", true)
			sub_input.text = ""
			body_input.text = ""
		else:
			show_toast("❌ Gửi phiếu thất bại: %s" % str(res.get("error", "Lỗi mạng")), false)
	)

# ==============================================================================
# AVATAR PICKER POPUP
# ==============================================================================
func _open_avatar_picker() -> void:
	_close_avatar_picker()

	_avatar_picker_wrap = Control.new()
	_avatar_picker_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_picker_wrap.anchor_right = 1.0
	_avatar_picker_wrap.anchor_bottom = 1.0
	_avatar_picker_wrap.size = size
	_avatar_picker_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_avatar_picker_wrap)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0, 0, 0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_avatar_picker()
	)
	_avatar_picker_wrap.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_picker_wrap.add_child(center)

	_avatar_picker_panel = PanelContainer.new()
	_avatar_picker_panel.custom_minimum_size = Vector2(480, 340)

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.9, 0.7, 0.25, 0.85)
	p_style.corner_radius_top_left = 8
	p_style.corner_radius_top_right = 8
	p_style.corner_radius_bottom_left = 8
	p_style.corner_radius_bottom_right = 8
	p_style.shadow_size = 20
	_avatar_picker_panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(_avatar_picker_panel)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 12)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_bottom", 12)
	_avatar_picker_panel.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var h_row := HBoxContainer.new()
	v.add_child(h_row)

	var t := Label.new()
	t.text = "🔄 CHỌN CHÂN DUNG ĐẠI DIỆN"
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 13)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	h_row.add_child(t)

	var close_av := Button.new()
	close_av.text = " ✕ "
	close_av.pressed.connect(_close_avatar_picker)
	h_row.add_child(close_av)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(scroll)

	var grid := HFlowContainer.new()
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)

	# Default Master option
	var def_btn := Button.new()
	def_btn.text = "🧙‍♂️\nMaster Gốc"
	def_btn.custom_minimum_size = Vector2(80, 80)
	def_btn.pressed.connect(func():
		GameState.selected_avatar_hero_id = ""
		show_toast("🧙‍♂️ Đã chọn đại diện Master Gốc!", true)
		_close_avatar_picker()
		_render_profile_tab()
	)
	grid.add_child(def_btn)

	for h in GameState.heroes:
		if h is Dictionary:
			var hid := str(h.get("id", ""))
			var hname := str(h.get("name", "Anh Hùng"))
			var elem := str(h.get("element", "NEUTRAL"))
			var btn := Button.new()
			btn.text = "%s\n%s" % [_get_element_emoji(elem), hname]
			btn.custom_minimum_size = Vector2(80, 80)
			btn.pressed.connect(func():
				GameState.selected_avatar_hero_id = hid
				show_toast("✨ Đã chọn đại diện: %s!" % hname, true)
				_close_avatar_picker()
				_render_profile_tab()
			)
			grid.add_child(btn)

func _close_avatar_picker() -> void:
	if _avatar_picker_wrap != null:
		_avatar_picker_wrap.queue_free()
		_avatar_picker_wrap = null
	_avatar_picker_panel = null

# ==============================================================================
# TOAST NOTIFICATION OVERLAY
# ==============================================================================
func _build_toast_overlay() -> void:
	_toast_banner = PanelContainer.new()
	_toast_banner.set_anchors_preset(PRESET_CENTER_TOP)
	_toast_banner.position = Vector2(0, 14)
	_toast_banner.visible = false
	_toast_banner.mouse_filter = MOUSE_FILTER_IGNORE
	_main_panel.add_child(_toast_banner)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_bottom", 8)
	_toast_banner.add_child(m)

	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 12)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.add_child(_toast_label)

func show_toast(msg: String, is_success: bool = true) -> void:
	if _toast_banner == null or _toast_label == null: return

	var style := StyleBoxFlat.new()
	if is_success:
		style.bg_color = Color(0.08, 0.28, 0.16, 0.95)
		style.border_color = Color(0.35, 0.9, 0.55)
	else:
		style.bg_color = Color(0.35, 0.08, 0.12, 0.95)
		style.border_color = Color(0.95, 0.4, 0.4)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	_toast_banner.add_theme_stylebox_override("panel", style)

	_toast_label.text = msg
	_toast_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_toast_banner.modulate.a = 0.0
	_toast_banner.visible = true

	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()

	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_banner, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_banner, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func():
		_toast_banner.visible = false
	)

func _close_modal() -> void:
	closed.emit()
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close_modal()
		get_viewport().set_input_as_handled()

# ==============================================================================
# HELPERS
# ==============================================================================
func _format_number(val: int) -> String:
	var s := str(absi(val))
	var res := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		count += 1
		if count % 3 == 0 and i > 0:
			res = "," + res
	return ("-" if val < 0 else "") + res

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"SSR", "UR": return Color(1.0, 0.85, 0.25)
		"SR": return Color(0.75, 0.45, 1.0)
		"R": return Color(0.35, 0.75, 1.0)
		_: return Color(0.65, 0.75, 0.85)

func _get_element_emoji(elem: String) -> String:
	match elem:
		"FIRE": return "🔥"
		"WATER": return "💧"
		"WIND": return "🌪️"
		"EARTH": return "🪨"
		"LIGHT": return "✨"
		"DARK": return "🌑"
		_: return "⚔️"
