extends Control
## World RTS Map Scene — Solar-Scale Fantasy Stylized 3D Planet & Tactical Expedition Map.
## Features:
## - Virtual Solar-Scale Planet (R_virtual = 696,000 km; 12x12 sector = 0.66 deg valley inside giant Emerald Reach)
## - Dual-Tier Render Budget (<= 3 Draw Calls): LocalTerrainPatch 64x64 GPU Micro-Terrain <-> 3D Morph Globe
## - Dual-Resolution Soft Swirling Cloud Fog-of-War (zero hard black squares!)
## - Stylized Vector Map Icons (3-Tower Castle Base, Runic Dungeon Portals, Terrain Motifs, Golden Wonder Spire)
## - Spatial Window Culling + Screen-Space Label Anti-Overlap + Cartographic Region Borders
## - Top-Left 2:1 Horizontal Minimap + Right-Edge Vertical Altitude Zoom Rail (km) + Region Inspector Card
## - Full Expedition gameplay preserved (Floating Tile Overlay, Fleet Panel, Dispatch, Reports, Airship Port)

const WorldMap3DScene := preload("res://world_map/scenes/world_map_3d.tscn")
const WorldMapManagerScript := preload("res://world_map/core/world_map_manager.gd")
const HorizontalMinimapScript := preload("res://world_map/map_2d/horizontal_minimap.gd")
const MapIconDrawerScript := preload("res://world_map/map_2d/map_icon_drawer.gd")

const POLL_INTERVAL_SEC := 3.0
const DRAG_CLICK_THRESHOLD_PX := 6.0

const TERRAIN_COLORS := {
	"OCEAN": Color(0.08, 0.28, 0.52),
	"PLAINS": Color(0.24, 0.46, 0.28),
	"FOREST": Color(0.12, 0.36, 0.22),
	"HILLS": Color(0.46, 0.38, 0.24),
	"MOUNTAIN": Color(0.36, 0.40, 0.50),
	"MARSH": Color(0.16, 0.36, 0.38),
	"RUINS": Color(0.44, 0.30, 0.52),
	"WONDER": Color(0.76, 0.58, 0.18),
}

const TERRAIN_NAMES := {
	"OCEAN": "Đại dương",
	"PLAINS": "Đồng bằng",
	"FOREST": "Rừng rậm",
	"HILLS": "Đồi núi",
	"MOUNTAIN": "Núi cao",
	"MARSH": "Đầm lầy",
	"RUINS": "Phế tích",
	"WONDER": "Kỳ quan",
}

const BIOME_NAMES := {
	"magic_forest": "Rừng Ma Thuật Lục Bảo",
	"crystal_desert": "Sa Mạc Pha Lê",
	"glacial_peaks": "Đỉnh Băng Vĩnh Cửu",
	"arcane_archipelago": "Quần Đảo Thiên Không",
	"cursed_volcanic": "Núi Lửa Nguyền Rủa",
	"imperial_wonder": "Thánh Địa Kỳ Quan",
}

const DUNGEON_RANK_COLORS := {
	"D": Color(0.42, 0.86, 0.52),
	"C": Color(0.30, 0.78, 0.98),
	"B": Color(0.76, 0.48, 0.98),
	"A": Color(0.98, 0.60, 0.20),
	"S": Color(0.98, 0.25, 0.28),
}

const MISSION_COLORS := {
	"SCOUT": Color(0.25, 0.88, 1.0),
	"GARRISON": Color(0.95, 0.78, 0.28),
	"DUNGEON": Color(1.0, 0.48, 0.22),
	"ATTACK": Color(0.96, 0.28, 0.32),
	"RESCUE": Color(0.28, 0.95, 0.56),
	"RETURNING": Color(0.45, 0.72, 1.0),
}

var _snapshot: Dictionary = {}
var _heroes: Array = []
var _busy_hero_ids: Dictionary = {}
var _selected_tile_id := ""
var _hovered_tile_id := ""
var _redirecting_expedition_id := ""
var _fleet_expanded := false
var _centered_once := false
var _updating_zoom_slider := false
var _coord_input_dirty := false
var _inspected_region: Dictionary = {}

var _pan_pressing := false
var _pan_dragged := false
var _pan_start_pos := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _poll_accum := 0.0
var _elapsed_since_sync := 0.0
var _pulse_time := 0.0
var _toast_timer := 0.0
var _last_chunk_center := Vector2i(-999, -999)
var _pending_chunk_center := Vector2i(-999, -999)
var _chunk_debounce_timer := 0.0
var _chunk_fetching := false
var _poll_interval_sec := POLL_INTERVAL_SEC
var _chunk_radius := 12

var world_map_manager: Node
var _viewport_container: SubViewportContainer
var _sub_viewport: SubViewport
var _world_3d: Node3D
var _map_canvas: Control
var _minimap: Control
var _coord_x_edit: LineEdit
var _coord_y_edit: LineEdit
var _lod_badge_lbl: Label
var _mode_toggle_btn: Button
var _zoom_slider: VSlider
var _altitude_lbl: Label
var _region_card: PanelContainer
var _region_card_title: Label
var _region_card_body: Label
var _toast_panel: PanelContainer
var _toast_lbl: Label
var _fleet_panel: PanelContainer
var _fleet_hdr_lbl: Label
var _fleet_scroll: ScrollContainer
var _fleet_list: VBoxContainer
var _fleet_compact_row: VBoxContainer
var _tile_popover: PanelContainer
var _popover_host: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_build_ui()
	if has_node("/root/GameState"):
		_apply_world_graphics_settings(GameState.get_world_graphics_settings())
	if has_node("/root/EventBus") and not EventBus.world_graphics_settings_changed.is_connected(_apply_world_graphics_settings):
		EventBus.world_graphics_settings_changed.connect(_apply_world_graphics_settings)
	if has_node("/root/ApiClient"):
		_sync_all()

func _apply_world_graphics_settings(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	if _sub_viewport != null:
		_sub_viewport.msaa_3d = int(cfg.get("msaa_3d", Viewport.MSAA_2X)) as Viewport.MSAA
	_chunk_radius = clampi(int(cfg.get("chunk_request_radius", 12)), 8, 16)
	_poll_interval_sec = clampf(float(cfg.get("poll_interval_sec", POLL_INTERVAL_SEC)), 2.0, 6.0)
	if world_map_manager != null and world_map_manager.has_method("apply_graphics_settings"):
		world_map_manager.call("apply_graphics_settings", cfg)
		if not _snapshot.is_empty():
			world_map_manager.call("rebuild_fog", _snapshot)

func _make_btn_style(bg: Color, border: Color, radius := 7) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s

func _style_button(btn: Button, accent := Color(0.32, 0.62, 0.92), bg := Color(0.10, 0.14, 0.22)) -> void:
	btn.add_theme_stylebox_override("normal", _make_btn_style(bg, accent.darkened(0.22)))
	btn.add_theme_stylebox_override("hover", _make_btn_style(bg.lightened(0.1), accent))
	btn.add_theme_stylebox_override("pressed", _make_btn_style(bg.darkened(0.12), accent.lightened(0.15)))
	btn.add_theme_stylebox_override("disabled", _make_btn_style(Color(0.07, 0.08, 0.12, 0.7), Color(0.2, 0.22, 0.28, 0.5)))
	btn.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.46, 0.5, 0.58))

