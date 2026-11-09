extends Node3D

## Isometric 3D Seamless 2-Tier Castle Lobby (Pick Me Up: Infinite Gacha Architecture)
## - Seamless 2-Tier Castle (No Split Rendering - 100% Visible at all times):
##   * Tier 1 (Hạ Thành - East): 100m x 100m (X in [-50.0, +50.0], Z in [-50.0, +50.0], Y = 0.0)
##   * Tier 2 (Thượng Thành - West): 60m x 100m (X in [-110.0, -50.0], Z in [-50.0, +50.0], Y = 5.2)
## - Compact Fountain Ring (radius ~4.2m) tightly wrapping the Fountain base and moving together with it
## - Fixed Structure: ONLY the East Gate (DUNGEON_PORTAL at X = +48.5, Z = 0.0)
## - Grid-Based Free Placement & Road Building System (2m x 2m cells):
##   * All other structures (Fountain, Summon Altar, Barracks, Infirmary, and all constructed Plot buildings)
##     can be freely placed, moved, and rotated 90° on the 2-Tier Castle grid.
##   * Cobblestone Road Paint & Erase tool with auto-connecting borders and persistent JSON save.
##   * Master Level / unlocked_plots building cap is strictly preserved.

const UNIT_ACTOR_SCENE := preload("res://scenes/common/unit_actor_3d.tscn")
const BASE_PLOT_SCENE := preload("res://scenes/base/base_plot_3d.tscn")
const UniversalHeroCardScript := preload("res://scripts/ui/universal_hero_card.gd")
const UniversalItemCardScript := preload("res://scripts/ui/universal_item_card.gd")

const MAX_LOBBY_FLOORS := 2
const FLOOR_HEIGHT := 5.2
const MASTER_LEVELS_PER_FLOOR := 15
const PLOTS_PER_FLOOR := 8
const MAX_TOTAL_PLOTS := 48

## Unified 2m x 2m Castle Grid Constants:
## World X = -50.0 + gx * 2.0, World Z = -50.0 + gz * 2.0
## - Tier 1 (100m x 100m, Y = 0.0): gx in [0, 49], gz in [0, 49]
## - Tier 2 (60m x 100m, Y = 5.2): gx in [-30, -1], gz in [0, 49]
const GRID_CELL_SIZE := 2.0
const GRID_ORIGIN_X := -50.0
const GRID_ORIGIN_Z := -50.0
const TIER1_GX_MIN := 1
const TIER1_GX_MAX := 49
const TIER2_GX_MIN := -29
const TIER2_GX_MAX := -1
const GRID_GZ_MIN := 1
const GRID_GZ_MAX := 49
const CASTLE_LAYOUT_SAVE_PATH := "user://castle_grid_layout_v4.json"

enum GridEditMode {
	NONE = 0,
	PLACE_NEW_BUILDING = 1,
	MOVE_STRUCTURE = 2,
	ROAD_PAINT = 3,
	ROAD_ERASE = 4
}

func get_floor_terrace_center(floor_num: int) -> Vector3:
	if floor_num <= 1:
		return Vector3(0.0, 0.0, 0.0)
	return Vector3(-80.0, FLOOR_HEIGHT, 0.0)

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var dir_light: DirectionalLight3D = $DirectionalLight3D
@onready var bonfire_light: OmniLight3D = %BonfireOmniLight3D
@onready var camera_rig: IsometricCameraRig = $IsometricCameraRig

@onready var summon_altar_mesh: MeshInstance3D = $BaseArchitecture/SummonAltar
@onready var dungeon_portal_mesh: MeshInstance3D = $BaseArchitecture/DungeonPortal
@onready var portal_sub_label: Label3D = %PortalSubLabel
@onready var barracks_mesh: MeshInstance3D = $BaseArchitecture/Barracks
@onready var infirmary_mesh: MeshInstance3D = $BaseArchitecture/Infirmary

@onready var bonfire_body: StaticBody3D = $BaseArchitecture/CentralBonfire/BonfireBody
@onready var altar_body: StaticBody3D = $BaseArchitecture/SummonAltar/AltarBody
@onready var portal_body: StaticBody3D = $BaseArchitecture/PortalBody
@onready var barracks_body: StaticBody3D = $BaseArchitecture/Barracks/BarracksBody
@onready var infirmary_body: StaticBody3D = $BaseArchitecture/Infirmary/InfirmaryBody

@onready var zones_container: Node3D = $ZonesContainer
@onready var plots_container: Node3D = $PlotsContainer
@onready var heroes_container: Node3D = $HeroesContainer

@onready var master_info_label: Label = %MasterInfoLabel
@onready var resource_info_label: Label = %ResourceInfoLabel
@onready var status_banner_label: Label = %StatusBannerLabel

@onready var lighting_toggle_btn: Button = %LightingToggleBtn
@onready var focus_base_btn: Button = %FocusBaseBtn
@onready var refresh_base_btn: Button = %RefreshBaseBtn
@onready var back_hub_btn: Button = %BackHubBtn
@onready var floor_buttons_container: VBoxContainer = %FloorButtonsContainer

@onready var summon_altar_btn: Button = %SummonAltarBtn
@onready var barracks_btn: Button = %BarracksBtn
@onready var expand_zone_btn: Button = %ExpandZoneBtn
@onready var collect_all_btn: Button = %CollectAllBtn
@onready var enter_pve_btn: Button = %EnterPveBtn

@onready var inspector_panel: PanelContainer = %InspectorPanel
@onready var inspector_title_label: Label = %InspectorTitleLabel
@onready var inspector_subtitle_label: Label = %InspectorSubtitleLabel
@onready var close_inspector_btn: Button = %CloseInspectorBtn
@onready var inspector_action_container: VBoxContainer = %InspectorActionContainer

var _current_lobby_floor: int = 1
var _plot_nodes: Dictionary = {} # plot_index (1..48) -> BasePlot3D
var _floor_platforms: Dictionary = {}
var _floor_banners: Dictionary = {} # floor_num (1..2) -> Label3D
var _floor_buttons: Dictionary = {} # floor_num (1..2) -> Button
var _panorama_btn: Button = null
var _manage_floor_heroes_btn: Button = null
var _build_menu_btn: Button = null
var _move_mode_btn: Button = null
var _road_paint_btn: Button = null
var _road_erase_btn: Button = null
var _cancel_grid_btn: Button = null

var _editing_floor_hero_selection: Dictionary = {} # floor_num (int) -> Array[String]
var _hero_actors: Dictionary = {} # hero_id -> UnitActor3D
var _active_banners: Array = []
var _floor1_current_trans: float = 0.0
var _floor_trans_map: Dictionary = {}
var _panorama_mode: bool = false

# Grid-Based Free Placement & Road System state
var _grid_edit_mode: int = GridEditMode.NONE
var _grid_structures: Dictionary = {} # id ("FOUNTAIN", "SUMMON_ALTAR", "BARRACKS", "INFIRMARY", "PLOT:1", ...) -> { "gx": int, "gz": int, "rot": int }
var _grid_roads: Dictionary = {} # "gx,gz" -> true
var _roads_container: Node3D = null
var _road_mesh_nodes: Dictionary = {} # "gx,gz" -> Node3D
var _grid_overlay_root: Node3D = null
var _grid_ghost_root: Node3D = null
var _grid_ghost_mesh: MeshInstance3D = null
var _grid_ghost_border: MeshInstance3D = null
var _grid_ghost_label: Label3D = null
var _pending_build_code: String = ""
var _pending_build_name: String = ""
var _moving_structure_id: String = ""
var _placement_rot_deg: int = 0
var _hover_gx: int = 23
var _hover_gz: int = 23
var _hover_valid: bool = false
var _is_painting_road_drag: bool = false

# Selection & Hover state
var _hovered_plot: BasePlot3D = null
var _selected_plot: BasePlot3D = null
var _inspector_context: Dictionary = {}
var _facility_subtab: int = 0
var _selected_facility_hero_id: String = ""

# Pick Me Up 3D Drag & Drop state
var _pressed_hero: UnitActor3D = null
var _dragging_hero: UnitActor3D = null
var _press_screen_pos: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD_PX := 8.0

# Lighting / Ambiance state (0 = Day, 1 = Sunset, 2 = Night Campfire)
var _lighting_mode: int = 0
var _bonfire_time: float = 0.0
var _auto_poll_timer: float = 0.0

func _ready() -> void:
	if camera_rig != null:
		camera_rig.use_castle_world_bounds = true
		camera_rig.castle_world_min = Vector2(-115.0, -54.0)
		camera_rig.castle_world_max = Vector2(54.0, 54.0)
		camera_rig.castle_tier2_x_threshold = -50.0
		camera_rig.castle_tier2_height = FLOOR_HEIGHT
		camera_rig.default_ortho_size = 38.0
		if camera_rig.camera != null:
			camera_rig.camera.size = 38.0

	_load_or_init_castle_grid_layout()
	_setup_grand_citadel_floor1()
	_setup_landmark_metadata()
	_spawn_stacked_3d_floors_and_plots()
	_setup_grid_overlay_and_roads()
	_apply_all_grid_transforms()
	_build_floor_elevator_buttons()

	back_hub_btn.visible = false
	collect_all_btn.visible = false

	lighting_toggle_btn.pressed.connect(_on_lighting_toggle_pressed)
	focus_base_btn.pressed.connect(_on_focus_base_pressed)
	refresh_base_btn.pressed.connect(_sync_all_from_backend)
	back_hub_btn.pressed.connect(_on_back_hub_pressed)
	close_inspector_btn.pressed.connect(_close_inspector)

	summon_altar_btn.pressed.connect(func():
		_exit_grid_edit_mode()
		var altar_pos := summon_altar_mesh.global_position if summon_altar_mesh != null else Vector3(-80.0, FLOOR_HEIGHT, 0.0)
		_current_lobby_floor = 2 if altar_pos.x < -50.0 else 1
		_open_landmark_inspector("SUMMON_ALTAR", true)
	)
	barracks_btn.pressed.connect(_on_barracks_pressed)
	expand_zone_btn.pressed.connect(_on_expand_zone_pressed)
	collect_all_btn.pressed.connect(_on_collect_all_pressed)
	enter_pve_btn.pressed.connect(_on_enter_pve_pressed)

	_apply_lighting_preset(0, false)
	_refresh_hud()
	_refresh_3d_plots()
	_spawn_resident_heroes()
	_apply_floor_focus_isolation(_current_lobby_floor, false, 0)

	var demo_ok := await GameState.ensure_demo_session()
	if demo_ok:
		await _sync_all_from_backend()
		status_banner_label.text = "🏰 Lâu Đài 2 Tầng Liền Khối (100×100 Hạ Thành + 60×100 Thượng Thành) — Tự do đặt Công trình & Lát Đường trên lưới!"
	else:
		status_banner_label.text = "⚠️ KHÔNG THỂ KẾT NỐI SERVER BACKEND (PORT 3000)! Vui lòng kiểm tra lại server."