func _make_panel_style(bg := Color(0.055, 0.078, 0.13, 0.92), border := Color(0.32, 0.52, 0.78, 0.7)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(10)
	s.set_content_margin_all(8)
	return s

func _make_recessed_style(_expanded: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	s.border_color = Color(0.0, 0.0, 0.0, 0.0)
	s.set_border_width_all(0)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _build_ui() -> void:
	# Solid deep-space backdrop prevents any 1px subpixel border bleed at viewport edges
	var space_bg := ColorRect.new()
	space_bg.name = "SpaceBackdropFill"
	space_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	space_bg.color = Color(0.012, 0.018, 0.042, 1.0)
	space_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(space_bg)

	# 0. Full-bleed 3D Fantasy Planet SubViewport (clipped cleanly with zero edge bleed)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "PlanetViewportContainer"
	_viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport_container.offset_left = 0.0
	_viewport_container.offset_top = 0.0
	_viewport_container.offset_right = 0.0
	_viewport_container.offset_bottom = 0.0
	_viewport_container.stretch = true
	_viewport_container.clip_contents = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_viewport_container)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "PlanetSubViewport"
	_sub_viewport.size = Vector2i(1280, 720)
	_sub_viewport.handle_input_locally = false
	_sub_viewport.msaa_3d = Viewport.MSAA_2X
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(_sub_viewport)

	_world_3d = WorldMap3DScene.instantiate()
	_world_3d.name = "WorldMap3D"
	_sub_viewport.add_child(_world_3d)

	world_map_manager = WorldMapManagerScript.new()
	world_map_manager.name = "WorldMapManager"
	add_child(world_map_manager)
	world_map_manager.call("setup", _world_3d)
	world_map_manager.call("set_focus_grid_immediate", 105.0, 105.0, 0.85)

	# Full-bleed transparent tactical overlay canvas
	_map_canvas = Control.new()
	_map_canvas.name = "TacticalMapCanvas"
	_map_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_canvas.draw.connect(_draw_rts_map)
	_map_canvas.gui_input.connect(_on_map_gui_input)
	add_child(_map_canvas)

	# 1. Top-Left: 2:1 Horizontal World Minimap + Editable Coordinates (X,Y) + Globe 3D Icon
	var mini_panel := PanelContainer.new()
	mini_panel.name = "HorizontalMinimapPanel"
	mini_panel.anchor_left = 0.0
	mini_panel.anchor_right = 0.0
	mini_panel.anchor_top = 0.0
	mini_panel.anchor_bottom = 0.0
	mini_panel.offset_left = 12.0
	mini_panel.offset_top = 12.0
	mini_panel.offset_right = 272.0
	mini_panel.offset_bottom = 198.0
	mini_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.042, 0.068, 0.118, 0.90), Color(0.84, 0.68, 0.32, 0.78)))
	add_child(mini_panel)

	var mini_vb := VBoxContainer.new()
	mini_vb.add_theme_constant_override("separation", 4)
	mini_panel.add_child(mini_vb)

	_minimap = HorizontalMinimapScript.new()
	_minimap.name = "HorizontalMinimap"
	_minimap.call(
		"configure",
		world_map_manager.call("get_albedo_texture"),
		world_map_manager.call("get_sector_bounds"),
		world_map_manager.call("get_global_fog_texture")
	)
	_minimap.navigate_lat_lon_requested.connect(_on_minimap_navigate)
	mini_vb.add_child(_minimap)

	var mini_bar := HBoxContainer.new()
	mini_bar.add_theme_constant_override("separation", 3)
	mini_vb.add_child(mini_bar)

	var x_lbl := Label.new()
	x_lbl.text = "X"
	x_lbl.add_theme_font_size_override("font_size", 10)
	x_lbl.add_theme_color_override("font_color", Color(0.96, 0.88, 0.56))
	mini_bar.add_child(x_lbl)

	_coord_x_edit = _make_coord_line_edit("105")
	mini_bar.add_child(_coord_x_edit)

	var y_lbl := Label.new()
	y_lbl.text = "Y"
	y_lbl.add_theme_font_size_override("font_size", 10)
	y_lbl.add_theme_color_override("font_color", Color(0.96, 0.88, 0.56))
	mini_bar.add_child(y_lbl)

	_coord_y_edit = _make_coord_line_edit("105")
	mini_bar.add_child(_coord_y_edit)

	var go_btn := Button.new()
	go_btn.text = "➜"
	go_btn.tooltip_text = "Đi tới tọa độ (X, Y)"
	go_btn.custom_minimum_size = Vector2(26, 26)
	go_btn.focus_mode = Control.FOCUS_NONE
	_style_button(go_btn, Color(0.95, 0.80, 0.36), Color(0.16, 0.13, 0.06))
	go_btn.pressed.connect(_navigate_to_input_coords)
	mini_bar.add_child(go_btn)

	_mode_toggle_btn = Button.new()
	_mode_toggle_btn.text = "🌐"
	_mode_toggle_btn.tooltip_text = "Chuyển nhanh Bản đồ 2D ↔ Hành tinh 3D"
	_mode_toggle_btn.custom_minimum_size = Vector2(30, 26)
	_style_button(_mode_toggle_btn, Color(0.62, 0.52, 1.0), Color(0.11, 0.10, 0.22))
	_mode_toggle_btn.pressed.connect(toggle_planet_3d_view)
	mini_bar.add_child(_mode_toggle_btn)

	var center_btn := Button.new()
	center_btn.text = "🎯"
	center_btn.tooltip_text = "Về Căn Cứ"
	center_btn.custom_minimum_size = Vector2(30, 26)
	_style_button(center_btn, Color(0.45, 0.78, 1.0))
	center_btn.pressed.connect(_center_on_base)
	mini_bar.add_child(center_btn)

	_lod_badge_lbl = Label.new()
	_lod_badge_lbl.text = "Chiến khu • Lục Bảo"
	_lod_badge_lbl.clip_text = true
	_lod_badge_lbl.add_theme_font_size_override("font_size", 10)
	_lod_badge_lbl.add_theme_color_override("font_color", Color(0.58, 0.86, 1.0))
	mini_vb.add_child(_lod_badge_lbl)

	# 2. Left (below Horizontal Minimap): Recessed Fleet Panel — collapsed by default
	_fleet_panel = PanelContainer.new()
	_fleet_panel.anchor_left = 0.0
	_fleet_panel.anchor_top = 0.0
	_fleet_panel.offset_left = 12.0
	_fleet_panel.offset_top = 206.0
	_fleet_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_fleet_panel)

	var fleet_vb := VBoxContainer.new()
	fleet_vb.add_theme_constant_override("separation", 6)
	_fleet_panel.add_child(fleet_vb)

	_fleet_hdr_lbl = Label.new()
	_fleet_hdr_lbl.text = "🛸 Hạm đội (0) ▾"
	_fleet_hdr_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	_fleet_hdr_lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_fleet_hdr_lbl.gui_input.connect(_on_fleet_panel_input)
	_fleet_hdr_lbl.add_theme_font_size_override("font_size", 12)
	_fleet_hdr_lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 0.62))
	fleet_vb.add_child(_fleet_hdr_lbl)

	_fleet_compact_row = VBoxContainer.new()
	_fleet_compact_row.add_theme_constant_override("separation", 3)
	fleet_vb.add_child(_fleet_compact_row)

	_fleet_scroll = ScrollContainer.new()
	_fleet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fleet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fleet_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_fleet_scroll.visible = false
	fleet_vb.add_child(_fleet_scroll)

	_fleet_list = VBoxContainer.new()
	_fleet_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fleet_list.add_theme_constant_override("separation", 6)
	_fleet_scroll.add_child(_fleet_list)

	_apply_fleet_panel_state()

	# 3. Right Edge: Vertical Altitude Zoom Rail (+ / Slider / - / km readout)
	var zoom_panel := PanelContainer.new()
	zoom_panel.name = "VerticalZoomRail"
	zoom_panel.anchor_left = 1.0
	zoom_panel.anchor_right = 1.0
	zoom_panel.anchor_top = 0.5
	zoom_panel.anchor_bottom = 0.5
	zoom_panel.offset_left = -66.0
	zoom_panel.offset_right = -12.0
	zoom_panel.offset_top = -132.0
	zoom_panel.offset_bottom = 112.0
	zoom_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.065, 0.115, 0.84), Color(0.45, 0.68, 0.92, 0.55)))
	add_child(zoom_panel)

	var z_vb := VBoxContainer.new()
	z_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	z_vb.add_theme_constant_override("separation", 4)
	zoom_panel.add_child(z_vb)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.tooltip_text = "Phóng gần (Chiến khu)"
	zoom_in_btn.custom_minimum_size = Vector2(34, 28)
	_style_button(zoom_in_btn, Color(0.45, 0.82, 1.0))
	zoom_in_btn.pressed.connect(func(): world_map_manager.call("zoom_by_step", 0.10))
	z_vb.add_child(zoom_in_btn)

	var slider_wrap := CenterContainer.new()
	slider_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	z_vb.add_child(slider_wrap)

	_zoom_slider = VSlider.new()
	_zoom_slider.min_value = 0.0
	_zoom_slider.max_value = 1.0
	_zoom_slider.step = 0.01
	_zoom_slider.value = 0.85
	_zoom_slider.custom_minimum_size = Vector2(24, 124)
	_zoom_slider.value_changed.connect(func(v: float):
		if not _updating_zoom_slider and world_map_manager != null:
			world_map_manager.call("set_zoom_target", v)
	)
	slider_wrap.add_child(_zoom_slider)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = "−"
	zoom_out_btn.tooltip_text = "Thu nhỏ (Hành tinh 3D)"
	zoom_out_btn.custom_minimum_size = Vector2(34, 28)
	_style_button(zoom_out_btn, Color(0.66, 0.56, 1.0))
	zoom_out_btn.pressed.connect(func(): world_map_manager.call("zoom_by_step", -0.10))
	z_vb.add_child(zoom_out_btn)

	_altitude_lbl = Label.new()
	_altitude_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_altitude_lbl.text = "120 km"
	_altitude_lbl.add_theme_font_size_override("font_size", 9)
	_altitude_lbl.add_theme_color_override("font_color", Color(0.76, 0.90, 1.0))
	z_vb.add_child(_altitude_lbl)

	# 4. Region / Continent Inspector Card (Bottom-Left glass card when clicking outside tactical tiles)
	_region_card = PanelContainer.new()
	_region_card.name = "RegionInspectorCard"
	_region_card.anchor_left = 0.0
	_region_card.anchor_right = 0.0
	_region_card.anchor_top = 1.0
	_region_card.anchor_bottom = 1.0
	_region_card.offset_left = 12.0
	_region_card.offset_right = 310.0
	_region_card.offset_top = -152.0
	_region_card.offset_bottom = -12.0
	_region_card.visible = false
	_region_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_region_card.add_theme_stylebox_override("panel", _make_panel_style(Color(0.04, 0.068, 0.12, 0.90), Color(0.78, 0.66, 0.36, 0.72)))
	add_child(_region_card)

	var rc_vb := VBoxContainer.new()
	rc_vb.add_theme_constant_override("separation", 6)
	_region_card.add_child(rc_vb)

	var rc_hdr := HBoxContainer.new()
	rc_vb.add_child(rc_hdr)

	_region_card_title = Label.new()
	_region_card_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_region_card_title.add_theme_font_size_override("font_size", 13)
	_region_card_title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.56))
	rc_hdr.add_child(_region_card_title)

	var rc_close := Button.new()
	rc_close.text = "✖"
	rc_close.custom_minimum_size = Vector2(26, 24)
	_style_button(rc_close, Color(0.75, 0.45, 0.45), Color(0.14, 0.08, 0.10))
	rc_close.pressed.connect(func(): _region_card.visible = false)
	rc_hdr.add_child(rc_close)

	_region_card_body = Label.new()
	_region_card_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_region_card_body.add_theme_font_size_override("font_size", 11)
	_region_card_body.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98))
	rc_vb.add_child(_region_card_body)

	var rc_actions := HBoxContainer.new()
	rc_actions.add_theme_constant_override("separation", 6)
	rc_vb.add_child(rc_actions)

	var fly_reg_btn := Button.new()
	fly_reg_btn.text = "🧭 Hạ độ cao tới đây"
	fly_reg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(fly_reg_btn, Color(0.35, 0.85, 1.0), Color(0.08, 0.18, 0.28))
	fly_reg_btn.pressed.connect(_fly_to_inspected_region)
	rc_actions.add_child(fly_reg_btn)

	# 5. Floating Tile Action Overlay
	_tile_popover = PanelContainer.new()
	_tile_popover.visible = false
	_tile_popover.mouse_filter = Control.MOUSE_FILTER_STOP
	var overlay_style := StyleBoxFlat.new()
	overlay_style.bg_color = Color(0.03, 0.05, 0.09, 0.68)
	overlay_style.border_color = Color(1.0, 1.0, 1.0, 0.20)
	overlay_style.set_border_width_all(1)
	overlay_style.set_corner_radius_all(12)
	overlay_style.content_margin_left = 14
	overlay_style.content_margin_right = 14
	overlay_style.content_margin_top = 10
	overlay_style.content_margin_bottom = 10
	_tile_popover.add_theme_stylebox_override("panel", overlay_style)
	add_child(_tile_popover)

	_popover_host = VBoxContainer.new()
	_popover_host.alignment = BoxContainer.ALIGNMENT_CENTER
	_popover_host.add_theme_constant_override("separation", 10)
	_tile_popover.add_child(_popover_host)

	# 6. Bottom-Right Dock: 📜 Chiến Báo directly above 🏰 Về Lâu Đài + ⚓ Cảng Tàu Bay
	var br_vb := VBoxContainer.new()
	br_vb.anchor_left = 1.0
	br_vb.anchor_right = 1.0
	br_vb.anchor_top = 1.0
	br_vb.anchor_bottom = 1.0
	br_vb.offset_left = -316.0
	br_vb.offset_right = -12.0
	br_vb.offset_top = -114.0
	br_vb.offset_bottom = -12.0
	br_vb.alignment = BoxContainer.ALIGNMENT_END
	br_vb.add_theme_constant_override("separation", 8)
	add_child(br_vb)

	var report_row := HBoxContainer.new()
	report_row.alignment = BoxContainer.ALIGNMENT_END
	br_vb.add_child(report_row)

	var report_btn := Button.new()
	report_btn.text = "📜 Chiến Báo"
	report_btn.custom_minimum_size = Vector2(146, 42)
	_style_button(report_btn, Color(0.76, 0.62, 1.0), Color(0.14, 0.10, 0.22))
	report_btn.pressed.connect(open_reports_modal)
	report_row.add_child(report_btn)

	var br_dock := HBoxContainer.new()
	br_dock.alignment = BoxContainer.ALIGNMENT_END
	br_dock.add_theme_constant_override("separation", 10)
	br_vb.add_child(br_dock)

	var port_btn := Button.new()
	port_btn.text = "⚓ Cảng Tàu Bay"
	port_btn.custom_minimum_size = Vector2(138, 48)
	_style_button(port_btn, Color(0.35, 0.8, 1.0), Color(0.08, 0.14, 0.22))
	port_btn.pressed.connect(_open_airship_port_overlay)
	br_dock.add_child(port_btn)

	var back_btn := Button.new()
	back_btn.text = "🏰 Về Lâu Đài"
	back_btn.custom_minimum_size = Vector2(146, 48)
	_style_button(back_btn, Color(0.95, 0.76, 0.28), Color(0.20, 0.14, 0.06))
	back_btn.pressed.connect(func():
		if has_node("/root/SceneTransition"):
			SceneTransition.change_scene("res://scenes/base/isometric_base_3d.tscn", "🏰 Đang quay về Căn Cứ 3D...")
	)
	br_dock.add_child(back_btn)

	# 7. Auto-fading Floating Toast
	_toast_panel = PanelContainer.new()
	_toast_panel.anchor_left = 0.5
	_toast_panel.anchor_right = 0.5
	_toast_panel.anchor_top = 0.0
	_toast_panel.anchor_bottom = 0.0
	_toast_panel.offset_left = -250.0
	_toast_panel.offset_right = 250.0
	_toast_panel.offset_top = 14.0
	_toast_panel.offset_bottom = 48.0
	_toast_panel.visible = false
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.08, 0.14, 0.92), Color(0.84, 0.68, 0.32, 0.75)))
	add_child(_toast_panel)

	_toast_lbl = Label.new()
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.add_theme_font_size_override("font_size", 13)
	_toast_lbl.add_theme_color_override("font_color", Color(0.96, 0.94, 0.84))
	_toast_panel.add_child(_toast_lbl)

func toggle_planet_3d_view() -> void:
	if world_map_manager == null:
		return
	world_map_manager.call("toggle_3d_planet_view")
	if _tile_popover != null:
		_tile_popover.visible = false

func open_region_inspector(region: Dictionary, lat_deg: float, lon_deg: float) -> void:
	if _region_card == null:
		return
	var rname := str(region.get("name", "Vùng Chưa Đặt Tên"))
	var cid := str(region.get("continent_id", ""))
	var cont: Dictionary = world_map_manager.call("get_continent_by_id", cid) if world_map_manager != null else {}
	var cname := str(cont.get("name", "Đại Dương Bao La"))
	var biome_key := str(region.get("biome", ""))
	var biome_vn := str(BIOME_NAMES.get(biome_key, biome_key if not biome_key.is_empty() else "Biển Sâu"))
	var elev := int(region.get("elevation", 0))
	var explored := bool(region.get("explored", false))
	var status_txt := "✅ Đã khai phá" if explored else "☁️ Sương mù — Cần Tàu Trinh Sát mở rộng"

	_inspected_region = {
		"name": rname,
		"latitude": lat_deg,
		"longitude": lon_deg,
		"is_expedition_sector": bool(region.get("is_expedition_sector", false)),
	}
	_region_card_title.text = "🗺️ %s" % rname
	_region_card_body.text = "%s • %s\nĐộ cao: %dm | LAT %+.2f°, LON %+.2f°\n%s" % [
		cname, biome_vn, elev, lat_deg, lon_deg, status_txt
	]
	_region_card.visible = true

func _fly_to_inspected_region() -> void:
	if _inspected_region.is_empty() or world_map_manager == null:
		return
	var dest_z := 0.85 if bool(_inspected_region.get("is_expedition_sector", false)) else 0.72
	world_map_manager.call(
		"fly_to_lat_lon",
		float(_inspected_region.get("latitude", 19.0)),
		float(_inspected_region.get("longitude", -11.0)),
		dest_z
	)
	_region_card.visible = false