## Configures the Seamless 2-Tier Castle Architecture (160m x 100m Total):
## - Tier 1 (Hạ Thành - East): 100m x 100m (X in [-50, +50], Z in [-50, +50], Y = 0.0)
## - Tier 2 (Thượng Thành - West): 60m x 100m (X in [-110, -50], Z in [-50, +50], Y = 5.2)
## - Continuous perimeter fortress walls + 6 Bastion Towers + Retaining Cliff at X = -50.0
## - Twin Solid Stone Staircases ascending East -> West (X: -40.0 -> -50.0) at Z = -18.0 and Z = +18.0
## - Fixed East Gate (DUNGEON_PORTAL) at X = +48.2, Z = 0.0
## - Compact Fountain Ring (radius = 4.25m) synced with the Fountain node so they move together
func _setup_grand_citadel_floor1() -> void:
	var arch := $BaseArchitecture
	if arch == null:
		return

	# 1. Tier 1 Ground Courtyard: 100m (X: -50..+50) x 100m (Z: -50..+50) at Y = 0.0
	var ground: MeshInstance3D = arch.get_node_or_null("Ground")
	if ground != null:
		var ground_box := BoxMesh.new()
		ground_box.size = Vector3(100.0, 0.6, 100.0)
		ground.mesh = ground_box
		ground.position = Vector3(0.0, -0.3, 0.0)

	# 2. Tier 2 Upper Citadel Deck: 60m (X: -110..-50) x 100m (Z: -50..+50) at Y = 5.2
	# Cut out a central stairwell slot (X in [-62.0, -50.0], Z in [-4.2, +4.2]) so the single central staircase is recessed inside Tier 2
	var old_t2 := arch.get_node_or_null("Tier2GroundDeck")
	if old_t2 != null:
		old_t2.queue_free()
	var tier2_deck := Node3D.new()
	tier2_deck.name = "Tier2GroundDeck"
	arch.add_child(tier2_deck)

	var t2_mat := StandardMaterial3D.new()
	t2_mat.albedo_color = Color(0.42, 0.38, 0.33) # Medieval cliff retaining stone
	t2_mat.roughness = 0.88

	# Main West Tier 2 Deck (X in [-110.0, -62.0], Z in [-50.0, +50.0]): 48m x 100m
	var main_t2 := MeshInstance3D.new()
	var mt2_box := BoxMesh.new()
	mt2_box.size = Vector3(48.0, FLOOR_HEIGHT + 0.6, 100.0)
	main_t2.mesh = mt2_box
	main_t2.position = Vector3(-86.0, (FLOOR_HEIGHT - 0.6) * 0.5, 0.0)
	main_t2.material_override = t2_mat
	tier2_deck.add_child(main_t2)

	# North Flank Deck (X in [-62.0, -50.0], Z in [-50.0, -4.2]): 12m x 45.8m
	var n_flank := MeshInstance3D.new()
	var nf_box := BoxMesh.new()
	nf_box.size = Vector3(12.0, FLOOR_HEIGHT + 0.6, 45.8)
	n_flank.mesh = nf_box
	n_flank.position = Vector3(-56.0, (FLOOR_HEIGHT - 0.6) * 0.5, -27.1)
	n_flank.material_override = t2_mat
	tier2_deck.add_child(n_flank)

	# South Flank Deck (X in [-62.0, -50.0], Z in [+4.2, +50.0]): 12m x 45.8m
	var s_flank := MeshInstance3D.new()
	var sf_box := BoxMesh.new()
	sf_box.size = Vector3(12.0, FLOOR_HEIGHT + 0.6, 45.8)
	s_flank.mesh = sf_box
	s_flank.position = Vector3(-56.0, (FLOOR_HEIGHT - 0.6) * 0.5, 27.1)
	s_flank.material_override = t2_mat
	tier2_deck.add_child(s_flank)

	# Remove legacy CrossAvenues if present (replaced by interactive Road Building System)
	var old_avenues := arch.get_node_or_null("CrossAvenues")
	if old_avenues != null:
		old_avenues.queue_free()

	# 3. Compact Fountain Base Ring (vòng tròn quanh đài phun nước thu bé lại đủ bao quanh đài)
	var plaza: MeshInstance3D = arch.get_node_or_null("CentralPlazaDisc")
	if plaza != null:
		var plaza_cyl := CylinderMesh.new()
		plaza_cyl.top_radius = 4.25
		plaza_cyl.bottom_radius = 4.45
		plaza_cyl.height = 0.16
		plaza.mesh = plaza_cyl
		var plaza_mat := StandardMaterial3D.new()
		plaza_mat.albedo_color = Color(0.26, 0.32, 0.42)
		plaza_mat.roughness = 0.72
		plaza.material_override = plaza_mat

	# 4. Authentic Medieval Machicolated Fortress Walls, Crenellations & Spired Bastion Towers
	var old_walls := arch.get_node_or_null("PerimeterFortressWalls")
	if old_walls != null:
		old_walls.queue_free()
	var walls_node := Node3D.new()
	walls_node.name = "PerimeterFortressWalls"
	arch.add_child(walls_node)

	# Medieval warm sandstone & dark slate spire materials (matching authentic castle photo)
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.48, 0.44, 0.38) # Warm golden-grey medieval limestone/sandstone
	wall_mat.roughness = 0.88

	var corbel_mat := StandardMaterial3D.new()
	corbel_mat.albedo_color = Color(0.38, 0.34, 0.29) # Shadowed machicolation stone brackets
	corbel_mat.roughness = 0.82

	var plinth_mat := StandardMaterial3D.new()
	plinth_mat.albedo_color = Color(0.32, 0.30, 0.27) # Darker battered base plinth
	plinth_mat.roughness = 0.90

	var spire_mat := StandardMaterial3D.new()
	spire_mat.albedo_color = Color(0.22, 0.25, 0.30) # Dark slate conical roof tiles
	spire_mat.roughness = 0.58
	spire_mat.metallic = 0.12

	var finial_mat := StandardMaterial3D.new()
	finial_mat.albedo_color = Color(0.85, 0.75, 0.45) # Gilded finial needle spire tip
	finial_mat.metallic = 0.75
	finial_mat.roughness = 0.32

	# Helper to build a machicolated curtain wall section with battlements (crenellations)
	var build_crenellated_wall = func(start_p: Vector3, end_p: Vector3, wall_h: float, wall_w: float) -> void:
		var dir := end_p - start_p
		var length := dir.length()
		var center := (start_p + end_p) * 0.5
		var is_x_aligned := absf(dir.x) > absf(dir.z)

		# 1. Main Curtain Wall Body
		var w_inst := MeshInstance3D.new()
		var w_box := BoxMesh.new()
		w_box.size = Vector3(length, wall_h, wall_w) if is_x_aligned else Vector3(wall_w, wall_h, length)
		w_inst.mesh = w_box
		w_inst.position = center + Vector3(0.0, wall_h * 0.5, 0.0)
		w_inst.material_override = wall_mat
		walls_node.add_child(w_inst)

		# 2. Machicolation Corbel Overhang Ledge (Gờ đá nhô ra dưới lỗ châu mai)
		var ledge := MeshInstance3D.new()
		var l_box := BoxMesh.new()
		l_box.size = Vector3(length + 0.1, 0.55, wall_w + 0.55) if is_x_aligned else Vector3(wall_w + 0.55, 0.55, length + 0.1)
		ledge.mesh = l_box
		ledge.position = center + Vector3(0.0, wall_h - 0.25, 0.0)
		ledge.material_override = corbel_mat
		walls_node.add_child(ledge)

		# 3. Crenellations / Merlons (Hàng răng cưa lỗ châu mai dọc đỉnh thành)
		var merlon_len := 1.35
		var gap_len := 0.85
		var step := merlon_len + gap_len
		var count := int(floor((length - 1.0) / step))
		var start_offset := -(float(count - 1) * step) * 0.5

		for m_i in range(count):
			var m_off := start_offset + float(m_i) * step
			var merlon := MeshInstance3D.new()
			var m_box := BoxMesh.new()
			m_box.size = Vector3(merlon_len, 0.95, wall_w + 0.35) if is_x_aligned else Vector3(wall_w + 0.35, 0.95, merlon_len)
			merlon.mesh = m_box
			var m_pos := center + Vector3(0.0, wall_h + 0.45, 0.0)
			if is_x_aligned:
				m_pos.x += m_off
			else:
				m_pos.z += m_off
			merlon.position = m_pos
			merlon.material_override = wall_mat
			walls_node.add_child(merlon)

	# A. Tier 1 North & South Curtain Walls (X in [-46, +46], Z = -49.3 / +49.3, Y = 0.0)
	for z_sign in [-1.0, 1.0]:
		build_crenellated_wall.call(Vector3(-46.0, 0.0, z_sign * 49.3), Vector3(46.0, 0.0, z_sign * 49.3), 6.2, 1.8)

	# B. Tier 1 East Curtain Wall (X = +49.3) with opening for East Gate (Z in [-6.0, +6.0])
	build_crenellated_wall.call(Vector3(49.3, 0.0, -46.0), Vector3(49.3, 0.0, -6.5), 6.2, 1.8)
	build_crenellated_wall.call(Vector3(49.3, 0.0, 6.5), Vector3(49.3, 0.0, 46.0), 6.2, 1.8)

	# C. Tier 2 North & South Curtain Walls (X in [-106, -53], Z = -49.3 / +49.3, sitting at Y = 5.2)
	for z_sign in [-1.0, 1.0]:
		build_crenellated_wall.call(Vector3(-106.0, FLOOR_HEIGHT, z_sign * 49.3), Vector3(-53.0, FLOOR_HEIGHT, z_sign * 49.3), 6.2, 1.8)

	# D. Tier 2 West Back Wall (X = -109.3, Z in [-46, +46], sitting at Y = 5.2)
	build_crenellated_wall.call(Vector3(-109.3, FLOOR_HEIGHT, -46.0), Vector3(-109.3, FLOOR_HEIGHT, 46.0), 6.6, 2.0)

	# E. Cliff Parapet along X = -50.0 with single central opening for Grand Recessed Staircase (Z in [-4.2, +4.2])
	for seg: Vector2 in [Vector2(-48.0, -4.2), Vector2(4.2, 48.0)]:
		var seg_len: float = seg.y - seg.x
		var seg_mid: float = (seg.x + seg.y) * 0.5
		var parapet := MeshInstance3D.new()
		var p_box := BoxMesh.new()
		p_box.size = Vector3(1.2, 1.35, seg_len)
		parapet.mesh = p_box
		parapet.position = Vector3(-50.0, FLOOR_HEIGHT + 0.675, seg_mid)
		parapet.material_override = wall_mat
		walls_node.add_child(parapet)

		var p_ledge := MeshInstance3D.new()
		var pl_box := BoxMesh.new()
		pl_box.size = Vector3(1.5, 0.25, seg_len)
		p_ledge.mesh = pl_box
		p_ledge.position = Vector3(-50.0, FLOOR_HEIGHT + 1.45, seg_mid)
		p_ledge.material_override = corbel_mat
		walls_node.add_child(p_ledge)

	# E2. Side Safety Balustrades flanking the recessed stairwell inside Tier 2 (X in [-62.0, -50.0] at Z = +-4.2)
	for z_side in [-4.2, 4.2]:
		var side_rail := MeshInstance3D.new()
		var sr_box := BoxMesh.new()
		sr_box.size = Vector3(12.0, 1.25, 0.55)
		side_rail.mesh = sr_box
		side_rail.position = Vector3(-56.0, FLOOR_HEIGHT + 0.625, z_side)
		side_rail.material_override = wall_mat
		walls_node.add_child(side_rail)

		var sr_cap := MeshInstance3D.new()
		var src_box := BoxMesh.new()
		src_box.size = Vector3(12.2, 0.22, 0.75)
		sr_cap.mesh = src_box
		sr_cap.position = Vector3(-56.0, FLOOR_HEIGHT + 1.35, z_side)
		sr_cap.material_override = corbel_mat
		walls_node.add_child(sr_cap)

	# F. 6 Grand Round Bastion Towers with Full Height Coverage, Machicolated Galleries & Conical Spire Roofs
	# Tower specs:
	# - East Towers (X = +49.3, Z = +-49.3): base_y = 0.0, shaft_top = 8.8 (above wall 6.2m), spire_h = 5.8m
	# - Mid Transition Cliff Towers (X = -50.0, Z = +-49.3): base_y = 0.0 (full ground coverage!), shaft_top = 14.2m (above T2 wall), spire_h = 6.2m
	# - West Towers (X = -109.3, Z = +-49.3): base_y = 0.0 (full ground plinth!), shaft_top = 14.2m (above T2 wall), spire_h = 6.2m
	var tower_defs := [
		{ "x": 49.3, "z": -49.3, "base_y": 0.0, "shaft_top": 8.8, "spire_h": 5.8, "r": 3.4 },
		{ "x": 49.3, "z": 49.3, "base_y": 0.0, "shaft_top": 8.8, "spire_h": 5.8, "r": 3.4 },
		{ "x": -50.0, "z": -49.3, "base_y": 0.0, "shaft_top": FLOOR_HEIGHT + 9.0, "spire_h": 6.4, "r": 3.6 },
		{ "x": -50.0, "z": 49.3, "base_y": 0.0, "shaft_top": FLOOR_HEIGHT + 9.0, "spire_h": 6.4, "r": 3.6 },
		{ "x": -109.3, "z": -49.3, "base_y": 0.0, "shaft_top": FLOOR_HEIGHT + 9.0, "spire_h": 6.4, "r": 3.6 },
		{ "x": -109.3, "z": 49.3, "base_y": 0.0, "shaft_top": FLOOR_HEIGHT + 9.0, "spire_h": 6.4, "r": 3.6 }
	]

	for tdef: Dictionary in tower_defs:
		var tx: float = float(tdef["x"])
		var tz: float = float(tdef["z"])
		var base_y: float = float(tdef["base_y"])
		var shaft_top: float = float(tdef["shaft_top"])
		var spire_h: float = float(tdef["spire_h"])
		var radius: float = float(tdef["r"])
		var total_shaft_h := shaft_top - base_y

		var tower_root := Node3D.new()
		tower_root.position = Vector3(tx, 0.0, tz)
		walls_node.add_child(tower_root)

		# 1. Battered Base Plinth (Chân tháp phình to loe ra dốc như ảnh trung cổ)
		var plinth := MeshInstance3D.new()
		var p_cyl := CylinderMesh.new()
		p_cyl.top_radius = radius + 0.1
		p_cyl.bottom_radius = radius + 1.2
		p_cyl.height = 2.4
		plinth.mesh = p_cyl
		plinth.position = Vector3(0.0, base_y + 1.2, 0.0)
		plinth.material_override = plinth_mat
		tower_root.add_child(plinth)

		# 2. Main Tower Shaft Cylinder (Bao phủ đủ toàn bộ chiều cao từ chân lên đỉnh)
		var shaft := MeshInstance3D.new()
		var s_cyl := CylinderMesh.new()
		s_cyl.top_radius = radius
		s_cyl.bottom_radius = radius + 0.1
		s_cyl.height = total_shaft_h - 2.0
		shaft.mesh = s_cyl
		shaft.position = Vector3(0.0, base_y + 2.0 + (total_shaft_h - 2.0) * 0.5, 0.0)
		shaft.material_override = wall_mat
		tower_root.add_child(shaft)

		# 3. Machicolated Gallery Overhang (Vành ban công chiến đấu nhô ra ngoài)
		var gallery_bottom := MeshInstance3D.new()
		var gb_cyl := CylinderMesh.new()
		gb_cyl.top_radius = radius + 0.95
		gb_cyl.bottom_radius = radius
		gb_cyl.height = 0.95
		gallery_bottom.mesh = gb_cyl
		gallery_bottom.position = Vector3(0.0, shaft_top + 0.475, 0.0)
		gallery_bottom.material_override = corbel_mat
		tower_root.add_child(gallery_bottom)

		# 4. Circular Tower Battlement Ring (Thành tròn với lỗ châu mai quanh đỉnh tháp)
		var battlement_ring := MeshInstance3D.new()
		var br_cyl := CylinderMesh.new()
		br_cyl.top_radius = radius + 0.92
		br_cyl.bottom_radius = radius + 0.95
		br_cyl.height = 0.95
		battlement_ring.mesh = br_cyl
		battlement_ring.position = Vector3(0.0, shaft_top + 0.95 + 0.475, 0.0)
		battlement_ring.material_override = wall_mat
		tower_root.add_child(battlement_ring)

		# 5. Conical Slate Spire Roof (Mái nón chóp nhọn cao vút lợp ngói đá phiến trung cổ)
		var roof := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.08
		cone.bottom_radius = radius + 1.05
		cone.height = spire_h
		roof.mesh = cone
		roof.position = Vector3(0.0, shaft_top + 1.9 + spire_h * 0.5, 0.0)
		roof.material_override = spire_mat
		tower_root.add_child(roof)

		# 6. Golden Finial Needle Spire Tip (Kim nhọn đỉnh tháp)
		var finial := MeshInstance3D.new()
		var f_mesh := CylinderMesh.new()
		f_mesh.top_radius = 0.02
		f_mesh.bottom_radius = 0.12
		f_mesh.height = 1.2
		finial.mesh = f_mesh
		finial.position = Vector3(0.0, shaft_top + 1.9 + spire_h + 0.55, 0.0)
		finial.material_override = finial_mat
		tower_root.add_child(finial)

	# 5. Grand Central Recessed Staircase: 1 single staircase recessed INSIDE Tier 2 (X: -50.0 -> -62.0, Z = 0.0)
	# Bottom of stairs starts flush at X = -50.0 (Tier 1 ground level Y = 0.0, zero protrusion onto Tier 1 floor)
	# Ascends westward into the heart of Tier 2, top step arrives at X = -62.0 (Tier 2 floor level Y = 5.2)
	var old_stairs := arch.get_node_or_null("TwinWallStairs")
	if old_stairs != null:
		old_stairs.queue_free()
	var central_stairs := Node3D.new()
	central_stairs.name = "TwinWallStairs"
	arch.add_child(central_stairs)

	var stair_mat := StandardMaterial3D.new()
	stair_mat.albedo_color = Color(0.44, 0.40, 0.35)
	stair_mat.roughness = 0.85

	var step_count := 18
	var stair_span_x := 12.0 # X from -50.0 (flush at cliff face) to -62.0 (inside Tier 2)
	var step_depth_x := stair_span_x / float(step_count)
	var stair_width_z := 8.0 # Grand 8m wide staircase (Z in [-4.0, +4.0])

	for s_idx in range(step_count):
		var t := float(s_idx + 1) / float(step_count)
		var step_h := lerpf(0.32, FLOOR_HEIGHT, t)
		var sx := -50.0 - (float(s_idx) + 0.5) * step_depth_x
		var step_inst := MeshInstance3D.new()
		var s_box := BoxMesh.new()
		s_box.size = Vector3(step_depth_x + 0.05, step_h, stair_width_z)
		step_inst.mesh = s_box
		step_inst.position = Vector3(sx, step_h * 0.5, 0.0)
		step_inst.material_override = stair_mat
		central_stairs.add_child(step_inst)

	# Stone curb stringers on North and South sides of the staircase
	for z_curb in [-4.15, 4.15]:
		var curb := MeshInstance3D.new()
		var c_box := BoxMesh.new()
		c_box.size = Vector3(stair_span_x, FLOOR_HEIGHT + 0.35, 0.35)
		curb.mesh = c_box
		curb.position = Vector3(-56.0, (FLOOR_HEIGHT + 0.35) * 0.5, z_curb)
		curb.material_override = corbel_mat
		central_stairs.add_child(curb)

	# 6. Centerpiece: Tiered Fountain (⛲ Đài Phun Nước - Movable 4x4 Grid Landmark)
	var bonfire_node := arch.get_node_or_null("CentralBonfire")
	if bonfire_node != null:
		var firepit: MeshInstance3D = bonfire_node.get_node_or_null("FirepitMesh")
		if firepit != null:
			firepit.visible = false
		var flame: MeshInstance3D = bonfire_node.get_node_or_null("FlameMesh")
		if flame != null:
			flame.visible = false

		var b_lbl: Label3D = bonfire_node.get_node_or_null("BonfireLabel")
		if b_lbl != null:
			b_lbl.text = "⛲ ĐÀI PHUN NƯỚC"
			b_lbl.position = Vector3(0.0, 3.8, 0.0)
			b_lbl.modulate = Color(0.45, 0.88, 1.0)
			b_lbl.font_size = 23

		var fountain_visuals := bonfire_node.get_node_or_null("FountainVisuals")
		if fountain_visuals == null:
			fountain_visuals = Node3D.new()
			fountain_visuals.name = "FountainVisuals"
			bonfire_node.add_child(fountain_visuals)

			var stone_mat := StandardMaterial3D.new()
			stone_mat.albedo_color = Color(0.38, 0.45, 0.55)
			stone_mat.roughness = 0.65

			var water_mat := StandardMaterial3D.new()
			water_mat.albedo_color = Color(0.18, 0.72, 0.96, 0.88)
			water_mat.roughness = 0.08
			water_mat.metallic = 0.1
			water_mat.emission_enabled = true
			water_mat.emission = Color(0.12, 0.52, 0.78)
			water_mat.emission_energy_multiplier = 0.6

			var lower_basin := MeshInstance3D.new()
			var lb_cyl := CylinderMesh.new()
			lb_cyl.top_radius = 3.4
			lb_cyl.bottom_radius = 3.6
			lb_cyl.height = 0.65
			lower_basin.mesh = lb_cyl
			lower_basin.position = Vector3(0.0, 0.32, 0.0)
			lower_basin.material_override = stone_mat
			fountain_visuals.add_child(lower_basin)

			var water_pool := MeshInstance3D.new()
			var wp_cyl := CylinderMesh.new()
			wp_cyl.top_radius = 3.15
			wp_cyl.bottom_radius = 3.15
			wp_cyl.height = 0.06
			water_pool.mesh = wp_cyl
			water_pool.position = Vector3(0.0, 0.60, 0.0)
			water_pool.material_override = water_mat
			fountain_visuals.add_child(water_pool)

			var pedestal := MeshInstance3D.new()
			var ped_cyl := CylinderMesh.new()
			ped_cyl.top_radius = 1.1
			ped_cyl.bottom_radius = 1.3
			ped_cyl.height = 1.1
			pedestal.mesh = ped_cyl
			pedestal.position = Vector3(0.0, 1.05, 0.0)
			pedestal.material_override = stone_mat
			fountain_visuals.add_child(pedestal)

			var upper_basin := MeshInstance3D.new()
			var ub_cyl := CylinderMesh.new()
			ub_cyl.top_radius = 2.0
			ub_cyl.bottom_radius = 1.65
			ub_cyl.height = 0.38
			upper_basin.mesh = ub_cyl
			upper_basin.position = Vector3(0.0, 1.62, 0.0)
			upper_basin.material_override = stone_mat
			fountain_visuals.add_child(upper_basin)

			var upper_water := MeshInstance3D.new()
			var uw_cyl := CylinderMesh.new()
			uw_cyl.top_radius = 1.85
			uw_cyl.bottom_radius = 1.85
			uw_cyl.height = 0.05
			upper_water.mesh = uw_cyl
			upper_water.position = Vector3(0.0, 1.78, 0.0)
			upper_water.material_override = water_mat
			fountain_visuals.add_child(upper_water)

			var spire := MeshInstance3D.new()
			var spire_cyl := CylinderMesh.new()
			spire_cyl.top_radius = 0.08
			spire_cyl.bottom_radius = 0.55
			spire_cyl.height = 1.55
			spire.mesh = spire_cyl
			spire.position = Vector3(0.0, 2.45, 0.0)
			var fountain_spire_mat := StandardMaterial3D.new()
			fountain_spire_mat.albedo_color = Color(0.45, 0.92, 1.0)
			fountain_spire_mat.emission_enabled = true
			fountain_spire_mat.emission = Color(0.35, 0.85, 1.0)
			fountain_spire_mat.emission_energy_multiplier = 1.8
			spire.material_override = fountain_spire_mat
			fountain_visuals.add_child(spire)

			# Compact Glowing Halo Ring tightly wrapping the Fountain (radius ~3.95m)
			var compact_ring := MeshInstance3D.new()
			var cr_torus := TorusMesh.new()
			cr_torus.inner_radius = 3.82
			cr_torus.outer_radius = 4.08
			compact_ring.mesh = cr_torus
			compact_ring.position = Vector3(0.0, 0.10, 0.0)
			var cr_mat := StandardMaterial3D.new()
			cr_mat.albedo_color = Color(0.32, 0.88, 1.0)
			cr_mat.emission_enabled = true
			cr_mat.emission = Color(0.22, 0.74, 1.0)
			cr_mat.emission_energy_multiplier = 1.6
			compact_ring.material_override = cr_mat
			fountain_visuals.add_child(compact_ring)

		if bonfire_light != null:
			bonfire_light.light_color = Color(0.42, 0.86, 1.0)
			bonfire_light.position = Vector3(0.0, 2.8, 0.0)
			bonfire_light.light_energy = 2.4
			bonfire_light.omni_range = 18.0

		if bonfire_body != null and bonfire_body.has_node("CollisionShape3D"):
			var bshape: CollisionShape3D = bonfire_body.get_node("CollisionShape3D")
			var cs := CylinderShape3D.new()
			cs.radius = 3.8
			cs.height = 2.6
			bshape.shape = cs
			bshape.position = Vector3(0.0, 1.3, 0.0)

	# 7. CỔNG PHÍA ĐÔNG (+X = 48.2): ONLY Permanently Fixed Structure in the Castle
	if dungeon_portal_mesh != null:
		dungeon_portal_mesh.position = Vector3(48.2, 2.8, 0.0)
		dungeon_portal_mesh.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	if portal_body != null:
		portal_body.position = Vector3(48.2, 0.0, 0.0)

	var portal_lbl: Label3D = arch.get_node_or_null("PortalLabel")
	if portal_lbl != null:
		portal_lbl.text = "⛩️ CỔNG THÁP CHINH PHẠT PvE (CỔNG ĐÔNG - CỐ ĐỊNH)"
		portal_lbl.position = Vector3(48.2, 6.8, 0.0)
	if portal_sub_label != null:
		portal_sub_label.position = Vector3(48.2, 6.1, 0.0)

	var old_gh := arch.get_node_or_null("GatehouseVisuals")
	if old_gh != null:
		old_gh.queue_free()
	var gatehouse_visuals := Node3D.new()
	gatehouse_visuals.name = "GatehouseVisuals"
	arch.add_child(gatehouse_visuals)

	var gh_mat := StandardMaterial3D.new()
	gh_mat.albedo_color = Color(0.48, 0.44, 0.38) # Authentic medieval gatehouse stone
	gh_mat.roughness = 0.85

	for z_pillar in [-4.5, 4.5]:
		var gp := MeshInstance3D.new()
		var gpb := BoxMesh.new()
		gpb.size = Vector3(2.8, 6.2, 2.2)
		gp.mesh = gpb
		gp.position = Vector3(48.2, 3.1, z_pillar)
		gp.material_override = gh_mat
		gatehouse_visuals.add_child(gp)

	var arch_beam := MeshInstance3D.new()
	var abb := BoxMesh.new()
	abb.size = Vector3(3.0, 1.5, 11.2)
	arch_beam.mesh = abb
	arch_beam.position = Vector3(48.2, 5.8, 0.0)
	arch_beam.material_override = gh_mat
	gatehouse_visuals.add_child(arch_beam)

	# 8. ĐÀI TRIỆU HỒI (✨ Summon Altar - Movable 4x4 Grid Landmark, Dais & Obelisks attached as children)
	var old_dais := arch.get_node_or_null("AltarDaisVisuals")
	if old_dais != null:
		old_dais.queue_free()
	if summon_altar_mesh != null:
		if altar_body != null and altar_body.get_parent() == summon_altar_mesh:
			altar_body.position = Vector3.ZERO
		var altar_lbl: Label3D = summon_altar_mesh.get_node_or_null("AltarLabel")
		if altar_lbl != null:
			altar_lbl.text = "✨ ĐÀI TRIỆU HỒI"
			altar_lbl.position = Vector3(0.0, 3.1, 0.0)
		var altar_sub: Label3D = summon_altar_mesh.get_node_or_null("AltarSubLabel")
		if altar_sub != null:
			altar_sub.position = Vector3(0.0, 2.5, 0.0)

		var altar_dais := summon_altar_mesh.get_node_or_null("AltarDaisChild")
		if altar_dais == null:
			altar_dais = Node3D.new()
			altar_dais.name = "AltarDaisChild"
			summon_altar_mesh.add_child(altar_dais)

			var dais_mat := StandardMaterial3D.new()
			dais_mat.albedo_color = Color(0.32, 0.38, 0.48)
			dais_mat.roughness = 0.60

			var dais_base := MeshInstance3D.new()
			var db_cyl := CylinderMesh.new()
			db_cyl.top_radius = 3.5
			db_cyl.bottom_radius = 3.8
			db_cyl.height = 0.5
			dais_base.mesh = db_cyl
			dais_base.position = Vector3(0.0, -0.45, 0.0)
			dais_base.material_override = dais_mat
			altar_dais.add_child(dais_base)

			var ob_mat := StandardMaterial3D.new()
			ob_mat.albedo_color = Color(0.25, 0.45, 0.65)
			ob_mat.emission_enabled = true
			ob_mat.emission = Color(0.2, 0.6, 0.95)
			ob_mat.emission_energy_multiplier = 1.2

			for z_sign in [-1.0, 1.0]:
				var ob := MeshInstance3D.new()
				var ob_mesh := CylinderMesh.new()
				ob_mesh.top_radius = 0.12
				ob_mesh.bottom_radius = 0.42
				ob_mesh.height = 3.2
				ob.mesh = ob_mesh
				ob.position = Vector3(0.0, 0.95, z_sign * 3.1)
				ob.material_override = ob_mat
				altar_dais.add_child(ob)

	# 9. Authentic Medieval Architecture for BARRACKS & INFIRMARY (Movable 3x3 Grid Landmarks)
	# 9A. BARRACKS (🛡️ Doanh Trại Quân Đội & Thăng Sao)
	if barracks_mesh != null:
		barracks_mesh.mesh = null # Remove legacy plain block box
		var old_bv := barracks_mesh.get_node_or_null("BarracksVisuals")
		if old_bv != null:
			old_bv.queue_free()

		var bv := Node3D.new()
		bv.name = "BarracksVisuals"
		barracks_mesh.add_child(bv)

		# Stone foundation plinth (5.6m x 0.4m x 5.6m)
		var b_plinth := MeshInstance3D.new()
		var bp_box := BoxMesh.new()
		bp_box.size = Vector3(5.6, 0.4, 5.6)
		b_plinth.mesh = bp_box
		b_plinth.position = Vector3(0.0, 0.2, 0.0)
		b_plinth.material_override = plinth_mat
		bv.add_child(b_plinth)

		# Main Garrison Fortress Hall (4.6m x 2.6m x 3.8m)
		var b_hall := MeshInstance3D.new()
		var bh_box := BoxMesh.new()
		bh_box.size = Vector3(4.6, 2.6, 3.8)
		b_hall.mesh = bh_box
		b_hall.position = Vector3(0.0, 1.7, -0.5)
		b_hall.material_override = wall_mat
		bv.add_child(b_hall)

		# Clay Gable Roof (4.9m x 1.7m x 4.2m)
		var b_roof := MeshInstance3D.new()
		var br_prism := PrismMesh.new()
		br_prism.size = Vector3(4.9, 1.7, 4.2)
		b_roof.mesh = br_prism
		b_roof.position = Vector3(0.0, 3.85, -0.5)
		var broof_mat := StandardMaterial3D.new()
		broof_mat.albedo_color = Color(0.68, 0.25, 0.20) # Medieval Knight Clay Red Tiles
		broof_mat.roughness = 0.70
		b_roof.material_override = broof_mat
		bv.add_child(b_roof)

		# Twin Front Corner Watchtowers (Tháp canh gác góc mặt tiền)
		for t_x in [-2.15, 2.15]:
			var wt := MeshInstance3D.new()
			var wt_cyl := CylinderMesh.new()
			wt_cyl.top_radius = 0.65
			wt_cyl.bottom_radius = 0.75
			wt_cyl.height = 3.6
			wt.mesh = wt_cyl
			wt.position = Vector3(t_x, 1.8, 1.25)
			wt.material_override = wall_mat
			bv.add_child(wt)

			var wt_cap := MeshInstance3D.new()
			var wtc_cyl := CylinderMesh.new()
			wtc_cyl.top_radius = 0.06
			wtc_cyl.bottom_radius = 0.85
			wtc_cyl.height = 1.6
			wt_cap.mesh = wtc_cyl
			wt_cap.position = Vector3(t_x, 4.4, 1.25)
			wt_cap.material_override = spire_mat
			bv.add_child(wt_cap)

		# Reinforced Oak Gate (Cổng gỗ đai sắt trung cổ)
		var b_gate := MeshInstance3D.new()
		var bg_box := BoxMesh.new()
		bg_box.size = Vector3(1.6, 2.0, 0.2)
		b_gate.mesh = bg_box
		b_gate.position = Vector3(0.0, 1.3, 1.42)
		var bg_mat := StandardMaterial3D.new()
		bg_mat.albedo_color = Color(0.38, 0.26, 0.16)
		bg_mat.roughness = 0.82
		b_gate.material_override = bg_mat
		bv.add_child(b_gate)

		# Golden Heraldic Shield & Crossed Swords Crest (Biểu tượng Khiên Hiệp Sĩ mạ vàng)
		var b_shield := MeshInstance3D.new()
		var bsh_box := BoxMesh.new()
		bsh_box.size = Vector3(0.85, 1.05, 0.12)
		b_shield.mesh = bsh_box
		b_shield.position = Vector3(0.0, 2.75, 1.45)
		var bsh_mat := StandardMaterial3D.new()
		bsh_mat.albedo_color = Color(0.96, 0.82, 0.25)
		bsh_mat.metallic = 0.75
		bsh_mat.roughness = 0.32
		bsh_mat.emission_enabled = true
		bsh_mat.emission = Color(0.85, 0.65, 0.15)
		bsh_mat.emission_energy_multiplier = 0.7
		b_shield.material_override = bsh_mat
		bv.add_child(b_shield)

		# War Banner Mast (Cột quân kỳ cao 5.5m với lá cờ chiến phấp phới)
		var b_mast := MeshInstance3D.new()
		var bm_cyl := CylinderMesh.new()
		bm_cyl.top_radius = 0.05
		bm_cyl.bottom_radius = 0.08
		bm_cyl.height = 5.2
		b_mast.mesh = bm_cyl
		b_mast.position = Vector3(-1.9, 2.6, 1.8)
		b_mast.material_override = corbel_mat
		bv.add_child(b_mast)

		var b_flag := MeshInstance3D.new()
		var bf_box := BoxMesh.new()
		bf_box.size = Vector3(0.04, 0.95, 1.35)
		b_flag.mesh = bf_box
		b_flag.position = Vector3(-1.9, 4.6, 2.45)
		var bflag_mat := StandardMaterial3D.new()
		bflag_mat.albedo_color = Color(0.85, 0.20, 0.18)
		b_flag.material_override = bflag_mat
		bv.add_child(b_flag)

		# Forecourt Weapon Rack & Training Dummy (Giá vũ khí & bia tập đánh)
		var rack := MeshInstance3D.new()
		var r_box := BoxMesh.new()
		r_box.size = Vector3(1.2, 0.85, 0.35)
		rack.mesh = r_box
		rack.position = Vector3(1.4, 0.65, 1.8)
		var rack_mat := StandardMaterial3D.new()
		rack_mat.albedo_color = Color(0.48, 0.35, 0.22)
		rack.material_override = rack_mat
		bv.add_child(rack)

		var bar_lbl: Label3D = barracks_mesh.get_node_or_null("BarracksLabel")
		if bar_lbl != null:
			bar_lbl.text = "🛡️ NHÀ CHIẾN LƯỢC (STRATEGIC HOUSE)"
			bar_lbl.position = Vector3(0.0, 5.2, 0.0)
	if barracks_btn != null:
		barracks_btn.text = "🛡️ Nhà Chiến Lược"

	if barracks_body != null and barracks_body.has_node("CollisionShape3D"):
		var b_shape: CollisionShape3D = barracks_body.get_node("CollisionShape3D")
		var bs := BoxShape3D.new()
		bs.size = Vector3(5.6, 4.5, 5.6)
		b_shape.shape = bs
		b_shape.position = Vector3(0.0, 2.25, 0.0)

	# 9B. INFIRMARY (✚ Bệnh Xá Thánh Điện & Hậu Cần Dược Liệu)
	if infirmary_mesh != null:
		infirmary_mesh.mesh = null # Remove legacy plain block box
		var old_iv := infirmary_mesh.get_node_or_null("InfirmaryVisuals")
		if old_iv != null:
			old_iv.queue_free()

		var iv := Node3D.new()
		iv.name = "InfirmaryVisuals"
		infirmary_mesh.add_child(iv)

		# Polished Marble Foundation Plinth (5.6m x 0.4m x 5.6m)
		var i_plinth := MeshInstance3D.new()
		var ip_box := BoxMesh.new()
		ip_box.size = Vector3(5.6, 0.4, 5.6)
		i_plinth.mesh = ip_box
		i_plinth.position = Vector3(0.0, 0.2, 0.0)
		var iplinth_mat := StandardMaterial3D.new()
		iplinth_mat.albedo_color = Color(0.72, 0.76, 0.80)
		i_plinth.material_override = iplinth_mat
		iv.add_child(i_plinth)

		# Sanctuary Hall Body (4.5m x 2.6m x 3.8m)
		var i_hall := MeshInstance3D.new()
		var ih_box := BoxMesh.new()
		ih_box.size = Vector3(4.5, 2.6, 3.8)
		i_hall.mesh = ih_box
		ih_box.material = null
		i_hall.position = Vector3(0.0, 1.7, -0.4)
		var ihall_mat := StandardMaterial3D.new()
		ihall_mat.albedo_color = Color(0.86, 0.90, 0.92) # Pure White Sanctuary Stone
		ihall_mat.roughness = 0.65
		i_hall.material_override = ihall_mat
		iv.add_child(i_hall)

		# Healing Emerald Roof (4.8m x 1.6m x 4.2m)
		var i_roof := MeshInstance3D.new()
		var ir_prism := PrismMesh.new()
		ir_prism.size = Vector3(4.8, 1.6, 4.2)
		i_roof.mesh = ir_prism
		i_roof.position = Vector3(0.0, 3.8, -0.4)
		var iroof_mat := StandardMaterial3D.new()
		iroof_mat.albedo_color = Color(0.18, 0.65, 0.48) # Emerald Green Healing Slate
		iroof_mat.roughness = 0.62
		i_roof.material_override = iroof_mat
		iv.add_child(i_roof)

		# Arched Portico Columns (Hàng cột vòm mặt tiền)
		for col_x in [-1.8, -0.6, 0.6, 1.8]:
			var col := MeshInstance3D.new()
			var c_cyl := CylinderMesh.new()
			c_cyl.top_radius = 0.16
			c_cyl.bottom_radius = 0.22
			c_cyl.height = 2.4
			col.mesh = c_cyl
			col.position = Vector3(col_x, 1.4, 1.45)
			col.material_override = ihall_mat
			iv.add_child(col)

		# Portico Canopy Roof (Mái hiên vòm)
		var canopy := MeshInstance3D.new()
		var can_box := BoxMesh.new()
		can_box.size = Vector3(4.2, 0.28, 1.2)
		canopy.mesh = can_box
		canopy.position = Vector3(0.0, 2.68, 1.45)
		canopy.material_override = iroof_mat
		iv.add_child(canopy)

		# Central Healing Cupola Spire (Chóp tháp ngọc bích trung tâm)
		var spire_dome := MeshInstance3D.new()
		var sd_cyl := CylinderMesh.new()
		sd_cyl.top_radius = 0.55
		sd_cyl.bottom_radius = 0.75
		sd_cyl.height = 1.1
		spire_dome.mesh = sd_cyl
		spire_dome.position = Vector3(0.0, 4.95, -0.4)
		spire_dome.material_override = ihall_mat
		iv.add_child(spire_dome)

		# Levitating Glowing Emerald Healing Cross (Thánh Giá Trị Liệu 3D phát sáng lơ lửng)
		var cross_root := Node3D.new()
		cross_root.position = Vector3(0.0, 6.2, -0.4)

		var cross_v := MeshInstance3D.new()
		var cv_box := BoxMesh.new()
		cv_box.size = Vector3(0.24, 1.15, 0.24)
		cross_v.mesh = cv_box
		var cross_mat := StandardMaterial3D.new()
		cross_mat.albedo_color = Color(0.35, 1.0, 0.65)
		cross_mat.emission_enabled = true
		cross_mat.emission = Color(0.22, 0.95, 0.55)
		cross_mat.emission_energy_multiplier = 2.4
		cross_v.material_override = cross_mat
		cross_root.add_child(cross_v)

		var cross_h := MeshInstance3D.new()
		var ch_box := BoxMesh.new()
		ch_box.size = Vector3(0.85, 0.24, 0.24)
		cross_h.mesh = ch_box
		cross_h.material_override = cross_mat
		cross_root.add_child(cross_h)
		iv.add_child(cross_root)

		# Logistics & Apothecary Staging Area (Bao lương thực, thùng gỗ tiếp tế & vạc sắc thuốc)
		var crate1 := MeshInstance3D.new()
		var cr1_box := BoxMesh.new()
		cr1_box.size = Vector3(0.55, 0.55, 0.55)
		crate1.mesh = cr1_box
		crate1.position = Vector3(-1.6, 0.65, 1.7)
		var cr_mat := StandardMaterial3D.new()
		cr_mat.albedo_color = Color(0.58, 0.42, 0.25)
		crate1.material_override = cr_mat
		iv.add_child(crate1)

		var cauldron := MeshInstance3D.new()
		var ca_cyl := CylinderMesh.new()
		ca_cyl.top_radius = 0.35
		ca_cyl.bottom_radius = 0.28
		ca_cyl.height = 0.52
		cauldron.mesh = ca_cyl
		cauldron.position = Vector3(1.6, 0.62, 1.7)
		var ca_mat := StandardMaterial3D.new()
		ca_mat.albedo_color = Color(0.25, 0.28, 0.32)
		cauldron.material_override = ca_mat
		iv.add_child(cauldron)

		var inf_lbl: Label3D = infirmary_mesh.get_node_or_null("InfirmaryLabel")
		if inf_lbl != null:
			inf_lbl.text = "✚ RECOVERY CENTER – TRUNG TÂM HỒI PHỤC"
			inf_lbl.position = Vector3(0.0, 7.2, 0.0)

	if infirmary_body != null and infirmary_body.has_node("CollisionShape3D"):
		var i_shape: CollisionShape3D = infirmary_body.get_node("CollisionShape3D")
		var ishape := BoxShape3D.new()
		ishape.size = Vector3(5.6, 4.5, 5.6)
		i_shape.shape = ishape
		i_shape.position = Vector3(0.0, 2.25, 0.0)

func _setup_landmark_metadata() -> void:
	bonfire_body.set_meta("interactable_type", "LANDMARK")
	bonfire_body.set_meta("landmark_code", "FOUNTAIN")

	altar_body.set_meta("interactable_type", "LANDMARK")
	altar_body.set_meta("landmark_code", "SUMMON_ALTAR")

	portal_body.set_meta("interactable_type", "LANDMARK")
	portal_body.set_meta("landmark_code", "DUNGEON_PORTAL")

	barracks_body.set_meta("interactable_type", "LANDMARK")
	barracks_body.set_meta("landmark_code", "BARRACKS")

	infirmary_body.set_meta("interactable_type", "LANDMARK")
	infirmary_body.set_meta("landmark_code", "INFIRMARY")

func _spawn_stacked_3d_floors_and_plots() -> void:
	for child in zones_container.get_children():
		child.queue_free()
	for child in plots_container.get_children():
		child.queue_free()
	_plot_nodes.clear()
	_floor_platforms.clear()
	_floor_banners.clear()
	_floor_trans_map.clear()

	# Tier 1 & Tier 2 Floating Header Banners
	var tier_configs := [
		{ "floor": 1, "pos": Vector3(0.0, 6.2, -46.5), "title": "🏰 HẠ THÀNH TẦNG 1 (100m × 100m)" },
		{ "floor": 2, "pos": Vector3(-80.0, FLOOR_HEIGHT + 6.2, -46.5), "title": "👑 THƯỢNG THÀNH TẦNG 2 (60m × 100m)" }
	]
	for cfg in tier_configs:
		var f_num: int = cfg["floor"]
		var f_banner := Label3D.new()
		f_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		f_banner.no_depth_test = true
		f_banner.font_size = 25
		f_banner.outline_size = 6
		f_banner.position = cfg["pos"]
		f_banner.text = cfg["title"]
		f_banner.modulate = Color(0.65, 0.94, 1.0)
		zones_container.add_child(f_banner)
		_floor_banners[f_num] = f_banner

	# Instantiate all 48 Plot Nodes (hidden when empty; positioned on the grid when constructed)
	for plot_num in range(1, MAX_TOTAL_PLOTS + 1):
		var plot_node: BasePlot3D = BASE_PLOT_SCENE.instantiate()
		plot_node.plot_index = plot_num
		plot_node.zone_index = 1
		plots_container.add_child(plot_node)
		_plot_nodes[plot_num] = plot_node

# ==============================================================================
# GRID-BASED FREE PLACEMENT & ROAD BUILDING SYSTEM (2m x 2m UNIFIED GRID)
# ==============================================================================

func _get_structure_footprint_size(structure_id: String) -> Vector2i:
	if structure_id == "FOUNTAIN" or structure_id == "SUMMON_ALTAR":
		return Vector2i(4, 4) # 8m x 8m
	elif structure_id == "BARRACKS" or structure_id == "INFIRMARY":
		return Vector2i(3, 3) # 6m x 6m
	return Vector2i(2, 2) # 4m x 4m for PLOT:1..48

func _get_structure_display_name(structure_id: String) -> String:
	match structure_id:
		"FOUNTAIN":
			return "⛲ Đài Phun Nước"
		"SUMMON_ALTAR":
			return "✨ Đài Triệu Hồi"
		"BARRACKS":
			return "🛡️ Nhà Chiến Lược (Strategic House)"
		"INFIRMARY":
			return "✚ Recovery Center – Trung Tâm Hồi Phục"
		_:
			if structure_id.begins_with("PLOT:"):
				var p_idx := int(structure_id.trim_prefix("PLOT:"))
				var b := GameState.get_building_on_plot(p_idx)
				if not b.is_empty():
					return str(b.get("typeName", b.get("buildingType", "Công trình #%d" % p_idx)))
				return "Ô Công Trình #%d" % p_idx
			return structure_id

func _world_to_grid_cell(world_pos: Vector3) -> Vector2i:
	var gx := int(floor((world_pos.x - GRID_ORIGIN_X) / GRID_CELL_SIZE))
	var gz := int(floor((world_pos.z - GRID_ORIGIN_Z) / GRID_CELL_SIZE))
	return Vector2i(gx, gz)

func _grid_footprint_to_world_center(gx: int, gz: int, size_cells: Vector2i) -> Vector3:
	var wx := GRID_ORIGIN_X + (float(gx) + float(size_cells.x) * 0.5) * GRID_CELL_SIZE
	var wz := GRID_ORIGIN_Z + (float(gz) + float(size_cells.y) * 0.5) * GRID_CELL_SIZE
	var wy := 0.0 if gx >= 0 else FLOOR_HEIGHT
	return Vector3(wx, wy, wz)

func _is_cell_in_reserved_zone(gx: int, gz: int) -> bool:
	# 1. Fixed East Gate entrance clearance (X near +48.2, Z near 0.0 -> gx in [45, 49], gz in [21, 28])
	if gx >= 45 and gx <= 49 and gz >= 21 and gz <= 28:
		return true
	# 2. Grand Central Recessed Staircase clearance (X in [-62.0, -50.0] inside Tier 2, plus front portal in Tier 1)
	# Grid: gx in [-6, 3], gz in [23, 26]
	if gx >= -6 and gx <= 3 and gz >= 23 and gz <= 26:
		return true
	return false

func _is_footprint_valid(gx: int, gz: int, size_cells: Vector2i, ignore_structure_id: String = "") -> bool:
	var w := size_cells.x
	var h := size_cells.y
	if gz < GRID_GZ_MIN or (gz + h) > GRID_GZ_MAX:
		return false
	var on_tier1 := (gx >= TIER1_GX_MIN and (gx + w) <= TIER1_GX_MAX)
	var on_tier2 := (gx >= TIER2_GX_MIN and (gx + w) <= TIER2_GX_MAX)
	if not on_tier1 and not on_tier2:
		return false

	for cx in range(gx, gx + w):
		for cz in range(gz, gz + h):
			if _is_cell_in_reserved_zone(cx, cz):
				return false

	for other_id in _grid_structures.keys():
		var s_id := str(other_id)
		if s_id == ignore_structure_id:
			continue
		if s_id.begins_with("PLOT:"):
			var p_idx := int(s_id.trim_prefix("PLOT:"))
			if _plot_nodes.has(p_idx):
				var p_node: BasePlot3D = _plot_nodes[p_idx]
				if p_node.building_data.is_empty():
					continue
			else:
				var b_data := GameState.get_building_on_plot(p_idx)
				if b_data.is_empty():
					continue
		var entry: Dictionary = _grid_structures[s_id]
		var ox := int(entry.get("gx", 0))
		var oz := int(entry.get("gz", 0))
		var osize := _get_structure_footprint_size(s_id)
		var overlap_x := (gx < ox + osize.x) and (gx + w > ox)
		var overlap_z := (gz < oz + osize.y) and (gz + h > oz)
		if overlap_x and overlap_z:
			return false

	return true

func _get_default_plot_grid_coord(plot_num: int) -> Vector2i:
	# Clean Master-Plan distribution for all 48 2x2 Plots along the Castle Avenues (no road overlap)
	var idx := plot_num - 1
	var coords_table := [
		# Tier 1 - West-North Quarter (Plots 1..4): Along Avenue North (gz=18, facing South)
		Vector2i(6, 18), Vector2i(10, 18), Vector2i(14, 18), Vector2i(17, 18),
		# Tier 1 - West-South Quarter (Plots 5..8): Along Avenue South (gz=30, facing North)
		Vector2i(6, 30), Vector2i(10, 30), Vector2i(14, 30), Vector2i(17, 30),
		# Tier 1 - West-North Secondary (Plots 9..12): North flank (gz=12)
		Vector2i(6, 12), Vector2i(10, 12), Vector2i(14, 12), Vector2i(17, 12),
		# Tier 1 - West-South Secondary (Plots 13..16): South flank (gz=36)
		Vector2i(6, 36), Vector2i(10, 36), Vector2i(14, 36), Vector2i(17, 36),
		# Tier 1 - East Gate North Boulevard (Plots 17..20): North of East Gate (gz=20)
		Vector2i(31, 20), Vector2i(35, 20), Vector2i(39, 20), Vector2i(43, 20),
		# Tier 1 - East Gate South Boulevard (Plots 21..24): South of East Gate (gz=28)
		Vector2i(31, 28), Vector2i(35, 28), Vector2i(39, 28), Vector2i(43, 28),
		# Tier 1 - Barracks & Infirmary Wings (Plots 25..32)
		Vector2i(19, 7), Vector2i(27, 7), Vector2i(19, 10), Vector2i(27, 10),
		Vector2i(19, 39), Vector2i(27, 39), Vector2i(19, 36), Vector2i(27, 36),
		# Tier 2 - Upper Citadel North Terrace (Plots 33..40)
		Vector2i(-6, 18), Vector2i(-10, 18), Vector2i(-22, 18), Vector2i(-26, 18),
		Vector2i(-6, 12), Vector2i(-10, 12), Vector2i(-22, 12), Vector2i(-26, 12),
		# Tier 2 - Upper Citadel South Terrace (Plots 41..48)
		Vector2i(-6, 30), Vector2i(-10, 30), Vector2i(-22, 30), Vector2i(-26, 30),
		Vector2i(-6, 36), Vector2i(-10, 36), Vector2i(-22, 36), Vector2i(-26, 36)
	]
	if idx >= 0 and idx < coords_table.size():
		return coords_table[idx]
	return Vector2i(6 + (idx % 6) * 4, 18)

func _load_or_init_castle_grid_layout() -> void:
	_grid_structures.clear()
	_grid_roads.clear()

	# 1. Default Landmark Placements (Aligned with Royal Master Plan Grid)
	_grid_structures["FOUNTAIN"] = { "gx": 23, "gz": 23, "rot": 0 }      # Center of Tier 1 (4x4, World X=0.0, Z=0.0)
	_grid_structures["SUMMON_ALTAR"] = { "gx": -17, "gz": 23, "rot": 0 } # Center of Tier 2 (4x4, World X=-80.0, Z=0.0)
	_grid_structures["BARRACKS"] = { "gx": 23, "gz": 6, "rot": 0 }       # North Courtyard Tier 1 (3x3, gx=23..25, gz=6..8, aligned with N-S Avenue)
	_grid_structures["INFIRMARY"] = { "gx": 23, "gz": 40, "rot": 0 }     # South Courtyard Tier 1 (3x3, gx=23..25, gz=40..42, aligned with N-S Avenue)

	# 2. Default Plot Positions (Plots 1..48)
	for p_num in range(1, MAX_TOTAL_PLOTS + 1):
		var def_cell := _get_default_plot_grid_coord(p_num)
		_grid_structures["PLOT:%d" % p_num] = { "gx": def_cell.x, "gz": def_cell.y, "rot": 0 }

	# 3. Default Grand Cobblestone Road Network connecting All Landmarks & Avenues
	_populate_default_road_network()

	if FileAccess.file_exists(CASTLE_LAYOUT_SAVE_PATH):
		var f := FileAccess.open(CASTLE_LAYOUT_SAVE_PATH, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary and int(parsed.get("version", 0)) >= 4:
				var saved_structs: Variant = parsed.get("structures", {})
				if saved_structs is Dictionary:
					for k in saved_structs.keys():
						if saved_structs[k] is Dictionary:
							_grid_structures[str(k)] = saved_structs[k]
				var saved_roads: Variant = parsed.get("roads", {})
				if saved_roads is Dictionary and not saved_roads.is_empty():
					_grid_roads.clear()
					for rk in saved_roads.keys():
						if bool(saved_roads[rk]):
							_grid_roads[str(rk)] = true

func _populate_default_road_network() -> void:
	# --- TIER 1 (HẠ THÀNH) ROYAL CENTRAL THOROUGHFARE ---
	# 1. Grand East Boulevard (East Gate to Fountain Plaza): gz=24, 25 from gx=46 down to gx=28
	for gx in range(28, 47):
		_grid_roads["%d,24" % gx] = true
		_grid_roads["%d,25" % gx] = true

	# 2. Fountain Grand Plaza Ring: 2-cell wide cobblestone belt around Fountain (gx in [23, 26], gz in [23, 26])
	for gx in range(21, 29):
		for gz in range(21, 29):
			if not (gx >= 23 and gx <= 26 and gz >= 23 and gz <= 26):
				_grid_roads["%d,%d" % [gx, gz]] = true

	# 3. Grand West Boulevard (Fountain Plaza straight to Grand Central Staircase):
	# Direct royal avenue along gz=24, 25 from gx=21 straight to staircase portal at gx=0
	for gx in range(0, 22):
		_grid_roads["%d,24" % gx] = true
		_grid_roads["%d,25" % gx] = true

	# 4. North-South Central Avenue:
	# - North Avenue to Barracks (gz=9..20 along gx=24, 25)
	for gz in range(9, 21):
		_grid_roads["24,%d" % gz] = true
		_grid_roads["25,%d" % gz] = true
	# - South Avenue to Infirmary (gz=29..39 along gx=24, 25)
	for gz in range(29, 40):
		_grid_roads["24,%d" % gz] = true
		_grid_roads["25,%d" % gz] = true

	# --- TIER 2 (THƯỢNG THÀNH) ROYAL HIGH AVENUE ---
	# 5. Grand Avenue from top of Central Staircase (gx=-6) westward to Summon Altar Plaza (gx=-13):
	for gx in range(-13, -5):
		_grid_roads["%d,24" % gx] = true
		_grid_roads["%d,25" % gx] = true

	# 6. Tier 2 Cross Avenue along gx=-13, -12 (gz in [15, 34])
	for gz in range(15, 35):
		_grid_roads["-13,%d" % gz] = true
		_grid_roads["-12,%d" % gz] = true

	# 7. Summon Altar Grand Plaza Ring: Cobblestone belt around Summon Altar (gx in [-17, -14], gz in [23, 26])
	for gx in range(-19, -11):
		for gz in range(21, 29):
			if not (gx >= -17 and gx <= -14 and gz >= 23 and gz <= 26):
				_grid_roads["%d,%d" % [gx, gz]] = true

func _save_castle_grid_layout() -> void:
	var payload := {
		"version": 4,
		"structures": _grid_structures,
		"roads": _grid_roads
	}
	var f := FileAccess.open(CASTLE_LAYOUT_SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload, "\t"))
		f.close()

func _setup_grid_overlay_and_roads() -> void:
	if _roads_container != null and is_instance_valid(_roads_container):
		_roads_container.queue_free()
	_roads_container = Node3D.new()
	_roads_container.name = "CastleRoadsContainer"
	add_child(_roads_container)
	_road_mesh_nodes.clear()
	_rebuild_all_road_meshes()

	if _grid_overlay_root != null and is_instance_valid(_grid_overlay_root):
		_grid_overlay_root.queue_free()
	_grid_overlay_root = Node3D.new()
	_grid_overlay_root.name = "CastleGridOverlay"
	_grid_overlay_root.visible = false
	add_child(_grid_overlay_root)

	# Build subtle grid lines on Tier 1 and Tier 2 so the 2m x 2m grid is crisp during build/move/road modes
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.38, 0.82, 1.0, 0.24)
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Tier 1 grid lines (X in [-48, 48], Z in [-48, 48], Y = 0.03)
	for gx in range(1, 50, 2):
		var wx := GRID_ORIGIN_X + float(gx) * GRID_CELL_SIZE
		var l_inst := MeshInstance3D.new()
		var l_box := BoxMesh.new()
		l_box.size = Vector3(0.05, 0.02, 96.0)
		l_inst.mesh = l_box
		l_inst.position = Vector3(wx, 0.03, 0.0)
		l_inst.material_override = line_mat
		_grid_overlay_root.add_child(l_inst)
	for gz in range(1, 50, 2):
		var wz := GRID_ORIGIN_Z + float(gz) * GRID_CELL_SIZE
		var l_inst := MeshInstance3D.new()
		var l_box := BoxMesh.new()
		l_box.size = Vector3(96.0, 0.02, 0.05)
		l_inst.mesh = l_box
		l_inst.position = Vector3(0.0, 0.03, wz)
		l_inst.material_override = line_mat
		_grid_overlay_root.add_child(l_inst)

	# Tier 2 grid lines (X in [-108, -52], Z in [-48, 48], Y = 5.23)
	for gx in range(-29, 0, 2):
		var wx := GRID_ORIGIN_X + float(gx) * GRID_CELL_SIZE
		var l_inst := MeshInstance3D.new()
		var l_box := BoxMesh.new()
		l_box.size = Vector3(0.05, 0.02, 96.0)
		l_inst.mesh = l_box
		l_inst.position = Vector3(wx, FLOOR_HEIGHT + 0.03, 0.0)
		l_inst.material_override = line_mat
		_grid_overlay_root.add_child(l_inst)
	for gz in range(1, 50, 2):
		var wz := GRID_ORIGIN_Z + float(gz) * GRID_CELL_SIZE
		var l_inst := MeshInstance3D.new()
		var l_box := BoxMesh.new()
		l_box.size = Vector3(56.0, 0.02, 0.05)
		l_inst.mesh = l_box
		l_inst.position = Vector3(-80.0, FLOOR_HEIGHT + 0.03, wz)
		l_inst.material_override = line_mat
		_grid_overlay_root.add_child(l_inst)

	# Ghost Footprint Preview Node
	_grid_ghost_root = Node3D.new()
	_grid_ghost_root.name = "GridGhostPreview"
	_grid_overlay_root.add_child(_grid_ghost_root)

	_grid_ghost_mesh = MeshInstance3D.new()
	var g_box := BoxMesh.new()
	g_box.size = Vector3(4.0, 0.25, 4.0)
	_grid_ghost_mesh.mesh = g_box
	_grid_ghost_mesh.position = Vector3(0.0, 0.14, 0.0)
	_grid_ghost_root.add_child(_grid_ghost_mesh)

	_grid_ghost_border = MeshInstance3D.new()
	var gb_box := BoxMesh.new()
	gb_box.size = Vector3(4.15, 0.08, 4.15)
	_grid_ghost_border.mesh = gb_box
	_grid_ghost_border.position = Vector3(0.0, 0.05, 0.0)
	_grid_ghost_root.add_child(_grid_ghost_border)

	_grid_ghost_label = Label3D.new()
	_grid_ghost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_grid_ghost_label.no_depth_test = true
	_grid_ghost_label.font_size = 22
	_grid_ghost_label.outline_size = 6
	_grid_ghost_label.position = Vector3(0.0, 2.2, 0.0)
	_grid_ghost_root.add_child(_grid_ghost_label)

func _rebuild_all_road_meshes() -> void:
	if _roads_container == null:
		return
	for child in _roads_container.get_children():
		child.queue_free()
	_road_mesh_nodes.clear()
	for rk in _grid_roads.keys():
		var parts := str(rk).split(",")
		if parts.size() == 2:
			_spawn_single_road_tile_mesh(int(parts[0]), int(parts[1]))

func _spawn_single_road_tile_mesh(gx: int, gz: int) -> void:
	var key := "%d,%d" % [gx, gz]
	if _road_mesh_nodes.has(key) and is_instance_valid(_road_mesh_nodes[key]):
		_road_mesh_nodes[key].queue_free()

	var center := _grid_footprint_to_world_center(gx, gz, Vector2i(1, 1))
	var tile_root := Node3D.new()
	tile_root.position = center + Vector3(0.0, 0.04, 0.0)

	var cobble_mat := StandardMaterial3D.new()
	cobble_mat.albedo_color = Color(0.31, 0.36, 0.45)
	cobble_mat.roughness = 0.72

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.44, 0.50, 0.60)
	trim_mat.roughness = 0.65

	var slab := MeshInstance3D.new()
	var s_box := BoxMesh.new()
	s_box.size = Vector3(1.88, 0.08, 1.88)
	slab.mesh = s_box
	slab.material_override = cobble_mat
	tile_root.add_child(slab)

	var curb := MeshInstance3D.new()
	var c_box := BoxMesh.new()
	c_box.size = Vector3(1.98, 0.04, 1.98)
	curb.mesh = c_box
	curb.position = Vector3(0.0, -0.01, 0.0)
	curb.material_override = trim_mat
	tile_root.add_child(curb)

	_roads_container.add_child(tile_root)
	_road_mesh_nodes[key] = tile_root

func _set_road_at_cell(gx: int, gz: int, place_road: bool) -> bool:
	if gz < GRID_GZ_MIN or gz >= GRID_GZ_MAX:
		return false
	if not ((gx >= TIER1_GX_MIN and gx < TIER1_GX_MAX) or (gx >= TIER2_GX_MIN and gx < TIER2_GX_MAX)):
		return false
	var key := "%d,%d" % [gx, gz]
	if place_road:
		if _grid_roads.has(key):
			return false
		_grid_roads[key] = true
		_spawn_single_road_tile_mesh(gx, gz)
		_save_castle_grid_layout()
		return true
	else:
		if not _grid_roads.has(key):
			return false
		_grid_roads.erase(key)
		if _road_mesh_nodes.has(key) and is_instance_valid(_road_mesh_nodes[key]):
			_road_mesh_nodes[key].queue_free()
		_road_mesh_nodes.erase(key)
		_save_castle_grid_layout()
		return true

func _apply_all_grid_transforms() -> void:
	var arch := $BaseArchitecture
	if arch == null:
		return

	# 1. FOUNTAIN (CentralBonfire + CentralPlazaDisc synced together)
	var f_entry: Dictionary = _grid_structures.get("FOUNTAIN", { "gx": 23, "gz": 23, "rot": 0 })
	var f_pos := _grid_footprint_to_world_center(int(f_entry.get("gx", 23)), int(f_entry.get("gz", 23)), Vector2i(4, 4))
	var bonfire_node := arch.get_node_or_null("CentralBonfire") as Node3D
	if bonfire_node != null:
		bonfire_node.position = f_pos
		bonfire_node.rotation_degrees.y = float(int(f_entry.get("rot", 0)))
	var plaza_disc := arch.get_node_or_null("CentralPlazaDisc") as Node3D
	if plaza_disc != null:
		plaza_disc.position = f_pos + Vector3(0.0, 0.05, 0.0)

	# 2. SUMMON_ALTAR
	var a_entry: Dictionary = _grid_structures.get("SUMMON_ALTAR", { "gx": -17, "gz": 23, "rot": 0 })
	var a_pos := _grid_footprint_to_world_center(int(a_entry.get("gx", -17)), int(a_entry.get("gz", 23)), Vector2i(4, 4))
	if summon_altar_mesh != null:
		summon_altar_mesh.position = a_pos + Vector3(0.0, 0.75, 0.0)
		summon_altar_mesh.rotation_degrees.y = float(int(a_entry.get("rot", 0)))
	if altar_body != null:
		if altar_body.get_parent() == summon_altar_mesh:
			altar_body.position = Vector3.ZERO
		else:
			altar_body.position = a_pos

	# 3. BARRACKS
	var b_entry: Dictionary = _grid_structures.get("BARRACKS", { "gx": 23, "gz": 6, "rot": 0 })
	var b_pos := _grid_footprint_to_world_center(int(b_entry.get("gx", 23)), int(b_entry.get("gz", 6)), Vector2i(3, 3))
	if barracks_mesh != null:
		barracks_mesh.position = b_pos
		barracks_mesh.rotation_degrees.y = float(int(b_entry.get("rot", 0)))

	# 4. INFIRMARY
	var i_entry: Dictionary = _grid_structures.get("INFIRMARY", { "gx": 23, "gz": 40, "rot": 0 })
	var i_pos := _grid_footprint_to_world_center(int(i_entry.get("gx", 23)), int(i_entry.get("gz", 40)), Vector2i(3, 3))
	if infirmary_mesh != null:
		infirmary_mesh.position = i_pos
		infirmary_mesh.rotation_degrees.y = float(int(i_entry.get("rot", 0)))

	# 5. All 48 Plot Nodes
	for p_num in _plot_nodes.keys():
		var plot_node: BasePlot3D = _plot_nodes[p_num]
		var p_key := "PLOT:%d" % int(p_num)
		if not _grid_structures.has(p_key):
			var def_c := _get_default_plot_grid_coord(int(p_num))
			_grid_structures[p_key] = { "gx": def_c.x, "gz": def_c.y, "rot": 0 }
		var p_entry: Dictionary = _grid_structures[p_key]
		var pgx := int(p_entry.get("gx", 10))
		var pgz := int(p_entry.get("gz", 10))
		var prot := int(p_entry.get("rot", 0))
		var p_pos := _grid_footprint_to_world_center(pgx, pgz, Vector2i(2, 2))
		plot_node.global_position = p_pos
		plot_node.zone_index = 1 if pgx >= 0 else 2
		plot_node.set_grid_rotation_deg(prot)

func _build_floor_elevator_buttons() -> void:
	for child in floor_buttons_container.get_children():
		child.queue_free()
	_floor_buttons.clear()

	var header_lbl := floor_buttons_container.get_parent().get_node_or_null("FloorHeaderLabel") as Label
	if header_lbl != null:
		header_lbl.text = "🏰 LÂU ĐÀI & XÂY DỰNG"

	# 1. Camera Quick Focus Buttons (Seamless 2-Tier Castle)
	var panorama_btn := Button.new()
	panorama_btn.custom_minimum_size = Vector2(0, 32)
	panorama_btn.text = "🌐 Toàn Cảnh Lâu Đài"
	panorama_btn.pressed.connect(_show_all_floors_panorama)
	floor_buttons_container.add_child(panorama_btn)
	_panorama_btn = panorama_btn

	var tier2_btn := Button.new()
	tier2_btn.custom_minimum_size = Vector2(0, 32)
	tier2_btn.text = "👑 Thượng Thành T2 (60×100)"
	tier2_btn.pressed.connect(func(): _switch_to_lobby_floor(2))
	floor_buttons_container.add_child(tier2_btn)
	_floor_buttons[2] = tier2_btn

	var tier1_btn := Button.new()
	tier1_btn.custom_minimum_size = Vector2(0, 32)
	tier1_btn.text = "🏰 Hạ Thành T1 (100×100)"
	tier1_btn.pressed.connect(func(): _switch_to_lobby_floor(1))
	floor_buttons_container.add_child(tier1_btn)
	_floor_buttons[1] = tier1_btn

	var sep := HSeparator.new()
	floor_buttons_container.add_child(sep)

	# 2. Grid-Based Free Placement & Road System Controls
	_build_menu_btn = Button.new()
	_build_menu_btn.custom_minimum_size = Vector2(0, 34)
	_build_menu_btn.text = "🏗️ Xây Công Trình Mới"
	_build_menu_btn.pressed.connect(_open_free_grid_build_catalog)
	floor_buttons_container.add_child(_build_menu_btn)

	_move_mode_btn = Button.new()
	_move_mode_btn.custom_minimum_size = Vector2(0, 34)
	_move_mode_btn.text = "✥ Di Dời Công Trình"
	_move_mode_btn.pressed.connect(_toggle_move_structure_prompt)
	floor_buttons_container.add_child(_move_mode_btn)

	_road_paint_btn = Button.new()
	_road_paint_btn.custom_minimum_size = Vector2(0, 32)
	_road_paint_btn.text = "🧱 Lát Đường Đá (1×1)"
	_road_paint_btn.pressed.connect(func(): _enter_road_edit_mode(false))
	floor_buttons_container.add_child(_road_paint_btn)

	_road_erase_btn = Button.new()
	_road_erase_btn.custom_minimum_size = Vector2(0, 32)
	_road_erase_btn.text = "🧹 Xóa Đường Đá"
	_road_erase_btn.pressed.connect(func(): _enter_road_edit_mode(true))
	floor_buttons_container.add_child(_road_erase_btn)

	_cancel_grid_btn = Button.new()
	_cancel_grid_btn.custom_minimum_size = Vector2(0, 32)
	_cancel_grid_btn.text = "✖ Thoát Chế Độ Lưới (ESC)"
	_cancel_grid_btn.modulate = Color(1.0, 0.55, 0.55)
	_cancel_grid_btn.visible = false
	_cancel_grid_btn.pressed.connect(_exit_grid_edit_mode)
	floor_buttons_container.add_child(_cancel_grid_btn)

	var sep2 := HSeparator.new()
	floor_buttons_container.add_child(sep2)

	var manage_btn := Button.new()
	manage_btn.custom_minimum_size = Vector2(0, 32)
	manage_btn.text = "👥 Quản Lý Tướng Sảnh"
	manage_btn.pressed.connect(func(): _open_floor_hero_manager(_current_lobby_floor))
	floor_buttons_container.add_child(manage_btn)
	_manage_floor_heroes_btn = manage_btn

func _show_all_floors_panorama() -> void:
	_close_inspector()
	_panorama_mode = true
	camera_rig.focus_base_overview(Vector3(-30.0, 2.6, 0.0), 92.0, 0.65)
	status_banner_label.text = "🌐 Toàn cảnh Lâu Đài 2 Tầng Liền Khối (160m × 100m — Không chia render)."
	_refresh_hud()

func _switch_to_lobby_floor(floor_num: int) -> void:
	var next_floor := clampi(floor_num, 1, MAX_LOBBY_FLOORS)
	_current_lobby_floor = next_floor
	_panorama_mode = false
	var terrace_center := get_floor_terrace_center(_current_lobby_floor)
	camera_rig.focus_base_overview(terrace_center, 44.0 if _current_lobby_floor == 1 else 36.0, 0.55)
	status_banner_label.text = (
		"🏰 Đang quan sát Hạ Thành Tầng 1 (100m × 100m) — Cổng Đông cố định, mọi công trình khác tự do trên lưới!"
		if _current_lobby_floor == 1
		else "👑 Đang quan sát Thượng Thành Tầng 2 (60m × 100m) — Nối liền vách Tây Hạ Thành qua 2 cầu thang đá!"
	)
	_refresh_hud()