func _make_coord_line_edit(init_text: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = init_text
	le.max_length = 4
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	le.custom_minimum_size = Vector2(44, 24)
	le.select_all_on_focus = true
	le.add_theme_font_size_override("font_size", 11)
	le.add_theme_color_override("font_color", Color(0.98, 0.92, 0.64))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	st.border_color = Color(0.45, 0.62, 0.84, 0.55)
	st.set_border_width_all(1)
	st.set_corner_radius_all(5)
	st.content_margin_left = 4
	st.content_margin_right = 4
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	var st_focus := st.duplicate() as StyleBoxFlat
	st_focus.border_color = Color(0.95, 0.82, 0.36, 0.95)
	le.add_theme_stylebox_override("normal", st)
	le.add_theme_stylebox_override("focus", st_focus)
	le.text_changed.connect(func(_t: String): _coord_input_dirty = true)
	le.text_submitted.connect(func(_t: String): _navigate_to_input_coords())
	return le

func _is_editing_coords() -> bool:
	return (_coord_x_edit != null and _coord_x_edit.has_focus()) or (_coord_y_edit != null and _coord_y_edit.has_focus())

func _navigate_to_input_coords() -> void:
	if _coord_x_edit == null or _coord_y_edit == null or world_map_manager == null:
		return
	var sx := _coord_x_edit.text.strip_edges()
	var sy := _coord_y_edit.text.strip_edges()
	if not sx.is_valid_int() or not sy.is_valid_int():
		_show_toast("⚠️ Vui lòng nhập số tọa độ X, Y hợp lệ!", 2.5)
		return
	var tx := sx.to_int()
	var ty := sy.to_int()
	if bool(world_map_manager.call("is_full_planet_grid")):
		var wg: Dictionary = _snapshot.get("worldGrid", {})
		var gw := maxi(1, int(wg.get("width", 600)))
		var gh := maxi(1, int(wg.get("height", 300)))
		tx = posmod(tx, gw)
		ty = clampi(ty, 0, gh - 1)
	_coord_input_dirty = false
	_coord_x_edit.text = str(tx)
	_coord_y_edit.text = str(ty)
	_coord_x_edit.release_focus()
	_coord_y_edit.release_focus()
	_center_on_coord(float(tx), float(ty))
	_show_toast("🧭 Đang di chuyển tới (%d, %d)" % [tx, ty], 2.2)

func _get_fleet_live_coord(f: Dictionary) -> Vector2:
	var ratio: float = WorldMapManagerScript.compute_live_fleet_ratio(f, _elapsed_since_sync)
	var fx := lerpf(float(f.get("fromX", 100)), float(f.get("toX", 100)), ratio)
	var fy := lerpf(float(f.get("fromY", 100)), float(f.get("toY", 100)), ratio)
	return Vector2(fx, fy)

func _focus_fleet_live(fleet_id: String) -> void:
	for f in _snapshot.get("activeFleets", []):
		if f is Dictionary and str(f.get("id", "")) == fleet_id:
			var pos := _get_fleet_live_coord(f)
			_center_on_coord(pos.x, pos.y)
			return

func _on_minimap_navigate(lat_deg: float, lon_deg: float) -> void:
	if world_map_manager == null:
		return
	world_map_manager.call("fly_to_lat_lon", lat_deg, lon_deg, -1.0)

func _show_toast(msg: String, duration := 3.0) -> void:
	if _toast_lbl == null or _toast_panel == null:
		return
	_toast_lbl.text = msg
	_toast_panel.visible = true
	_toast_timer = duration

func _set_fleet_expanded(expanded: bool) -> void:
	_fleet_expanded = expanded
	_apply_fleet_panel_state()

func _apply_fleet_panel_state() -> void:
	if _fleet_panel == null:
		return
	_fleet_panel.add_theme_stylebox_override("panel", _make_recessed_style(_fleet_expanded))
	var count := (_snapshot.get("activeFleets", []) as Array).size()
	_fleet_hdr_lbl.text = "🛸 Hạm đội (%d) %s" % [count, "▴" if _fleet_expanded else "▾"]
	_fleet_scroll.visible = _fleet_expanded
	_fleet_compact_row.visible = not _fleet_expanded
	if _fleet_expanded:
		var vp_h := get_viewport_rect().size.y
		var avail_h := maxf(210.0, vp_h - 226.0)
		var target_h := roundf(avail_h * 0.60)
		_fleet_panel.anchor_bottom = 0.0
		_fleet_panel.offset_right = 272.0
		_fleet_panel.offset_bottom = 206.0 + target_h
	else:
		_fleet_panel.anchor_bottom = 0.0
		_fleet_panel.offset_right = 220.0
		var compact_h := 28.0 + minf(3, count) * 20.0
		_fleet_panel.offset_bottom = 206.0 + compact_h

func _on_fleet_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_fleet_expanded(not _fleet_expanded)

func _get_screen_center_coord() -> Vector2i:
	if world_map_manager != null:
		return world_map_manager.call("get_center_grid_coord")
	var base: Dictionary = _snapshot.get("base", {"x": 100, "y": 100})
	return Vector2i(int(base.get("x", 100)), int(base.get("y", 100)))

func _process(delta: float) -> void:
	_pulse_time += delta * 3.2
	var move := Vector2.ZERO
	if not _is_editing_coords():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if move != Vector2.ZERO and world_map_manager != null:
		_coord_input_dirty = false
		world_map_manager.call("apply_directional_move", move.normalized(), delta)

	_elapsed_since_sync += delta
	# Step 3D camera + live 60 FPS fleet beacons BEFORE reading projection for 2D canvas -> 0-frame lag!
	if world_map_manager != null:
		var fleets_now: Array = _snapshot.get("activeFleets", [])
		if fleets_now.size() > 0:
			world_map_manager.call("update_active_fleets", fleets_now, MISSION_COLORS, _elapsed_since_sync)
		world_map_manager.call("step_camera", delta)

	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false

	if world_map_manager != null:
		var lod: Dictionary = world_map_manager.call("get_lod_snapshot")
		var is_3d: bool = bool(world_map_manager.call("is_planet_3d_mode"))
		var zoom_lvl: float = float(world_map_manager.call("get_zoom_level"))
		var morph: float = float(world_map_manager.call("get_morph_factor"))
		if _coord_x_edit != null and _coord_y_edit != null and not _is_editing_coords() and not _coord_input_dirty:
			var c := _get_screen_center_coord()
			var sx := str(c.x)
			var sy := str(c.y)
			if _coord_x_edit.text != sx:
				_coord_x_edit.text = sx
			if _coord_y_edit.text != sy:
				_coord_y_edit.text = sy
		if _lod_badge_lbl != null:
			var near_reg: Dictionary = world_map_manager.call("get_nearest_region_at_focus")
			var cont: Dictionary = world_map_manager.call("get_continent_by_id", str(near_reg.get("continent_id", "")))
			var cname := str(cont.get("name", ""))
			var stage := str(lod.get("label", "Chiến khu"))
			_lod_badge_lbl.text = "%s • %s" % [stage, cname] if not cname.is_empty() else stage
		if _mode_toggle_btn != null:
			_mode_toggle_btn.text = "🗺️" if is_3d else "🌐"
		if _zoom_slider != null:
			_updating_zoom_slider = true
			_zoom_slider.value = zoom_lvl
			_updating_zoom_slider = false
		if _altitude_lbl != null:
			_altitude_lbl.text = str(world_map_manager.call("get_formatted_altitude_km"))
		if _minimap != null:
			_sync_minimap_state(zoom_lvl, morph)

	# Viewport Chunk Streaming (snappy 0.16s debounce when panning >= 5 tiles on full 600x300 planet)
	if has_node("/root/ApiClient") and world_map_manager != null and bool(world_map_manager.call("is_full_planet_grid")):
		var z_now := float(world_map_manager.call("get_zoom_level"))
		if z_now >= 0.45 and _last_chunk_center.x >= 0:
			var cg := _get_screen_center_coord()
			var wg: Dictionary = _snapshot.get("worldGrid", {})
			var gw := maxi(1, int(wg.get("width", 600)))
			var gh := maxi(1, int(wg.get("height", 300)))
			var wx := posmod(cg.x, gw)
			var wy := clampi(cg.y, 0, gh - 1)
			var dx := mini(absi(wx - _last_chunk_center.x), gw - absi(wx - _last_chunk_center.x))
			var dy := absi(wy - _last_chunk_center.y)
			if dx >= 5 or dy >= 5:
				var target_c := Vector2i(wx, wy)
				if target_c != _pending_chunk_center:
					_pending_chunk_center = target_c
					_chunk_debounce_timer = 0.16
				elif _chunk_debounce_timer > 0.0:
					_chunk_debounce_timer -= delta
					if _chunk_debounce_timer <= 0.0 and not _chunk_fetching:
						_poll_accum = 0.0
						_sync_snapshot(target_c.x, target_c.y)

	_poll_accum += delta
	if _poll_accum >= _poll_interval_sec and has_node("/root/ApiClient") and not _chunk_fetching:
		_poll_accum = 0.0
		if _last_chunk_center.x >= 0 and world_map_manager != null and bool(world_map_manager.call("is_full_planet_grid")):
			_sync_snapshot(_last_chunk_center.x, _last_chunk_center.y)
		else:
			_sync_snapshot()

	if _map_canvas != null:
		_map_canvas.queue_redraw()
	if _tile_popover != null and _tile_popover.visible:
		if world_map_manager != null and float(world_map_manager.call("get_zoom_level")) < 0.64:
			_tile_popover.visible = false
		else:
			_position_tile_overlay()

func _sync_minimap_state(zoom_lvl: float, morph: float) -> void:
	var dungeons_ll: Array = []
	for t in _snapshot.get("tiles", []):
		if t is Dictionary and bool(t.get("visible", false)) and t.get("dungeon", null) is Dictionary:
			dungeons_ll.append(world_map_manager.call("grid_to_lat_lon", float(t.get("x", 100)), float(t.get("y", 100))))

	var fleets_ll: Array = []
	for f in _snapshot.get("activeFleets", []):
		if not (f is Dictionary):
			continue
		var ratio: float = WorldMapManagerScript.compute_live_fleet_ratio(f, _elapsed_since_sync)
		var gx := lerpf(float(f.get("fromX", 100)), float(f.get("toX", 100)), ratio)
		var gy := lerpf(float(f.get("fromY", 100)), float(f.get("toY", 100)), ratio)
		var ll: Vector2 = world_map_manager.call("grid_to_lat_lon", gx, gy)
		var st := str(f.get("status", "TRAVELING"))
		var m := str(f.get("mission", "SCOUT"))
		var col: Color = Color(0.98, 0.22, 0.26) if st == "STRANDED" else MISSION_COLORS.get("RETURNING" if st == "RETURNING" else m, Color(1.0, 0.92, 0.35))
		fleets_ll.append({"lat": ll.x, "lon": ll.y, "color": col})

	_minimap.call(
		"sync_state",
		world_map_manager.call("get_player_base_lat_lon"),
		world_map_manager.call("get_focus_lat_lon"),
		zoom_lvl,
		morph,
		dungeons_ll,
		fleets_ll,
		_pulse_time
	)

func apply_snapshot(data: Dictionary, hero_list: Array = []) -> void:
	# Locked worlds return explicit nulls; Dictionary.get defaults only cover missing keys.
	# Normalize our own copy so every renderer and navigation control receives dictionaries.
	_snapshot = data.duplicate()
	if not (_snapshot.get("base") is Dictionary):
		_snapshot["base"] = {"x": 100, "y": 100}
	if not (_snapshot.get("chunkCenter") is Dictionary):
		_snapshot["chunkCenter"] = _snapshot["base"]
	_elapsed_since_sync = 0.0
	if hero_list.size() > 0:
		_heroes = hero_list

	_busy_hero_ids.clear()
	for f in _snapshot.get("activeFleets", []):
		for hm in f.get("heroes", []):
			_busy_hero_ids[str(hm.get("id", ""))] = true

	var base: Dictionary = _snapshot.get("base", {"x": 100, "y": 100})
	var bx := float(base.get("x", 100))
	var by := float(base.get("y", 100))
	var cc: Dictionary = _snapshot.get("chunkCenter", base)
	_last_chunk_center = Vector2i(int(cc.get("x", bx)), int(cc.get("y", by)))

	if world_map_manager != null:
		var wg = _snapshot.get("worldGrid", {})
		world_map_manager.call("apply_world_grid_config", wg if wg is Dictionary else {})
		world_map_manager.call("set_player_base_grid", bx, by)
		world_map_manager.call("update_active_fleets", _snapshot.get("activeFleets", []), MISSION_COLORS)
		world_map_manager.call("rebuild_fog", _snapshot)
		if _minimap != null:
			_minimap.call(
				"configure",
				world_map_manager.call("get_albedo_texture"),
				world_map_manager.call("get_sector_bounds"),
				world_map_manager.call("get_global_fog_texture")
			)
		var tiles: Array = _snapshot.get("tiles", [])
		if not _centered_once and tiles.size() > 0:
			_centered_once = true
			world_map_manager.call("set_focus_grid_immediate", bx, by, 0.85)

	_rebuild_fleet_sidebar()
	_rebuild_tile_popover()

func _sync_all() -> void:
	var h_res: Dictionary = await ApiClient.get_req("/api/heroes?aliveOnly=true")
	if bool(h_res.get("ok", false)) and h_res.get("data", null) is Array:
		var raw: Array = h_res.get("data", [])
		_heroes = raw.filter(func(h): return h is Dictionary and GameState.is_hero_alive(h))
	await _sync_snapshot()

func _sync_snapshot(cx: int = -1, cy: int = -1) -> void:
	if _chunk_fetching:
		return
	_chunk_fetching = true
	var url := "/api/world/rts/snapshot"
	if cx >= 0 and cy >= 0:
		url = "/api/world/rts/snapshot?cx=%d&cy=%d&radius=%d" % [cx, cy, _chunk_radius]
	var res: Dictionary = await ApiClient.get_req(url)
	_chunk_fetching = false
	if not bool(res.get("ok", false)):
		_show_toast("⚠️ Không thể tải bản đồ: %s" % str(res.get("error", "")))
		return
	var data = res.get("data", {})
	if data is Dictionary:
		if not bool(data.get("unlocked", false)) and int(data.get("clearedFloor", 1)) >= int(data.get("requiredFloor", 25)):
			var unlock_res: Dictionary = await ApiClient.post_req("/api/world/global/unlock", {})
			if bool(unlock_res.get("ok", false)):
				var retry: Dictionary = await ApiClient.get_req("/api/world/rts/snapshot")
				if bool(retry.get("ok", false)) and retry.get("data", null) is Dictionary:
					apply_snapshot(retry.get("data", {}))
					return
		apply_snapshot(data)

func _tile_to_screen(tx: float, ty: float) -> Vector2:
	if world_map_manager != null:
		var proj: Dictionary = world_map_manager.call("project_grid_to_screen", tx, ty)
		return proj.get("pos", Vector2(-9999.0, -9999.0))
	return Vector2.ZERO

func _estimate_tile_px() -> float:
	if world_map_manager == null:
		return 56.0
	var c := _get_screen_center_coord()
	var p0: Vector2 = _tile_to_screen(float(c.x), float(c.y))
	var p1: Vector2 = _tile_to_screen(float(c.x + 1), float(c.y))
	return clampf(p0.distance_to(p1), 6.0, 160.0)

func _center_on_coord(tx: float, ty: float) -> void:
	_coord_input_dirty = false
	if world_map_manager != null:
		world_map_manager.call("fly_to_grid", tx, ty, 0.85)
		if _region_card != null:
			_region_card.visible = false
		if has_node("/root/ApiClient") and bool(world_map_manager.call("is_full_planet_grid")):
			var target_c := Vector2i(int(round(tx)), int(round(ty)))
			if absi(target_c.x - _last_chunk_center.x) >= 5 or absi(target_c.y - _last_chunk_center.y) >= 5:
				_poll_accum = 0.0
				_sync_snapshot(target_c.x, target_c.y)

func _center_on_base() -> void:
	var base: Dictionary = _snapshot.get("base", {"x": 100, "y": 100})
	_center_on_coord(float(base.get("x", 100)), float(base.get("y", 100)))

func _on_map_gui_input(event: InputEvent) -> void:
	if world_map_manager == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			world_map_manager.call("zoom_by_step", 0.065)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			world_map_manager.call("zoom_by_step", -0.065)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
					_handle_double_click(mb.position)
					return
				_pan_pressing = true
				_pan_dragged = false
				_pan_start_pos = mb.position
				_last_mouse = mb.position
				if _fleet_expanded:
					_set_fleet_expanded(false)
			else:
				var was_left_tap := (mb.button_index == MOUSE_BUTTON_LEFT and not _pan_dragged)
				_pan_pressing = false
				_pan_dragged = false
				if was_left_tap:
					_pick_tile_at(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pan_pressing:
			if not _pan_dragged and mm.position.distance_to(_pan_start_pos) >= DRAG_CLICK_THRESHOLD_PX:
				_pan_dragged = true
			if _pan_dragged:
				_coord_input_dirty = false
				world_map_manager.call("apply_screen_drag", mm.position - _last_mouse, get_viewport_rect().size)
			_last_mouse = mm.position
		else:
			_update_hovered_tile(mm.position)

func _update_hovered_tile(screen_pos: Vector2) -> void:
	if world_map_manager == null or float(world_map_manager.call("get_zoom_level")) < 0.66:
		_hovered_tile_id = ""
		return
	var pick: Dictionary = world_map_manager.call("pick_at_screen", screen_pos)
	if not bool(pick.get("hit", false)):
		_hovered_tile_id = ""
		return
	var g: Vector2 = pick.get("grid", Vector2(-999.0, -999.0))
	var gx := int(round(g.x))
	var gy := int(round(g.y))
	for t in _snapshot.get("tiles", []):
		if int(t.get("x", -1)) == gx and int(t.get("y", -1)) == gy:
			_hovered_tile_id = str(t.get("id", ""))
			return
	_hovered_tile_id = ""

func _handle_double_click(screen_pos: Vector2) -> void:
	var pick: Dictionary = world_map_manager.call("pick_at_screen", screen_pos)
	if not bool(pick.get("hit", false)):
		return
	var lat := float(pick.get("lat", 19.0))
	var lon := float(pick.get("lon", -11.0))
	var reg: Dictionary = pick.get("nearest_region", {})
	var dest_z := 0.85 if bool(reg.get("is_expedition_sector", false)) else 0.72
	world_map_manager.call("fly_to_lat_lon", lat, lon, dest_z)
	if _region_card != null:
		_region_card.visible = false
	if not reg.is_empty():
		_show_toast("🧭 Đang hạ độ cao tới %s (LAT %+.1f°, LON %+.1f°)" % [str(reg.get("name", "")), lat, lon], 2.5)

func _pick_tile_at(screen_pos: Vector2) -> void:
	var lod: Dictionary = world_map_manager.call("get_lod_snapshot")
	var tac_alpha := float(lod.get("tactical_overlay_alpha", 1.0))
	var morph := float(world_map_manager.call("get_morph_factor"))
	var pick: Dictionary = world_map_manager.call("pick_at_screen", screen_pos)

	if tac_alpha > 0.25 and morph < 0.20 and bool(pick.get("hit", false)):
		var g: Vector2 = pick.get("grid", Vector2(-999.0, -999.0))
		var gx := int(round(g.x))
		var gy := int(round(g.y))
		for t in _snapshot.get("tiles", []):
			if int(t.get("x", -1)) == gx and int(t.get("y", -1)) == gy:
				var tid := str(t.get("id", ""))
				if not _redirecting_expedition_id.is_empty():
					_execute_redirect(_redirecting_expedition_id, tid)
					return
				_selected_tile_id = tid
				if _region_card != null:
					_region_card.visible = false
				_rebuild_tile_popover()
				return

	# Clicking outside tactical tiles or on continents / 3D globe opens Region Inspector Card
	_selected_tile_id = ""
	_tile_popover.visible = false
	if bool(pick.get("hit", false)):
		var reg: Dictionary = pick.get("nearest_region", {})
		open_region_inspector(reg, float(pick["lat"]), float(pick["lon"]))

func _draw_airship_icon(pos: Vector2, angle: float, bp_code: String, col: Color, alpha: float, icon_scale := 1.0) -> void:
	if not pos.is_finite() or is_nan(angle) or is_inf(angle) or icon_scale < 0.05 or alpha <= 0.005:
		return
	if absf(pos.x) > 50000.0 or absf(pos.y) > 50000.0:
		return
	var fwd := Vector2(cos(angle), sin(angle)) * icon_scale
	var side := Vector2(-sin(angle), cos(angle)) * icon_scale
	var pts: PackedVector2Array
	if bp_code == "TRANSPORT_CARRIER":
		pts = PackedVector2Array([
			pos + fwd * 14.0,
			pos + fwd * 6.0 + side * 9.0,
			pos - fwd * 12.0 + side * 8.0,
			pos - fwd * 12.0 - side * 8.0,
			pos + fwd * 6.0 - side * 9.0,
		])
	elif bp_code == "WAR_DREADNOUGHT":
		pts = PackedVector2Array([
			pos + fwd * 15.0,
			pos - fwd * 4.0 + side * 10.0,
			pos - fwd * 11.0 + side * 5.0,
			pos - fwd * 11.0 - side * 5.0,
			pos - fwd * 4.0 - side * 10.0,
		])
	else:
		pts = PackedVector2Array([
			pos + fwd * 14.0,
			pos - fwd * 9.0 + side * 8.0,
			pos - fwd * 5.0,
			pos - fwd * 9.0 - side * 8.0,
		])
	var c := Color(col.r, col.g, col.b, alpha)
	_map_canvas.draw_colored_polygon(pts, c)
	_map_canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 1.0, 1.0, 0.85 * alpha), 1.5)