## Seamless 2-Tier Castle: No split rendering! Both tiers, all walls, landmarks, buildings, and heroes remain 100% visible.
func _apply_floor_focus_isolation(_active_floor_num: int, _animate: bool = true, _travel_dir: int = 0) -> void:
	var arch := $BaseArchitecture
	if arch != null:
		arch.visible = true
		arch.process_mode = Node.PROCESS_MODE_INHERIT
	_set_floor1_landmarks_interactive(true)
	if bonfire_light != null:
		bonfire_light.visible = true
	if dungeon_portal_mesh != null:
		dungeon_portal_mesh.visible = true
	_apply_floor1_architecture_transparency(0.0)

	for p_num in _plot_nodes.keys():
		var plot_node: BasePlot3D = _plot_nodes[p_num]
		plot_node.set_floor_focus_state(true, false, false, 0)

	for hid in _hero_actors.keys():
		var actor: UnitActor3D = _hero_actors[hid]
		if is_instance_valid(actor):
			actor.set_floor_focus_state(true, false)

func _set_terrace_node_transparency(_terrace_root: Node3D, _trans: float) -> void:
	pass

func _set_floor1_landmarks_interactive(enabled: bool) -> void:
	for body in [bonfire_body, altar_body, portal_body, barracks_body, infirmary_body]:
		if body != null and body.has_node("CollisionShape3D"):
			var shape: CollisionShape3D = body.get_node("CollisionShape3D")
			shape.disabled = not enabled

func _apply_floor1_architecture_transparency(_trans: float) -> void:
	_floor1_current_trans = 0.0

func _process(delta: float) -> void:
	_bonfire_time += delta * 2.2
	if bonfire_light != null:
		var base_energy := 3.2 if _lighting_mode == 2 else (2.4 if _lighting_mode == 1 else 1.8)
		bonfire_light.light_energy = base_energy + sin(_bonfire_time) * 0.22 + cos(_bonfire_time * 1.7) * 0.12
	if dungeon_portal_mesh != null:
		dungeon_portal_mesh.rotate_z(delta * 0.85)

	_auto_poll_timer += delta
	if _auto_poll_timer >= 6.0:
		_auto_poll_timer = 0.0
		if _has_pending_construction() and GameState.is_logged_in():
			_poll_construction_progress()

func _has_pending_construction() -> bool:
	var buildings: Array = GameState.base_overview.get("buildings", [])
	for b in buildings:
		if b is Dictionary:
			var st := str(b.get("status", "READY"))
			if st == "CONSTRUCTING" or st == "UPGRADING":
				return true
	return false

func _poll_construction_progress() -> void:
	var ok := await GameState.refresh_base_overview()
	if ok:
		_refresh_hud()
		_refresh_3d_plots()
		_re_render_inspector_if_open()

func _sync_all_from_backend() -> void:
	await GameState.refresh_profile()
	await GameState.refresh_base_overview()
	await GameState.refresh_inventory()
	await GameState.refresh_crafting()
	await GameState.refresh_heroes()
	await GameState.refresh_party()
	_refresh_hud()
	_refresh_3d_plots()
	_spawn_resident_heroes()
	_re_render_inspector_if_open()

func _format_num(val: int) -> String:
	var s := str(val)
	var res := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0:
			res = "," + res
		res = s[i] + res
		cnt += 1
	return res

func _get_constructed_building_count() -> int:
	var buildings: Array = GameState.base_overview.get("buildings", [])
	return buildings.size()

func _find_first_free_unlocked_plot_index() -> int:
	var max_plots := GameState.unlocked_plots
	for p_idx in range(1, max_plots + 1):
		var b_data := GameState.get_building_on_plot(p_idx)
		if b_data.is_empty():
			return p_idx
	return -1

func _refresh_hud() -> void:
	var m_name := GameState.master_name if GameState.master_name != "" else "Master"
	var built_cnt := _get_constructed_building_count()
	var max_plots := GameState.unlocked_plots

	master_info_label.text = "🏰 %s (Lv.%d) · Lâu Đài 2 Tầng · Công trình: %d/%d (Theo cấp Master)" % [
		m_name,
		GameState.master_level,
		built_cnt,
		max_plots
	]

	var gems := _format_num(GameState.gem_stones)
	var gold := _format_num(GameState.silver_coins)
	var scrolls := _format_num(GameState.normal_scrolls)
	var ration := _format_num(int(GameState.materials.get("RATION", 0)))

	resource_info_label.text = "💎 Đá Quý: %s   |   🪙 Vàng: %s   |   📜 Thiên Thư: %s   |   🍖 Khẩu Phần: %s" % [
		gems,
		gold,
		scrolls,
		ration
	]

	if portal_sub_label != null:
		portal_sub_label.text = "Đội hình xuất kích: %d/5 Tướng [Kéo-thả Tướng vào đây]" % GameState.active_party_ids.size()

	if _panorama_btn != null:
		if _panorama_mode:
			_panorama_btn.text = "▶ 🌐 Toàn Cảnh Lâu Đài"
			_panorama_btn.modulate = Color(1.0, 0.92, 0.45)
		else:
			_panorama_btn.text = "🌐 Toàn Cảnh Lâu Đài"
			_panorama_btn.modulate = Color(0.85, 0.92, 1.0)

	for f_num in _floor_buttons.keys():
		var btn: Button = _floor_buttons[f_num]
		var is_active := (int(f_num) == _current_lobby_floor and not _panorama_mode)
		var active_prefix := "▶ " if is_active else ""
		if int(f_num) == 1:
			btn.text = "%s🏰 Hạ Thành T1 (100×100)" % active_prefix
		else:
			btn.text = "%s👑 Thượng Thành T2 (60×100)" % active_prefix
		btn.modulate = Color(1.0, 0.92, 0.45) if is_active else Color(0.84, 0.95, 0.88)

	if _build_menu_btn != null:
		_build_menu_btn.text = "🏗️ Xây Công Trình (%d/%d)" % [built_cnt, max_plots]
		_build_menu_btn.modulate = Color(0.55, 1.0, 0.68) if _grid_edit_mode == GridEditMode.PLACE_NEW_BUILDING else Color(0.92, 0.96, 1.0)
	if _move_mode_btn != null:
		_move_mode_btn.modulate = Color(1.0, 0.88, 0.38) if _grid_edit_mode == GridEditMode.MOVE_STRUCTURE else Color(0.92, 0.96, 1.0)
	if _road_paint_btn != null:
		_road_paint_btn.modulate = Color(0.55, 0.92, 1.0) if _grid_edit_mode == GridEditMode.ROAD_PAINT else Color(0.92, 0.96, 1.0)
	if _road_erase_btn != null:
		_road_erase_btn.modulate = Color(1.0, 0.65, 0.55) if _grid_edit_mode == GridEditMode.ROAD_ERASE else Color(0.92, 0.96, 1.0)
	if _cancel_grid_btn != null:
		_cancel_grid_btn.visible = (_grid_edit_mode != GridEditMode.NONE)

	if _manage_floor_heroes_btn != null:
		_manage_floor_heroes_btn.text = "👥 Chọn Tướng Tầng %d" % _current_lobby_floor
		_manage_floor_heroes_btn.disabled = false

	# Update Expand Quota button (Master Level / Zone expansion)
	var exp_info: Dictionary = GameState.base_overview.get("expansion", {})
	if bool(exp_info.get("canExpand", true)) and GameState.base_zones < 6:
		var cost := int(exp_info.get("costSilver", 2000))
		expand_zone_btn.text = "🏗️ Mở Rộng Giới Hạn Ô (+%d Ô · 🪙 %s)" % [PLOTS_PER_FLOOR, _format_num(cost)]
		expand_zone_btn.disabled = false
	else:
		expand_zone_btn.text = "🏗️ Đã Mở Tối Đa (%d Ô)" % max_plots
		expand_zone_btn.disabled = true

func _refresh_3d_plots() -> void:
	var unlocked_plot_count := GameState.unlocked_plots
	var built_cnt := _get_constructed_building_count()

	if _floor_banners.has(1):
		var b1: Label3D = _floor_banners[1]
		b1.text = "🏰 HẠ THÀNH TẦNG 1 (100m × 100m) — Công trình: %d/%d" % [built_cnt, unlocked_plot_count]
	if _floor_banners.has(2):
		var b2: Label3D = _floor_banners[2]
		b2.text = "👑 THƯỢNG THÀNH TẦNG 2 (60m × 100m) — Tự Do Đặt Trên Lưới"

	_apply_all_grid_transforms()

	var has_medical_plot := false
	for plot_num in _plot_nodes.keys():
		var plot_node: BasePlot3D = _plot_nodes[plot_num]
		var is_unlocked := int(plot_num) <= unlocked_plot_count
		var b_data := GameState.get_building_on_plot(int(plot_num))
		if not b_data.is_empty() and str(b_data.get("buildingType", "")) == "MEDICAL":
			has_medical_plot = true
		plot_node.setup_plot(int(plot_num), is_unlocked, b_data)

	# Unify all infirmaries into 1 single Recovery Center: if a MEDICAL plot is built, hide the standalone Infirmary mesh
	if infirmary_mesh != null:
		infirmary_mesh.visible = not has_medical_plot
	if infirmary_body != null and infirmary_body.has_node("CollisionShape3D"):
		var ishape: CollisionShape3D = infirmary_body.get_node("CollisionShape3D")
		ishape.disabled = has_medical_plot

const MAX_HEROES_PER_FLOOR := 6

func _spawn_resident_heroes() -> void:
	for child in heroes_container.get_children():
		child.queue_free()
	_hero_actors.clear()

	var roster := GameState.heroes
	if roster.is_empty():
		roster = [
			{ "id": "preview-1", "name": "Aaron", "rarity": 4, "level": 12, "classCode": "WARRIOR", "hp": 420, "maxHp": 420 },
			{ "id": "preview-2", "name": "Jenna", "rarity": 3, "level": 10, "classCode": "THIEF", "hp": 310, "maxHp": 310 },
			{ "id": "preview-3", "name": "Eolka", "rarity": 4, "level": 11, "classCode": "MAGE", "hp": 290, "maxHp": 290 }
		]

	var worker_map := GameState.get_worker_assignment_map()
	var floor_heroes: Dictionary = { 1: [], 2: [] }
	var assigned_hero_ids: Dictionary = {}

	for f in range(1, MAX_LOBBY_FLOORS + 1):
		var custom_ids: Array = GameState.get_assigned_heroes_for_floor(f)
		for hid in custom_ids:
			if assigned_hero_ids.has(hid):
				continue
			var h_data := GameState.get_hero_by_id(hid)
			if not h_data.is_empty() and floor_heroes[f].size() < MAX_HEROES_PER_FLOOR:
				floor_heroes[f].append(h_data)
				assigned_hero_ids[hid] = f

	for h in roster:
		var hid := str(h.get("id", ""))
		if assigned_hero_ids.has(hid):
			continue
		if worker_map.has(hid):
			var w_entry: Dictionary = worker_map[hid]
			var b: Dictionary = w_entry.get("building", {})
			var p_idx := int(b.get("plotIndex", -1))
			if _plot_nodes.has(p_idx):
				var plot_node: BasePlot3D = _plot_nodes[p_idx]
				var f_idx: int = clampi(plot_node.zone_index, 1, MAX_LOBBY_FLOORS)
				if floor_heroes[f_idx].size() < MAX_HEROES_PER_FLOOR:
					floor_heroes[f_idx].append(h)
					assigned_hero_ids[hid] = f_idx

	for h in roster:
		var hid := str(h.get("id", ""))
		if assigned_hero_ids.has(hid):
			continue
		if GameState.active_party_ids.has(hid) and floor_heroes[1].size() < MAX_HEROES_PER_FLOOR:
			floor_heroes[1].append(h)
			assigned_hero_ids[hid] = 1

	for h in roster:
		var hid := str(h.get("id", ""))
		if assigned_hero_ids.has(hid):
			continue
		for f in range(1, MAX_LOBBY_FLOORS + 1):
			if floor_heroes[f].size() < MAX_HEROES_PER_FLOOR:
				floor_heroes[f].append(h)
				assigned_hero_ids[hid] = f
				break

	var arch := $BaseArchitecture
	var bonfire_node := arch.get_node_or_null("CentralBonfire") as Node3D if arch != null else null
	var f1_hub := bonfire_node.global_position if bonfire_node != null else get_floor_terrace_center(1)
	var f2_hub := summon_altar_mesh.global_position if (summon_altar_mesh != null and summon_altar_mesh.global_position.x < -50.0) else get_floor_terrace_center(2)
	f2_hub.y = FLOOR_HEIGHT

	for f_num in range(1, MAX_LOBBY_FLOORS + 1):
		var heroes_on_floor: Array = floor_heroes[f_num]
		var count := heroes_on_floor.size()
		if count == 0:
			continue

		var hub_center := f1_hub if f_num == 1 else f2_hub
		var terrace_center := get_floor_terrace_center(f_num)

		for i in range(count):
			var h: Dictionary = heroes_on_floor[i]
			var hid := str(h.get("id", ""))
			var actor: UnitActor3D = UNIT_ACTOR_SCENE.instantiate()
			heroes_container.add_child(actor)

			var angle := (TAU / float(count)) * float(i) + randf_range(-0.15, 0.15)
			var radius := randf_range(5.2, 8.8)

			var worker_info: Dictionary = {}
			if worker_map.has(hid):
				var w_entry: Dictionary = worker_map[hid]
				var b: Dictionary = w_entry.get("building", {})
				var p_idx := int(b.get("plotIndex", -1))
				var slot_idx := int(w_entry.get("slotIndex", 0))
				if _plot_nodes.has(p_idx):
					var plot_node: BasePlot3D = _plot_nodes[p_idx]
					worker_info = {
						"building": b,
						"stationPos": plot_node.get_worker_slot_global_position(slot_idx),
						"buildingCenter": plot_node.global_position
					}

			var default_pos := hub_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			default_pos.y = terrace_center.y
			var in_party := GameState.active_party_ids.has(hid)
			actor.floor_index = f_num
			actor.setup_base_resident(h, default_pos, worker_info, in_party, infirmary_mesh.global_position, terrace_center)
			actor.set_floor_focus_state(true, false)
			_hero_actors[hid] = actor

# ==============================================================================
# 3D RAYCAST INPUT, GRID PLACEMENT / RELOCATION / ROAD PAINTING & DRAG-AND-DROP
# ==============================================================================

func _project_mouse_to_castle_ground(screen_pos: Vector2) -> Vector3:
	var cam := camera_rig.get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)

	# Check Tier 2 plane (Y = 5.2, X in [-110, -50]) first
	var plane_t2 := Plane(Vector3.UP, FLOOR_HEIGHT)
	var hit_t2: Variant = plane_t2.intersects_ray(from, dir)
	if hit_t2 is Vector3:
		var pt2: Vector3 = hit_t2
		if pt2.x < -50.0 and pt2.x >= -112.0 and pt2.z >= -52.0 and pt2.z <= 52.0:
			return pt2

	# Otherwise intersect Tier 1 plane (Y = 0.0)
	var plane_t1 := Plane(Vector3.UP, 0.0)
	var hit_t1: Variant = plane_t1.intersects_ray(from, dir)
	if hit_t1 is Vector3:
		return hit_t1
	return Vector3.ZERO

func _project_mouse_to_active_floor(screen_pos: Vector2) -> Vector3:
	return _project_mouse_to_castle_ground(screen_pos)

func _exit_grid_edit_mode() -> void:
	_grid_edit_mode = GridEditMode.NONE
	_pending_build_code = ""
	_pending_build_name = ""
	_moving_structure_id = ""
	_is_painting_road_drag = false
	if _grid_overlay_root != null:
		_grid_overlay_root.visible = false
	_refresh_hud()

func _enter_place_new_building_mode(b_code: String, b_name: String) -> void:
	var free_plot := _find_first_free_unlocked_plot_index()
	if free_plot < 0:
		status_banner_label.text = "⚠️ Đã đạt giới hạn số lượng công trình theo cấp Master (%d/%d)! Hãy nâng cấp Master/Mở rộng hoặc phá dỡ bớt." % [
			_get_constructed_building_count(),
			GameState.unlocked_plots
		]
		return
	_grid_edit_mode = GridEditMode.PLACE_NEW_BUILDING
	_pending_build_code = b_code
	_pending_build_name = b_name
	_moving_structure_id = ""
	_placement_rot_deg = 0
	if _grid_overlay_root != null:
		_grid_overlay_root.visible = true
	status_banner_label.text = "🏗️ Chế độ Đặt [%s] (2×2 Ô): Di chuột trên lưới Tầng 1 hoặc Tầng 2 • Nhấn [R] xoay 90° • Chuột Trái để Xây • Chuột Phải/ESC để hủy." % b_name
	_refresh_hud()

func _start_moving_structure(structure_id: String) -> void:
	if structure_id == "DUNGEON_PORTAL" or structure_id == "":
		status_banner_label.text = "⛩️ Cổng Thành Phía Đông là công trình duy nhất gắn cố định vào tường thành!"
		return
	_grid_edit_mode = GridEditMode.MOVE_STRUCTURE
	_moving_structure_id = structure_id
	_pending_build_code = ""
	var cur_entry: Dictionary = _grid_structures.get(structure_id, { "gx": 23, "gz": 23, "rot": 0 })
	_placement_rot_deg = int(cur_entry.get("rot", 0))
	if _grid_overlay_root != null:
		_grid_overlay_root.visible = true
	var d_name := _get_structure_display_name(structure_id)
	var f_size := _get_structure_footprint_size(structure_id)
	status_banner_label.text = "✥ Đang di dời [%s] (%d×%d Ô): Chọn vị trí mới trên lưới Tầng 1 hoặc Tầng 2 • Nhấn [R] xoay 90° • Chuột Trái để Đặt." % [d_name, f_size.x, f_size.y]
	_refresh_hud()

func _toggle_move_structure_prompt() -> void:
	if _grid_edit_mode == GridEditMode.MOVE_STRUCTURE:
		_exit_grid_edit_mode()
		status_banner_label.text = "✅ Đã thoát chế độ Di Dời Công Trình."
		return
	# If a plot or movable landmark is currently open in Inspector, start moving it immediately
	if inspector_panel.visible and not _inspector_context.is_empty():
		var ctype := str(_inspector_context.get("type", ""))
		if ctype == "PLOT":
			var p_idx := int(_inspector_context.get("plot_index", -1))
			if p_idx > 0 and not GameState.get_building_on_plot(p_idx).is_empty():
				_start_moving_structure("PLOT:%d" % p_idx)
				return
		elif ctype == "LANDMARK":
			var l_code := str(_inspector_context.get("landmark_code", ""))
			if l_code != "" and l_code != "DUNGEON_PORTAL":
				_start_moving_structure(l_code)
				return
	_open_movable_structures_picker()

func _enter_road_edit_mode(erase_mode: bool) -> void:
	_grid_edit_mode = GridEditMode.ROAD_ERASE if erase_mode else GridEditMode.ROAD_PAINT
	_pending_build_code = ""
	_moving_structure_id = ""
	_is_painting_road_drag = false
	if _grid_overlay_root != null:
		_grid_overlay_root.visible = true
	status_banner_label.text = (
		"🧹 Chế độ Xóa Đường Đá (1×1 Ô): Nhấn hoặc giữ kéo Chuột Trái trên mặt đường để xóa • Chuột Phải/ESC để thoát."
		if erase_mode
		else "🧱 Chế độ Lát Đường Đá (1×1 Ô): Nhấn hoặc giữ kéo Chuột Trái trên lưới Tầng 1 / Tầng 2 để lát đường • Chuột Phải/ESC để thoát."
	)
	_refresh_hud()

func _update_grid_ghost_preview(screen_pos: Vector2) -> void:
	if _grid_edit_mode == GridEditMode.NONE or _grid_ghost_root == null:
		return

	var ground_pt := _project_mouse_to_castle_ground(screen_pos)
	var cell := _world_to_grid_cell(ground_pt)
	var size_cells := Vector2i(1, 1)
	var ignore_id := ""
	var label_txt := ""

	if _grid_edit_mode == GridEditMode.PLACE_NEW_BUILDING:
		size_cells = Vector2i(2, 2)
		cell.x -= 1
		cell.y -= 1
		_hover_valid = _is_footprint_valid(cell.x, cell.y, size_cells, "")
		label_txt = "🏗️ %s (%d°)\n[%s]" % [_pending_build_name, _placement_rot_deg, "Hợp lệ - Nhấn để Xây" if _hover_valid else "Không thể đặt tại đây"]
	elif _grid_edit_mode == GridEditMode.MOVE_STRUCTURE:
		size_cells = _get_structure_footprint_size(_moving_structure_id)
		ignore_id = _moving_structure_id
		cell.x -= int(float(size_cells.x) / 2.0)
		cell.y -= int(float(size_cells.y) / 2.0)
		_hover_valid = _is_footprint_valid(cell.x, cell.y, size_cells, ignore_id)
		var d_name := _get_structure_display_name(_moving_structure_id)
		label_txt = "✥ %s (%d°)\n[%s]" % [d_name, _placement_rot_deg, "Hợp lệ - Nhấn để Đặt" if _hover_valid else "Vị trí bị vướng"]
	elif _grid_edit_mode == GridEditMode.ROAD_PAINT:
		size_cells = Vector2i(1, 1)
		_hover_valid = (cell.y >= GRID_GZ_MIN and cell.y < GRID_GZ_MAX) and ((cell.x >= TIER1_GX_MIN and cell.x < TIER1_GX_MAX) or (cell.x >= TIER2_GX_MIN and cell.x < TIER2_GX_MAX))
		label_txt = "🧱 Lát Đường (%d, %d)" % [cell.x, cell.y]
	elif _grid_edit_mode == GridEditMode.ROAD_ERASE:
		size_cells = Vector2i(1, 1)
		_hover_valid = _grid_roads.has("%d,%d" % [cell.x, cell.y])
		label_txt = "🧹 Xóa Đường (%d, %d)" % [cell.x, cell.y]

	_hover_gx = cell.x
	_hover_gz = cell.y

	var world_center := _grid_footprint_to_world_center(_hover_gx, _hover_gz, size_cells)
	_grid_ghost_root.global_position = world_center

	var w_m := float(size_cells.x) * GRID_CELL_SIZE
	var h_m := float(size_cells.y) * GRID_CELL_SIZE
	if _grid_ghost_mesh != null and _grid_ghost_mesh.mesh is BoxMesh:
		(_grid_ghost_mesh.mesh as BoxMesh).size = Vector3(w_m - 0.12, 0.28, h_m - 0.12)
	if _grid_ghost_border != null and _grid_ghost_border.mesh is BoxMesh:
		(_grid_ghost_border.mesh as BoxMesh).size = Vector3(w_m + 0.08, 0.08, h_m + 0.08)

	var ghost_col := Color(0.22, 0.96, 0.48, 0.46) if _hover_valid else Color(0.98, 0.26, 0.26, 0.48)
	var border_col := Color(0.35, 1.0, 0.58, 0.90) if _hover_valid else Color(1.0, 0.35, 0.35, 0.90)
	if _grid_edit_mode == GridEditMode.ROAD_ERASE:
		ghost_col = Color(1.0, 0.58, 0.24, 0.52)
		border_col = Color(1.0, 0.72, 0.32, 0.92)

	var g_mat := StandardMaterial3D.new()
	g_mat.albedo_color = ghost_col
	g_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g_mat.emission_enabled = true
	g_mat.emission = Color(ghost_col.r, ghost_col.g, ghost_col.b)
	g_mat.emission_energy_multiplier = 1.2
	_grid_ghost_mesh.material_override = g_mat

	var b_mat := StandardMaterial3D.new()
	b_mat.albedo_color = border_col
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.emission_enabled = true
	b_mat.emission = Color(border_col.r, border_col.g, border_col.b)
	b_mat.emission_energy_multiplier = 1.6
	_grid_ghost_border.material_override = b_mat

	if _grid_ghost_label != null:
		_grid_ghost_label.text = label_txt
		_grid_ghost_label.modulate = Color(0.58, 1.0, 0.68) if _hover_valid else Color(1.0, 0.55, 0.55)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_ESCAPE and _grid_edit_mode != GridEditMode.NONE:
			_exit_grid_edit_mode()
			status_banner_label.text = "✅ Đã thoát chế độ chỉnh sửa lưới."
			return
		elif ke.keycode == KEY_R and (_grid_edit_mode == GridEditMode.PLACE_NEW_BUILDING or _grid_edit_mode == GridEditMode.MOVE_STRUCTURE):
			_placement_rot_deg = (_placement_rot_deg + 90) % 360
			_update_grid_ghost_preview(get_viewport().get_mouse_position())
			status_banner_label.text = "🔄 Đã xoay hướng công trình: %d°" % _placement_rot_deg
			return
		elif ke.keycode == KEY_E or ke.keycode == KEY_PAGEUP:
			_switch_to_lobby_floor(mini(MAX_LOBBY_FLOORS, _current_lobby_floor + 1))
			return
		elif ke.keycode == KEY_Q or ke.keycode == KEY_PAGEDOWN:
			_switch_to_lobby_floor(maxi(1, _current_lobby_floor - 1))
			return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _grid_edit_mode != GridEditMode.NONE:
			_update_grid_ghost_preview(mm.position)
			if _is_painting_road_drag:
				if _grid_edit_mode == GridEditMode.ROAD_PAINT:
					_set_road_at_cell(_hover_gx, _hover_gz, true)
				elif _grid_edit_mode == GridEditMode.ROAD_ERASE:
					_set_road_at_cell(_hover_gx, _hover_gz, false)
			return

		if _pressed_hero != null and _dragging_hero == null:
			if mm.position.distance_to(_press_screen_pos) >= DRAG_THRESHOLD_PX:
				_dragging_hero = _pressed_hero
				_dragging_hero.start_drag_lift()
				status_banner_label.text = "🙌 Đang nhấc [%s]! Thả vào Công trình bất kỳ để phân công, hoặc thả vào Cổng Đông để vào Đội hình PvE!" % _dragging_hero.unit_name

		if _dragging_hero != null:
			var ground_hit := _project_mouse_to_castle_ground(mm.position)
			_dragging_hero.update_drag_ground_position(ground_hit)
			_update_hover_feedback(mm.position, true)
		else:
			_update_hover_feedback(mm.position, false)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _grid_edit_mode != GridEditMode.NONE:
			_exit_grid_edit_mode()
			status_banner_label.text = "✅ Đã thoát chế độ chỉnh sửa lưới."
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_mouse_down(mb.position)
			else:
				_on_left_mouse_up(mb.position)

func _on_left_mouse_down(screen_pos: Vector2) -> void:
	if _grid_edit_mode != GridEditMode.NONE:
		_update_grid_ghost_preview(screen_pos)
		if _grid_edit_mode == GridEditMode.ROAD_PAINT:
			_is_painting_road_drag = true
			_set_road_at_cell(_hover_gx, _hover_gz, true)
		elif _grid_edit_mode == GridEditMode.ROAD_ERASE:
			_is_painting_road_drag = true
			_set_road_at_cell(_hover_gx, _hover_gz, false)
		return

	_press_screen_pos = screen_pos
	_pressed_hero = null
	_dragging_hero = null

	var hit := _raycast_3d(screen_pos)
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider")
	if collider is Node and collider.has_meta("interactable_type"):
		if str(collider.get_meta("interactable_type")) == "HERO":
			var hero_actor: UnitActor3D = collider.get_meta("hero_node")
			if hero_actor != null:
				_pressed_hero = hero_actor

func _on_left_mouse_up(screen_pos: Vector2) -> void:
	if _grid_edit_mode != GridEditMode.NONE:
		_is_painting_road_drag = false
		_update_grid_ghost_preview(screen_pos)
		if _grid_edit_mode == GridEditMode.PLACE_NEW_BUILDING:
			if not _hover_valid:
				status_banner_label.text = "❌ Vị trí lưới không hợp lệ hoặc bị vướng công trình khác!"
				return
			var free_plot := _find_first_free_unlocked_plot_index()
			if free_plot < 0:
				status_banner_label.text = "⚠️ Đã đạt giới hạn công trình theo cấp Master!"
				_exit_grid_edit_mode()
				return
			var b_code := _pending_build_code
			_grid_structures["PLOT:%d" % free_plot] = {
				"gx": _hover_gx,
				"gz": _hover_gz,
				"rot": _placement_rot_deg
			}
			_save_castle_grid_layout()
			_apply_all_grid_transforms()
			_exit_grid_edit_mode()
			await _construct_building_on_plot(b_code, free_plot)
			return
		elif _grid_edit_mode == GridEditMode.MOVE_STRUCTURE:
			if not _hover_valid:
				status_banner_label.text = "❌ Vị trí mới bị vướng hoặc nằm ngoài khuôn viên Lâu Đài!"
				return
			var s_id := _moving_structure_id
			var d_name := _get_structure_display_name(s_id)
			_grid_structures[s_id] = {
				"gx": _hover_gx,
				"gz": _hover_gz,
				"rot": _placement_rot_deg
			}
			_save_castle_grid_layout()
			_apply_all_grid_transforms()
			_spawn_resident_heroes()
			_exit_grid_edit_mode()
			camera_rig.shake(0.14, 0.18)
			status_banner_label.text = "✅ Đã di dời [%s] tới tọa độ lưới (%d, %d)!" % [d_name, _hover_gx, _hover_gz]
			_re_render_inspector_if_open()
			return
		return

	if _dragging_hero != null:
		var dropped_hero := _dragging_hero
		_dragging_hero = null
		_pressed_hero = null
		await _handle_hero_drop(dropped_hero, screen_pos)
		return

	var clicked_hero := _pressed_hero
	_pressed_hero = null

	if clicked_hero != null:
		_open_hero_inspector(clicked_hero)
		return

	var hit := _raycast_3d(screen_pos)
	if hit.is_empty():
		return

	var collider: Object = hit.get("collider")
	if not (collider is Node) or not collider.has_meta("interactable_type"):
		return

	var itype := str(collider.get_meta("interactable_type"))
	match itype:
		"PLOT":
			var plot_node: BasePlot3D = collider.get_meta("plot_node")
			if plot_node != null and not plot_node.building_data.is_empty():
				_current_lobby_floor = 2 if plot_node.global_position.x < -50.0 else 1
				_refresh_hud()
				_open_plot_inspector(plot_node)
		"LANDMARK":
			var l_code := str(collider.get_meta("landmark_code"))
			_open_landmark_inspector(l_code, true)
		"HERO":
			var hero_actor: UnitActor3D = collider.get_meta("hero_node")
			if hero_actor != null:
				_open_hero_inspector(hero_actor)

func _handle_hero_drop(hero_actor: UnitActor3D, screen_pos: Vector2) -> void:
	var ground_pos := _project_mouse_to_castle_ground(screen_pos)
	var target_tier := 2 if ground_pos.x < -50.0 else 1
	_current_lobby_floor = target_tier
	var terrace_center := get_floor_terrace_center(target_tier)
	var max_r := 44.0 if target_tier == 1 else 26.0

	hero_actor.floor_index = target_tier
	hero_actor.terrace_center = terrace_center
	hero_actor.max_walk_radius = max_r
	hero_actor.end_drag_drop(ground_pos)

	var hit := _raycast_3d(screen_pos, [hero_actor.click_body.get_rid()])
	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is Node and collider.has_meta("interactable_type"):
			var itype := str(collider.get_meta("interactable_type"))
			if itype == "PLOT":
				var plot_node: BasePlot3D = collider.get_meta("plot_node")
				if plot_node != null and not plot_node.building_data.is_empty():
					var b_id := str(plot_node.building_data.get("id", ""))
					var b_name := str(plot_node.building_data.get("typeName", "Công trình"))
					await _assign_worker_to_building(b_id, hero_actor.unit_id, hero_actor.unit_name, b_name)
					return
			elif itype == "LANDMARK":
				var l_code := str(collider.get_meta("landmark_code"))
				if l_code == "DUNGEON_PORTAL":
					await _toggle_hero_in_party(hero_actor.unit_id, hero_actor.unit_name)
					return
				elif l_code == "INFIRMARY":
					await _feed_hero(hero_actor.unit_id, hero_actor.unit_name)
					return
				elif l_code == "BARRACKS":
					_on_barracks_pressed()
					return

	status_banner_label.text = "📍 Đã đặt [%s] tại %s." % [
		hero_actor.unit_name,
		"Hạ Thành Tầng 1" if target_tier == 1 else "Thượng Thành Tầng 2"
	]
	hero_actor.show_speech_bubble("😮‍💨 Phù... Lâu đài rộng rãi thật đấy!", 2.8)

func _update_hover_feedback(screen_pos: Vector2, is_dragging: bool) -> void:
	var exclude: Array[RID] = []
	if _dragging_hero != null and _dragging_hero.click_body != null:
		exclude.append(_dragging_hero.click_body.get_rid())

	var hit := _raycast_3d(screen_pos, exclude)
	var next_hovered_plot: BasePlot3D = null

	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		if collider is Node and collider.has_meta("interactable_type"):
			var itype := str(collider.get_meta("interactable_type"))
			if itype == "PLOT":
				next_hovered_plot = collider.get_meta("plot_node")
				if is_dragging and next_hovered_plot != null and not next_hovered_plot.building_data.is_empty():
					var b_name := str(next_hovered_plot.building_data.get("typeName", "Công trình"))
					status_banner_label.text = "🎯 Thả chuột để phân công [%s] vào [%s]!" % [_dragging_hero.unit_name, b_name]
			elif itype == "LANDMARK" and is_dragging:
				var l_code := str(collider.get_meta("landmark_code"))
				if l_code == "DUNGEON_PORTAL":
					status_banner_label.text = "⚔️ Thả chuột để thêm/bỏ [%s] trong Đội hình Chinh phạt Tháp PvE!" % _dragging_hero.unit_name
				elif l_code == "INFIRMARY":
					status_banner_label.text = "🍖 Thả chuột để cấp Khẩu phần hồi sức cho [%s] tại Bệnh Xá!" % _dragging_hero.unit_name

	if _hovered_plot != next_hovered_plot:
		if _hovered_plot != null and is_instance_valid(_hovered_plot):
			_hovered_plot.set_hovered(false)
		_hovered_plot = next_hovered_plot
		if _hovered_plot != null:
			_hovered_plot.set_hovered(true)

func _raycast_3d(screen_pos: Vector2, exclude_rids: Array[RID] = []) -> Dictionary:
	var cam := camera_rig.get_camera_3d()
	if cam == null:
		return {}
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var to := from + dir * 350.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude_rids
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

# ==============================================================================
# CONTEXTUAL RIGHT-SIDE INSPECTOR PANEL (AUTHENTIC PICK ME UP BUILDINGS)
# ==============================================================================

func _close_inspector() -> void:
	inspector_panel.visible = false
	_inspector_context.clear()
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

func _clear_inspector_actions() -> void:
	for child in inspector_action_container.get_children():
		child.queue_free()

func _add_inspector_info(text: String, color: Color = Color(0.88, 0.92, 0.98)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 13)
	inspector_action_container.add_child(lbl)
	return lbl

func _add_inspector_button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 34)
	btn.disabled = disabled
	btn.pressed.connect(callback)
	inspector_action_container.add_child(btn)
	return btn

func _add_inspector_section_header(title: String, color: Color = Color(1.0, 0.88, 0.38)) -> void:
	var sep := HSeparator.new()
	inspector_action_container.add_child(sep)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	inspector_action_container.add_child(lbl)

func _add_inspector_tab_bar(tabs: Array, active_idx: int = -1) -> void:
	var cur_idx := _facility_subtab if active_idx < 0 else active_idx
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for idx in range(tabs.size()):
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 32)
		var is_cur := (idx == cur_idx)
		btn.text = ("▶ " if is_cur else "") + str(tabs[idx])
		btn.modulate = Color(1.0, 0.92, 0.42) if is_cur else Color(0.78, 0.86, 0.96)
		var target_tab := idx
		btn.pressed.connect(func():
			_facility_subtab = target_tab
			_re_render_inspector_if_open()
		)
		row.add_child(btn)
	inspector_action_container.add_child(row)

func _get_or_pick_facility_hero() -> Dictionary:
	if GameState.heroes.is_empty():
		return {}
	if _selected_facility_hero_id != "":
		var found := GameState.get_hero_by_id(_selected_facility_hero_id)
		if not found.is_empty():
			return found
	var first: Dictionary = GameState.heroes[0]
	_selected_facility_hero_id = str(first.get("id", ""))
	return first

func _render_hero_selector_row(prompt_text: String = "🎯 Chọn Hero thao tác:") -> Dictionary:
	_add_inspector_info(prompt_text, Color(0.75, 0.90, 1.0))
	var active_h := _get_or_pick_facility_hero()
	if active_h.is_empty():
		_add_inspector_info("Chưa có Hero nào trong Sảnh Chờ.")
		return {}

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in range(mini(GameState.heroes.size(), 6)):
		var h: Dictionary = GameState.heroes[i]
		var hid := str(h.get("id", ""))
		var hname := str(h.get("name", "Hero"))
		var hlvl := int(h.get("level", 1))
		var hstar := int(h.get("rarity", 1))
		var is_sel := (hid == _selected_facility_hero_id)
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 30)
		btn.text = "%s%s (%d★ Lv.%d)" % ["✅ " if is_sel else "", hname, hstar, hlvl]
		btn.modulate = Color(1.0, 0.92, 0.45) if is_sel else Color(0.84, 0.90, 0.96)
		btn.pressed.connect(func():
			_selected_facility_hero_id = hid
			_re_render_inspector_if_open()
		)
		grid.add_child(btn)
	inspector_action_container.add_child(grid)
	return active_h

func _re_render_inspector_if_open() -> void:
	if not inspector_panel.visible or _inspector_context.is_empty():
		return
	var ctype := str(_inspector_context.get("type", ""))
	if ctype == "PLOT":
		var p_idx := int(_inspector_context.get("plot_index", -1))
		if _plot_nodes.has(p_idx):
			_open_plot_inspector(_plot_nodes[p_idx], false)
	elif ctype == "LANDMARK":
		var l_code := str(_inspector_context.get("landmark_code", ""))
		_open_landmark_inspector(l_code, false)
	elif ctype == "HERO":
		var hid := str(_inspector_context.get("hero_id", ""))
		if _hero_actors.has(hid):
			_open_hero_inspector(_hero_actors[hid], false)
	elif ctype == "FLOOR_HERO_MANAGER":
		var f_num := int(_inspector_context.get("floor", _current_lobby_floor))
		_open_floor_hero_manager(f_num)
	elif ctype == "FREE_BUILD_CATALOG":
		_open_free_grid_build_catalog()
	elif ctype == "MOVE_PICKER":
		_open_movable_structures_picker()

func _open_free_grid_build_catalog() -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

	_inspector_context = {
		"type": "FREE_BUILD_CATALOG"
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	var built_cnt := _get_constructed_building_count()
	var max_cnt := GameState.unlocked_plots
	var free_slot := _find_first_free_unlocked_plot_index()

	inspector_title_label.text = "🏗️ XÂY CÔNG TRÌNH TRÊN LƯỚI (%d/%d)" % [built_cnt, max_cnt]
	inspector_subtitle_label.text = "Đặt tự do trên lưới 2m×2m tại Hạ Thành (100×100m) hoặc Thượng Thành (60×100m)"

	_add_inspector_section_header("📏 GIỚI HẠN THEO LEVEL MASTER (Lv.%d)" % GameState.master_level, Color(1.0, 0.88, 0.42))
	_add_inspector_info(
		"• Số lượng công trình đã xây: %d / %d (Mở rộng thêm ô xây dựng khi tăng cấp Master / Mở rộng Khu vực).\n• Các ô chưa xây được ẩn hoàn toàn để mặt sân Lâu đài thoáng đãng." % [
			built_cnt, max_cnt
		],
		Color(0.85, 0.94, 1.0)
	)

	if built_cnt >= max_cnt or free_slot < 0:
		var exp_info: Dictionary = GameState.base_overview.get("expansion", {})
		var next_z := int(exp_info.get("nextZone", GameState.base_zones + 1))
		var cost := int(exp_info.get("costSilver", 2000))
		var req_wl := int(exp_info.get("requiredWorldLevel", maxi(1, next_z - 1)))
		var req_ml := 1 if next_z <= 1 else (next_z - 1) * MASTER_LEVELS_PER_FLOOR
		_add_inspector_info(
			"⚠️ Bạn đã đạt giới hạn %d/%d công trình theo cấp Master hiện tại!\nHãy nâng cấp Master Lv.%d (hoặc WL %d) để mở khóa thêm ô công trình mới." % [
				built_cnt, max_cnt, req_ml, req_wl
			],
			Color(1.0, 0.78, 0.42)
		)
		if next_z <= MAX_LOBBY_FLOORS:
			_add_inspector_button(
				"🔓 Mở Thêm Giới Hạn Công Trình Cấp #%d (🪙 %d Bạc)" % [next_z, cost],
				_on_expand_zone_pressed,
				(GameState.master_level < req_ml and GameState.world_level < req_wl) or GameState.silver_coins < cost
			)

	_add_inspector_section_header("📐 DANH MỤC BẢN VẼ CÔNG TRÌNH (2×2 Ô = 4m×4m)", Color(0.62, 0.96, 0.75))

	var b_types: Array = GameState.base_overview.get("buildingTypes", [])
	if b_types.is_empty():
		_add_inspector_info("Đang tải danh mục công trình từ máy chủ...")
		return

	for bt in b_types:
		if not (bt is Dictionary):
			continue
		var code := str(bt.get("code", ""))
		var bname := str(bt.get("name", code))
		var desc_txt := str(bt.get("description", ""))
		var cost := int(bt.get("buildCostSilver", 1000))
		var req_wl := int(bt.get("requiredWorldLevel", 1))
		var req_ml := int(bt.get("requiredMasterLevel", 1))
		var unlocked := bool(bt.get("unlocked", true))
		var max_w := int(bt.get("maxWorkers", 0))

		var info_line := "📌 %s [Kích thước: 2×2 ô]\n   • %s\n   • Giá xây: 🪙 %d Bạc | Cần WL %d%s | Tối đa %d Hero" % [
			bname,
			desc_txt,
			cost,
			req_wl,
			(" & Master Lv.%d" % req_ml) if req_ml > 1 else "",
			max_w
		]
		_add_inspector_info(info_line, Color(0.86, 0.95, 0.88) if unlocked else Color(0.68, 0.65, 0.65))

		var can_pick := unlocked and GameState.silver_coins >= cost and free_slot > 0
		_add_inspector_button(
			"📐 Chọn Vị Trí Đặt %s Trên Lưới (🪙 %d)" % [bname, cost],
			func(): _enter_place_new_building_mode(code, bname),
			not can_pick
		)

func _open_movable_structures_picker() -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

	_inspector_context = {
		"type": "MOVE_PICKER"
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	inspector_title_label.text = "✥ DI DỜI & QUY HOẠCH CÔNG TRÌNH"
	inspector_subtitle_label.text = "Nhóm 1 (Mặc định & Trung tâm) + Nhóm 2 (Công trình tự do trên lưới)"

	_add_inspector_info(
		"⛩️ Cổng Thành Đông & Cổng Tháp Thử Thách dính liền là kiến trúc mặc định cố định của Map.",
		Color(1.0, 0.88, 0.45)
	)

	_add_inspector_section_header("🏛️ NHÓM 1: CÔNG TRÌNH TRUNG TÂM", Color(0.65, 0.92, 1.0))
	var group1_landmarks := [
		{"key": "SUMMON_ALTAR", "label": "✨ Đài Triệu Hồi Anh Hùng (4×4 ô)"},
		{"key": "BARRACKS", "label": "🛡️ Nhà Chiến Lược – Strategic House (3×3 ô)"}
	]
	for lm in group1_landmarks:
		var k := str(lm["key"])
		var lbl := str(lm["label"])
		var pos: Dictionary = _grid_structures.get(k, {"gx": 0, "gz": 0, "rot": 0})
		var tier_txt := "Thượng Thành (T2)" if int(pos.get("gx", 0)) < 0 else "Hạ Thành (T1)"
		_add_inspector_info("• %s — Ô (%d, %d) [%s]" % [lbl, int(pos.get("gx", 0)), int(pos.get("gz", 0)), tier_txt], Color(0.88, 0.94, 1.0))
		_add_inspector_button(
			"✥ Di Dời %s" % lbl,
			func(): _start_moving_structure(k)
		)

	_add_inspector_section_header("🏗️ NHÓM 2: CÔNG TRÌNH TỰ DO TRÊN LƯỚI", Color(1.0, 0.88, 0.42))
	var has_medical_plot := false
	for p_idx in _plot_nodes.keys():
		var p_node_chk: BasePlot3D = _plot_nodes[p_idx]
		if str(p_node_chk.building_data.get("buildingType", "")) == "MEDICAL":
			has_medical_plot = true
			break

	var group2_landmarks := [
		{"key": "FOUNTAIN", "label": "⛲ Đài Phun Nước (4×4 ô)"}
	]
	if not has_medical_plot:
		group2_landmarks.append({"key": "INFIRMARY", "label": "✚ Recovery Center – Trung Tâm Hồi Phục (3×3 ô)"})

	for lm2 in group2_landmarks:
		var k2 := str(lm2["key"])
		var lbl2 := str(lm2["label"])
		var pos2: Dictionary = _grid_structures.get(k2, {"gx": 0, "gz": 0, "rot": 0})
		var tier_txt2 := "Thượng Thành (T2)" if int(pos2.get("gx", 0)) < 0 else "Hạ Thành (T1)"
		_add_inspector_info("• %s — Ô (%d, %d) [%s]" % [lbl2, int(pos2.get("gx", 0)), int(pos2.get("gz", 0)), tier_txt2], Color(0.88, 0.94, 1.0))
		_add_inspector_button(
			"✥ Di Dời %s" % lbl2,
			func(): _start_moving_structure(k2)
		)

	var any_built := false
	for p_idx in _plot_nodes.keys():
		var p_node: BasePlot3D = _plot_nodes[p_idx]
		if not p_node.building_data.is_empty():
			any_built = true
			var b_name := str(p_node.building_data.get("typeName", p_node.building_data.get("buildingType", "Công trình")))
			var b_lvl := int(p_node.building_data.get("level", 1))
			var skey := "PLOT:%d" % int(p_idx)
			var pos: Dictionary = _grid_structures.get(skey, {"gx": 0, "gz": 0, "rot": 0})
			var tier_txt := "Thượng Thành (T2)" if int(pos.get("gx", 0)) < 0 else "Hạ Thành (T1)"
			_add_inspector_button(
				"✥ Di Dời %s (Lv.%d/3) — Ô (%d, %d) [%s]" % [b_name, b_lvl, int(pos.get("gx", 0)), int(pos.get("gz", 0)), tier_txt],
				func(): _start_moving_structure(skey)
			)
	if not any_built:
		_add_inspector_info("Chưa có công trình ô 2×2 nào thêm được xây dựng.", Color(0.75, 0.8, 0.88))

	_add_inspector_section_header("🔄 KHÔI PHỤC QUY HOẠCH HOÀNG GIA", Color(1.0, 0.72, 0.42))
	_add_inspector_button(
		"🔄 Đặt Lại Toàn Bộ Bố Cục & Đường Đá Mặc Định",
		func():
			if FileAccess.file_exists(CASTLE_LAYOUT_SAVE_PATH):
				DirAccess.remove_absolute(CASTLE_LAYOUT_SAVE_PATH)
			_load_or_init_castle_grid_layout()
			_setup_grid_overlay_and_roads()
			_apply_all_grid_transforms()
			_save_castle_grid_layout()
			status_banner_label.text = "🏛️ Đã khôi phục toàn bộ Bố Cục Hoàng Gia & Đường Đá chuẩn lưới 2m×2m!"
			_re_render_inspector_if_open()
	)

func _open_floor_hero_manager(target_floor: int) -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

	var f_num := clampi(target_floor, 1, MAX_LOBBY_FLOORS)
	_inspector_context = {
		"type": "FLOOR_HERO_MANAGER",
		"floor": f_num
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	inspector_title_label.text = "👥 QUẢN LÝ TƯỚNG TẦNG #%d" % f_num
	inspector_subtitle_label.text = "Chỉ định tối đa 6 Hero xuất hiện tại tầng này để giảm lag"

	# Floor selection tabs row: allow switching between Floor 1..unlocked
	var floor_tabs_row := HBoxContainer.new()
	floor_tabs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for f in range(1, GameState.unlocked_lobby_floors + 1):
		var f_tab_btn := Button.new()
		f_tab_btn.text = "Tầng %d" % f
		f_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if f == f_num:
			f_tab_btn.modulate = Color(1.0, 0.88, 0.38)
		var target_f := f
		f_tab_btn.pressed.connect(func():
			_open_floor_hero_manager(target_f)
		)
		floor_tabs_row.add_child(f_tab_btn)
	inspector_action_container.add_child(floor_tabs_row)

	# Working selection list for this floor
	if not _editing_floor_hero_selection.has(f_num):
		_editing_floor_hero_selection[f_num] = GameState.get_assigned_heroes_for_floor(f_num).duplicate()
	var selected_ids: Array = _editing_floor_hero_selection[f_num]

	var has_custom: bool = not GameState.get_assigned_heroes_for_floor(f_num).is_empty()
	var status_text: String
	if selected_ids.is_empty() and not has_custom:
		status_text = "⚪ Trạng thái: TỰ ĐỘNG PHÂN BỔ (Mặc định)"
	else:
		status_text = "🟢 Trạng thái: ĐÃ CHỌN %d / %d HERO" % [selected_ids.size(), MAX_HEROES_PER_FLOOR]

	_add_inspector_section_header("THIẾT LẬP HIỆN TẠI", Color(0.65, 0.92, 1.0))
	_add_inspector_info(
		"%s\n💡 Hero được chọn sẽ xuất hiện tại Tầng #%d.\nNếu để trống hoặc nhấn 'Tự Động', hệ thống sẽ tự xếp theo công việc/đội hình." % [
			status_text,
			f_num
		],
		Color(0.85, 0.95, 1.0)
	)

	# Action buttons row: [💾 Lưu & Áp Dụng] [🔄 Đặt Lại Tự Động]
	var btn_row := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "💾 Lưu & Áp Dụng"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.pressed.connect(func():
		GameState.set_assigned_heroes_for_floor(f_num, selected_ids)
		_spawn_resident_heroes()
		status_banner_label.text = "✅ Đã lưu cấu hình %d Hero xuất hiện tại Tầng #%d!" % [selected_ids.size(), f_num]
		_open_floor_hero_manager(f_num)
	)
	btn_row.add_child(save_btn)

	var reset_btn := Button.new()
	reset_btn.text = "🔄 Đặt Lại Tự Động"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.pressed.connect(func():
		_editing_floor_hero_selection[f_num] = []
		GameState.clear_assigned_heroes_for_floor(f_num)
		_spawn_resident_heroes()
		status_banner_label.text = "🔄 Đã chuyển Tầng #%d về chế độ tự động phân bổ Hero!" % f_num
		_open_floor_hero_manager(f_num)
	)
	btn_row.add_child(reset_btn)
	inspector_action_container.add_child(btn_row)

	_add_inspector_section_header("DANH SÁCH ANH HÙNG (%d Tướng)" % GameState.heroes.size(), Color(1.0, 0.88, 0.38))

	var roster := GameState.heroes
	if roster.is_empty():
		_add_inspector_info("Chưa có Anh Hùng nào trong Doanh Trại.", Color(0.7, 0.7, 0.7))
		return

	for h in roster:
		var hid := str(h.get("id", ""))
		var hname := str(h.get("name", "Hero"))
		var hstar := int(h.get("rarity", 1))
		var hlvl := int(h.get("level", 1))
		var hclass := str(h.get("classCode", h.get("heroClass", "WARRIOR")))
		var is_selected := selected_ids.has(hid)

		var card := PanelContainer.new()
		var card_box := HBoxContainer.new()
		card_box.alignment = BoxContainer.ALIGNMENT_CENTER

		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.text = "%s %s (Lv.%d)" % ["★".repeat(clampi(hstar, 1, 7)), hname, hlvl]
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.65) if is_selected else Color(0.9, 0.9, 0.95))
		info_box.add_child(name_lbl)

		var sub_lbl := Label.new()
		var party_tag := " [⚔️ Party]" if GameState.active_party_ids.has(hid) else ""
		sub_lbl.text = "[%s]%s" % [hclass, party_tag]
		sub_lbl.add_theme_font_size_override("font_size", 11)
		sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 1.0))
		info_box.add_child(sub_lbl)
		card_box.add_child(info_box)

		var toggle_btn := Button.new()
		toggle_btn.custom_minimum_size = Vector2(95, 32)
		if is_selected:
			toggle_btn.text = "✅ Đang Chọn"
			toggle_btn.modulate = Color(0.45, 1.0, 0.55)
		else:
			toggle_btn.text = "➕ Chọn"
			toggle_btn.modulate = Color(0.85, 0.88, 0.95)

		toggle_btn.pressed.connect(func():
			if selected_ids.has(hid):
				selected_ids.erase(hid)
				_open_floor_hero_manager(f_num)
			else:
				if selected_ids.size() >= MAX_HEROES_PER_FLOOR:
					status_banner_label.text = "⚠️ Mỗi tầng chỉ tối đa %d Hero! Vui lòng bỏ bớt một Hero trước." % MAX_HEROES_PER_FLOOR
				else:
					selected_ids.append(hid)
					_open_floor_hero_manager(f_num)
		)
		card_box.add_child(toggle_btn)

		card.add_child(card_box)
		inspector_action_container.add_child(card)