func _draw_shadow_text(font: Font, pos: Vector2, text: String, font_size: int, col: Color) -> void:
	var shadow_col := Color(0.02, 0.03, 0.07, col.a * 0.88)
	_map_canvas.draw_string(font, pos + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, shadow_col)
	_map_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, col)

func _tile_quad_pts(tx: float, ty: float, inset := 0.02) -> PackedVector2Array:
	var h := 0.5 - inset
	var p0 := _tile_to_screen(tx - h, ty - h)
	var p1 := _tile_to_screen(tx + h, ty - h)
	var p2 := _tile_to_screen(tx + h, ty + h)
	var p3 := _tile_to_screen(tx - h, ty + h)
	return PackedVector2Array([p0, p1, p2, p3, p0])

func _draw_dashed_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color, width: float, dash: float) -> void:
	_map_canvas.draw_dashed_line(p0, p1, col, width, dash)
	_map_canvas.draw_dashed_line(p1, p2, col, width, dash)
	_map_canvas.draw_dashed_line(p2, p3, col, width, dash)
	_map_canvas.draw_dashed_line(p3, p0, col, width, dash)

func _draw_rts_map() -> void:
	if world_map_manager == null:
		return
	var font := ThemeDB.fallback_font
	var pulse := 0.5 + 0.5 * sin(_pulse_time)
	var lod: Dictionary = world_map_manager.call("get_lod_snapshot")
	var tac_alpha := float(lod.get("tactical_overlay_alpha", 1.0))
	var fleet_alpha := float(lod.get("fleet_overlay_alpha", 1.0))
	var reg_alpha := float(lod.get("region_label_alpha", 0.0))
	var border_alpha := float(lod.get("region_border_alpha", 0.0))
	var cont_alpha := float(lod.get("continent_label_alpha", 0.0))
	var vp_rect := get_viewport_rect().grow(96.0)
	var placed_label_rects: Array[Rect2] = []

	# 1. Perspective-Accurate Tactical Overlay (real 3D Castle/Forest/Mountains/Dungeons sit on crisp ground below!)
	if tac_alpha > 0.02:
		var tiles: Array = _snapshot.get("tiles", [])
		var size_px := _estimate_tile_px()

		# Legacy dashed golden frontier border ONLY in non-planet 12x12 sector mode
		if not bool(world_map_manager.call("is_full_planet_grid")):
			var f0 := _tile_to_screen(99.5, 99.5)
			var f1 := _tile_to_screen(111.5, 99.5)
			var f2 := _tile_to_screen(111.5, 111.5)
			var f3 := _tile_to_screen(99.5, 111.5)
			if f0.distance_to(f1) > 16.0:
				_draw_dashed_quad(f0, f1, f2, f3, Color(0.95, 0.82, 0.42, 0.38 * tac_alpha), 1.4, 8.0)

		for t in tiles:
			var tx := float(t.get("x", 0))
			var ty := float(t.get("y", 0))
			var proj: Dictionary = world_map_manager.call("project_grid_to_screen", tx, ty)
			if not bool(proj.get("visible", false)):
				continue
			var center: Vector2 = proj["pos"]
			if not vp_rect.has_point(center):
				continue
			var tid := str(t.get("id", ""))
			var visible_flag := bool(t.get("visible", false))
			var is_base := bool(t.get("isBase", false))
			var dungeon = t.get("dungeon", null)

			if visible_flag:
				var quad := _tile_quad_pts(tx, ty)
				# Ultra-thin subtle tactical grid lines (alpha 0.10) letting crisp ground & 3D landscape shine!
				_map_canvas.draw_polyline(quad, Color(0.92, 0.98, 0.94, 0.10 * tac_alpha), 1.0)
				var rem := int(t.get("visionSecondsRemaining", 0))
				if rem > 0:
					var va := clampf(float(rem) / 3600.0, 0.25, 0.75) * tac_alpha
					_map_canvas.draw_polyline(quad, Color(0.32, 0.90, 1.0, va * 0.36), 1.5)

			if tid == _hovered_tile_id and tid != _selected_tile_id:
				var hq := _tile_quad_pts(tx, ty)
				_map_canvas.draw_polyline(hq, Color(0.88, 0.96, 1.0, 0.65 * tac_alpha), 1.8)
			if tid == _selected_tile_id:
				var sq := _tile_quad_pts(tx, ty)
				_map_canvas.draw_polyline(sq, Color(1.0, 0.90, 0.30, tac_alpha), 2.8)

			# Crisp compact labels floating cleanly with the 3D Castle Citadel & 3D Dungeon Portals
			if is_base and size_px >= 24.0:
				_draw_shadow_text(font, center + Vector2(-24.0, size_px * 0.42), "🏰 Căn Cứ", 11, Color(0.76, 0.96, 1.0, tac_alpha))

			if visible_flag and dungeon is Dictionary and size_px >= 20.0:
				var rank := str(dungeon.get("rank", "D"))
				var d_col: Color = DUNGEON_RANK_COLORS.get(rank, Color(1.0, 0.6, 0.2))
				var pill_w := 34.0
				var pill_h := 15.0
				var pill_rect := Rect2(center + Vector2(-pill_w * 0.5, size_px * 0.22), Vector2(pill_w, pill_h))
				_map_canvas.draw_rect(pill_rect, Color(0.04, 0.05, 0.10, 0.86 * tac_alpha), true)
				_map_canvas.draw_rect(pill_rect, Color(d_col.r, d_col.g, d_col.b, 0.92 * tac_alpha), false, 1.3)
				_map_canvas.draw_string(font, pill_rect.position + Vector2(6.0, 11.5), "D-%s" % rank, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(1.0, 0.98, 0.94, tac_alpha))

		# Nearby Rival Player Citadels (floating nameplate + novice shield badge on visible tiles)
		for np in _snapshot.get("nearbyPlayers", []):
			if not (np is Dictionary) or not bool(np.get("visible", false)):
				continue
			var nproj: Dictionary = world_map_manager.call("project_grid_to_screen", float(np.get("x", 0)), float(np.get("y", 0)))
			if not bool(nproj.get("visible", false)):
				continue
			var npos: Vector2 = nproj["pos"]
			if not vp_rect.has_point(npos):
				continue
			var shield_tag := " 🛡️" if bool(np.get("shieldActive", false)) else ""
			var pname := "👑 %s%s" % [str(np.get("masterName", "Lãnh chúa")), shield_tag]
			_draw_shadow_text(font, npos + Vector2(-38.0, size_px * 0.42), pname, 11, Color(1.0, 0.72, 0.66, tac_alpha))

	# 1B. Continuous Active Fleets & Dashed Flight Vectors (visible from Tactical through Continent view -> ZERO dead-zone!)
	if fleet_alpha > 0.02:
		var ship_scale := lerpf(0.76, 1.0, tac_alpha)
		for f in _snapshot.get("activeFleets", []):
			var from_gx := float(f.get("fromX", 0))
			var from_gy := float(f.get("fromY", 0))
			var to_gx := float(f.get("toX", 0))
			var to_gy := float(f.get("toY", 0))
			var live_ratio: float = WorldMapManagerScript.compute_live_fleet_ratio(f, _elapsed_since_sync)
			var cur_gx := lerpf(from_gx, to_gx, live_ratio)
			var cur_gy := lerpf(from_gy, to_gy, live_ratio)

			var from_proj: Dictionary = world_map_manager.call("project_grid_to_screen", from_gx, from_gy)
			var to_proj: Dictionary = world_map_manager.call("project_grid_to_screen", to_gx, to_gy)
			var cur_proj: Dictionary = world_map_manager.call("project_grid_to_screen", cur_gx, cur_gy)
			var from_vis := bool(from_proj.get("visible", false))
			var to_vis := bool(to_proj.get("visible", false))
			var cur_vis := bool(cur_proj.get("visible", false))
			if not from_vis and not to_vis and not cur_vis:
				continue

			var from_pt: Vector2 = from_proj["pos"]
			var to_pt: Vector2 = to_proj["pos"]
			var cur_pos: Vector2 = cur_proj["pos"]
			var status_str := str(f.get("status", "TRAVELING"))
			var mission_str := str(f.get("mission", "SCOUT"))
			var col: Color = MISSION_COLORS.get("RETURNING" if status_str == "RETURNING" else mission_str, Color(0.9, 0.9, 0.9))

			if from_vis and to_vis and from_pt.is_finite() and to_pt.is_finite():
				_map_canvas.draw_dashed_line(from_pt, to_pt, Color(col.r, col.g, col.b, 0.80 * fleet_alpha), lerpf(1.8, 2.5, tac_alpha), 8.0)

			if status_str == "STRANDED":
				if to_vis and to_pt.is_finite() and vp_rect.has_point(to_pt):
					_map_canvas.draw_circle(to_pt, (16.0 + pulse * 6.0) * ship_scale, Color(0.98, 0.18, 0.22, 0.35 * fleet_alpha))
					_map_canvas.draw_circle(to_pt, 13.0 * ship_scale, Color(0.98, 0.18, 0.22, 0.96 * fleet_alpha))
					_draw_shadow_text(font, to_pt + Vector2(-14.0, 4.0), "SOS!", 11, Color(1.0, 1.0, 1.0, fleet_alpha))
			elif status_str == "GARRISONED":
				if to_vis and to_pt.is_finite() and vp_rect.has_point(to_pt):
					_map_canvas.draw_circle(to_pt, 15.0 * ship_scale, Color(0.95, 0.78, 0.28, 0.30 * fleet_alpha))
					_map_canvas.draw_circle(to_pt, 11.0 * ship_scale, Color(0.95, 0.78, 0.28, 0.96 * fleet_alpha))
					_map_canvas.draw_arc(to_pt, 13.0 * ship_scale, 0.0, TAU, 20, Color(1.0, 1.0, 1.0, 0.9 * fleet_alpha), 1.5)
					_map_canvas.draw_string(font, to_pt + Vector2(-14.0, 4.0), "CAMP", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.08, 0.08, 0.1, fleet_alpha))
			elif cur_vis and cur_pos.is_finite() and vp_rect.has_point(cur_pos):
				var ship = f.get("airship", null)
				var bp := str(ship.get("blueprintCode", "SCOUT_SKIFF")) if ship is Dictionary else "SCOUT_SKIFF"
				var dir_vec := (to_pt - cur_pos) if (to_vis and to_pt.is_finite() and to_pt.distance_squared_to(cur_pos) > 1.0) else ((cur_pos - from_pt) if (from_vis and from_pt.is_finite() and from_pt.distance_squared_to(cur_pos) > 1.0) else Vector2(to_gx - from_gx, to_gy - from_gy))
				var angle := dir_vec.angle() if dir_vec.length_squared() > 1e-6 else 0.0
				_draw_airship_icon(cur_pos, angle, bp, col, fleet_alpha, ship_scale)
				var eta := maxi(0, int(f.get("secondsRemaining", 0)) - int(_elapsed_since_sync))
				_draw_shadow_text(font, cur_pos + Vector2(-20.0, -16.0), "%s %ds" % [mission_str.substr(0, 3), eta], 11, Color(1.0, 1.0, 1.0, fleet_alpha))

	# 2. Imperial Wonder Golden Citadel Icon (visible across Province / Continental / Planetary zooms)
	var sb: Dictionary = world_map_manager.call("get_sector_bounds")
	var w_proj: Dictionary = world_map_manager.call("project_lat_lon_to_screen", float(sb.get("wonder_lat", 6.0)), float(sb.get("wonder_lon", 32.0)))
	if bool(w_proj.get("visible", false)) and vp_rect.has_point(w_proj["pos"]):
		var w_alpha := maxf(reg_alpha, cont_alpha)
		if w_alpha > 0.08:
			MapIconDrawerScript.draw_wonder_citadel(_map_canvas, w_proj["pos"], lerpf(11.0, 18.0, reg_alpha), pulse, w_alpha)

	# 3. Spatial-Culled Regional Borders & Anti-Overlapping Labels (STRICTLY hidden at Tactical LOD 0!)
	if reg_alpha > 0.06:
		var focus_ll: Vector2 = world_map_manager.call("get_focus_lat_lon")
		var half_span: Vector2 = world_map_manager.call("get_visible_lat_lon_half_span")
		var drawn_regions := 0

		for reg in world_map_manager.call("get_regions"):
			if drawn_regions >= 28:
				break
			if not (reg is Dictionary):
				continue
			if not bool(reg.get("explored", false)) and not bool(reg.get("is_wonder", false)) and int(reg.get("tier", 1)) < 4:
				continue
			var rlat := float(reg.get("latitude", 0.0))
			var rlon := float(reg.get("longitude", 0.0))
			# Spatial Window Culling on CPU (skips off-screen regions before projection!)
			if absf(rlat - focus_ll.x) > half_span.x * 1.35:
				continue
			var dlon := absf(fmod(rlon - focus_ll.y + 540.0, 360.0) - 180.0)
			if dlon > half_span.y * 1.35:
				continue

			var rproj: Dictionary = world_map_manager.call("project_lat_lon_to_screen", rlat, rlon)
			if not bool(rproj.get("visible", false)):
				continue
			var rpos: Vector2 = rproj["pos"]
			if not vp_rect.has_point(rpos):
				continue

			# Subtle cartographic region boundary circle
			if border_alpha > 0.08:
				var ring_r := 34.0 if bool(reg.get("is_expedition_sector", false)) else 24.0
				var ring_col := Color(0.95, 0.85, 0.42, 0.36 * border_alpha) if bool(reg.get("is_expedition_sector", false)) else Color(0.76, 0.88, 1.0, 0.20 * border_alpha)
				_map_canvas.draw_arc(rpos, ring_r, 0.0, TAU, 24, ring_col, 1.1)

			var rname := str(reg.get("name", ""))
			var lbl_rect := Rect2(rpos + Vector2(-58.0, -10.0), Vector2(116.0, 20.0))
			if _rect_overlaps_any(lbl_rect, placed_label_rects):
				continue
			placed_label_rects.append(lbl_rect)

			var rcol := Color(1.0, 0.90, 0.48, reg_alpha * 0.94) if bool(reg.get("is_wonder", false)) else Color(0.92, 0.96, 1.0, reg_alpha * 0.82)
			_draw_shadow_text(font, rpos + Vector2(-46.0, 4.0), rname, 11, rcol)
			drawn_regions += 1

	# 4. Continental Banners & 3D Planet Player Position Callout (LOD 2-3)
	if cont_alpha > 0.06:
		# Reserve Player Callout rect first so continent titles never overlap player dot!
		var base_ll: Vector2 = world_map_manager.call("get_player_base_lat_lon")
		var pproj: Dictionary = world_map_manager.call("project_lat_lon_to_screen", base_ll.x, base_ll.y)
		if bool(pproj.get("visible", false)):
			var ppos: Vector2 = pproj["pos"]
			_map_canvas.draw_arc(ppos, 9.0 + pulse * 4.5, 0.0, TAU, 24, Color(0.32, 0.94, 1.0, 0.78 * cont_alpha), 1.6)
			_draw_shadow_text(font, ppos + Vector2(14.0, 4.0), "📍 Vị trí của bạn", 12, Color(0.78, 0.98, 1.0, cont_alpha))
			placed_label_rects.append(Rect2(ppos + Vector2(8.0, -10.0), Vector2(126.0, 22.0)))

		for cont in world_map_manager.call("get_continents"):
			if not (cont is Dictionary):
				continue
			var cproj: Dictionary = world_map_manager.call("project_lat_lon_to_screen", float(cont.get("latitude", 0.0)), float(cont.get("longitude", 0.0)))
			if not bool(cproj.get("visible", false)):
				continue
			var cpos: Vector2 = cproj["pos"]
			if not vp_rect.has_point(cpos):
				continue
			var crect := Rect2(cpos + Vector2(-72.0, -24.0), Vector2(144.0, 22.0))
			if _rect_overlaps_any(crect, placed_label_rects):
				cpos.y -= 22.0
			placed_label_rects.append(Rect2(cpos + Vector2(-72.0, -24.0), Vector2(144.0, 22.0)))
			var accent := Color.html(str(cont.get("accent_hex", "#ffffff")))
			accent.a = cont_alpha * 0.95
			_draw_shadow_text(font, cpos + Vector2(-58.0, -10.0), str(cont.get("name", "")).to_upper(), 13, accent)

static func _rect_overlaps_any(candidate: Rect2, placed: Array[Rect2]) -> bool:
	for r in placed:
		if r.intersects(candidate):
			return true
	return false

func _rebuild_fleet_sidebar() -> void:
	for c in _fleet_list.get_children(): c.queue_free()
	for c in _fleet_compact_row.get_children(): c.queue_free()

	var fleets: Array = _snapshot.get("activeFleets", [])
	_apply_fleet_panel_state()

	for i in range(mini(3, fleets.size())):
		var f: Dictionary = fleets[i]
		var fid_c := str(f.get("id", ""))
		var st := str(f.get("status", ""))
		var m := str(f.get("mission", ""))
		var chip := Label.new()
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.tooltip_text = "Nhấn để nhảy tới vị trí hiện tại của tàu"
		chip.add_theme_font_size_override("font_size", 11)
		chip.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42) if st == "STRANDED" else Color(0.76, 0.9, 1.0))
		chip.text = "• %s (%s)" % [m, "SOS!" if st == "STRANDED" else ("CAMP" if st == "GARRISONED" else "%ds" % int(f.get("secondsRemaining", 0)))]
		chip.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_focus_fleet_live(fid_c)
				get_viewport().set_input_as_handled()
		)
		_fleet_compact_row.add_child(chip)

	for f in fleets:
		var fid := str(f.get("id", ""))
		var target_tid := str(f.get("tileId", ""))
		var status_str := str(f.get("status", ""))
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.tooltip_text = "Nhấn vào hộp để nhảy đến vị trí hiện tại của tàu"
		card.add_theme_stylebox_override("panel", _make_panel_style(
			Color(0.16, 0.07, 0.08, 0.92) if status_str == "STRANDED" else Color(0.09, 0.12, 0.2, 0.92),
			Color(0.95, 0.28, 0.32) if status_str == "STRANDED" else Color(0.28, 0.48, 0.72)
		))
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_focus_fleet_live(fid)
				get_viewport().set_input_as_handled()
		)
		var vb := VBoxContainer.new()
		vb.mouse_filter = Control.MOUSE_FILTER_PASS
		vb.add_theme_constant_override("separation", 5)
		card.add_child(vb)

		var ship = f.get("airship", null)
		var ship_name := str(ship.get("name", "Đội bộ")) if ship is Dictionary else "Đội bộ"
		var h_count := (f.get("heroes", []) as Array).size()
		var title := Label.new()
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.text = "🛸 %s (%d Hero)\n%s • %s" % [ship_name, h_count, str(f.get("mission", "")), status_str]
		title.add_theme_font_size_override("font_size", 12)
		title.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42) if status_str == "STRANDED" else Color(0.92, 0.96, 1.0))
		vb.add_child(title)

		var prog := ProgressBar.new()
		prog.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prog.min_value = 0.0
		prog.max_value = 1.0
		prog.value = clampf(float(f.get("progressRatio", 0.0)), 0.0, 1.0)
		prog.show_percentage = false
		prog.custom_minimum_size.y = 6
		vb.add_child(prog)

		var btn_row := HBoxContainer.new()
		btn_row.mouse_filter = Control.MOUSE_FILTER_PASS
		btn_row.add_theme_constant_override("separation", 4)
		vb.add_child(btn_row)

		var fx := float(f.get("toX", 100))
		var fy := float(f.get("toY", 100))

		var focus_btn := Button.new()
		focus_btn.text = "🎯"
		focus_btn.tooltip_text = "Nhảy tới vị trí hiện tại của tàu"
		_style_button(focus_btn, Color(0.45, 0.75, 1.0))
		focus_btn.pressed.connect(func(): _focus_fleet_live(fid))
		btn_row.add_child(focus_btn)

		if status_str == "TRAVELING" or status_str == "GARRISONED":
			var redir_btn := Button.new()
			redir_btn.text = "↪ Đi tiếp" if status_str == "GARRISONED" else "↪ Đổi"
			_style_button(redir_btn, Color(0.35, 0.78, 1.0))
			redir_btn.pressed.connect(func():
				_redirecting_expedition_id = fid
				_set_fleet_expanded(false)
				_show_toast("🎯 Click bất kỳ ô nào trên bản đồ để đổi hướng hạm đội!", 5.0)
			)
			btn_row.add_child(redir_btn)
		if status_str == "TRAVELING" or status_str == "RETURNING" or status_str == "GARRISONED":
			var rec_btn := Button.new()
			rec_btn.text = "↩ Rút về"
			_style_button(rec_btn, Color(0.92, 0.65, 0.28))
			rec_btn.pressed.connect(func(): _recall_fleet(fid))
			btn_row.add_child(rec_btn)
		if status_str == "STRANDED":
			var sos_btn := Button.new()
			sos_btn.text = "🚑 Cứu Hộ"
			_style_button(sos_btn, Color(0.28, 0.92, 0.56), Color(0.08, 0.18, 0.12))
			sos_btn.pressed.connect(func():
				_selected_tile_id = target_tid
				_center_on_coord(fx, fy)
				_set_fleet_expanded(false)
				_rebuild_tile_popover()
			)
			btn_row.add_child(sos_btn)

		_fleet_list.add_child(card)