func _open_plot_inspector(plot_node: BasePlot3D, focus_cam: bool = true) -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
	_selected_plot = plot_node
	_selected_plot.set_selected(true)

	_inspector_context = {
		"type": "PLOT",
		"plot_index": plot_node.plot_index
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	if focus_cam:
		camera_rig.focus_action_unit(plot_node.global_position, 11.5, 0.35)

	var req_master_lvl := 1 if plot_node.zone_index <= 1 else (plot_node.zone_index - 1) * MASTER_LEVELS_PER_FLOOR

	# Case 1: Locked Floor / Plot
	if not plot_node.is_unlocked:
		inspector_title_label.text = "🔒 Ô Công Trình #%d (Tầng %d)" % [plot_node.plot_index, plot_node.zone_index]
		inspector_subtitle_label.text = "Tầng Sảnh Chờ #%d chưa được mở khóa." % plot_node.zone_index

		var exp_info: Dictionary = GameState.base_overview.get("expansion", {})
		var next_z := int(exp_info.get("nextZone", GameState.base_zones + 1))
		var cost := int(exp_info.get("costSilver", 2000))
		var req_wl := int(exp_info.get("requiredWorldLevel", maxi(1, plot_node.zone_index - 1)))

		_add_inspector_info("• Quy tắc Sảnh Đa Tầng: Mỗi 15 cấp Master sẽ mở 1 tầng cao hơn.")
		_add_inspector_info("• Điều kiện mở Tầng #%d: Master đạt cấp %d (Hiện tại: Lv.%d) hoặc World Level %d" % [
			plot_node.zone_index, req_master_lvl, GameState.master_level, req_wl
		], Color(1.0, 0.86, 0.38))
		_add_inspector_button(
			"🏗️ Mở Khóa Tầng #%d (🪙 %d Bạc)" % [next_z, cost],
			_on_expand_zone_pressed,
			(GameState.master_level < req_master_lvl and GameState.world_level < req_wl) or GameState.silver_coins < cost
		)
		return

	# Case 2: Unlocked Empty Plot -> Show Authentic Pick Me Up Building Blueprints
	if plot_node.building_data.is_empty():
		inspector_title_label.text = "🟩 Ô Công Trình Trống #%d (Tầng %d)" % [plot_node.plot_index, plot_node.zone_index]
		inspector_subtitle_label.text = "Chọn công trình chức năng để xây dựng tại Tầng %d:" % plot_node.zone_index

		var b_types: Array = GameState.base_overview.get("buildingTypes", [])
		if b_types.is_empty():
			_add_inspector_info("Đang tải danh mục công trình từ máy chủ...")
			return

		for bt in b_types:
			if not (bt is Dictionary):
				continue
			var code := str(bt.get("code", ""))
			var bname := str(bt.get("name", code))
			var desc_txt := str(bt.get("description", ""))
			var cost := int(bt.get("buildCostSilver", 1000))
			var req_wl := int(bt.get("requiredWorldLevel", 1))
			var req_ml := int(bt.get("requiredMasterLevel", 1))
			var unlocked := bool(bt.get("unlocked", true))
			var bt_max_w := int(bt.get("maxWorkers", 0))

			var info_line := "📌 %s\n   • %s\n   • Giá xây: 🪙 %d Bạc | Cần WL %d%s | Tối đa %d Hero" % [
				bname,
				desc_txt,
				cost,
				req_wl,
				(" & Master Lv.%d" % req_ml) if req_ml > 1 else "",
				bt_max_w
			]
			_add_inspector_info(info_line, Color(0.86, 0.95, 0.88) if unlocked else Color(0.68, 0.65, 0.65))

			var p_idx := plot_node.plot_index
			_add_inspector_button(
				"🔨 Xây %s (🪙 %d)" % [bname, cost],
				func(): _construct_building_on_plot(code, p_idx),
				(not unlocked) or GameState.silver_coins < cost
			)
		return

	# Case 3: Constructed Building -> Specialized Facility Inspector + Upgrade/Workers/Demolish
	var b: Dictionary = plot_node.building_data
	var b_id := str(b.get("id", ""))
	var b_code := str(b.get("buildingType", ""))
	var b_name := str(b.get("typeName", b_code))
	var b_lvl := int(b.get("level", 1))
	var max_lvl := int(b.get("maxLevel", 3))
	var b_status := str(b.get("status", "READY"))
	var stored := float(b.get("stored", 0.0))
	var cap := int(b.get("capacity", 0))
	var rate := float(b.get("ratePerHour", 0.0))
	var res_type := str(b.get("resourceType", ""))
	var max_w := int(b.get("maxWorkers", 0))
	var workers: Array = b.get("workers", [])

	inspector_title_label.text = "%s %s (Lv.%d/%d)" % [plot_node._icon_for_type(b_code), b_name, b_lvl, max_lvl]
	inspector_subtitle_label.text = "Ô #%d (Tầng %d) • Trạng thái: %s" % [plot_node.plot_index, plot_node.zone_index, b_status]

	_add_inspector_grid_placement_controls("PLOT:%d" % plot_node.plot_index)

	# Specialized Facility Operations by Building Type
	_render_specialized_facility_section(b_id, b_code, b_lvl, b_status)

	# Passive production harvest (for Kitchen, Library, Alchemy Workshop)
	if cap > 0 and res_type != "":
		_add_inspector_info("📦 Tích lũy %s: %d / %d (+%.1f/giờ)" % [res_type, int(floor(stored)), cap, rate], Color(1.0, 0.90, 0.45))
		_add_inspector_button(
			"🌾 Thu Hoạch Ngay (+%d %s)" % [int(floor(stored)), res_type],
			func(): _collect_building(b_id),
			int(floor(stored)) <= 0 or b_status != "READY"
		)

	# Upgrade section
	if b_lvl < max_lvl:
		var target_lvl := b_lvl + 1
		var build_cost := _get_blueprint_build_cost(b_code)
		var upg_silver := int(round(float(build_cost) * float(maxi(2, target_lvl)) * 0.75))
		var req_wood := 10 * maxi(2, target_lvl)
		var req_stone := 5 * maxi(2, target_lvl)
		_add_inspector_info(
			"⬆️ Nâng cấp công trình lên Lv.%d/%d:\n   🪙 %d Bạc | 🪵 %d Gỗ | 🪨 %d Đá" % [target_lvl, max_lvl, upg_silver, req_wood, req_stone],
			Color(0.68, 0.88, 1.0)
		)
		var can_upg := (
			b_status == "READY"
			and GameState.silver_coins >= upg_silver
			and int(GameState.materials.get("WOOD", 0)) >= req_wood
			and int(GameState.materials.get("STONE", 0)) >= req_stone
		)
		_add_inspector_button(
			"⬆️ Nâng Cấp Lên Lv.%d/%d" % [target_lvl, max_lvl],
			func(): _upgrade_building(b_id),
			not can_upg
		)

	# Workers management section
	if max_w > 0:
		var worker_hint := "👷 Hero phụ trách (%d/%d) — Mẹo: Kéo-thả Tướng 3D trực tiếp vào ô này!" % [workers.size(), max_w]
		if b_code == "LIBRARY":
			worker_hint += "\n🔮 Quy tắc Thư Viện: Chỉ Hero hệ MAGE (only MAGE class) mới được phân công & sản xuất Sách EXP!"
		_add_inspector_info(worker_hint, Color(0.95, 0.85, 0.55))
		for w in workers:
			if w is Dictionary:
				var w_hid := str(w.get("heroInstanceId", ""))
				var w_name := str(w.get("heroName", "Hero"))
				var w_lvl := int(w.get("heroLevel", 1))
				var boost := int(round((float(w.get("efficiencyBoost", 1.0)) - 1.0) * 100.0))
				_add_inspector_button(
					"➖ Gỡ %s (Lv.%d, Hiệu suất +%d%%)" % [w_name, w_lvl, boost],
					func(): _remove_worker_from_building(b_id, w_hid, w_name)
				)

		if workers.size() < max_w and b_status == "READY":
			var assigned_map := GameState.get_worker_assignment_map()
			var shown := 0
			for h in GameState.heroes:
				if shown >= 4:
					break
				var hid := str(h.get("id", ""))
				var hstate := str(h.get("state", "IDLE"))
				var hclass := str(h.get("classCode", h.get("heroClass", "WARRIOR"))).to_upper()
				if assigned_map.has(hid) or hstate == "DEAD":
					continue
				if b_code == "LIBRARY" and hclass != "MAGE":
					continue
				var hname := str(h.get("name", "Hero"))
				var hlvl := int(h.get("level", 1))
				shown += 1
				_add_inspector_button(
					"➕ Phân công %s [%s Lv.%d]" % [hname, hclass, hlvl],
					func(): _assign_worker_to_building(b_id, hid, hname, b_name)
				)
			if b_code == "LIBRARY" and shown == 0:
				_add_inspector_info("⚠️ Chưa có Hero hệ MAGE nào rảnh rỗi để phân công vào Thư Viện Ma Thuật.", Color(1.0, 0.75, 0.45))

	_add_inspector_button(
		"🏚️ Phá Dỡ Công Trình (Hoàn 50% Bạc)",
		func(): _demolish_building(b_id, b_name),
		b_status != "READY"
	)

func _render_specialized_facility_section(building_id: String, b_code: String, b_lvl: int, b_status: String) -> void:
	match b_code:
		"HOUSE":
			var cap_by_lvl := 5 if b_lvl <= 1 else (7 if b_lvl == 2 else 10)
			var mult_by_lvl := 1.0 if b_lvl <= 1 else (1.5 if b_lvl == 2 else 2.0)
			var fat_per_hr := 15.0 * mult_by_lvl
			_add_inspector_section_header("🏠 DORMITORY – KHU CƯ TRÚ (Lv.%d/3)" % b_lvl, Color(0.75, 0.92, 1.0))
			_add_inspector_info(
				"• Công trình tự do Nhóm 2 (3 Level, 0 Hero làm việc).\n" +
				"• Sức chứa nghỉ ngơi theo cấp: Lv.1 = 5 người | Lv.2 = 7 người | Lv.3 = 10 người (Hiện tại: %d người).\n" % cap_by_lvl +
				"• Hệ số hồi phục thể lực & tinh thần: %.1fx (-%.1f Fatigue/giờ)." % [mult_by_lvl, fat_per_hr],
				Color(0.78, 0.92, 1.0)
			)
			_render_dormitory_rest_section(false)

		"PARTY_MANSION":
			_add_inspector_section_header("🏰 BIỆT THỰ TỔ ĐỘI – PARTY MANSION (Lv.%d/3)" % b_lvl, Color(1.0, 0.88, 0.38))
			_add_inspector_info(
				"• Công trình riêng biệt (độc lập với Dormitory – Khu Cư Trú).\n" +
				"• Sức chứa tối đa: 5 người nghỉ dưỡng cùng lúc.\n" +
				"• Hệ số hồi phục thể lực & tinh thần: 4.0x (= x2 của Dormitory Level 3, giảm -60 Fatigue/giờ)!",
				Color(1.0, 0.9, 0.52)
			)
			_render_dormitory_rest_section(true)

		"FORGE":
			_render_forge_facility(b_lvl, b_status)

		"TRAINING_CENTER":
			_render_training_center_facility(b_lvl, b_status)

		"HALL_OF_MAGIC":
			_render_hall_of_magic_subwings(building_id, b_lvl)

		"LIBRARY":
			_add_inspector_section_header("📚 1. THƯ VIỆN MA THUẬT (LIBRARY Lv.%d/3)" % b_lvl, Color(0.55, 0.88, 1.0))
			_render_library_actions(building_id, b_lvl)

		"ALCHEMY_WORKSHOP":
			_add_inspector_section_header("⚗️ 2. XƯỞNG GIẢ KIM (ALCHEMY WORKSHOP Lv.%d/3)" % b_lvl, Color(0.52, 0.95, 0.68))
			_render_alchemy_workshop_actions(b_lvl)

		"MAGIC_RESEARCH_LAB":
			_add_inspector_section_header("✨ 3. PHÒNG NGHIÊN CỨU (RESEARCH LAB Lv.%d/3)" % b_lvl, Color(0.95, 0.62, 0.95))
			_render_magic_research_actions(b_lvl)

		"WAREHOUSE":
			_render_warehouse_facility(b_lvl)

		"KITCHEN":
			var worker_cap := clampi(b_lvl, 1, 3)
			var food_rate := 20 if b_lvl <= 1 else (40 if b_lvl == 2 else 80)
			_add_inspector_section_header("🍖 BẾP (KITCHEN Lv.%d/3)" % b_lvl, Color(1.0, 0.82, 0.48))
			_add_inspector_info(
				"• 3 Level — Mỗi level tăng +1 Hero làm việc (Hiện tại tối đa %d Hero: Lv.1=1, Lv.2=2, Lv.3=3).\n" % worker_cap +
				"• Tự động nấu Lương thực (FOOD): +%d/giờ (Lv.1: 20/h | Lv.2: 40/h | Lv.3: 80/h).\n" % food_rate +
				"• Chế biến các món ăn đặc biệt tạo Buff chiến đấu cho Đội hình!\n" +
				"• Tồn kho hiện tại: 🍖 %d Khẩu phần | 🌾 %d Lương thực thô" % [
					int(GameState.materials.get("RATION", 0)),
					int(GameState.materials.get("RAW_FOOD", 0))
				],
				Color(1.0, 0.88, 0.62)
			)
			_add_inspector_button("🍳 Nấu Ngay 5 Khẩu Phần Quân Lương", func(): _cook_rations(5))
			_add_inspector_button("🍲 Nấu Tiệc Buff Đặc Biệt (15 Khẩu Phần + Tăng Sĩ Khí)", func(): _cook_rations(15))

		"MEDICAL":
			var treat_slots := clampi(b_lvl, 1, 3) * 2
			_add_inspector_section_header("✚ RECOVERY CENTER – TRUNG TÂM HỒI PHỤC (Lv.%d/3)" % b_lvl, Color(0.55, 0.98, 0.78))
			_add_inspector_info(
				"• Hợp nhất toàn bộ Bệnh Xá thành 1 Công trình tự do duy nhất.\n" +
				"• Nhân sự: 1 Hero phụ trách | Số giường chữa trị: %d slot (Lv.1: 2 | Lv.2: 4 | Lv.3: 6).\n" % treat_slots +
				"• Quản lý danh sách hồi phục theo Card Hero Grid, Hàng chờ tự động và Quick Heal.",
				Color(0.68, 0.98, 0.82)
			)
			_add_inspector_button(
				"🏥 Mở Giao Diện Hồi Phục (Recovery Center UI)",
				_open_recovery_center_modal
			)

func _render_dormitory_rest_section(is_mansion: bool) -> void:
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		return
	_render_hero_selector_row("🛏️ Chọn Hero nghỉ ngơi / tiếp tế:")
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))
	var hstate := str(h.get("state", "IDLE"))
	var hp := int(h.get("hp", 100))
	var mhp := int(h.get("maxHp", 100))
	var fat := int(h.get("fatigue", 0))
	var hun := int(h.get("hunger", 100))
	var rations := int(GameState.materials.get("RATION", 0))
	_add_inspector_info(
		"• Trạng thái [%s]: %s | ❤️ HP %d/%d | 😓 Mệt mỏi: %d%% | 🍖 No bụng: %d%%" % [
			hname, hstate, hp, mhp, fat, hun
		],
		Color(0.88, 0.94, 1.0)
	)
	var is_resting := hstate == "RESTING"
	_add_inspector_button(
		"🌅 Kết Thúc Nghỉ Ngơi (%s)" % hname if is_resting else ("🏰 Cho %s Nghỉ Dưỡng Tại Biệt Thự (4.0x)" % hname if is_mansion else "🛏️ Cho %s Vào Dormitory Nghỉ Ngơi" % hname),
		func(): _toggle_hero_rest(hid, hname, is_resting)
	)
	_add_inspector_button(
		"🍖 Cấp 1 Khẩu Phần Cho %s (Còn %d 🍖)" % [hname, rations],
		func(): _feed_hero(hid, hname),
		rations <= 0
	)

func _render_forge_facility(b_lvl: int, b_status: String) -> void:
	_add_inspector_section_header("⚒️ XƯỞNG RÈN TRANG BỊ (FORGE Lv.%d/3)" % b_lvl, Color(1.0, 0.78, 0.42))
	var iron_qty := int(GameState.materials.get("IRON", 0))
	var wood_qty := int(GameState.materials.get("WOOD", 0))
	var stone_qty := int(GameState.materials.get("STONE", 0))
	var enh_qty := int(GameState.materials.get("ENHANCEMENT_STONE", 0))
	_add_inspector_info(
		"📦 Kho Nguyên Liệu Rèn: ⛓️ %d Sắt | 🪵 %d Gỗ | 🪨 %d Đá | 💎 %d Đá Cường Hóa" % [iron_qty, wood_qty, stone_qty, enh_qty],
		Color(0.96, 0.86, 0.65)
	)
	_add_inspector_tab_bar(["🔨 Rèn Trang Bị", "✨ Cường Hóa (+15)", "🌟 Ghép Thăng Sao"])
	var tab_idx := clampi(_facility_subtab, 0, 2)

	if tab_idx == 0:
		var recipes: Array = GameState.crafting_overview.get("recipes", [])
		if recipes.is_empty():
			_add_inspector_info("ℹ️ Chưa tải được danh sách Bản vẽ Rèn.", Color(0.75, 0.78, 0.85))
		for rec in recipes:
			if rec is Dictionary:
				var rcode := str(rec.get("code", ""))
				var rname := str(rec.get("targetName", rcode))
				var rslot := str(rec.get("slot", "WEAPON"))
				var rfee := int(rec.get("craftFeeSilver", 500))
				var req_b_lvl := int(rec.get("requiredForgeLevel", 1))
				var mats: Array = rec.get("materials", [])
				var mat_parts: PackedStringArray = []
				for m in mats:
					if m is Dictionary:
						mat_parts.append("%s ×%d" % [str(m.get("code", "")), int(m.get("quantity", 0))])
				var val: Dictionary = rec.get("validation", {})
				var ok_craft := bool(val.get("ok", false))
				var reason := str(val.get("reason", ""))
				_add_inspector_info(
					"📜 [%s] %s (Yêu cầu Lò Rèn Lv.%d)\n   Nguyên liệu: %s | Phí: 🪙 %d Bạc%s" % [
						rslot, rname, req_b_lvl, ", ".join(mat_parts), rfee,
						"" if ok_craft else ("\n   ⚠️ " + reason)
					],
					Color(0.88, 0.95, 0.82) if ok_craft else Color(0.95, 0.72, 0.68)
				)
				_add_inspector_button(
					"🔨 Rèn Ngay: %s (🪙 %d)" % [rname, rfee],
					func(): _craft_equipment_recipe(rcode, rname),
					not ok_craft or b_status != "READY"
				)

	elif tab_idx == 1:
		var equips: Array = GameState.crafting_overview.get("equipment", [])
		if equips.is_empty():
			_add_inspector_info("ℹ️ Chưa có trang bị nào trong kho. Hãy chuyển sang tab [🔨 Rèn Trang Bị] để chế tạo!", Color(0.82, 0.86, 0.95))
		for eq_item in equips:
			if eq_item is Dictionary:
				var eid := str(eq_item.get("id", ""))
				var ename := str(eq_item.get("name", "Trang bị"))
				var eslot := str(eq_item.get("slot", "EQ"))
				var estar := int(eq_item.get("starLevel", 1))
				var eenh := int(eq_item.get("enhanceLevel", 0))
				var atk := int(eq_item.get("atkBonus", 0))
				var def_b := int(eq_item.get("defBonus", 0))
				var hp_b := int(eq_item.get("hpBonus", 0))
				var eq_hero := str(eq_item.get("equippedHeroName", ""))
				var owner_tag := (" [Đang mặc: %s]" % eq_hero) if eq_hero != "" else " [Trong Kho]"
				_add_inspector_info(
					"⚔️ %s (%d★ +%d)%s\n   [%s] +ATK %d | +DEF %d | +HP %d" % [
						ename, estar, eenh, owner_tag, eslot, atk, def_b, hp_b
					],
					Color(0.75, 0.92, 1.0)
				)
				_add_inspector_button(
					"✨ Cường Hóa %s Lên +%d" % [ename, eenh + 1],
					func(): _enhance_equipment_item(eid, ename),
					eenh >= 15 or b_status != "READY"
				)

	elif tab_idx == 2:
		_add_inspector_info(
			"🌟 Ghép 2 Trang Bị cùng loại & cùng cấp Sao (chưa mặc) để đột phá lên cấp Sao cao hơn!",
			Color(1.0, 0.88, 0.45)
		)
		var equips: Array = GameState.crafting_overview.get("equipment", [])
		var groups: Dictionary = {}
		for eq_item in equips:
			if eq_item is Dictionary:
				var eq_hero_id := str(eq_item.get("equippedHeroId", ""))
				if eq_hero_id != "":
					continue
				var tcode := str(eq_item.get("templateCode", ""))
				var s_lvl := int(eq_item.get("starLevel", 1))
				if tcode == "" or s_lvl >= 6:
					continue
				var gkey := "%s__%d" % [tcode, s_lvl]
				if not groups.has(gkey):
					groups[gkey] = {
						"templateCode": tcode,
						"name": str(eq_item.get("name", tcode)),
						"starLevel": s_lvl,
						"count": 0
					}
				groups[gkey]["count"] = int(groups[gkey]["count"]) + 1

		if groups.is_empty():
			_add_inspector_info("ℹ️ Chưa có trang bị rảnh rỗi trong kho để ghép Sao.", Color(0.8, 0.84, 0.92))
		else:
			for gkey in groups.keys():
				var g: Dictionary = groups[gkey]
				var tcode := str(g["templateCode"])
				var gname := str(g["name"])
				var slvl := int(g["starLevel"])
				var cnt := int(g["count"])
				var can_fuse := cnt >= 2 and b_status == "READY"
				_add_inspector_button(
					"🌟 Ghép %s (%d★ → %d★) [Hiện có: %d/2]" % [gname, slvl, slvl + 1, cnt],
					func(): _fuse_equipment_items(tcode, slvl, gname),
					not can_fuse
				)

func _render_training_center_facility(b_lvl: int, b_status: String) -> void:
	var cap_heroes := 3 if b_lvl <= 1 else (5 if b_lvl == 2 else 7)
	var max_tc_count := 2 if GameState.master_level >= 30 else 1
	_add_inspector_section_header("🥋 KHU HUẤN LUYỆN (TRAINING CENTER Lv.%d/3)" % b_lvl, Color(0.58, 0.96, 0.72))
	_add_inspector_info(
		"• Sức chứa Hero huấn luyện theo cấp: Lv.1 = 3 Hero | Lv.2 = 5 Hero | Lv.3 = 7 Hero (Hiện tại: %d Hero).\n" % cap_heroes +
		"• Xây dựng tối đa 2 công trình theo cấp Master (Hiện mở: %d/2 công trình — Mở công trình thứ 2 ở Master Lv.30).\n" % max_tc_count +
		"• Rèn luyện chuyên sâu 4 chỉ số gốc (STR / AGI / INT / STA) và lĩnh hội Kỹ năng chiến đấu!",
		Color(0.75, 0.96, 0.82)
	)
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		_add_inspector_info("⚠️ Chưa có Hero nào trong Sảnh Chờ để huấn luyện.", Color(1.0, 0.75, 0.45))
		return

	_render_hero_selector_row("🥋 Chọn Hero tham gia huấn luyện:")
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))
	var hlvl := int(h.get("level", 1))
	var hclass := str(h.get("classCode", "UNCLASSIFIED"))
	var str_val := int(h.get("str", 10))
	var agi_val := int(h.get("agi", 10))
	var int_val := int(h.get("int", 10))
	var sta_val := int(h.get("sta", 10))
	var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))

	_add_inspector_info(
		"📊 Chỉ số hiện tại của [%s] (%s Lv.%d):\n   💪 STR: %d | ⚡ AGI: %d | 🔮 INT: %d | 🛡️ STA: %d\n   📕 Sách Kỹ Năng hiện có: %d quyển" % [
			hname, hclass, hlvl, str_val, agi_val, int_val, sta_val, skill_books
		],
		Color(0.92, 0.98, 0.85)
	)

	# 2x2 grid for training all 4 base stats
	var stat_grid := GridContainer.new()
	stat_grid.columns = 2
	stat_grid.add_theme_constant_override("h_separation", 6)
	stat_grid.add_theme_constant_override("v_separation", 6)
	var stat_defs := [
		{"code": "str", "label": "💪 Rèn STR (%d → %d)" % [str_val, str_val + 1]},
		{"code": "agi", "label": "⚡ Rèn AGI (%d → %d)" % [agi_val, agi_val + 1]},
		{"code": "int", "label": "🔮 Rèn INT (%d → %d)" % [int_val, int_val + 1]},
		{"code": "sta", "label": "🛡️ Rèn STA (%d → %d)" % [sta_val, sta_val + 1]}
	]
	for sdef in stat_defs:
		var scode := str(sdef["code"])
		var btn := Button.new()
		btn.text = str(sdef["label"])
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = b_status != "READY"
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _train_hero_stat(hid, hname, scode))
		stat_grid.add_child(btn)
	inspector_action_container.add_child(stat_grid)

	# Hero combat skills section
	var skills: Array = h.get("skills", [])
	if not skills.is_empty():
		_add_inspector_section_header("⚔️ KỸ NĂNG THỰC CHIẾN CỦA %s" % hname.to_upper(), Color(0.65, 0.92, 1.0))
		for sk in skills:
			if sk is Dictionary:
				var sk_code := str(sk.get("code", ""))
				var sk_name := str(sk.get("name", sk_code))
				var sk_lvl := int(sk.get("level", 0))
				var sk_max := int(sk.get("maxLevel", 5))
				var unlocked := bool(sk.get("unlocked", sk_lvl > 0))
				if not unlocked:
					_add_inspector_button(
						"🔓 Mở Khóa Kỹ Năng: %s" % sk_name,
						func(): _unlock_hero_skill(hid, hname, sk_code, sk_name),
						b_status != "READY"
					)
				else:
					_add_inspector_button(
						"⬆️ Nâng Cấp %s (Lv.%d/%d)" % [sk_name, sk_lvl, sk_max],
						func(): _upgrade_hero_skill(hid, hname, sk_code, sk_name),
						sk_lvl >= sk_max or b_status != "READY"
					)

func _render_hall_of_magic_subwings(building_id: String, b_lvl: int) -> void:
	_add_inspector_section_header("🔮 ĐẠI SẢNH MA THUẬT (Lv.%d/3 • 2 NGƯỜI/PHÂN KHU = TỔNG 6)" % b_lvl, Color(0.82, 0.72, 1.0))
	_add_inspector_info(
		"• Mở khóa theo cấp Master, có 3 Level, mỗi phân khu tối đa 2 Hero (tổng cộng 6 Hero cho 3 phân khu).",
		Color(0.88, 0.80, 1.0)
	)
	_add_inspector_tab_bar(["📚 1. Thư Viện", "⚗️ 2. Giả Kim", "✨ 3. Phòng Nghiên Cứu"])
	var tab_idx := clampi(_facility_subtab, 0, 2)
	if tab_idx == 0:
		_render_library_actions(building_id, b_lvl)
	elif tab_idx == 1:
		_render_alchemy_workshop_actions(b_lvl)
	else:
		_render_magic_research_actions(b_lvl)

func _render_library_actions(building_id: String, b_lvl: int) -> void:
	var exp_100 := int(GameState.materials.get("SAMPLE_HERO_EXP_100", 0))
	var exp_1000 := int(GameState.materials.get("SAMPLE_HERO_EXP_1000", 0))
	var exp_10000 := int(GameState.materials.get("SAMPLE_HERO_EXP_10000", 0))
	var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))
	var prod_desc := "📘 100 Sách EXP Sơ Cấp/giờ" if b_lvl <= 1 else ("📗 50 Sách EXP Trung Cấp/giờ" if b_lvl == 2 else "📙 15 Sách EXP Cao Cấp/giờ")
	var mage_exp_rate := 25000 if b_lvl <= 1 else (1250000 if b_lvl == 2 else 16500000)

	_add_inspector_info(
		"📚 [1. Thư Viện Ma Thuật – Library Lv.%d/3 (Tối đa 2 Hero hệ MAGE)]:\n" % b_lvl +
		"• 🔮 Quy tắc: Chỉ Hero class MAGE mới được phân công vào Thư Viện & sản xuất Sách EXP!\n" +
		"• Tự động sản xuất hiện tại: %s\n" % prod_desc +
		"  (Lv.1: 100 Sách Sơ Cấp/h | Lv.2: 50 Sách Trung Cấp/h | Lv.3: 15 Sách Cao Cấp/h)\n" +
		"• Pháp Sư (MAGE) tu luyện tăng cấp trực tiếp: +%s EXP/giờ\n" % _format_num(mage_exp_rate) +
		"• Kho Sách: 📘 Sơ Cấp ×%d | 📗 Trung Cấp ×%d | 📙 Cao Cấp ×%d | 📕 Kỹ Năng ×%d" % [
			exp_100, exp_1000, exp_10000, skill_books
		],
		Color(0.58, 0.9, 1.0)
	)
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		return
	_render_hero_selector_row("📖 Chọn Hero lĩnh hội tại Thư Viện Ma Thuật:")
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))
	var hlvl := int(h.get("level", 1))
	var hexp := int(h.get("exp", 0))
	var hclass := str(h.get("classCode", h.get("heroClass", "WARRIOR"))).to_upper()
	_add_inspector_info("• [%s] Hệ: %s | Cấp hiện tại: Lv.%d (EXP: %s)" % [hname, hclass, hlvl, _format_num(hexp)], Color(0.86, 0.94, 1.0))

	if hclass == "MAGE":
		_add_inspector_button(
			"🔮 Tu Luyện Ma Pháp Cho %s (+%s EXP / 1 Giờ)" % [hname, _format_num(mage_exp_rate)],
			func(): _study_mage_in_library(building_id, hid, hname)
		)
	else:
		_add_inspector_info("ℹ️ Chỉ Hero class MAGE mới có thể tu luyện tăng cấp trực tiếp tại Thư Viện Ma Thuật.", Color(1.0, 0.82, 0.48))

	_add_inspector_button(
		"📘 Đọc Sách EXP Sơ Cấp (+1,000 EXP) Cho %s (Còn %d)" % [hname, exp_100],
		func(): _use_exp_book_on_hero(hid, hname, "SAMPLE_HERO_EXP_100"),
		exp_100 <= 0
	)
	if exp_1000 > 0 or b_lvl >= 2:
		_add_inspector_button(
			"📗 Đọc Sách EXP Trung Cấp (+100,000 EXP) Cho %s (Còn %d)" % [hname, exp_1000],
			func(): _use_exp_book_on_hero(hid, hname, "SAMPLE_HERO_EXP_1000"),
			exp_1000 <= 0
		)
	if exp_10000 > 0 or b_lvl >= 3:
		_add_inspector_button(
			"📙 Đọc Sách EXP Cao Cấp (+10,000,000 EXP) Cho %s (Còn %d)" % [hname, exp_10000],
			func(): _use_exp_book_on_hero(hid, hname, "SAMPLE_HERO_EXP_10000"),
			exp_10000 <= 0
		)

	var skills: Array = h.get("skills", [])
	for sk in skills:
		if sk is Dictionary:
			var sk_code := str(sk.get("code", ""))
			var sk_name := str(sk.get("name", sk_code))
			var sk_lvl := int(sk.get("level", 0))
			var sk_max := int(sk.get("maxLevel", 5))
			var unlocked := bool(sk.get("unlocked", sk_lvl > 0))
			if not unlocked:
				_add_inspector_button(
					"🔓 Nghiên Cứu Mở Khóa Kỹ Năng: %s" % sk_name,
					func(): _unlock_hero_skill(hid, hname, sk_code, sk_name)
				)
			elif sk_lvl < sk_max:
				_add_inspector_button(
					"📕 Lĩnh Hội Nâng Cấp %s (Lv.%d → Lv.%d)" % [sk_name, sk_lvl, sk_lvl + 1],
					func(): _upgrade_hero_skill(hid, hname, sk_code, sk_name)
				)

func _render_alchemy_workshop_actions(b_lvl: int) -> void:
	var enh_stones := int(GameState.materials.get("ENHANCEMENT_STONE", 0))
	var rations := int(GameState.materials.get("RATION", 0))
	var raw_food := int(GameState.materials.get("RAW_FOOD", 0))
	var stone_rate := 15 if b_lvl <= 1 else (30 if b_lvl == 2 else 60)
	_add_inspector_info(
		"⚗️ [2. Xưởng Giả Kim – Alchemy Workshop Lv.%d/3 (Tối đa 2 Hero)]:\n" % b_lvl +
		"• Tự động điều chế Đá Cường Hóa: +%d viên/giờ (Lv.1: 15/h | Lv.2: 30/h | Lv.3: 60/h).\n" % stone_rate +
		"• Chế tạo bình thuốc & vật phẩm tiêu hao: %s\n" % ("Đã mở khóa (Lv.2+)" if b_lvl >= 2 else "🔒 Mở khóa ở Level 2") +
		"• Chuyển đổi nguyên liệu theo tỉ lệ: %s (Tính năng cập nhật sau)\n" % ("Sẵn sàng khung Lv.2+" if b_lvl >= 2 else "🔒 Mở khóa ở Level 2") +
		"• Tồn kho: 💎 Đá Cường Hóa ×%d | 🧪 Khẩu phần/Dược phẩm ×%d | 🌾 Thảo dược ×%d" % [
			enh_stones, rations, raw_food
		],
		Color(0.55, 0.96, 0.72)
	)
	_add_inspector_button(
		"⚗️ Điều Chế Bình Thuốc & Vật Phẩm Tiêu Hao (Yêu cầu Lv.2+)",
		func(): _cook_rations(5),
		b_lvl < 2
	)
	_add_inspector_button(
		"🔄 Chuyển Đổi Nguyên Liệu Theo Tỉ Lệ (Mở ở Lv.2 — Làm sau)",
		func(): status_banner_label.text = "ℹ️ Tính năng Chuyển đổi nguyên liệu theo tỉ lệ sẽ được cập nhật ở bản tiếp theo!",
		true
	)
	var h := _get_or_pick_facility_hero()
	if not h.is_empty():
		_render_hero_selector_row("🧪 Chọn Hero dùng Bình thuốc / Vật phẩm tiêu hao:")
		var hid := str(h.get("id", ""))
		var hname := str(h.get("name", "Hero"))
		var hp := int(h.get("hp", 100))
		var mhp := int(h.get("maxHp", 100))
		_add_inspector_button(
			"🧪 Tiếp Tế Bình Thuốc Hồi Sức Cho %s (HP %d/%d)" % [hname, hp, mhp],
			func(): _feed_hero(hid, hname),
			rations <= 0 or b_lvl < 2
		)

func _render_magic_research_actions(b_lvl: int) -> void:
	_add_inspector_info(
		"✨ [3. Phòng Nghiên Cứu – Research Lab Lv.%d/3 (Tối đa 2 Hero)]:\n" % b_lvl +
		"• Nghiên cứu các công nghệ ma导 & chiến thuật toàn Căn cứ.\n" +
		"• Thực hiện Chuyển Chức (Class Change khi đạt Lv.20+).\n" +
		"• Thức Tỉnh Huyết Mạch (Bloodline Awakening) cho Hero!",
		Color(0.95, 0.68, 0.98)
	)
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		return
	_render_hero_selector_row("🔮 Chọn Hero tại Phòng Nghiên Cứu:")
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))
	var hlvl := int(h.get("level", 1))
	var hclass := str(h.get("classCode", h.get("heroClass", "UNCLASSIFIED")))
	var awaken_lvl := int(h.get("awakeningRank", h.get("awakenLevel", 0)))
	_add_inspector_info(
		"• [%s] Hệ phái hiện tại: %s | Cấp: Lv.%d | Tầng Thức Tỉnh: +%d" % [hname, hclass, hlvl, awaken_lvl],
		Color(0.96, 0.84, 1.0)
	)

	var aff_dict: Dictionary = h.get("elementAffinities", {}) if h.get("elementAffinities") is Dictionary else {}
	if hclass.to_upper() == "MAGE" or not aff_dict.is_empty():
		_add_inspector_info(
			"🔮 Tương Thích 7 Nguyên Tố Pháp Sư (Mage Affinity):\n" +
			"   🔥 Hỏa: %d | 💧 Thủy: %d | 🌪️ Phong: %d | 🪨 Địa: %d\n" % [
				int(aff_dict.get("FIRE", 60)), int(aff_dict.get("WATER", 45)),
				int(aff_dict.get("WIND", 40)), int(aff_dict.get("EARTH", 35))
			] +
			"   ☀️ Quang: %d | 🌑 Ám: %d | ⚡ Lôi: %d" % [
				int(aff_dict.get("LIGHT", 50)), int(aff_dict.get("DARK", 30)),
				int(aff_dict.get("LIGHTNING", 55))
			],
			Color(0.68, 0.94, 1.0)
		)

	var classes := ["WARRIOR", "KNIGHT", "MAGE", "RANGER", "ASSASSIN", "PRIEST"]
	var class_grid := GridContainer.new()
	class_grid.columns = 2
	class_grid.add_theme_constant_override("h_separation", 6)
	class_grid.add_theme_constant_override("v_separation", 6)
	for target_cls in classes:
		var cls_code := str(target_cls)
		var btn := Button.new()
		var is_current := hclass.to_upper() == cls_code
		btn.text = ("✅ Hệ " + cls_code) if is_current else ("🔮 Chuyển " + cls_code)
		btn.custom_minimum_size = Vector2(0, 32)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = is_current or hlvl < 20
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _perform_class_change(hid, hname, cls_code))
		class_grid.add_child(btn)
	inspector_action_container.add_child(class_grid)

	if hlvl < 20:
		_add_inspector_info("ℹ️ Hero cần đạt Lv.20 để mở khóa nghi thức Chuyển Chức.", Color(0.95, 0.78, 0.55))

	_add_inspector_button(
		"🌟 Thức Tỉnh Huyết Mạch (Awaken +%d → +%d) Cho %s" % [awaken_lvl, awaken_lvl + 1, hname],
		func(): _awaken_hero(hid, hname)
	)

func _render_warehouse_facility(b_lvl: int) -> void:
	var bonus_slots := clampi(b_lvl, 1, 3) * 100
	_add_inspector_section_header("📦 NHÀ KHO (WAREHOUSE Lv.%d/3)" % b_lvl, Color(0.95, 0.85, 0.58))
	var equips: Array = GameState.crafting_overview.get("equipment", [])
	_add_inspector_info(
		"• Không cần Hero làm việc (0 Hero).\n" +
		"• Mỗi level mở thêm +100 slot ô đồ: Hiện mở rộng +%d slot ô đồ (Lv.1: +100 | Lv.2: +200 | Lv.3: +300).\n" % bonus_slots +
		"• Tổng số Trang bị: %d món | 📜 Thiên Thư: %d | 🍖 Khẩu phần: %d" % [
			equips.size(), GameState.normal_scrolls, int(GameState.materials.get("RATION", 0))
		],
		Color(0.96, 0.9, 0.72)
	)
	_add_inspector_tab_bar(["⚔️ Trang Bị (%d)" % equips.size(), "🎒 Vật Phẩm", "🪨 Nguyên Liệu"])
	var tab_idx := clampi(_facility_subtab, 0, 2)

	if tab_idx == 0:
		var h := _get_or_pick_facility_hero()
		var target_hid := str(h.get("id", ""))
		var target_hname := str(h.get("name", "Hero"))
		if not h.is_empty():
			_render_hero_selector_row("🛡️ Chọn Hero để Mặc / Tháo trang bị từ Kho:")

		if equips.is_empty():
			_add_inspector_info("ℹ️ Kho Trang Bị hiện đang trống. Hãy rèn trang bị mới tại Xưởng Rèn (Forge)!", Color(0.8, 0.85, 0.92))
		for eq_item in equips:
			if eq_item is Dictionary:
				var eid := str(eq_item.get("id", ""))
				var ename := str(eq_item.get("name", "Trang bị"))
				var eslot := str(eq_item.get("slot", "EQ"))
				var estar := int(eq_item.get("starLevel", 1))
				var eenh := int(eq_item.get("enhanceLevel", 0))
				var eq_hid := str(eq_item.get("equippedHeroId", ""))
				var eq_hname := str(eq_item.get("equippedHeroName", ""))
				var atk := int(eq_item.get("atkBonus", 0))
				var def_b := int(eq_item.get("defBonus", 0))
				var hp_b := int(eq_item.get("hpBonus", 0))
				_add_inspector_info(
					"• [%s] %s (%d★ +%d) — +ATK %d | +DEF %d | +HP %d\n   Trạng thái: %s" % [
						eslot, ename, estar, eenh, atk, def_b, hp_b,
						("Đang mặc bởi " + eq_hname) if eq_hid != "" else "Đang lưu kho"
					],
					Color(0.84, 0.94, 1.0) if eq_hid == "" else Color(1.0, 0.88, 0.55)
				)
				if eq_hid != "":
					_add_inspector_button(
						"➖ Tháo %s (Khỏi %s về Kho)" % [ename, eq_hname],
						func(): _unequip_item_from_hero(eid, ename)
					)
				elif target_hid != "":
					_add_inspector_button(
						"🛡️ Mặc %s Cho %s" % [ename, target_hname],
						func(): _equip_item_to_hero(eid, ename, target_hid, target_hname)
					)

	elif tab_idx == 1:
		var exp_books := int(GameState.materials.get("SAMPLE_HERO_EXP_100", 0))
		var exp_books_mid := int(GameState.materials.get("SAMPLE_HERO_EXP_1000", 0))
		var exp_books_high := int(GameState.materials.get("SAMPLE_HERO_EXP_10000", 0))
		var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))
		var rations := int(GameState.materials.get("RATION", 0))
		_add_inspector_info(
			"🎒 Vật Phẩm Tiêu Hao Trong Kho (+%d Slot mở rộng):\n" % bonus_slots +
			"   • 📜 Thiên Thư Triệu Hồi: ×%d\n" % GameState.normal_scrolls +
			"   • 📘 Sách EXP Sơ Cấp: ×%d | 📗 Trung Cấp: ×%d | 📙 Cao Cấp: ×%d\n" % [exp_books, exp_books_mid, exp_books_high] +
			"   • 📕 Sách Kỹ Năng Hero: ×%d\n" % skill_books +
			"   • 🍖 Khẩu Phần Quân Lương: ×%d" % rations,
			Color(0.86, 0.95, 0.88)
		)
		var h := _get_or_pick_facility_hero()
		if not h.is_empty():
			_render_hero_selector_row("🎯 Chọn Hero sử dụng nhanh vật phẩm:")
			var hid := str(h.get("id", ""))
			var hname := str(h.get("name", "Hero"))
			_add_inspector_button(
				"📘 Dùng 1 Sách EXP Sơ Cấp Cho %s" % hname,
				func(): _use_exp_book_on_hero(hid, hname, "SAMPLE_HERO_EXP_100"),
				exp_books <= 0
			)
			_add_inspector_button(
				"🍖 Cấp 1 Khẩu Phần Ăn Cho %s" % hname,
				func(): _feed_hero(hid, hname),
				rations <= 0
			)

	elif tab_idx == 2:
		_add_inspector_info("🪨 Kiểm Kê Toàn Bộ Nguyên Liệu Chế Tác & Xây Dựng:", Color(0.95, 0.88, 0.65))
		var mat_labels := {
			"WOOD": "🪵 Gỗ Kiến Trúc (WOOD)",
			"STONE": "🪨 Đá Khối (STONE)",
			"IRON": "⛓️ Quặng Sắt (IRON)",
			"ENHANCEMENT_STONE": "💎 Đá Cường Hóa (ENHANCEMENT_STONE)",
			"RAW_FOOD": "🌾 Lương Thực Thô (RAW_FOOD)",
			"RATION": "🍖 Khẩu Phần Ăn (RATION)"
		}
		for k in mat_labels.keys():
			var qty := int(GameState.materials.get(k, 0))
			_add_inspector_info("   • %s: ×%d" % [mat_labels[k], qty], Color(0.84, 0.92, 0.88))
		for k in GameState.materials.keys():
			if not mat_labels.has(str(k)):
				var qty := int(GameState.materials[k])
				if qty > 0:
					_add_inspector_info("   • %s: ×%d" % [str(k), qty], Color(0.78, 0.86, 0.84))

func _add_inspector_grid_placement_controls(structure_key: String) -> void:
	var fp := _get_structure_footprint_size(structure_key)
	var pos: Dictionary = _grid_structures.get(structure_key, {"gx": 0, "gz": 0, "rot": 0})
	var gx := int(pos.get("gx", 0))
	var gz := int(pos.get("gz", 0))
	var rot := int(pos.get("rot", 0)) % 360
	var tier_label := "Thượng Thành (Tầng 2)" if gx < 0 else "Hạ Thành (Tầng 1)"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var move_btn := Button.new()
	move_btn.text = "✥ Di Dời Trên Lưới (%d×%d Ô)" % [fp.x, fp.y]
	move_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	move_btn.custom_minimum_size = Vector2(0, 32)
	move_btn.modulate = Color(0.55, 0.96, 0.72)
	move_btn.pressed.connect(func():
		_start_moving_structure(structure_key)
	)
	row.add_child(move_btn)

	var rot_btn := Button.new()
	rot_btn.text = "🔄 Xoay 90° (%d°)" % rot
	rot_btn.custom_minimum_size = Vector2(115, 32)
	rot_btn.modulate = Color(0.68, 0.90, 1.0)
	rot_btn.pressed.connect(func():
		var next_rot := (rot + 90) % 360
		_grid_structures[structure_key] = {
			"gx": gx,
			"gz": gz,
			"rot": next_rot
		}
		_apply_all_grid_transforms()
		_save_castle_grid_layout()
		_re_render_inspector_if_open()
	)
	row.add_child(rot_btn)
	inspector_action_container.add_child(row)
	_add_inspector_info("📐 Tọa độ lưới hiện tại: Ô (%d, %d) • %s" % [gx, gz, tier_label], Color(0.75, 0.88, 0.98))