func _find_tile(tile_id: String) -> Dictionary:
	for t in _snapshot.get("tiles", []):
		if str(t.get("id", "")) == tile_id:
			return t
	return {}

func _position_tile_overlay() -> void:
	var tile := _find_tile(_selected_tile_id)
	if tile.is_empty():
		_tile_popover.visible = false
		return
	var center := _tile_to_screen(float(tile.get("x", 0)), float(tile.get("y", 0)))
	var vp := get_viewport_rect().size
	var sz := _tile_popover.get_combined_minimum_size()
	var tile_px := _estimate_tile_px()
	var pos := Vector2(center.x - sz.x * 0.5, center.y - sz.y - (tile_px * 0.55))
	if pos.y < 14.0:
		pos.y = center.y + (tile_px * 0.55)
	pos.x = clampf(pos.x, 12.0, maxf(12.0, vp.x - sz.x - 12.0))
	pos.y = clampf(pos.y, 12.0, maxf(12.0, vp.y - sz.y - 124.0))
	_tile_popover.position = pos
	_tile_popover.size = sz

func _rebuild_tile_popover() -> void:
	for c in _popover_host.get_children():
		c.queue_free()

	var tile := _find_tile(_selected_tile_id)
	if tile.is_empty():
		_tile_popover.visible = false
		return
	_tile_popover.visible = true

	var vis := bool(tile.get("visible", false))
	var dungeon = tile.get("dungeon", null)
	var t_name := str(TERRAIN_NAMES.get(str(tile.get("terrain", "")), str(tile.get("terrain", ""))))
	var title_text := t_name
	if vis and dungeon is Dictionary:
		title_text = "⚔️ %s [%s]" % [str(dungeon.get("name", t_name)), str(dungeon.get("rank", "D"))]

	var info_lbl := Label.new()
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var terrain_code := str(tile.get("terrain", ""))
	if terrain_code == "OCEAN":
		info_lbl.text = "🌊 %s\n(%d, %d)" % [title_text, int(tile.get("x", 0)), int(tile.get("y", 0))]
	else:
		info_lbl.text = "%s\n(%d, %d)" % [title_text, int(tile.get("x", 0)), int(tile.get("y", 0))]
	info_lbl.add_theme_font_size_override("font_size", 14)
	info_lbl.add_theme_color_override("font_color", Color(0.76, 0.92, 1.0) if terrain_code == "OCEAN" else Color(0.98, 0.96, 0.88))
	_popover_host.add_child(info_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 10)
	_popover_host.add_child(btn_row)

	if not vis:
		var scout_btn := Button.new()
		scout_btn.text = "🔭 Scout"
		scout_btn.custom_minimum_size = Vector2(96, 36)
		_style_button(scout_btn, Color(0.30, 0.88, 1.0), Color(0.08, 0.22, 0.34))
		scout_btn.pressed.connect(func(): open_dispatch_modal(tile, "SCOUT", ""))
		btn_row.add_child(scout_btn)

	if not bool(tile.get("isBase", false)):
		var gar_btn := Button.new()
		gar_btn.text = "⛺ Tập kết"
		gar_btn.custom_minimum_size = Vector2(104, 36)
		_style_button(gar_btn, Color(0.98, 0.80, 0.28), Color(0.24, 0.17, 0.06))
		gar_btn.pressed.connect(func(): open_dispatch_modal(tile, "GARRISON", ""))
		btn_row.add_child(gar_btn)

	if vis and dungeon is Dictionary:
		var raid_btn := Button.new()
		raid_btn.text = "⚔️ Thám hiểm"
		raid_btn.custom_minimum_size = Vector2(114, 36)
		_style_button(raid_btn, Color(1.0, 0.50, 0.22), Color(0.28, 0.12, 0.07))
		raid_btn.pressed.connect(func(): open_dispatch_modal(tile, "DUNGEON", ""))
		btn_row.add_child(raid_btn)

	var tid := str(tile.get("id", ""))
	for f in _snapshot.get("activeFleets", []):
		if str(f.get("status", "")) == "STRANDED" and str(f.get("tileId", "")) == tid:
			var stranded_id := str(f.get("id", ""))
			var rescue_btn := Button.new()
			rescue_btn.text = "🚑 Cứu hộ"
			rescue_btn.custom_minimum_size = Vector2(100, 36)
			_style_button(rescue_btn, Color(0.28, 0.96, 0.56), Color(0.08, 0.24, 0.14))
			rescue_btn.pressed.connect(func(): open_dispatch_modal(tile, "RESCUE", stranded_id))
			btn_row.add_child(rescue_btn)

	_position_tile_overlay()

func open_dispatch_modal(tile: Dictionary, mission: String, rescue_target_id: String) -> Control:
	var existing := get_node_or_null("WorldDispatchModal")
	if existing != null:
		existing.queue_free()
	var script = load("res://scripts/ui/world_dispatch_modal.gd")
	if script == null:
		return null
	var port: Dictionary = _snapshot.get("portState", {})
	var docked: Array = []
	for s in port.get("airships", []):
		if str(s.get("status", "")) == "DOCKED":
			docked.append(s)
	var base: Dictionary = _snapshot.get("base", {"x": 100, "y": 100})
	var modal = script.new()
	modal.name = "WorldDispatchModal"
	modal.configure({
		"tile": tile,
		"mission": mission,
		"baseCoord": Vector2i(int(base.get("x", 100)), int(base.get("y", 100))),
		"dockedShips": docked,
		"heroes": _heroes,
		"busyHeroIds": _busy_hero_ids,
		"rescueTargetId": rescue_target_id,
	})
	modal.dispatch_confirmed.connect(_submit_dispatch_payload)
	add_child(modal)
	return modal

func open_reports_modal() -> Control:
	var existing := get_node_or_null("WorldReportsModal")
	if existing != null:
		existing.queue_free()
	var script = load("res://scripts/ui/world_reports_modal.gd")
	if script == null:
		return null
	var modal = script.new()
	modal.name = "WorldReportsModal"
	modal.focus_tile_requested.connect(func(x: float, y: float): _center_on_coord(x, y))
	add_child(modal)
	return modal

func _submit_dispatch_payload(payload: Dictionary) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/world/expeditions", payload)
	if bool(res.get("ok", false)):
		_show_toast("🚀 Đã xuất kích hạm đội [%s] (%d Hero)!" % [str(payload.get("mission", "")), (payload.get("heroIds", []) as Array).size()])
		await _sync_snapshot()
	else:
		_show_toast("⚠️ %s" % str(res.get("error", "Không thể xuất kích")))

func _execute_redirect(exp_id: String, new_tile_id: String) -> void:
	_redirecting_expedition_id = ""
	var res: Dictionary = await ApiClient.post_req("/api/world/expeditions/%s/redirect" % exp_id, {"tileId": new_tile_id})
	if bool(res.get("ok", false)):
		_show_toast("↪ Đã đổi hướng hạm đội thành công!")
		await _sync_snapshot()
	else:
		_show_toast("⚠️ %s" % str(res.get("error", "Không thể đổi hướng")))

func _recall_fleet(exp_id: String) -> void:
	var res: Dictionary = await ApiClient.post_req("/api/world/expeditions/%s/recall" % exp_id, {})
	if bool(res.get("ok", false)):
		_show_toast("↩ Đã triệu hồi hạm đội về Cảng!")
		await _sync_snapshot()
	else:
		_show_toast("⚠️ %s" % str(res.get("error", "Không thể triệu hồi")))

func _open_airship_port_overlay() -> void:
	var existing := get_node_or_null("AirshipPortModal")
	if existing != null: existing.queue_free()
	var ap_script = load("res://scripts/ui/airship_port_modal.gd")
	if ap_script != null:
		var modal = ap_script.new()
		modal.name = "AirshipPortModal"
		modal.closed.connect(func(): await _sync_snapshot())
		add_child(modal)