func _open_landmark_inspector(landmark_code: String, focus_cam: bool = true) -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

	_inspector_context = {
		"type": "LANDMARK",
		"landmark_code": landmark_code
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	match landmark_code:
		"SUMMON_ALTAR":
			if focus_cam:
				camera_rig.focus_action_unit(summon_altar_mesh.global_position, 11.0, 0.35)
			inspector_title_label.text = "✨ ĐÀI TRIỆU HỒI ANH HÙNG"
			inspector_subtitle_label.text = "Nghi thức triệu hồi Anh Hùng & Thiên Thư (Công trình tự do 4×4 ô trên lưới)"
			_add_inspector_grid_placement_controls("SUMMON_ALTAR")
			var banner_name := "Thiên Thư Thường (Standard Banner)"
			if not _active_banners.is_empty() and _active_banners[0] is Dictionary:
				banner_name = str(_active_banners[0].get("name", banner_name))
			_add_inspector_section_header("🔮 BANNER HIỆN HÀNH: %s" % banner_name.to_upper(), Color(0.65, 0.92, 1.0))
			_add_inspector_info(
				"📜 Thiên Thư Thường hiện có: %s\n🪙 Vàng (Bạc) hiện có: %s\n💡 Tự động đổi Bạc sang Thiên Thư nếu thiếu khi nhấn Triệu hồi!" % [
					_format_num(GameState.normal_scrolls),
					_format_num(GameState.silver_coins)
				],
				Color(0.75, 0.94, 1.0)
			)
			_add_inspector_button(
				"✨ Triệu Hồi 3D ×1 (Tốn 1 📜 Thiên Thư)",
				func(): _perform_gacha_summon(1)
			)
			_add_inspector_button(
				"🌟 Đại Nghi Thức Triệu Hồi 3D ×10 (Tốn 10 📜 Thiên Thư)",
				func(): _perform_gacha_summon(10)
			)
			_add_inspector_section_header("🪙 ĐỔI THIÊN THƯ & QUẢN LÝ TƯỚNG", Color(1.0, 0.88, 0.45))
			_add_inspector_button(
				"🪙 Đổi 1 Thiên Thư Thường (10,000 Vàng)",
				func(): _exchange_scrolls(1),
				GameState.silver_coins < 10000
			)
			_add_inspector_button(
				"🪙 Đổi 10 Thiên Thư Thường (100,000 Vàng)",
				func(): _exchange_scrolls(10),
				GameState.silver_coins < 100000
			)
			_add_inspector_button(
				"🛡️ Mở Doanh Trại, Chi Tiết Tướng & Ghép Thăng Sao",
				_on_barracks_pressed
			)

		"DUNGEON_PORTAL":
			if focus_cam:
				camera_rig.focus_action_unit(dungeon_portal_mesh.global_position, 12.0, 0.35)
			inspector_title_label.text = "⛩️ CỔNG THÀNH ĐÔNG & CỔNG THÁP THỬ THÁCH"
			inspector_subtitle_label.text = "Kiến trúc mặc định của Map (Nhóm 1) — Tầng %d (World Level %d)" % [GameState.current_floor, GameState.world_level]
			_add_inspector_info("📌 Cổng thành phía Đông & Cổng Tháp Thử Thách dính liền là mặc định của Map.", Color(1.0, 0.88, 0.45))
			_add_inspector_info("⚔️ Đội hình xuất kích (%d/5 Tướng):\n(Mẹo: Kéo-thả Tướng 3D vào Cổng Tháp hoặc nhấn nút bên dưới)" % GameState.active_party_ids.size(), Color(0.88, 0.72, 1.0))

			for h in GameState.heroes:
				var hid := str(h.get("id", ""))
				var hname := str(h.get("name", "Hero"))
				var hstar := int(h.get("rarity", 1))
				var hlvl := int(h.get("level", 1))
				var in_p := GameState.active_party_ids.has(hid)
				var prefix := "✅ [Trong Đội] " if in_p else "➕ [Thêm vào Đội] "
				_add_inspector_button(
					"%s%s (%d★ Lv.%d)" % [prefix, hname, hstar, hlvl],
					func(): _toggle_hero_in_party(hid, hname)
				)

			_add_inspector_button(
				"⚔️ Tiến Vào Đấu Trường Tháp 3D Ngay!",
				_on_enter_pve_pressed
			)

		"BARRACKS":
			if focus_cam:
				camera_rig.focus_action_unit(barracks_mesh.global_position, 11.0, 0.35)
			inspector_title_label.text = "🛡️ NHÀ CHIẾN LƯỢC (STRATEGIC HOUSE)"
			inspector_subtitle_label.text = "Nhóm 1: Điều phối Tướng, Đội hình & Ghép Thăng Sao (3×3 ô trên lưới)"
			_add_inspector_grid_placement_controls("BARRACKS")
			_add_inspector_info("Tổng số Tướng sở hữu: %d Tướng" % GameState.heroes.size())
			_add_inspector_button("👥 Quản Lý Hero Từng Tầng Sảnh Chờ", func(): _open_floor_hero_manager(_current_lobby_floor))
			_add_inspector_button("🛡️ Mở Bảng Tướng & Ghép Thăng Sao", _on_barracks_pressed)

		"FOUNTAIN", "BONFIRE":
			var f_node := get_node_or_null("BaseArchitecture/CentralBonfire") as Node3D
			if focus_cam and f_node != null:
				camera_rig.focus_action_unit(f_node.global_position, 12.0, 0.35)
			inspector_title_label.text = "⛲ ĐÀI PHUN NƯỚC (FOUNTAIN)"
			inspector_subtitle_label.text = "Công trình tự do Nhóm 2 — Điểm tụ năng lượng linh hồn (4×4 ô trên lưới)"
			_add_inspector_grid_placement_controls("FOUNTAIN")
			_add_inspector_info("🍖 Khẩu phần dự trữ: %d | 🌾 Lương thực thô: %d" % [
				int(GameState.materials.get("RATION", 0)),
				int(GameState.materials.get("RAW_FOOD", 0))
			])
			_add_inspector_button("🌤️🌅🌙 Đổi Bầu Không Khí: Ngày / Hoàng Hôn / Đêm", _on_lighting_toggle_pressed)

			for h in GameState.heroes:
				var hid := str(h.get("id", ""))
				var hname := str(h.get("name", "Hero"))
				var hp := int(h.get("hp", 100))
				var mhp := int(h.get("maxHp", 100))
				_add_inspector_button(
					"🍖 Cấp Khẩu Phần cho %s (HP %d/%d)" % [hname, hp, mhp],
					func(): _feed_hero(hid, hname),
					int(GameState.materials.get("RATION", 0)) <= 0
				)

		"INFIRMARY":
			if focus_cam:
				camera_rig.focus_action_unit(infirmary_mesh.global_position, 11.0, 0.35)
			inspector_title_label.text = "✚ RECOVERY CENTER – TRUNG TÂM HỒI PHỤC"
			inspector_subtitle_label.text = "Công trình tự do Nhóm 2 (3 Level • 1 Hero • 2/4/6 Slot chữa trị theo Level)"
			_add_inspector_grid_placement_controls("INFIRMARY")
			_add_inspector_info(
				"• Hợp nhất toàn bộ Bệnh Xá thành 1 công trình tự do duy nhất.\n" +
				"• Cấu hình chuẩn: 3 Level | 1 Hero phụ trách | 2 / 4 / 6 slot chữa trị theo mỗi Level.\n" +
				"• Quản lý danh sách hồi phục theo Card Hero Grid, Hàng chờ tự động và Quick Heal.",
				Color(0.68, 0.98, 0.82)
			)
			_add_inspector_button(
				"🏥 Mở Giao Diện Hồi Phục (Recovery Center UI)",
				_open_recovery_center_modal
			)

func _open_hero_inspector(hero_actor: UnitActor3D, focus_cam: bool = true) -> void:
	if _selected_plot != null and is_instance_valid(_selected_plot):
		_selected_plot.set_selected(false)
		_selected_plot = null

	_inspector_context = {
		"type": "HERO",
		"hero_id": hero_actor.unit_id
	}
	inspector_panel.visible = true
	_clear_inspector_actions()

	if focus_cam:
		camera_rig.focus_action_unit(hero_actor.global_position, 9.5, 0.3)

	var h := hero_actor.hero_raw_data
	var hid := hero_actor.unit_id
	var hname := hero_actor.unit_name
	var hstar := hero_actor.star_rating
	var hlvl := int(h.get("level", 1))
	var hclass := hero_actor.class_code

	inspector_title_label.text = "%s %s (Lv.%d)" % ["★".repeat(clampi(hstar, 1, 7)), hname, hlvl]
	inspector_subtitle_label.text = "Hệ phái: %s • HP: %d/%d" % [hclass, hero_actor.current_hp, hero_actor.max_hp]

	var in_party := GameState.active_party_ids.has(hid)
	_add_inspector_info("• Đội hình Chinh phạt PvE: %s" % ("Đang tham chiến ⚔️" if in_party else "Dự bị"))
	_add_inspector_button(
		"⚔️ Bỏ khỏi Đội hình PvE" if in_party else "⚔️ Thêm vào Đội hình PvE",
		func(): _toggle_hero_in_party(hid, hname)
	)

	if hero_actor.assigned_building_id != "":
		_add_inspector_info("• Công trình phụ trách: 👷 %s" % hero_actor.assigned_building_name, Color(1.0, 0.86, 0.38))
		_add_inspector_button(
			"➖ Rời khỏi %s" % hero_actor.assigned_building_name,
			func(): _remove_worker_from_building(hero_actor.assigned_building_id, hid, hname)
		)
	else:
		var buildings: Array = GameState.base_overview.get("buildings", [])
		for b in buildings:
			if b is Dictionary and str(b.get("status", "")) == "READY":
				var b_type := str(b.get("buildingType", ""))
				if b_type == "LIBRARY" and hclass.to_upper() != "MAGE":
					continue
				var max_w := int(b.get("maxWorkers", 0))
				var cur_w: Array = b.get("workers", [])
				if cur_w.size() < max_w:
					var b_id := str(b.get("id", ""))
					var b_name := str(b.get("typeName", b_type))
					var p_idx := int(b.get("plotIndex", 0))
					_add_inspector_button(
						"👷 Phân công vào %s (Ô #%d)" % [b_name, p_idx],
						func(): _assign_worker_to_building(b_id, hid, hname, b_name)
					)

	_add_inspector_button("🛡️ Mở Nhà Chiến Lược & Thăng Sao", _on_barracks_pressed)

func _get_blueprint_build_cost(b_code: String) -> int:
	var b_types: Array = GameState.base_overview.get("buildingTypes", [])
	for bt in b_types:
		if bt is Dictionary and str(bt.get("code", "")) == b_code:
			return int(bt.get("buildCostSilver", 1000))
	return 1000

# ==============================================================================
# BACKEND API ACTIONS (BASE, FORGE CRAFTING, TRAINING, HALL OF MAGIC, MANOR)
# ==============================================================================

func _construct_building_on_plot(building_type: String, plot_index: int) -> void:
	status_banner_label.text = "🔨 Đang khởi công [%s] tại Ô #%d..." % [building_type, plot_index]
	var res := await ApiClient.post_req("/api/base/buildings", {
		"buildingType": building_type,
		"plotIndex": plot_index
	})
	if res["ok"]:
		status_banner_label.text = "✅ Khởi công [%s] thành công tại Ô #%d!" % [building_type, plot_index]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể xây dựng: " + str(res["error"])

func _promote_house_to_party_mansion(building_id: String) -> void:
	status_banner_label.text = "🏰 Đang nâng cấp Nhà Nghỉ thành Biệt Thự Tổ Đội (Party Mansion)..."
	var res := await ApiClient.post_req("/api/base/buildings/%s/promote-mansion" % building_id, {})
	if res["ok"]:
		camera_rig.shake(0.24, 0.25)
		status_banner_label.text = "🎉 Đã nâng cấp thành công Nhà Nghỉ lên Biệt Thự Tổ Đội (Party Mansion)!"
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể nâng cấp Party Mansion: " + str(res["error"])

func _craft_equipment_recipe(recipe_code: String, target_name: String) -> void:
	status_banner_label.text = "⚒️ Đang rèn [%s] tại Xưởng Rèn..." % target_name
	var res := await ApiClient.post_req("/api/crafting/craft", { "recipeCode": recipe_code })
	if res["ok"]:
		camera_rig.shake(0.18, 0.2)
		status_banner_label.text = "⚒️ Rèn thành công trang bị [%s]!" % target_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể rèn trang bị: " + str(res["error"])

func _enhance_equipment_item(equip_id: String, equip_name: String) -> void:
	var res := await ApiClient.post_req("/api/crafting/equipment/%s/enhance" % equip_id, {})
	if res["ok"] and res["data"] is Dictionary:
		var new_lvl := int(res["data"].get("enhanceLevel", 1))
		camera_rig.shake(0.14, 0.16)
		status_banner_label.text = "✨ Cường hóa thành công [%s] lên +%d!" % [equip_name, new_lvl]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể cường hóa: " + str(res["error"])

func _fuse_equipment_items(template_code: String, star_level: int, equip_name: String) -> void:
	status_banner_label.text = "🌟 Đang ghép 2 [%s (%d★)]..." % [equip_name, star_level]
	var res := await ApiClient.post_req("/api/crafting/fuse", {
		"templateCode": template_code,
		"starLevel": star_level
	})
	if res["ok"]:
		camera_rig.shake(0.2, 0.22)
		status_banner_label.text = "🌟 Đột phá thành công [%s] lên %d★!" % [equip_name, star_level + 1]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể ghép sao trang bị: " + str(res["error"])

func _equip_item_to_hero(item_id: String, item_name: String, hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.put_req("/api/equipment/%s/equip" % item_id, {
		"heroId": hero_id
	})
	if res["ok"]:
		status_banner_label.text = "🛡️ Đã trang bị [%s] cho [%s] từ Nhà Kho!" % [item_name, hero_name]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể mặc trang bị: " + str(res["error"])

func _unequip_item_from_hero(item_id: String, item_name: String) -> void:
	var res := await ApiClient.post_req("/api/equipment/%s/unequip" % item_id, {})
	if res["ok"]:
		status_banner_label.text = "📦 Đã tháo [%s] cất vào Nhà Kho!" % item_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể tháo trang bị: " + str(res["error"])

func _train_hero_stat(hero_id: String, hero_name: String, stat_code: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/train" % hero_id, {
		"stat": stat_code,
		"points": 1
	})
	if res["ok"]:
		status_banner_label.text = "🥋 [%s] đã hoàn thành bài huấn luyện tăng chỉ số %s!" % [hero_name, stat_code.to_upper()]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa thể huấn luyện: " + str(res["error"])

func _unlock_hero_skill(hero_id: String, hero_name: String, skill_code: String, skill_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/skills/%s/unlock" % [hero_id, skill_code], {})
	if res["ok"]:
		status_banner_label.text = "🔓 [%s] đã lĩnh hội kỹ năng mới: [%s]!" % [hero_name, skill_name]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa thể mở khóa kỹ năng: " + str(res["error"])

func _upgrade_hero_skill(hero_id: String, hero_name: String, skill_code: String, skill_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/skills/%s/upgrade" % [hero_id, skill_code], {})
	if res["ok"]:
		status_banner_label.text = "📕 [%s] đã nâng cấp kỹ năng [%s]!" % [hero_name, skill_name]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa thể nâng cấp kỹ năng: " + str(res["error"])

func _use_exp_book_on_hero(hero_id: String, hero_name: String, item_code: String = "SAMPLE_HERO_EXP_100") -> void:
	var res := await ApiClient.post_req("/api/inventory/items/%s/use" % item_code, {
		"quantity": 1,
		"targetHeroId": hero_id
	})
	if res["ok"]:
		status_banner_label.text = "📘 [%s] đã lĩnh hội Sách EXP (%s) tại Thư Viện Ma Thuật!" % [hero_name, item_code]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể dùng Sách EXP: " + str(res["error"])

func _study_mage_in_library(building_id: String, hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.post_req("/api/base/buildings/%s/mage-study" % building_id, {
		"heroId": hero_id,
		"hours": 1
	})
	if res["ok"] and res["data"] is Dictionary:
		var exp_gained := int(res["data"].get("expGained", 0))
		var new_lvl := int(res["data"].get("newLevel", 1))
		camera_rig.shake(0.16, 0.18)
		status_banner_label.text = "🔮 [%s] đã tu luyện Ma Pháp tại Thư Viện (+%s EXP → Lv.%d)!" % [
			hero_name, _format_num(exp_gained), new_lvl
		]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể tu luyện tại Thư Viện: " + str(res["error"])

func _perform_class_change(hero_id: String, hero_name: String, target_class: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/class-change" % hero_id, {
		"targetClass": target_class
	})
	if res["ok"]:
		camera_rig.shake(0.18, 0.2)
		status_banner_label.text = "🔮 [%s] đã chuyển chức thành công sang [%s] tại Phòng Nghiên Cứu!" % [hero_name, target_class]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa đủ điều kiện Chuyển Chức: " + str(res["error"])

func _awaken_hero(hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/awaken" % hero_id, {})
	if res["ok"]:
		camera_rig.shake(0.2, 0.22)
		status_banner_label.text = "🌟 [%s] đã Thức Tỉnh Huyết Mạch tại Phòng Nghiên Cứu!" % hero_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa đủ nguyên liệu Thức Tỉnh: " + str(res["error"])

func _toggle_hero_rest(hero_id: String, hero_name: String, is_currently_resting: bool) -> void:
	var res: Dictionary
	if is_currently_resting:
		res = await ApiClient.delete_req("/api/survival/heroes/%s/rest" % hero_id)
	else:
		res = await ApiClient.post_req("/api/survival/heroes/%s/rest" % hero_id, {})
	if res["ok"]:
		status_banner_label.text = (
			"🌅 [%s] đã kết thúc nghỉ ngơi và sẵn sàng làm việc!" % hero_name
			if is_currently_resting
			else "🛏️ [%s] đã bắt đầu nghỉ ngơi hồi phục thể lực!" % hero_name
		)
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Không thể đổi trạng thái nghỉ ngơi: " + str(res["error"])

func _upgrade_building(building_id: String) -> void:
	status_banner_label.text = "⬆️ Đang nâng cấp công trình..."
	var res := await ApiClient.post_req("/api/base/buildings/%s/upgrade" % building_id, {})
	if res["ok"]:
		status_banner_label.text = "✅ Đã bắt đầu nâng cấp công trình!"
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể nâng cấp: " + str(res["error"])

func _demolish_building(building_id: String, b_name: String) -> void:
	status_banner_label.text = "🏚️ Đang phá dỡ [%s]..." % b_name
	var res := await ApiClient.post_req("/api/base/buildings/%s/demolish" % building_id, {})
	if res["ok"]:
		var refund := int(res["data"].get("refundSilver", 0)) if res["data"] is Dictionary else 0
		status_banner_label.text = "✅ Đã phá dỡ [%s], hoàn lại 🪙 %d Bạc." % [b_name, refund]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể phá dỡ: " + str(res["error"])

func _collect_building(building_id: String) -> void:
	var res := await ApiClient.post_req("/api/base/buildings/%s/collect" % building_id, {})
	if res["ok"] and res["data"] is Dictionary:
		var amt := int(res["data"].get("collected", 0))
		var rtype := str(res["data"].get("resourceType", ""))
		status_banner_label.text = "🌾 Thu hoạch thành công +%d %s!" % [amt, rtype]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể thu hoạch: " + str(res["error"])

func _on_collect_all_pressed() -> void:
	var buildings: Array = GameState.base_overview.get("buildings", [])
	var total_harvested := 0
	for b in buildings:
		if b is Dictionary and str(b.get("status", "")) == "READY" and float(b.get("stored", 0.0)) >= 1.0:
			var bid := str(b.get("id", ""))
			var res := await ApiClient.post_req("/api/base/buildings/%s/collect" % bid, {})
			if res["ok"] and res["data"] is Dictionary:
				total_harvested += int(res["data"].get("collected", 0))
	if total_harvested > 0:
		status_banner_label.text = "🌾 Đã thu hoạch toàn bộ Sảnh Chờ: +%d vật phẩm!" % total_harvested
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Hiện chưa có công trình nào tích lũy đủ vật phẩm để thu hoạch."

func _on_expand_zone_pressed() -> void:
	status_banner_label.text = "🏗️ Đang mở khóa Tầng Sảnh Chờ tiếp theo..."
	var res := await ApiClient.post_req("/api/base/expand", {})
	if res["ok"] and res["data"] is Dictionary:
		var new_z := int(res["data"].get("zones", GameState.base_zones + 1))
		status_banner_label.text = "🎉 Đã mở khóa Tầng Sảnh Chờ #%d (+3 Ô công trình mới)!" % new_z
		camera_rig.shake(0.22, 0.25)
		await _sync_all_from_backend()
		_switch_to_lobby_floor(new_z)
	else:
		status_banner_label.text = "❌ Chưa thể mở Tầng mới: " + str(res["error"])

func _assign_worker_to_building(building_id: String, hero_id: String, hero_name: String, building_name: String) -> void:
	if hero_id.begins_with("preview-"):
		status_banner_label.text = "ℹ️ Hãy đăng nhập tài khoản để phân công Tướng thực tế vào công trình."
		return
	status_banner_label.text = "👷 Đang phân công [%s] vào [%s]..." % [hero_name, building_name]
	var res := await ApiClient.post_req("/api/base/buildings/%s/workers" % building_id, {
		"heroId": hero_id
	})
	if res["ok"]:
		status_banner_label.text = "✅ [%s] đã bắt đầu phụ trách tại [%s]!" % [hero_name, building_name]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể phân công: " + str(res["error"])

func _remove_worker_from_building(building_id: String, hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.delete_req("/api/base/buildings/%s/workers/%s" % [building_id, hero_id])
	if res["ok"]:
		status_banner_label.text = "✅ Đã cho [%s] rời công trình về Sảnh Chờ." % hero_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể gỡ nhân công: " + str(res["error"])

func _toggle_hero_in_party(hero_id: String, hero_name: String) -> void:
	if hero_id.begins_with("preview-"):
		return
	var next_party := GameState.active_party_ids.duplicate()
	if next_party.has(hero_id):
		next_party.erase(hero_id)
	else:
		if next_party.size() >= 5:
			status_banner_label.text = "⚠️ Đội hình tối đa 5 Tướng! Hãy bỏ bớt 1 Tướng trước."
			return
		next_party.append(hero_id)

	var res := await ApiClient.put_req("/api/combat/party", { "heroIds": next_party })
	if res["ok"]:
		GameState.set_active_party(next_party)
		status_banner_label.text = "⚔️ Đã cập nhật Đội hình Chinh phạt cho [%s] (%d/5 Tướng)!" % [hero_name, next_party.size()]
		_refresh_hud()
		_spawn_resident_heroes()
		_re_render_inspector_if_open()
	else:
		status_banner_label.text = "❌ Không thể cập nhật đội hình: " + str(res["error"])

func _exchange_scrolls(amount: int) -> void:
	var res := await ApiClient.post_req("/api/economy/exchange-scrolls", { "amount": amount })
	if res["ok"]:
		status_banner_label.text = "📜 Đã đổi thành công +%d Thiên Thư Thường!" % amount
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể đổi Thiên Thư: " + str(res["error"])

func _perform_gacha_summon(roll_count: int) -> void:
	_switch_to_lobby_floor(1)
	camera_rig.focus_action_unit(summon_altar_mesh.global_position, 8.8, 0.3)
	status_banner_label.text = "✨ Đang kích hoạt Đại Nghi Thức Triệu Hồi 3D ×%d..." % roll_count

	if _active_banners.is_empty():
		var b_res := await ApiClient.get_req("/api/gacha/banners")
		if b_res["ok"] and b_res["data"] is Array:
			_active_banners = b_res["data"]

	if _active_banners.is_empty():
		status_banner_label.text = "❌ Hiện không có Banner triệu hồi nào đang mở."
		return

	if GameState.normal_scrolls < roll_count and GameState.silver_coins >= roll_count * 10000:
		var needed := roll_count - GameState.normal_scrolls
		await ApiClient.post_req("/api/economy/exchange-scrolls", { "amount": needed })

	var banner_id := str(_active_banners[0].get("id", ""))
	var idem_key := "godot-summon-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var res := await ApiClient.post_req(
		"/api/gacha/summon",
		{ "bannerId": banner_id, "rollCount": roll_count },
		{ "Idempotency-Key": idem_key }
	)

	if res["ok"] and res["data"] is Dictionary:
		var results: Array = res["data"].get("results", [])
		var pity_counter := int(res["data"].get("pityCounter", 0))
		var highest_rarity := 1
		var hero_names: Array[String] = []
		var item_count := 0
		for r in results:
			if r is Dictionary:
				var rar := int(r.get("rarity", 1))
				if rar > highest_rarity:
					highest_rarity = rar
				var rtype := str(r.get("rewardType", r.get("itemType", ""))).to_upper()
				if rtype == "HERO":
					hero_names.append("%s (%d★)" % [str(r.get("rewardName", "Anh Hùng")), rar])
				else:
					item_count += 1

		_play_3d_summon_ritual_vfx(highest_rarity)
		camera_rig.shake(0.32 if highest_rarity >= 4 else 0.22, 0.30)

		if hero_names.size() > 0:
			if item_count > 0:
				status_banner_label.text = "🌟 Triệu hồi thành công %d Anh Hùng: %s (+%d Vật phẩm)!" % [hero_names.size(), ", ".join(hero_names), item_count]
			else:
				status_banner_label.text = "🌟 Triệu hồi thành công Anh Hùng: %s!" % ", ".join(hero_names)
		else:
			status_banner_label.text = "✨ Đã triệu hồi ×%d: Nhận %d Vật phẩm / Nguyên liệu!" % [roll_count, item_count]

		await _sync_all_from_backend()
		await get_tree().create_timer(0.45).timeout
		_show_gacha_results_modal(roll_count, results, pity_counter, highest_rarity)
	else:
		status_banner_label.text = "❌ Không thể triệu hồi: " + str(res["error"])

func _play_3d_summon_ritual_vfx(highest_rarity: int) -> void:
	if summon_altar_mesh == null or not is_instance_valid(summon_altar_mesh):
		return

	var vfx_color := Color(0.28, 0.85, 1.0)
	if highest_rarity >= 5:
		vfx_color = Color(1.0, 0.85, 0.22)
	elif highest_rarity == 4:
		vfx_color = Color(0.82, 0.38, 1.0)

	var vfx_root := Node3D.new()
	vfx_root.name = "SummonRitualVfx3D"
	vfx_root.global_position = summon_altar_mesh.global_position
	add_child(vfx_root)

	# 1. Sky Pillar Beam descending onto Summon Altar
	var beam_node := MeshInstance3D.new()
	var beam_cyl := CylinderMesh.new()
	beam_cyl.top_radius = 0.85
	beam_cyl.bottom_radius = 1.35
	beam_cyl.height = 18.0
	beam_node.mesh = beam_cyl
	beam_node.position = Vector3(0, 9.0, 0)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.albedo_color = Color(vfx_color.r, vfx_color.g, vfx_color.b, 0.55)
	beam_mat.emission_enabled = true
	beam_mat.emission = vfx_color
	beam_mat.emission_energy_multiplier = 3.6
	beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam_node.material_override = beam_mat
	vfx_root.add_child(beam_node)

	# 2. Expanding Shockwave Rune Ring
	var ring_node := MeshInstance3D.new()
	var ring_torus := TorusMesh.new()
	ring_torus.inner_radius = 1.4
	ring_torus.outer_radius = 1.75
	ring_node.mesh = ring_torus
	ring_node.position = Vector3(0, 0.45, 0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.albedo_color = Color(vfx_color.r, vfx_color.g, vfx_color.b, 0.88)
	ring_mat.emission_enabled = true
	ring_mat.emission = vfx_color
	ring_mat.emission_energy_multiplier = 4.0
	ring_node.material_override = ring_mat
	vfx_root.add_child(ring_node)

	# 3. Dynamic Altar Flash OmniLight3D
	var flash_light := OmniLight3D.new()
	flash_light.position = Vector3(0, 2.2, 0)
	flash_light.light_color = vfx_color
	flash_light.light_energy = 6.5
	flash_light.omni_range = 14.0
	vfx_root.add_child(flash_light)

	# 4. Rising Mana Orbs around the Altar
	for i in range(8):
		var orb := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.16
		sph.height = 0.32
		orb.mesh = sph
		var ang := float(i) * TAU / 8.0
		orb.position = Vector3(cos(ang) * 1.4, 0.5 + float(i % 3) * 0.4, sin(ang) * 1.4)
		orb.material_override = ring_mat
		vfx_root.add_child(orb)
		var orb_tw := create_tween().set_parallel(true)
		orb_tw.tween_property(orb, "position", Vector3(cos(ang + 1.2) * 2.2, 5.2 + float(i % 2) * 1.4, sin(ang + 1.2) * 2.2), 1.15)
		orb_tw.tween_property(orb, "scale", Vector3.ZERO, 1.15)

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(beam_node, "scale", Vector3(0.05, 1.0, 0.05), 1.15)
	tw.tween_property(beam_mat, "albedo_color:a", 0.0, 1.15)
	tw.tween_property(ring_node, "scale", Vector3(2.8, 1.0, 2.8), 1.1)
	tw.tween_property(ring_node, "position:y", 2.6, 1.1)
	tw.tween_property(ring_mat, "albedo_color:a", 0.0, 1.1)
	tw.tween_property(flash_light, "light_energy", 0.0, 1.15)
	tw.chain().tween_callback(vfx_root.queue_free)

func _show_gacha_results_modal(roll_count: int, results: Array, pity_counter: int, highest_rarity: int) -> void:
	var existing := $HUD.get_node_or_null("GachaResultsOverlay")
	if existing != null:
		existing.queue_free()

	var overlay := ColorRect.new()
	overlay.name = "GachaResultsOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.03, 0.05, 0.09, 0.82)
	$HUD.add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)

	var card_panel := PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(980, 560)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.07, 0.10, 0.16, 0.97)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(1.0, 0.84, 0.25, 0.95) if highest_rarity >= 4 else Color(0.32, 0.78, 1.0, 0.85)
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	card_panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(card_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	card_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "✨ KẾT QUẢ ĐẠI NGHI THỨC TRIỆU HỒI ×%d ✨" % roll_count
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.38) if highest_rarity >= 4 else Color(0.55, 0.92, 1.0))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "📜 Thiên Thư còn lại: %s  |  🪙 Vàng: %s  |  🎯 Tích lũy Pity 5★: %d / 90" % [
		_format_num(GameState.normal_scrolls),
		_format_num(GameState.silver_coins),
		pity_counter
	]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.80, 0.88, 0.98))
	vbox.add_child(sub)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 320)
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = mini(5, maxi(1, results.size()))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for r in results:
		if not (r is Dictionary):
			continue
		var rtype := str(r.get("rewardType", r.get("itemType", "MATERIAL"))).to_upper()
		var is_hero := (rtype == "HERO")
		var rname := str(r.get("rewardName", "Anh Hùng" if is_hero else "Vật phẩm"))
		var rar := int(r.get("rarity", 1))

		if is_hero:
			var hero_dict: Dictionary = r.get("hero", {}) if r.get("hero") is Dictionary else {}
			if hero_dict.is_empty():
				hero_dict = {
					"id": str(r.get("heroId", r.get("id", ""))),
					"name": rname,
					"rarity": rar,
					"level": 1,
					"classCode": str(r.get("classCode", "WARRIOR")),
					"element": str(r.get("element", "NEUTRAL")),
					"state": "HEALTHY"
				}
			else:
				hero_dict = hero_dict.duplicate()
				if not hero_dict.has("rarity"):
					hero_dict["rarity"] = rar
				if not hero_dict.has("name"):
					hero_dict["name"] = rname

			var card = UniversalHeroCardScript.new()
			card.setup(hero_dict, UniversalHeroCardScript.ContextMode.DEFAULT, false)
			if bool(r.get("isDuplicate", false)):
				card.add_badge("🔄 Trùng (+1 Mảnh)", Color(0.85, 0.45, 0.15, 0.95))
			else:
				card.add_badge("✨ MỚI", Color(0.18, 0.65, 0.35, 0.95))
			grid.add_child(card)
		else:
			var item_dict := {
				"id": str(r.get("itemId", r.get("id", ""))),
				"name": rname,
				"rarity": rar,
				"starLevel": rar,
				"quantity": int(r.get("quantity", 1)),
				"itemType": rtype,
				"slot": rtype
			}
			var icard = UniversalItemCardScript.new()
			icard.setup(item_dict, UniversalItemCardScript.ContextMode.MATERIAL, false)
			icard.add_badge("📦 VẬT PHẨM", Color(0.20, 0.35, 0.55, 0.95))
			grid.add_child(icard)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var again1_btn := Button.new()
	again1_btn.text = "✨ Triệu Hồi Tiếp ×1"
	again1_btn.custom_minimum_size = Vector2(165, 38)
	again1_btn.pressed.connect(func():
		overlay.queue_free()
		_perform_gacha_summon(1)
	)
	btn_row.add_child(again1_btn)

	var again10_btn := Button.new()
	again10_btn.text = "🌟 Triệu Hồi Tiếp ×10"
	again10_btn.custom_minimum_size = Vector2(175, 38)
	again10_btn.pressed.connect(func():
		overlay.queue_free()
		_perform_gacha_summon(10)
	)
	btn_row.add_child(again10_btn)

	var roster_btn := Button.new()
	roster_btn.text = "🛡️ Xem Tướng & Thăng Sao"
	roster_btn.custom_minimum_size = Vector2(190, 38)
	roster_btn.pressed.connect(func():
		overlay.queue_free()
		_on_barracks_pressed()
	)
	btn_row.add_child(roster_btn)

	var close_btn := Button.new()
	close_btn.text = "✖ Đóng"
	close_btn.custom_minimum_size = Vector2(110, 38)
	close_btn.pressed.connect(overlay.queue_free)
	btn_row.add_child(close_btn)

func _cook_rations(qty: int) -> void:
	var res := await ApiClient.post_req("/api/survival/kitchen/cook", { "quantity": qty })
	if res["ok"]:
		status_banner_label.text = "🍳 Đã nấu thêm Khẩu phần Quân lương!"
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Chưa thể nấu Khẩu phần: " + str(res["error"])

func _feed_hero(hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.post_req("/api/survival/heroes/%s/feed" % hero_id, { "quantity": 1 })
	if res["ok"]:
		status_banner_label.text = "🍖 [%s] đã dùng Khẩu phần và hồi phục thể lực!" % hero_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Không thể dùng Khẩu phần: " + str(res["error"])

# ==============================================================================
# LIGHTING AMBIANCE & NAVIGATION
# ==============================================================================

func _on_lighting_toggle_pressed() -> void:
	_lighting_mode = (_lighting_mode + 1) % 3
	_apply_lighting_preset(_lighting_mode, true)

func _apply_lighting_preset(mode_idx: int, animate: bool) -> void:
	var env := world_env.environment
	var target_light_col := Color(1.0, 0.98, 0.92)
	var target_light_energy := 1.15
	var target_bg := Color(0.12, 0.16, 0.23)
	var target_ambient := Color(0.70, 0.76, 0.88)
	var target_ambient_energy := 0.88

	match mode_idx:
		0:
			lighting_toggle_btn.text = "🌤️ Ngày"
			target_light_col = Color(1.0, 0.98, 0.92)
			target_light_energy = 1.18
			target_bg = Color(0.13, 0.18, 0.26)
			target_ambient = Color(0.72, 0.78, 0.90)
			target_ambient_energy = 0.90
		1:
			lighting_toggle_btn.text = "🌅 Hoàng Hôn"
			target_light_col = Color(1.0, 0.62, 0.34)
			target_light_energy = 0.95
			target_bg = Color(0.16, 0.10, 0.18)
			target_ambient = Color(0.78, 0.52, 0.45)
			target_ambient_energy = 0.68
		2:
			lighting_toggle_btn.text = "🌙 Đêm"
			target_light_col = Color(0.38, 0.50, 0.82)
			target_light_energy = 0.35
			target_bg = Color(0.05, 0.07, 0.12)
			target_ambient = Color(0.25, 0.32, 0.52)
			target_ambient_energy = 0.42

	if not animate or env == null:
		dir_light.light_color = target_light_col
		dir_light.light_energy = target_light_energy
		if env != null:
			env.background_color = target_bg
			env.ambient_light_color = target_ambient
			env.ambient_light_energy = target_ambient_energy
		return

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tw.tween_property(dir_light, "light_color", target_light_col, 0.55)
	tw.tween_property(dir_light, "light_energy", target_light_energy, 0.55)
	tw.tween_property(env, "background_color", target_bg, 0.55)
	tw.tween_property(env, "ambient_light_color", target_ambient, 0.55)
	tw.tween_property(env, "ambient_light_energy", target_ambient_energy, 0.55)

func _on_focus_base_pressed() -> void:
	if not _panorama_mode:
		_show_all_floors_panorama()
	else:
		_switch_to_lobby_floor(_current_lobby_floor)

func _on_barracks_pressed() -> void:
	_switch_to_lobby_floor(1)
	camera_rig.focus_action_unit(barracks_mesh.global_position, 8.5, 0.3)
	status_banner_label.text = "🛡️ Đang mở Doanh Trại & Bảng Thăng Sao (Pick Me Up style)..."
	await get_tree().create_timer(0.32).timeout
	get_tree().change_scene_to_file("res://scenes/heroes/hero_roster.tscn")

func _on_enter_pve_pressed() -> void:
	_switch_to_lobby_floor(1)
	camera_rig.focus_action_unit(dungeon_portal_mesh.global_position, 8.5, 0.35)
	status_banner_label.text = "🌀 Đang tiến vào Cổng Tháp PvE (Isometric 3D Combat v2)..."
	await get_tree().create_timer(0.4).timeout
	get_tree().change_scene_to_file("res://scenes/pve/isometric_pve_arena_3d.tscn")

const RecoveryCenterModalScript = preload("res://scripts/ui/recovery_center_modal.gd")

func _on_back_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/main_hub.tscn")

func _open_recovery_center_modal() -> void:
	var existing = $HUD.get_node_or_null("RecoveryCenterModal")
	if existing != null:
		existing.queue_free()
	var modal = RecoveryCenterModalScript.new()
	modal.name = "RecoveryCenterModal"
	$HUD.add_child(modal)
