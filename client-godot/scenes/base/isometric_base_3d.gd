extends Node3D

## Isometric 3D Grand Citadel Multi-Floor Lobby (Pick Me Up: Infinite Gacha Architecture)
## - 5x Grand Fortress Area: 44m x 36m Rectangular Perimeter + Central Circular Plaza & Cross Avenues
## - Tiered Central Fountain (⛲ Đài Phun Nước Trung Tâm) replacing the central bonfire
## - South Wall (+Z): Tower Dungeon Gate (⛩️ Cổng Tháp / Cổng Thành) integrated into perimeter wall
## - North Wall (-Z): Summon Altar (✨ Đài Triệu Hồi) on stone terrace
## - West Wall (-X): Barracks (Doanh Trại Tướng & Thăng Sao)
## - East Wall (+X): Infirmary (Bệnh Xá & Hậu Cần)
## - Multi-Floor Grand Atrium / Mezzanine Citadel: Vertically stacked at X=0, Z=0 (Y = (floor-1) * 5.2m)
## - 8 Building Plots per Floor (Total 48 plots across 6 floors: 2 North, 2 South, 2 West, 2 East)

const UNIT_ACTOR_SCENE := preload("res://scenes/common/unit_actor_3d.tscn")
const BASE_PLOT_SCENE := preload("res://scenes/base/base_plot_3d.tscn")

const MAX_LOBBY_FLOORS := 6
const FLOOR_HEIGHT := 5.2
const MASTER_LEVELS_PER_FLOOR := 15
const PLOTS_PER_FLOOR := 8

## 3D Stepped Fortress Citadel ("Thành Trì Bậc Thang Đông -> Tây"):
## Floor 1 is the lower East grand courtyard (Gate at East +X, Fountain in center, Altar at West -X).
## Each upper floor terrace (Floors 2..6) sits flush at the West retaining wall of the previous floor,
## stepping backward and upward toward the West with zero overhead overlap (100% open-air ziggurat).
const FLOOR1_WEST_WALL_X := -23.5
const UPPER_TERRACE_WIDTH := 28.0
const UPPER_TERRACE_HALF_WIDTH := 14.0 # UPPER_TERRACE_WIDTH * 0.5

## 8 Building plot offsets on each stepped terrace floor:
## Placed symmetrically with wide clearance for staircases, avenues, and retaining walls
const FLOOR_PLOT_OFFSETS: Array[Vector3] = [
	# 4 North plots (Z = -8.0)
	Vector3(7.5, 0.0, -8.0),
	Vector3(2.5, 0.0, -8.0),
	Vector3(-2.5, 0.0, -8.0),
	Vector3(-7.5, 0.0, -8.0),
	# 4 South plots (Z = 8.0)
	Vector3(7.5, 0.0, 8.0),
	Vector3(2.5, 0.0, 8.0),
	Vector3(-2.5, 0.0, 8.0),
	Vector3(-7.5, 0.0, 8.0)
]

func get_floor_terrace_center(floor_num: int) -> Vector3:
	if floor_num <= 1:
		return Vector3.ZERO
	var idx := clampi(floor_num, 1, MAX_LOBBY_FLOORS) - 2 # 0 for floor 2, 1 for floor 3, ...
	var cx := FLOOR1_WEST_WALL_X - UPPER_TERRACE_HALF_WIDTH - (float(idx) * UPPER_TERRACE_WIDTH)
	var cy := float(floor_num - 1) * FLOOR_HEIGHT
	return Vector3(cx, cy, 0.0)

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
var _plot_nodes: Dictionary = {} # plot_index (1..18) -> BasePlot3D
var _floor_platforms: Dictionary = {} # floor_num (2..6) -> Node3D (Terrace Deck + Retaining Wall + 10h->4h Stairs)
var _floor_banners: Dictionary = {} # floor_num (1..6) -> Label3D
var _floor_buttons: Dictionary = {} # floor_num (1..6) -> Button
var _panorama_btn: Button = null
var _manage_floor_heroes_btn: Button = null
var _editing_floor_hero_selection: Dictionary = {} # floor_num (int) -> Array[String]
var _hero_actors: Dictionary = {} # hero_id -> UnitActor3D
var _active_banners: Array = []
var _active_floor_ring: MeshInstance3D = null
var _active_floor_light: OmniLight3D = null
var _floor1_current_trans: float = 0.0
var _floor_trans_map: Dictionary = {} # floor_num -> float
var _floor_isolation_tween: Tween = null
var _panorama_mode: bool = false

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
	_setup_grand_citadel_floor1()
	_setup_landmark_metadata()
	_spawn_stacked_3d_floors_and_plots()
	_build_floor_elevator_buttons()

	# Temporarily hide 2D Hub / Login navigation button for direct demo testing
	back_hub_btn.visible = false
	collect_all_btn.visible = false

	lighting_toggle_btn.pressed.connect(_on_lighting_toggle_pressed)
	focus_base_btn.pressed.connect(_on_focus_base_pressed)
	refresh_base_btn.pressed.connect(_sync_all_from_backend)
	back_hub_btn.pressed.connect(_on_back_hub_pressed)
	close_inspector_btn.pressed.connect(_close_inspector)

	summon_altar_btn.pressed.connect(func():
		_switch_to_lobby_floor(1)
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

	# Auto-authenticate default `demo` account so F5 enters straight into the 3D Waiting Room
	var demo_ok := await GameState.ensure_demo_session()
	if demo_ok:
		await _sync_all_from_backend()
		status_banner_label.text = "🏰 Đại Sảnh Thành Trì Thông Tầng — Tài khoản mặc định [%s (Lv.%d)] đã sẵn sàng!" % [
			GameState.master_name,
			GameState.master_level
		]
	else:
		status_banner_label.text = "⚠️ KHÔNG THỂ KẾT NỐI SERVER BACKEND (PORT 3000)! Vui lòng kiểm tra lại server."

## Configures the Grand Stepped Citadel Floor 1 Ground Courtyard (Thành Trì Bậc Thang):
## - Perimeter fortress walls: North, South, West, and East (embedded Gate facing inward)
## - East Wall (+X): Grand Tower Dungeon Gate (⛩️ Cổng Tháp Chinh Phạt PvE)
## - West Wall (-X): Raised Summon Altar (✨ Đài Triệu Hồi) with twin obelisks
## - Center: Tiered Central Fountain (⛲ Đài Phun Nước Trung Tâm)
## - North side: Barracks (🛡️ Doanh Trại & Thăng Sao)
## - South side: Infirmary (✚ Bệnh Xá & Hậu Cần)
## - Twin Symmetrical Grand Stairs flush against the West Wall flanking the Summon Altar leading up to Floor 2
func _setup_grand_citadel_floor1() -> void:
	var arch := $BaseArchitecture
	if arch == null:
		return

	# 1. Fortress Ground Courtyard: 48m (X) x 40m (Z)
	var ground: MeshInstance3D = arch.get_node_or_null("Ground")
	if ground != null:
		var ground_box := BoxMesh.new()
		ground_box.size = Vector3(48.0, 0.5, 40.0)
		ground.mesh = ground_box
		ground.position = Vector3(0.0, -0.25, 0.0)

	# 2. Central Cobblestone Plaza Disc (radius 11.5m)
	var plaza: MeshInstance3D = arch.get_node_or_null("CentralPlazaDisc")
	if plaza != null:
		var plaza_cyl := CylinderMesh.new()
		plaza_cyl.top_radius = 11.5
		plaza_cyl.bottom_radius = 11.8
		plaza_cyl.height = 0.22
		plaza.mesh = plaza_cyl
		plaza.position = Vector3(0.0, 0.05, 0.0)
		var plaza_mat := StandardMaterial3D.new()
		plaza_mat.albedo_color = Color(0.24, 0.28, 0.35)
		plaza_mat.roughness = 0.78
		plaza.material_override = plaza_mat

	# 3. Cross Avenues (+) connecting the Central Plaza to the 4 Citadel Gates/Wings
	var avenues_node := arch.get_node_or_null("CrossAvenues")
	if avenues_node == null:
		avenues_node = Node3D.new()
		avenues_node.name = "CrossAvenues"
		arch.add_child(avenues_node)

		var ave_mat := StandardMaterial3D.new()
		ave_mat.albedo_color = Color(0.28, 0.32, 0.40)
		ave_mat.roughness = 0.72

		# East-West Avenue (Z = 0, connecting Gate on East to Altar on West)
		var ew_ave := MeshInstance3D.new()
		var ew_box := BoxMesh.new()
		ew_box.size = Vector3(44.0, 0.12, 5.6)
		ew_ave.mesh = ew_box
		ew_ave.position = Vector3(0.0, 0.06, 0.0)
		ew_ave.material_override = ave_mat
		avenues_node.add_child(ew_ave)

		# North-South Avenue (X = 0, connecting Barracks to Infirmary)
		var ns_ave := MeshInstance3D.new()
		var ns_box := BoxMesh.new()
		ns_box.size = Vector3(5.6, 0.12, 36.0)
		ns_ave.mesh = ns_box
		ns_ave.position = Vector3(0.0, 0.06, 0.0)
		ns_ave.material_override = ave_mat
		avenues_node.add_child(ns_ave)

	# 4. Perimeter Fortress Walls & 4 Corner Bastion Towers
	var walls_node := arch.get_node_or_null("PerimeterFortressWalls")
	if walls_node == null:
		walls_node = Node3D.new()
		walls_node.name = "PerimeterFortressWalls"
		arch.add_child(walls_node)

		var wall_mat := StandardMaterial3D.new()
		wall_mat.albedo_color = Color(0.20, 0.24, 0.31)
		wall_mat.roughness = 0.85

		var trim_mat := StandardMaterial3D.new()
		trim_mat.albedo_color = Color(0.35, 0.42, 0.52)
		trim_mat.roughness = 0.65

		# North Wall (Z = -18.5)
		var north_w := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(47.0, 4.5, 1.4)
		north_w.mesh = nb
		north_w.position = Vector3(0.0, 2.25, -18.5)
		north_w.material_override = wall_mat
		walls_node.add_child(north_w)

		# South Wall (Z = 18.5)
		var south_w := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(47.0, 4.5, 1.4)
		south_w.mesh = sb
		south_w.position = Vector3(0.0, 2.25, 18.5)
		south_w.material_override = wall_mat
		walls_node.add_child(south_w)

		# West Wall (X = -23.5)
		var west_w := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(1.4, 4.5, 37.0)
		west_w.mesh = wb
		west_w.position = Vector3(-23.5, 2.25, 0.0)
		west_w.material_override = wall_mat
		walls_node.add_child(west_w)

		# East Wall (X = 23.5) with open center gateway (Z = [-4.0, 4.0])
		var east_w_north := MeshInstance3D.new()
		var ewn_box := BoxMesh.new()
		ewn_box.size = Vector3(1.4, 4.5, 14.5)
		east_w_north.mesh = ewn_box
		east_w_north.position = Vector3(23.5, 2.25, -11.25)
		east_w_north.material_override = wall_mat
		walls_node.add_child(east_w_north)

		var east_w_south := MeshInstance3D.new()
		var ews_box := BoxMesh.new()
		ews_box.size = Vector3(1.4, 4.5, 14.5)
		east_w_south.mesh = ews_box
		east_w_south.position = Vector3(23.5, 2.25, 11.25)
		east_w_south.material_override = wall_mat
		walls_node.add_child(east_w_south)

		# 4 Corner Bastion Towers
		var tower_corners := [
			Vector3(-23.5, 0.0, -18.5),
			Vector3(23.5, 0.0, -18.5),
			Vector3(-23.5, 0.0, 18.5),
			Vector3(23.5, 0.0, 18.5)
		]
		for c_pos in tower_corners:
			var tower := MeshInstance3D.new()
			var t_cyl := CylinderMesh.new()
			t_cyl.top_radius = 2.6
			t_cyl.bottom_radius = 2.8
			t_cyl.height = 6.2
			tower.mesh = t_cyl
			tower.position = c_pos + Vector3(0.0, 3.1, 0.0)
			tower.material_override = wall_mat
			walls_node.add_child(tower)

			var cap := MeshInstance3D.new()
			var cap_mesh := CylinderMesh.new()
			cap_mesh.top_radius = 2.9
			cap_mesh.bottom_radius = 2.6
			cap_mesh.height = 0.5
			cap.mesh = cap_mesh
			cap.position = c_pos + Vector3(0.0, 6.35, 0.0)
			cap.material_override = trim_mat
			walls_node.add_child(cap)

	# 5. Centerpiece: Tiered Central Fountain (⛲ Đài Phun Nước Trung Tâm)
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
			b_lbl.text = "⛲ ĐÀI PHUN NƯỚC TRUNG TÂM"
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

			# Lower stone basin
			var lower_basin := MeshInstance3D.new()
			var lb_cyl := CylinderMesh.new()
			lb_cyl.top_radius = 3.6
			lb_cyl.bottom_radius = 3.8
			lb_cyl.height = 0.65
			lower_basin.mesh = lb_cyl
			lower_basin.position = Vector3(0.0, 0.32, 0.0)
			lower_basin.material_override = stone_mat
			fountain_visuals.add_child(lower_basin)

			# Lower water pool
			var water_pool := MeshInstance3D.new()
			var wp_cyl := CylinderMesh.new()
			wp_cyl.top_radius = 3.35
			wp_cyl.bottom_radius = 3.35
			wp_cyl.height = 0.06
			water_pool.mesh = wp_cyl
			water_pool.position = Vector3(0.0, 0.60, 0.0)
			water_pool.material_override = water_mat
			fountain_visuals.add_child(water_pool)

			# Central pedestal
			var pedestal := MeshInstance3D.new()
			var ped_cyl := CylinderMesh.new()
			ped_cyl.top_radius = 1.15
			ped_cyl.bottom_radius = 1.35
			ped_cyl.height = 1.1
			pedestal.mesh = ped_cyl
			pedestal.position = Vector3(0.0, 1.05, 0.0)
			pedestal.material_override = stone_mat
			fountain_visuals.add_child(pedestal)

			# Upper stone basin
			var upper_basin := MeshInstance3D.new()
			var ub_cyl := CylinderMesh.new()
			ub_cyl.top_radius = 2.1
			ub_cyl.bottom_radius = 1.7
			ub_cyl.height = 0.38
			upper_basin.mesh = ub_cyl
			upper_basin.position = Vector3(0.0, 1.62, 0.0)
			upper_basin.material_override = stone_mat
			fountain_visuals.add_child(upper_basin)

			# Upper water layer
			var upper_water := MeshInstance3D.new()
			var uw_cyl := CylinderMesh.new()
			uw_cyl.top_radius = 1.95
			uw_cyl.bottom_radius = 1.95
			uw_cyl.height = 0.05
			upper_water.mesh = uw_cyl
			upper_water.position = Vector3(0.0, 1.78, 0.0)
			upper_water.material_override = water_mat
			fountain_visuals.add_child(upper_water)

			# Spire / Crystal fountain obelisk
			var spire := MeshInstance3D.new()
			var spire_cyl := CylinderMesh.new()
			spire_cyl.top_radius = 0.08
			spire_cyl.bottom_radius = 0.55
			spire_cyl.height = 1.55
			spire.mesh = spire_cyl
			spire.position = Vector3(0.0, 2.45, 0.0)
			var spire_mat := StandardMaterial3D.new()
			spire_mat.albedo_color = Color(0.45, 0.92, 1.0)
			spire_mat.emission_enabled = true
			spire_mat.emission = Color(0.35, 0.85, 1.0)
			spire_mat.emission_energy_multiplier = 1.8
			spire.material_override = spire_mat
			fountain_visuals.add_child(spire)

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

	# 6. CỔNG PHÍA ĐÔNG (+X): Tower Dungeon Gate (⛩️ Cổng Tháp / Cổng Thành)
	if dungeon_portal_mesh != null:
		dungeon_portal_mesh.position = Vector3(21.8, 2.8, 0.0)
		dungeon_portal_mesh.rotation = Vector3(0.0, deg_to_rad(90.0), 0.0)
	if portal_body != null:
		portal_body.position = Vector3(21.8, 0.0, 0.0)

	var portal_lbl: Label3D = arch.get_node_or_null("PortalLabel")
	if portal_lbl != null:
		portal_lbl.text = "⛩️ CỔNG THÁP CHINH PHẠT PvE (CỔNG ĐÔNG)"
		portal_lbl.position = Vector3(21.8, 6.5, 0.0)
	if portal_sub_label != null:
		portal_sub_label.position = Vector3(21.8, 5.9, 0.0)

	var gatehouse_visuals := arch.get_node_or_null("GatehouseVisuals")
	if gatehouse_visuals == null:
		gatehouse_visuals = Node3D.new()
		gatehouse_visuals.name = "GatehouseVisuals"
		arch.add_child(gatehouse_visuals)

		var gh_mat := StandardMaterial3D.new()
		gh_mat.albedo_color = Color(0.26, 0.30, 0.40)
		gh_mat.roughness = 0.70

		# Left gate pillar (North side of East gate)
		var lp := MeshInstance3D.new()
		var lpb := BoxMesh.new()
		lpb.size = Vector3(2.4, 5.8, 1.8)
		lp.mesh = lpb
		lp.position = Vector3(21.8, 2.9, -3.8)
		lp.material_override = gh_mat
		gatehouse_visuals.add_child(lp)

		# Right gate pillar (South side of East gate)
		var rp := MeshInstance3D.new()
		var rpb := BoxMesh.new()
		rpb.size = Vector3(2.4, 5.8, 1.8)
		rp.mesh = rpb
		rp.position = Vector3(21.8, 2.9, 3.8)
		rp.material_override = gh_mat
		gatehouse_visuals.add_child(rp)

		# Top gate arch / lintel spanning East gate
		var arch_beam := MeshInstance3D.new()
		var abb := BoxMesh.new()
		abb.size = Vector3(2.6, 1.4, 8.4)
		arch_beam.mesh = abb
		arch_beam.position = Vector3(21.8, 5.5, 0.0)
		arch_beam.material_override = gh_mat
		gatehouse_visuals.add_child(arch_beam)

	# 7. ĐÀI TRIỆU HỒI PHÍA TÂY (-X): Summon Altar (✨ Đài Triệu Hồi)
	if summon_altar_mesh != null:
		summon_altar_mesh.position = Vector3(-18.5, 0.75, 0.0)
	if altar_body != null:
		altar_body.position = Vector3(-18.5, 0.0, 0.0)
	var altar_lbl: Label3D = summon_altar_mesh.get_node_or_null("AltarLabel")
	if altar_lbl != null:
		altar_lbl.text = "✨ ĐÀI TRIỆU HỒI (TÂY)"
		altar_lbl.position = Vector3(0.0, 2.7, 0.0)
	var altar_sub: Label3D = summon_altar_mesh.get_node_or_null("AltarSubLabel")
	if altar_sub != null:
		altar_sub.position = Vector3(0.0, 2.15, 0.0)

	var altar_dais := arch.get_node_or_null("AltarDaisVisuals")
	if altar_dais == null:
		altar_dais = Node3D.new()
		altar_dais.name = "AltarDaisVisuals"
		arch.add_child(altar_dais)

		var dais_mat := StandardMaterial3D.new()
		dais_mat.albedo_color = Color(0.32, 0.38, 0.48)
		dais_mat.roughness = 0.60

		var dais_base := MeshInstance3D.new()
		var db_cyl := CylinderMesh.new()
		db_cyl.top_radius = 3.6
		db_cyl.bottom_radius = 4.0
		db_cyl.height = 0.6
		dais_base.mesh = db_cyl
		dais_base.position = Vector3(-18.5, 0.3, 0.0)
		dais_base.material_override = dais_mat
		altar_dais.add_child(dais_base)

		# Twin arcane obelisks flanking the West Altar
		var ob_mat := StandardMaterial3D.new()
		ob_mat.albedo_color = Color(0.25, 0.45, 0.65)
		ob_mat.emission_enabled = true
		ob_mat.emission = Color(0.2, 0.6, 0.95)
		ob_mat.emission_energy_multiplier = 1.2

		for z_sign in [-1.0, 1.0]:
			var ob := MeshInstance3D.new()
			var ob_mesh := CylinderMesh.new()
			ob_mesh.top_radius = 0.12
			ob_mesh.bottom_radius = 0.45
			ob_mesh.height = 3.4
			ob.mesh = ob_mesh
			ob.position = Vector3(-18.5, 1.7, z_sign * 3.6)
			ob.material_override = ob_mat
			altar_dais.add_child(ob)

	# 8. HAI CẦU THANG ĐỐI XỨNG ÁP SÁT TƯỜNG TÂY (KIỂU A - FLANKING SUMMON ALTAR LEADING TO FLOOR 2)
	var twin_stairs := arch.get_node_or_null("TwinWallStairs")
	if twin_stairs == null:
		twin_stairs = Node3D.new()
		twin_stairs.name = "TwinWallStairs"
		arch.add_child(twin_stairs)

		var stair_mat := StandardMaterial3D.new()
		stair_mat.albedo_color = Color(0.35, 0.40, 0.50)
		stair_mat.roughness = 0.70

		var rail_mat := StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.45, 0.52, 0.65)
		rail_mat.roughness = 0.55

		var step_count := 14
		for s_idx in range(step_count):
			var t := float(s_idx + 1) / float(step_count + 1)
			var sy := lerpf(0.20, FLOOR_HEIGHT, t)

			# North Staircase (flush against West wall X = -21.4, ascending from Z = -15.5 towards center Z = -4.8)
			var n_step := MeshInstance3D.new()
			var step_box := BoxMesh.new()
			step_box.size = Vector3(2.4, 0.38, 0.88)
			n_step.mesh = step_box
			var n_sz := lerpf(-15.5, -4.8, t)
			n_step.position = Vector3(-21.4, sy, n_sz)
			n_step.material_override = stair_mat
			twin_stairs.add_child(n_step)

			# South Staircase (flush against West wall X = -21.4, ascending from Z = +15.5 towards center Z = +4.8)
			var s_step := MeshInstance3D.new()
			s_step.mesh = step_box
			var s_sz := lerpf(15.5, 4.8, t)
			s_step.position = Vector3(-21.4, sy, s_sz)
			s_step.material_override = stair_mat
			twin_stairs.add_child(s_step)

		# Upper stone landing platforms connecting the top of the stairs directly to Floor 2 terrace
		for z_side in [-4.4, 4.4]:
			var landing := MeshInstance3D.new()
			var l_box := BoxMesh.new()
			l_box.size = Vector3(2.6, 0.42, 1.8)
			landing.mesh = l_box
			landing.position = Vector3(-21.4, FLOOR_HEIGHT - 0.21, z_side)
			landing.material_override = stair_mat
			twin_stairs.add_child(landing)

	# 9. Doanh Trại & Bệnh Xá (North & South courtyard wings)
	if barracks_mesh != null:
		barracks_mesh.position = Vector3(-5.0, 1.6, -11.0)
		var b_box := BoxMesh.new()
		b_box.size = Vector3(4.6, 3.2, 5.8)
		barracks_mesh.mesh = b_box
	if barracks_body != null and barracks_body.has_node("CollisionShape3D"):
		var b_shape: CollisionShape3D = barracks_body.get_node("CollisionShape3D")
		var bs := BoxShape3D.new()
		bs.size = Vector3(5.0, 3.6, 6.2)
		b_shape.shape = bs
	var bar_lbl: Label3D = barracks_mesh.get_node_or_null("BarracksLabel")
	if bar_lbl != null:
		bar_lbl.position = Vector3(0.0, 2.4, 0.0)

	if infirmary_mesh != null:
		infirmary_mesh.position = Vector3(-5.0, 1.6, 11.0)
		var i_box := BoxMesh.new()
		i_box.size = Vector3(4.6, 3.2, 5.8)
		infirmary_mesh.mesh = i_box
	if infirmary_body != null and infirmary_body.has_node("CollisionShape3D"):
		var i_shape: CollisionShape3D = infirmary_body.get_node("CollisionShape3D")
		var ishape := BoxShape3D.new()
		ishape.size = Vector3(5.0, 3.6, 6.2)
		i_shape.shape = ishape
	var inf_lbl: Label3D = infirmary_mesh.get_node_or_null("InfirmaryLabel")
	if inf_lbl != null:
		inf_lbl.position = Vector3(0.0, 2.4, 0.0)

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

	# Glowing Active Terrace Halo Ring & Focus Light that rides with the observed floor
	_active_floor_ring = MeshInstance3D.new()
	var ring_torus := TorusMesh.new()
	ring_torus.inner_radius = 11.2
	ring_torus.outer_radius = 11.6
	_active_floor_ring.mesh = ring_torus
	_active_floor_ring.position = Vector3(0.0, 0.08, 0.0)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.32, 0.86, 1.0)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.22, 0.72, 1.0)
	ring_mat.emission_energy_multiplier = 1.8
	_active_floor_ring.material_override = ring_mat
	zones_container.add_child(_active_floor_ring)

	_active_floor_light = OmniLight3D.new()
	_active_floor_light.light_color = Color(0.85, 0.94, 1.0)
	_active_floor_light.light_energy = 2.0
	_active_floor_light.omni_range = 24.0
	_active_floor_light.position = Vector3(0.0, 5.0, 0.0)
	zones_container.add_child(_active_floor_light)

	for f_idx in range(MAX_LOBBY_FLOORS):
		var floor_num := f_idx + 1
		var terrace_center := get_floor_terrace_center(floor_num)
		_floor_trans_map[floor_num] = 0.0

		# Upper Stepped Fortress Terraces (Floors 2..6)
		if floor_num >= 2:
			var terrace_root := _build_terrace_step_3d(floor_num, terrace_center)
			zones_container.add_child(terrace_root)
			_floor_platforms[floor_num] = terrace_root

		var req_lvl := 1 if floor_num <= 1 else (floor_num - 1) * MASTER_LEVELS_PER_FLOOR
		var f_banner := Label3D.new()
		f_banner.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		f_banner.no_depth_test = true
		f_banner.font_size = 24
		f_banner.outline_size = 6
		f_banner.position = terrace_center + Vector3(0.0, 4.8, -16.5)
		f_banner.text = "🏰 THÀNH TRÌ BẬC THANG TẦNG #%d (Mở ở Master Lv.%d)" % [floor_num, req_lvl]
		zones_container.add_child(f_banner)
		_floor_banners[floor_num] = f_banner

		for p_local in range(PLOTS_PER_FLOOR):
			var plot_num := f_idx * PLOTS_PER_FLOOR + p_local + 1
			var plot_node: BasePlot3D = BASE_PLOT_SCENE.instantiate()
			plot_node.plot_index = plot_num
			plot_node.zone_index = floor_num
			plots_container.add_child(plot_node)
			plot_node.global_position = terrace_center + FLOOR_PLOT_OFFSETS[p_local]
			_plot_nodes[plot_num] = plot_node

## Builds a 3D Stepped Fortress Terrace ("Thành Trì Bậc Thang") for `floor_num` >= 2:
## - Solid stone terrace platform deck (no open hole)
## - Fortified retaining wall / cliff foundation along the East front
## - North & South perimeter walls
## - 2 Symmetrical stone staircases along North & South walls ascending to the next tier
func _build_terrace_step_3d(floor_num: int, terrace_center: Vector3) -> Node3D:
	var terrace_root := Node3D.new()
	terrace_root.name = "SteppedTerrace_%d" % floor_num
	terrace_root.position = terrace_center

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.29, 0.38)
	floor_mat.roughness = 0.74

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.20, 0.24, 0.31)
	wall_mat.roughness = 0.85

	var stair_mat := StandardMaterial3D.new()
	stair_mat.albedo_color = Color(0.35, 0.40, 0.50)
	stair_mat.roughness = 0.70

	# 1. Solid rectangular stone terrace deck (28m x 36m)
	var deck := MeshInstance3D.new()
	var deck_box := BoxMesh.new()
	deck_box.size = Vector3(UPPER_TERRACE_WIDTH, 0.45, 36.0)
	deck.mesh = deck_box
	deck.position = Vector3(0.0, -0.225, 0.0)
	deck.material_override = floor_mat
	terrace_root.add_child(deck)

	# 2. Fortified retaining wall dropping down to the lower tier along the East front edge
	var retaining_w := MeshInstance3D.new()
	var rw_box := BoxMesh.new()
	rw_box.size = Vector3(1.2, FLOOR_HEIGHT, 36.0)
	retaining_w.mesh = rw_box
	retaining_w.position = Vector3(UPPER_TERRACE_HALF_WIDTH - 0.6, -(FLOOR_HEIGHT * 0.5), 0.0)
	retaining_w.material_override = wall_mat
	terrace_root.add_child(retaining_w)

	# 3. Perimeter walls for this terrace
	var pw_north := MeshInstance3D.new()
	var pwn_box := BoxMesh.new()
	pwn_box.size = Vector3(UPPER_TERRACE_WIDTH, 4.2, 1.2)
	pw_north.mesh = pwn_box
	pw_north.position = Vector3(0.0, 2.1, -18.0)
	pw_north.material_override = wall_mat
	terrace_root.add_child(pw_north)

	var pw_south := MeshInstance3D.new()
	var pws_box := BoxMesh.new()
	pws_box.size = Vector3(UPPER_TERRACE_WIDTH, 4.2, 1.2)
	pw_south.mesh = pws_box
	pw_south.position = Vector3(0.0, 2.1, 18.0)
	pw_south.material_override = wall_mat
	terrace_root.add_child(pw_south)

	var pw_west := MeshInstance3D.new()
	var pww_box := BoxMesh.new()
	pww_box.size = Vector3(1.2, 4.2, 36.0)
	pw_west.mesh = pww_box
	pw_west.position = Vector3(-UPPER_TERRACE_HALF_WIDTH + 0.6, 2.1, 0.0)
	pw_west.material_override = wall_mat
	terrace_root.add_child(pw_west)

	# Front stone balustrade overlooking lower floor with center opening
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.45, 0.52, 0.65)
	rail_mat.roughness = 0.55

	for z_side in [-11.5, 11.5]:
		var f_rail := MeshInstance3D.new()
		var fb_box := BoxMesh.new()
		fb_box.size = Vector3(0.32, 0.95, 11.0)
		f_rail.mesh = fb_box
		f_rail.position = Vector3(UPPER_TERRACE_HALF_WIDTH - 0.25, 0.48, z_side)
		f_rail.material_override = rail_mat
		terrace_root.add_child(f_rail)

	# 4. Two Symmetrical Staircases flush against the West Wall leading up to the next tier (Kiểu A)
	if floor_num < MAX_LOBBY_FLOORS:
		var step_count := 12
		for s_idx in range(step_count):
			var t := float(s_idx + 1) / float(step_count + 1)
			var sy := lerpf(0.20, FLOOR_HEIGHT, t)

			# North Staircase (flush against West wall X = -12.4, ascending from Z = -13.5 to -4.2)
			var n_step := MeshInstance3D.new()
			var step_box := BoxMesh.new()
			step_box.size = Vector3(2.2, 0.38, 0.85)
			n_step.mesh = step_box
			var n_sz := lerpf(-13.5, -4.2, t)
			n_step.position = Vector3(-UPPER_TERRACE_HALF_WIDTH + 1.6, sy, n_sz)
			n_step.material_override = stair_mat
			terrace_root.add_child(n_step)

			# South Staircase (flush against West wall X = -12.4, ascending from Z = +13.5 to +4.2)
			var s_step := MeshInstance3D.new()
			s_step.mesh = step_box
			var s_sz := lerpf(13.5, 4.2, t)
			s_step.position = Vector3(-UPPER_TERRACE_HALF_WIDTH + 1.6, sy, s_sz)
			s_step.material_override = stair_mat
			terrace_root.add_child(s_step)

		# Upper landing connectors bridging into next terrace
		for z_side in [-4.4, 4.4]:
			var landing := MeshInstance3D.new()
			var l_box := BoxMesh.new()
			l_box.size = Vector3(2.4, 0.42, 1.8)
			landing.mesh = l_box
			landing.position = Vector3(-UPPER_TERRACE_HALF_WIDTH + 0.5, FLOOR_HEIGHT - 0.21, z_side)
			landing.material_override = stair_mat
			terrace_root.add_child(landing)

	# 5. Central stone terrace pavilion / mosaic plaza ring
	var plaza_disc := MeshInstance3D.new()
	var pd_mesh := CylinderMesh.new()
	pd_mesh.top_radius = 5.2
	pd_mesh.bottom_radius = 5.5
	pd_mesh.height = 0.12
	plaza_disc.mesh = pd_mesh
	plaza_disc.position = Vector3(0.0, 0.06, 0.0)
	var pd_mat := StandardMaterial3D.new()
	pd_mat.albedo_color = Color(0.30, 0.35, 0.46)
	pd_mat.roughness = 0.65
	plaza_disc.material_override = pd_mat
	terrace_root.add_child(plaza_disc)

	return terrace_root

func _build_floor_elevator_buttons() -> void:
	for child in floor_buttons_container.get_children():
		child.queue_free()
	_floor_buttons.clear()

	# 1. Nút Xem Toàn Bộ 6 Tầng (Panorama mode)
	var panorama_btn := Button.new()
	panorama_btn.custom_minimum_size = Vector2(0, 34)
	panorama_btn.text = "🌐 Xem Toàn Bộ 6 Tầng"
	panorama_btn.pressed.connect(_show_all_floors_panorama)
	floor_buttons_container.add_child(panorama_btn)
	_panorama_btn = panorama_btn

	# 2. Render from Floor 6 down to Floor 1
	for f_num in range(MAX_LOBBY_FLOORS, 0, -1):
		var req_lvl := 1 if f_num <= 1 else (f_num - 1) * MASTER_LEVELS_PER_FLOOR
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 34)
		btn.text = "🏢 Tầng %d (Lv.%d)" % [f_num, req_lvl]
		var target_floor := f_num
		btn.pressed.connect(func(): _switch_to_lobby_floor(target_floor))
		floor_buttons_container.add_child(btn)
		_floor_buttons[f_num] = btn

	# 3. Nút tùy chọn chọn tướng xuất hiện tại sảnh cho tầng đang xem
	var manage_btn := Button.new()
	manage_btn.custom_minimum_size = Vector2(0, 34)
	manage_btn.text = "👥 Chọn Tướng Tầng %d" % _current_lobby_floor
	manage_btn.pressed.connect(func(): _open_floor_hero_manager(_current_lobby_floor))
	floor_buttons_container.add_child(manage_btn)
	_manage_floor_heroes_btn = manage_btn

func _show_all_floors_panorama() -> void:
	_close_inspector()
	_panorama_mode = true
	var mid_center := get_floor_terrace_center(1).lerp(get_floor_terrace_center(MAX_LOBBY_FLOORS), 0.5)
	camera_rig.focus_base_overview(mid_center + Vector3(0.0, 2.0, 0.0), 98.0, 0.65)
	_apply_floor_focus_isolation(0, false, 0)
	status_banner_label.text = "🌐 Đang xem toàn cảnh tất cả 6 tầng Thành Trì Bậc Thang (Stepped Citadel Terraces Đông -> Tây)."
	_refresh_hud()

func _switch_to_lobby_floor(floor_num: int) -> void:
	var next_floor := clampi(floor_num, 1, MAX_LOBBY_FLOORS)
	var travel_dir := signi(next_floor - _current_lobby_floor)
	_current_lobby_floor = next_floor
	_panorama_mode = false
	var terrace_center := get_floor_terrace_center(_current_lobby_floor)
	camera_rig.focus_lobby_floor(terrace_center, 0.55)
	_apply_floor_focus_isolation(_current_lobby_floor, true, travel_dir)

	var req_lvl := 1 if _current_lobby_floor <= 1 else (_current_lobby_floor - 1) * MASTER_LEVELS_PER_FLOOR
	var is_open := _current_lobby_floor <= GameState.unlocked_lobby_floors
	status_banner_label.text = "🏰 Đang quan sát Tầng Bậc Thang #%d (Thành Trì Đông -> Tây & 8 Ô Xây Dựng) — %s" % [
		_current_lobby_floor,
		"Đã mở khóa ✅" if is_open else ("🔒 Mở khóa khi Master đạt cấp %d (hoặc nhấn Mở Tầng)" % req_lvl)
	]
	_refresh_hud()

## Isolates the currently observed floor (`active_floor_num`) while keeping lower stepped
## terraces visible to maintain the grand mountain citadel tiered aesthetic.
func _apply_floor_focus_isolation(active_floor_num: int, animate: bool = true, travel_dir: int = 0) -> void:
	if _floor_isolation_tween and _floor_isolation_tween.is_valid():
		_floor_isolation_tween.kill()

	var target_center := get_floor_terrace_center(active_floor_num)
	var ring_radius_scale := 1.15 if active_floor_num == 1 else 0.95

	# 1. Move & pulse the Active Terrace Halo Ring + Spotlight
	if _active_floor_ring != null and _active_floor_light != null:
		if _panorama_mode:
			_active_floor_ring.visible = false
			_active_floor_light.visible = false
		else:
			var target_ring_pos := target_center + Vector3(0.0, 0.08, 0.0)
			var target_light_pos := target_center + Vector3(0.0, 5.0, 0.0)
			_active_floor_ring.visible = true
			_active_floor_light.visible = true
			if not animate:
				_active_floor_ring.position = target_ring_pos
				_active_floor_ring.scale = Vector3(ring_radius_scale, 1.0, ring_radius_scale)
				_active_floor_light.position = target_light_pos
			else:
				_floor_isolation_tween = create_tween().set_parallel(true)
				_floor_isolation_tween.tween_property(_active_floor_ring, "position", target_ring_pos, 0.45).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
				_floor_isolation_tween.tween_property(_active_floor_light, "position", target_light_pos, 0.45).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
				_active_floor_ring.scale = Vector3(ring_radius_scale * 0.84, 1.0, ring_radius_scale * 0.84)
				_floor_isolation_tween.tween_property(_active_floor_ring, "scale", Vector3(ring_radius_scale, 1.0, ring_radius_scale), 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 2. Floor 1 Central Plaza & Landmarks:
	# Visible whenever viewing Floor 1 or as lower terrace in panorama / upper tiers
	var floor1_interactive := (active_floor_num == 1)
	var floor1_visible := (active_floor_num == 1 or _panorama_mode or active_floor_num <= 3)
	var arch := $BaseArchitecture
	if arch != null:
		arch.visible = floor1_visible
		arch.process_mode = Node.PROCESS_MODE_INHERIT if floor1_interactive else Node.PROCESS_MODE_DISABLED
	_set_floor1_landmarks_interactive(floor1_interactive)
	if bonfire_light != null:
		bonfire_light.visible = floor1_visible
	if dungeon_portal_mesh != null:
		dungeon_portal_mesh.visible = floor1_visible
	var floor1_trans := 0.0 if (active_floor_num == 1 or _panorama_mode) else 0.15
	_apply_floor1_architecture_transparency(floor1_trans)

	# 3. Upper Stepped Fortress Terraces (Floors 2..6):
	# Show active floor platform, or all floors in panorama mode.
	# Terraces above the active floor are hidden so they don't occlude the camera view.
	for f_num in range(2, MAX_LOBBY_FLOORS + 1):
		var is_active := (f_num == active_floor_num or _panorama_mode)
		var is_below := (f_num < active_floor_num)

		if _floor_banners.has(f_num):
			var banner: Label3D = _floor_banners[f_num]
			banner.visible = is_active
			banner.modulate.a = 1.0 if is_active else 0.0

		if _floor_platforms.has(f_num):
			var terrace_root: Node3D = _floor_platforms[f_num]
			var show_platform := (is_active or is_below)
			terrace_root.visible = show_platform
			terrace_root.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
			if show_platform:
				terrace_root.scale = Vector3.ONE
				terrace_root.position = get_floor_terrace_center(f_num)
				var trans := 0.0 if is_active else 0.20
				_set_terrace_node_transparency(terrace_root, trans)

	# 4. All Building Plots (8 per Floor): Render plot thuộc tầng đang xem hoặc toàn bộ khi xem Toàn Cảnh
	for p_num in _plot_nodes.keys():
		var plot_node: BasePlot3D = _plot_nodes[p_num]
		var is_active := (plot_node.zone_index == active_floor_num or _panorama_mode)
		var is_above := (plot_node.zone_index > active_floor_num)
		plot_node.set_floor_focus_state(is_active, is_above, animate, travel_dir)

	# 5. Resident Heroes: Render hero thuộc tầng đang xem hoặc toàn bộ khi xem Toàn Cảnh
	for hid in _hero_actors.keys():
		var actor: UnitActor3D = _hero_actors[hid]
		if is_instance_valid(actor):
			var is_actor_active := (actor.floor_index == active_floor_num or _panorama_mode)
			actor.set_floor_focus_state(is_actor_active, animate)

func _set_terrace_node_transparency(terrace_root: Node3D, trans: float) -> void:
	if terrace_root == null:
		return
	for child in terrace_root.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).transparency = trans

func _set_floor1_landmarks_interactive(enabled: bool) -> void:
	for body in [bonfire_body, altar_body, portal_body, barracks_body, infirmary_body]:
		if body != null and body.has_node("CollisionShape3D"):
			var shape: CollisionShape3D = body.get_node("CollisionShape3D")
			shape.disabled = not enabled

func _apply_floor1_architecture_transparency(trans: float) -> void:
	_floor1_current_trans = trans
	var arch := $BaseArchitecture
	if arch == null:
		return
	var show_labels := trans < 0.35
	var label_alpha := clampf(1.0 - trans * 1.2, 0.0, 1.0)
	for node in arch.find_children("*", "GeometryInstance3D", true, false):
		if node is Label3D:
			var lbl := node as Label3D
			lbl.visible = show_labels
			lbl.modulate.a = label_alpha
		elif node is MeshInstance3D:
			(node as MeshInstance3D).transparency = trans

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

func _refresh_hud() -> void:
	var m_name := GameState.master_name if GameState.master_name != "" else "Master"
	var unlocked_floors := GameState.unlocked_lobby_floors

	master_info_label.text = "🏰 %s (Lv.%d) · Tầng %d/%d (Đã mở %d Tầng)" % [
		m_name,
		GameState.master_level,
		_current_lobby_floor,
		MAX_LOBBY_FLOORS,
		unlocked_floors
	]

	var gems := _format_num(GameState.gem_stones)
	var gold := _format_num(GameState.silver_coins)
	var scrolls := _format_num(GameState.normal_scrolls)
	var ration := _format_num(int(GameState.materials.get("RATION", 0)))

	# Chỉ hiển thị Đá Quý, Vàng, Thiên Thư, Khẩu Phần theo đúng thiết kế Sảnh Chờ
	resource_info_label.text = "💎 Đá Quý: %s   |   🪙 Vàng: %s   |   📜 Thiên Thư: %s   |   🍖 Khẩu Phần: %s" % [
		gems,
		gold,
		scrolls,
		ration
	]

	if portal_sub_label != null:
		portal_sub_label.text = "Đội hình xuất kích: %d/5 Tướng [Kéo-thả Tướng vào đây]" % GameState.active_party_ids.size()

	# Update Panorama Button
	if _panorama_btn != null:
		if _panorama_mode:
			_panorama_btn.text = "▶ 🌐 Toàn Bộ 6 Tầng"
			_panorama_btn.modulate = Color(1.0, 0.92, 0.45)
		else:
			_panorama_btn.text = "🌐 Xem Toàn Bộ 6 Tầng"
			_panorama_btn.modulate = Color(0.85, 0.92, 1.0)

	# Update Floor Elevator Buttons
	for f_num in _floor_buttons.keys():
		var btn: Button = _floor_buttons[f_num]
		var req_lvl := 1 if int(f_num) <= 1 else (int(f_num) - 1) * MASTER_LEVELS_PER_FLOOR
		var is_open := int(f_num) <= unlocked_floors
		var is_active := (int(f_num) == _current_lobby_floor and not _panorama_mode)
		var active_prefix := "▶ " if is_active else ""
		var lock_icon := "🏢" if is_open else "🔒"
		btn.text = "%s%s Tầng %d (Lv.%d)" % [active_prefix, lock_icon, int(f_num), req_lvl]
		btn.modulate = Color(1.0, 0.92, 0.45) if is_active else (Color(0.82, 0.96, 0.86) if is_open else Color(0.65, 0.65, 0.72))

	if _manage_floor_heroes_btn != null:
		_manage_floor_heroes_btn.text = "👥 Chọn Tướng Tầng %d" % _current_lobby_floor
		_manage_floor_heroes_btn.disabled = (_current_lobby_floor > unlocked_floors)

	# Update Expand Floor button
	var exp_info: Dictionary = GameState.base_overview.get("expansion", {})
	if bool(exp_info.get("canExpand", true)) and GameState.base_zones < MAX_LOBBY_FLOORS:
		var next_z := int(exp_info.get("nextZone", GameState.base_zones + 1))
		var cost := int(exp_info.get("costSilver", 2000))
		expand_zone_btn.text = "🏗️ Mở Tầng %d (🪙 %s)" % [next_z, _format_num(cost)]
		expand_zone_btn.disabled = false
	else:
		expand_zone_btn.text = "🏗️ Tối Đa (6 Tầng)"
		expand_zone_btn.disabled = true

func _refresh_3d_plots() -> void:
	var unlocked_floors := GameState.unlocked_lobby_floors
	var unlocked_plot_count := GameState.unlocked_plots

	for f_num in _floor_banners.keys():
		var banner: Label3D = _floor_banners[f_num]
		var req_lvl := 1 if int(f_num) <= 1 else (int(f_num) - 1) * MASTER_LEVELS_PER_FLOOR
		if int(f_num) <= unlocked_floors:
			banner.text = "🏢 TẦNG SẢNH CHỜ #%d [ĐÃ MỞ — Master Lv.%d+]" % [int(f_num), req_lvl]
			banner.modulate = Color(0.55, 0.96, 0.68)
		else:
			banner.text = "🔒 TẦNG SẢNH CHỜ #%d [Mở ở Master Lv.%d]" % [int(f_num), req_lvl]
			banner.modulate = Color(0.78, 0.62, 0.65)

	for plot_num in _plot_nodes.keys():
		var plot_node: BasePlot3D = _plot_nodes[plot_num]
		var is_unlocked := int(plot_num) <= unlocked_plot_count
		var b_data := GameState.get_building_on_plot(int(plot_num))
		plot_node.setup_plot(int(plot_num), is_unlocked, b_data)

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
	var unlocked_floors: int = clampi(GameState.unlocked_lobby_floors, 1, MAX_LOBBY_FLOORS)

	# Phân bổ hero cho các tầng: mỗi tầng TỐI ĐA 6 hero để chống lag
	var floor_heroes: Dictionary = {}
	for f in range(1, MAX_LOBBY_FLOORS + 1):
		floor_heroes[f] = []

	var assigned_hero_ids: Dictionary = {}

	# 1. Ưu tiên cấu hình tùy chọn Master đã chọn riêng cho từng tầng (nếu có)
	for f in range(1, MAX_LOBBY_FLOORS + 1):
		var custom_ids: Array = GameState.get_assigned_heroes_for_floor(f)
		for hid in custom_ids:
			if assigned_hero_ids.has(hid):
				continue
			var h_data := GameState.get_hero_by_id(hid)
			if not h_data.is_empty() and floor_heroes[f].size() < MAX_HEROES_PER_FLOOR:
				floor_heroes[f].append(h_data)
				assigned_hero_ids[hid] = f

	# 2. Với các tầng chưa cấu hình hoặc còn slot:
	# 2a. Ưu tiên các hero đang được phân công làm việc (worker) tại các plot của tầng đó
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
				var has_custom: bool = not GameState.get_assigned_heroes_for_floor(f_idx).is_empty()
				if not has_custom and floor_heroes[f_idx].size() < MAX_HEROES_PER_FLOOR:
					floor_heroes[f_idx].append(h)
					assigned_hero_ids[hid] = f_idx

	# 2b. Ưu tiên các hero trong Đội hình Chinh phạt (active party): xếp tại Tầng 1 (nếu Tầng 1 chưa có custom list)
	var f1_has_custom: bool = not GameState.get_assigned_heroes_for_floor(1).is_empty()
	if not f1_has_custom:
		for h in roster:
			var hid := str(h.get("id", ""))
			if assigned_hero_ids.has(hid):
				continue
			if GameState.active_party_ids.has(hid):
				if floor_heroes[1].size() < MAX_HEROES_PER_FLOOR:
					floor_heroes[1].append(h)
					assigned_hero_ids[hid] = 1

	# 2c. Các hero còn lại: rải đều vào các tầng đã mở khóa chưa có custom list (mỗi tầng tối đa 6 hero)
	for h in roster:
		var hid := str(h.get("id", ""))
		if assigned_hero_ids.has(hid):
			continue
		var placed := false
		for f in range(1, unlocked_floors + 1):
			var f_has_custom: bool = not GameState.get_assigned_heroes_for_floor(f).is_empty()
			if not f_has_custom and floor_heroes[f].size() < MAX_HEROES_PER_FLOOR:
				floor_heroes[f].append(h)
				assigned_hero_ids[hid] = f
				placed = true
				break
		if not placed:
			# Tất cả các tầng mở khóa đã đủ 6 hero -> dừng lại (không spawn thêm tránh lag)
			pass

	# Spawn các hero đã phân bổ cho từng tầng
	for f_num in range(1, MAX_LOBBY_FLOORS + 1):
		var heroes_on_floor: Array = floor_heroes[f_num]
		var count := heroes_on_floor.size()
		if count == 0:
			continue

		var terrace_center := get_floor_terrace_center(f_num)

		for i in range(count):
			var h: Dictionary = heroes_on_floor[i]
			var hid := str(h.get("id", ""))
			var actor: UnitActor3D = UNIT_ACTOR_SCENE.instantiate()
			heroes_container.add_child(actor)

			var angle := (TAU / float(count)) * float(i) + randf_range(-0.15, 0.15)
			var radius := randf_range(5.0, 9.2) if f_num == 1 else randf_range(11.0, 14.8)

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

			var default_pos := terrace_center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
			var in_party := GameState.active_party_ids.has(hid)
			actor.floor_index = f_num
			actor.setup_base_resident(h, default_pos, worker_info, in_party, infirmary_mesh.global_position, terrace_center)
			actor.set_floor_focus_state(f_num == _current_lobby_floor or _panorama_mode, false)
			_hero_actors[hid] = actor

	_apply_floor_focus_isolation(_current_lobby_floor, false, 0)

# ==============================================================================
# 3D RAYCAST INPUT, FLOOR ELEVATOR SHORTCUTS & PICK ME UP DRAG-AND-DROP
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_E or ke.keycode == KEY_PAGEUP:
			_switch_to_lobby_floor(mini(MAX_LOBBY_FLOORS, _current_lobby_floor + 1))
			return
		elif ke.keycode == KEY_Q or ke.keycode == KEY_PAGEDOWN:
			_switch_to_lobby_floor(maxi(1, _current_lobby_floor - 1))
			return

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pressed_hero != null and _dragging_hero == null:
			if mm.position.distance_to(_press_screen_pos) >= DRAG_THRESHOLD_PX:
				_dragging_hero = _pressed_hero
				_dragging_hero.start_drag_lift()
				status_banner_label.text = "🙌 Đang nhấc [%s]! Thả vào Công trình trên Tầng %d để phân công, hoặc thả vào Cổng Tháp để vào Đội hình PvE!" % [_dragging_hero.unit_name, _current_lobby_floor]

		if _dragging_hero != null:
			var ground_hit := _project_mouse_to_active_floor(mm.position)
			_dragging_hero.update_drag_ground_position(ground_hit)
			_update_hover_feedback(mm.position, true)
		else:
			_update_hover_feedback(mm.position, false)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_mouse_down(mb.position)
			else:
				_on_left_mouse_up(mb.position)

func _on_left_mouse_down(screen_pos: Vector2) -> void:
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
			if plot_node != null:
				_current_lobby_floor = plot_node.zone_index
				var t_center := get_floor_terrace_center(_current_lobby_floor)
				camera_rig.current_floor_y = t_center.y
				camera_rig.current_terrace_center = t_center
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
	var ground_pos := _project_mouse_to_active_floor(screen_pos)
	var terrace_center := get_floor_terrace_center(_current_lobby_floor)
	var max_r := 16.5 if _current_lobby_floor == 1 else 16.0
	var drop_rel := ground_pos - terrace_center
	var drop_horiz := Vector2(drop_rel.x, drop_rel.z)
	if drop_horiz.length() > max_r:
		drop_horiz = drop_horiz.normalized() * (max_r - 0.3)
	ground_pos = terrace_center + Vector3(drop_horiz.x, 0.0, drop_horiz.y)

	hero_actor.floor_index = _current_lobby_floor
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

	status_banner_label.text = "📍 Đã đặt [%s] tại Tầng Sảnh Chờ #%d." % [hero_actor.unit_name, _current_lobby_floor]
	hero_actor.show_speech_bubble("😮‍💨 Phù... Tầng %d nhìn thoáng đãng thật đấy!" % _current_lobby_floor, 2.8)

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
					status_banner_label.text = "🎯 Thả chuột để phân công [%s] vào [%s] (Tầng %d)!" % [_dragging_hero.unit_name, b_name, next_hovered_plot.zone_index]
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
	var to := from + dir * 250.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = exclude_rids
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)

func _project_mouse_to_active_floor(screen_pos: Vector2) -> Vector3:
	var cam := camera_rig.get_camera_3d()
	var terrace_center := get_floor_terrace_center(_current_lobby_floor)
	if cam == null:
		return terrace_center
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, terrace_center.y)
	var intersection: Variant = plane.intersects_ray(from, dir)
	if intersection is Vector3:
		return intersection
	return terrace_center

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
			var max_w := int(bt.get("maxWorkers", 0))

			var info_line := "📌 %s\n   • %s\n   • Giá xây: 🪙 %d Bạc | Cần WL %d%s | Tối đa %d Hero" % [
				bname,
				desc_txt,
				cost,
				req_wl,
				(" & Master Lv.%d" % req_ml) if req_ml > 1 else "",
				max_w
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
	var max_lvl := int(b.get("maxLevel", 5))
	var b_status := str(b.get("status", "READY"))
	var stored := float(b.get("stored", 0.0))
	var cap := int(b.get("capacity", 0))
	var rate := float(b.get("ratePerHour", 0.0))
	var res_type := str(b.get("resourceType", ""))
	var max_w := int(b.get("maxWorkers", 0))
	var workers: Array = b.get("workers", [])

	inspector_title_label.text = "%s %s (Lv.%d/%d)" % [plot_node._icon_for_type(b_code), b_name, b_lvl, max_lvl]
	inspector_subtitle_label.text = "Ô #%d (Tầng %d) • Trạng thái: %s" % [plot_node.plot_index, plot_node.zone_index, b_status]

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
			"⬆️ Nâng cấp công trình lên Lv.%d:\n   🪙 %d Bạc | 🪵 %d Gỗ | 🪨 %d Đá" % [target_lvl, upg_silver, req_wood, req_stone],
			Color(0.68, 0.88, 1.0)
		)
		var can_upg := (
			b_status == "READY"
			and GameState.silver_coins >= upg_silver
			and int(GameState.materials.get("WOOD", 0)) >= req_wood
			and int(GameState.materials.get("STONE", 0)) >= req_stone
		)
		_add_inspector_button(
			"⬆️ Nâng Cấp Lên Lv.%d" % target_lvl,
			func(): _upgrade_building(b_id),
			not can_upg
		)

	# Workers management section
	if max_w > 0:
		_add_inspector_info("👷 Hero phụ trách (%d/%d) — Mẹo: Kéo-thả Tướng 3D trực tiếp vào ô này!" % [workers.size(), max_w], Color(0.95, 0.85, 0.55))
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
				if assigned_map.has(hid) or hstate == "DEAD":
					continue
				var hname := str(h.get("name", "Hero"))
				var hlvl := int(h.get("level", 1))
				shown += 1
				_add_inspector_button(
					"➕ Phân công %s (Lv.%d)" % [hname, hlvl],
					func(): _assign_worker_to_building(b_id, hid, hname, b_name)
				)

	_add_inspector_button(
		"🏚️ Phá Dỡ Công Trình (Hoàn 50% Bạc)",
		func(): _demolish_building(b_id, b_name),
		b_status != "READY"
	)

func _render_specialized_facility_section(building_id: String, b_code: String, b_lvl: int, b_status: String) -> void:
	match b_code:
		"HOUSE":
			_add_inspector_section_header("🏠 NHÀ NGHỈ & ĐỘT PHÁ BIỆT THỰ TỔ ĐỘI", Color(0.75, 0.92, 1.0))
			_add_inspector_info(
				"• Nơi các Hero nghỉ ngơi giảm mệt mỏi (Fatigue) và hồi phục thể lực.\n🏰 Đột phá: Khi Master đạt cấp 30, có thể nâng cấp Nhà Nghỉ thành Biệt Thự Tổ Đội (Party Mansion)!",
				Color(0.78, 0.92, 1.0)
			)
			var can_promote := b_status == "READY" and GameState.master_level >= 30 and GameState.silver_coins >= 5000
			_add_inspector_button(
				"🏰 Nâng Cấp Thành Party Mansion (Biệt Thự Tổ Đội) [Master Lv.30, 🪙 5,000]",
				func(): _promote_house_to_party_mansion(building_id),
				not can_promote
			)
			_render_dormitory_rest_section(false)

		"PARTY_MANSION":
			_add_inspector_section_header("🏰 BIỆT THỰ TỔ ĐỘI (PARTY MANSION Lv.%d)" % b_lvl, Color(1.0, 0.88, 0.38))
			_add_inspector_info(
				"• Công trình nâng cấp từ Nhà Nghỉ (Master Lv.30+).\n• Tăng mạnh tốc độ hồi phục thể lực, giảm Fatigue và tiếp tế khẩu phần cho toàn bộ các Đội hình!",
				Color(1.0, 0.9, 0.52)
			)
			_render_dormitory_rest_section(true)

		"FORGE":
			_render_forge_facility(b_lvl, b_status)

		"TRAINING_CENTER":
			_render_training_center_facility(b_lvl, b_status)

		"HALL_OF_MAGIC":
			_render_hall_of_magic_subwings()

		"LIBRARY":
			_add_inspector_section_header("📚 PHÂN KHU 1: LIBRARY (THƯ VIỆN MA THUẬT)", Color(0.55, 0.88, 1.0))
			_render_library_actions()

		"ALCHEMY_WORKSHOP":
			_add_inspector_section_header("⚗️ PHÂN KHU 2: ALCHEMY WORKSHOP (XƯỞNG GIẢ KIM)", Color(0.52, 0.95, 0.68))
			_render_alchemy_workshop_actions()

		"MAGIC_RESEARCH_LAB":
			_add_inspector_section_header("✨ PHÂN KHU 3: MAGIC RESEARCH LAB (NGHIÊN CỨU MA THUẬT)", Color(0.95, 0.62, 0.95))
			_render_magic_research_actions()

		"WAREHOUSE":
			_render_warehouse_facility(b_lvl)

		"KITCHEN":
			_add_inspector_section_header("🍖 BẾP QUÂN LƯƠNG (KITCHEN Lv.%d)" % b_lvl, Color(1.0, 0.82, 0.48))
			_add_inspector_info("• Chế biến lương thực thô thành Khẩu phần ăn (🍖 RATION) cho Hero.\n• Tồn kho hiện tại: 🍖 %d Khẩu phần | 🌾 %d Lương thực thô" % [
				int(GameState.materials.get("RATION", 0)),
				int(GameState.materials.get("RAW_FOOD", 0))
			], Color(1.0, 0.88, 0.62))
			_add_inspector_button("🍳 Nấu Ngay 5 Khẩu Phần Quân Lương", func(): _cook_rations(5))
			_add_inspector_button("🍳 Nấu Ngay 15 Khẩu Phần Quân Lương", func(): _cook_rations(15))

		"MEDICAL":
			_add_inspector_section_header("✚ BỆNH XÁ (MEDICAL SANCTUARY Lv.%d)" % b_lvl, Color(0.55, 0.98, 0.78))
			_add_inspector_info("• Chữa trị vết thương, hồi phục HP và chăm sóc sinh tồn cho các Hero sau khi chinh phục Tháp.", Color(0.68, 0.98, 0.82))
			_render_dormitory_rest_section(false)

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
		"🌅 Kết Thúc Nghỉ Ngơi (%s)" % hname if is_resting else ("🏰 Cho %s Nghỉ Dưỡng Tại Biệt Thự" % hname if is_mansion else "🛏️ Cho %s Vào Nghỉ Ngơi Giảm Mệt Mỏi" % hname),
		func(): _toggle_hero_rest(hid, hname, is_resting)
	)
	_add_inspector_button(
		"🍖 Cấp 1 Khẩu Phần Cho %s (Còn %d 🍖)" % [hname, rations],
		func(): _feed_hero(hid, hname),
		rations <= 0
	)

func _render_forge_facility(b_lvl: int, b_status: String) -> void:
	_add_inspector_section_header("⚒️ XƯỞNG RÈN TRANG BỊ (FORGE Lv.%d)" % b_lvl, Color(1.0, 0.78, 0.42))
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
	_add_inspector_section_header("🥋 KHU HUẤN LUYỆN (TRAINING CENTER Lv.%d)" % b_lvl, Color(0.58, 0.96, 0.72))
	_add_inspector_info(
		"• Rèn luyện chuyên sâu 4 chỉ số gốc (STR / AGI / INT / STA) và lĩnh hội Kỹ năng chiến đấu cho từng Hero!",
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

func _render_hall_of_magic_subwings() -> void:
	_add_inspector_section_header("🔮 ĐẠI SẢNH MA THUẬT (3 PHÂN KHU CHUYÊN SÂU)", Color(0.82, 0.72, 1.0))
	_add_inspector_tab_bar(["📚 1. Thư Viện", "⚗️ 2. Giả Kim", "✨ 3. Nghiên Cứu"])
	var tab_idx := clampi(_facility_subtab, 0, 2)
	if tab_idx == 0:
		_render_library_actions()
	elif tab_idx == 1:
		_render_alchemy_workshop_actions()
	else:
		_render_magic_research_actions()

func _render_library_actions() -> void:
	var exp_books := int(GameState.materials.get("SAMPLE_HERO_EXP_100", 0))
	var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))
	_add_inspector_info(
		"📚 [Library - Thư Viện Cổ Thư]:\n• 📘 Sách EXP Hero (+100): %d quyển | 📕 Sách Kỹ Năng: %d quyển" % [exp_books, skill_books],
		Color(0.58, 0.9, 1.0)
	)
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		return
	_render_hero_selector_row("📖 Chọn Hero lĩnh hội tại Thư Viện:")
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))
	var hlvl := int(h.get("level", 1))
	var hexp := int(h.get("exp", 0))
	_add_inspector_info("• [%s] Cấp hiện tại: Lv.%d (EXP: %d)" % [hname, hlvl, hexp], Color(0.86, 0.94, 1.0))
	_add_inspector_button(
		"📘 Đọc Sách EXP (+100 EXP) Cho %s (Còn %d)" % [hname, exp_books],
		func(): _use_exp_book_on_hero(hid, hname),
		exp_books <= 0
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

func _render_alchemy_workshop_actions() -> void:
	var enh_stones := int(GameState.materials.get("ENHANCEMENT_STONE", 0))
	var rations := int(GameState.materials.get("RATION", 0))
	var raw_food := int(GameState.materials.get("RAW_FOOD", 0))
	_add_inspector_info(
		"⚗️ [Alchemy Workshop - Xưởng Giả Kim]:\n• 💎 Đá Cường Hóa: %d viên | 🍖 Khẩu phần tinh luyện: %d | 🌾 Thảo dược & Lương thô: %d" % [
			enh_stones, rations, raw_food
		],
		Color(0.55, 0.96, 0.72)
	)
	_add_inspector_button("⚗️ Chưng Cất 5 Khẩu Phần Dinh Dưỡng Cao Cấp", func(): _cook_rations(5))
	var h := _get_or_pick_facility_hero()
	if not h.is_empty():
		_render_hero_selector_row("🧪 Chọn Hero dùng Dược phẩm / Khẩu phần:")
		var hid := str(h.get("id", ""))
		var hname := str(h.get("name", "Hero"))
		var hp := int(h.get("hp", 100))
		var mhp := int(h.get("maxHp", 100))
		_add_inspector_button(
			"🧪 Tiếp Tế Dược Phẩm Hồi Sức Cho %s (HP %d/%d)" % [hname, hp, mhp],
			func(): _feed_hero(hid, hname),
			rations <= 0
		)

func _render_magic_research_actions() -> void:
	_add_inspector_info(
		"✨ [Magic Research Lab - Phòng Nghiên Cứu Ma Thuật]:\n• Thực hiện Chuyển Chức (Class Change khi đạt Lv.20+) và Thức Tỉnh Huyết Mạch (Awaken) cho Hero!",
		Color(0.95, 0.68, 0.98)
	)
	var h := _get_or_pick_facility_hero()
	if h.is_empty():
		return
	_render_hero_selector_row("🔮 Chọn Hero nghiên cứu Chuyển Chức & Thức Tỉnh:")
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
	_add_inspector_section_header("📦 NHÀ KHO TRUNG TÂM (WAREHOUSE Lv.%d)" % b_lvl, Color(0.95, 0.85, 0.58))
	var equips: Array = GameState.crafting_overview.get("equipment", [])
	_add_inspector_info(
		"• Lưu trữ & phân phối Trang bị, Vật phẩm tiêu hao và Nguyên liệu toàn Căn cứ.\n• Tổng số Trang bị: %d món | 📜 Thiên Thư: %d | 🍖 Khẩu phần: %d" % [
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
		var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))
		var rations := int(GameState.materials.get("RATION", 0))
		_add_inspector_info(
			"🎒 Vật Phẩm Tiêu Hao Trong Kho:\n" +
			"   • 📜 Thiên Thư Triệu Hồi: ×%d\n" % GameState.normal_scrolls +
			"   • 📘 Sách EXP Hero (+100): ×%d\n" % exp_books +
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
				"📘 Dùng 1 Sách EXP (+100) Cho %s" % hname,
				func(): _use_exp_book_on_hero(hid, hname),
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
			inspector_title_label.text = "✨ ĐÀI TRIỆU HỒI (PHÍA TÂY)"
			inspector_subtitle_label.text = "Nghi thức triệu hồi Anh Hùng & Thiên Thư tại Thánh điện phía Tây"
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
			inspector_title_label.text = "⛩️ CỔNG THÁP CHINH PHẠT PvE (PHÍA ĐÔNG)"
			inspector_subtitle_label.text = "Cổng thành phía Đông tích hợp phòng thủ & viễn chinh — Tầng %d (World Level %d)" % [GameState.current_floor, GameState.world_level]
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
			inspector_title_label.text = "🛡️ DOANH TRẠI & THĂNG SAO"
			inspector_subtitle_label.text = "Quản lý đội ngũ Tướng và Ghép Thăng Sao (Pick Me Up)"
			_add_inspector_info("Tổng số Tướng sở hữu: %d Tướng" % GameState.heroes.size())
			_add_inspector_button("👥 Quản Lý Hero Từng Tầng Sảnh Chờ", func(): _open_floor_hero_manager(_current_lobby_floor))
			_add_inspector_button("🛡️ Mở Bảng Tướng & Ghép Thăng Sao", _on_barracks_pressed)

		"FOUNTAIN", "BONFIRE":
			if focus_cam:
				camera_rig.focus_action_unit(Vector3(0.0, 1.2, 0.0), 12.0, 0.35)
			inspector_title_label.text = "⛲ ĐÀI PHUN NƯỚC TRUNG TÂM & KHÔNG GIAN"
			inspector_subtitle_label.text = "Điểm tụ năng lượng linh hồn, hồi phục thể lực và điều chỉnh thời tiết Sảnh Chờ"
			_add_inspector_info("🍖 Khẩu phần dự trữ: %d | 🌾 Lương thực thô: %d" % [
				int(GameState.materials.get("RATION", 0)),
				int(GameState.materials.get("RAW_FOOD", 0))
			])
			_add_inspector_button("🍳 Nấu 5 Khẩu Phần Quân Lương", func(): _cook_rations(5))
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
			inspector_title_label.text = "✚ BỆNH XÁ & HẬU CẦN"
			inspector_subtitle_label.text = "Chữa trị thương tích và hồi phục thể lực cho Tướng sau viễn chinh"
			_add_inspector_info("🍖 Khẩu phần dự trữ: %d | 🌾 Lương thực thô: %d" % [
				int(GameState.materials.get("RATION", 0)),
				int(GameState.materials.get("RAW_FOOD", 0))
			])
			_add_inspector_button("🍳 Nấu 5 Khẩu Phần Quân Lương", func(): _cook_rations(5))

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
				var max_w := int(b.get("maxWorkers", 0))
				var cur_w: Array = b.get("workers", [])
				if cur_w.size() < max_w:
					var b_id := str(b.get("id", ""))
					var b_name := str(b.get("typeName", b.get("buildingType", "Công trình")))
					var p_idx := int(b.get("plotIndex", 0))
					_add_inspector_button(
						"👷 Phân công vào %s (Ô #%d)" % [b_name, p_idx],
						func(): _assign_worker_to_building(b_id, hid, hname, b_name)
					)

	_add_inspector_button("🛡️ Mở Chi Tiết & Thăng Sao", _on_barracks_pressed)

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

func _use_exp_book_on_hero(hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.post_req("/api/inventory/items/SAMPLE_HERO_EXP_100/use", {
		"quantity": 1,
		"targetHeroId": hero_id
	})
	if res["ok"]:
		status_banner_label.text = "📘 [%s] đã lĩnh hội Sách EXP tại Thư Viện Ma Thuật!" % hero_name
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "❌ Không thể dùng Sách EXP: " + str(res["error"])

func _perform_class_change(hero_id: String, hero_name: String, target_class: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/class-change" % hero_id, {
		"targetClass": target_class
	})
	if res["ok"]:
		camera_rig.shake(0.18, 0.2)
		status_banner_label.text = "🔮 [%s] đã chuyển chức thành công sang [%s] tại Phòng Nghiên Cứu Ma Thuật!" % [hero_name, target_class]
		await _sync_all_from_backend()
	else:
		status_banner_label.text = "ℹ️ Chưa đủ điều kiện Chuyển Chức: " + str(res["error"])

func _awaken_hero(hero_id: String, hero_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/awaken" % hero_id, {})
	if res["ok"]:
		camera_rig.shake(0.2, 0.22)
		status_banner_label.text = "🌟 [%s] đã Thức Tỉnh Huyết Mạch tại Phòng Nghiên Cứu Ma Thuật!" % hero_name
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
	card_panel.custom_minimum_size = Vector2(780, 480)
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
	scroll.custom_minimum_size = Vector2(0, 290)
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 5 if results.size() > 2 else maxi(1, results.size())
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)

	for r in results:
		if not (r is Dictionary):
			continue
		var rtype := str(r.get("rewardType", r.get("itemType", "MATERIAL"))).to_upper()
		var is_hero := (rtype == "HERO")
		var rname := str(r.get("rewardName", "Anh Hùng" if is_hero else "Vật phẩm"))
		var rar := int(r.get("rarity", 1))

		var item_card := PanelContainer.new()
		item_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_card.custom_minimum_size = Vector2(138, 136)
		var cstyle := StyleBoxFlat.new()
		cstyle.corner_radius_top_left = 8
		cstyle.corner_radius_top_right = 8
		cstyle.corner_radius_bottom_left = 8
		cstyle.corner_radius_bottom_right = 8
		cstyle.border_width_left = 2
		cstyle.border_width_top = 2
		cstyle.border_width_right = 2
		cstyle.border_width_bottom = 2
		if is_hero and rar >= 5:
			cstyle.bg_color = Color(0.24, 0.18, 0.05, 0.96)
			cstyle.border_color = Color(1.0, 0.84, 0.18)
		elif is_hero and rar == 4:
			cstyle.bg_color = Color(0.18, 0.09, 0.26, 0.96)
			cstyle.border_color = Color(0.84, 0.42, 1.0)
		elif is_hero:
			cstyle.bg_color = Color(0.08, 0.16, 0.26, 0.96)
			cstyle.border_color = Color(0.35, 0.80, 1.0)
		else:
			cstyle.bg_color = Color(0.10, 0.13, 0.18, 0.92)
			cstyle.border_color = Color(0.38, 0.46, 0.58)
		item_card.add_theme_stylebox_override("panel", cstyle)

		var cm := MarginContainer.new()
		cm.add_theme_constant_override("margin_left", 8)
		cm.add_theme_constant_override("margin_top", 8)
		cm.add_theme_constant_override("margin_right", 8)
		cm.add_theme_constant_override("margin_bottom", 8)
		item_card.add_child(cm)

		var cv := VBoxContainer.new()
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 5)
		cm.add_child(cv)

		var badge_lbl := Label.new()
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_size_override("font_size", 13)
		if is_hero:
			badge_lbl.text = "🦸 ANH HÙNG " + "★".repeat(clampi(rar, 1, 5))
			badge_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25) if rar >= 4 else Color(0.55, 0.90, 1.0))
		else:
			badge_lbl.text = "🪨 NGUYÊN LIỆU" if rtype == "MATERIAL" else "📦 VẬT PHẨM"
			badge_lbl.add_theme_color_override("font_color", Color(0.70, 0.82, 0.90))
		cv.add_child(badge_lbl)

		var name_lbl := Label.new()
		name_lbl.text = rname
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cv.add_child(name_lbl)

		var detail_lbl := Label.new()
		detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail_lbl.add_theme_font_size_override("font_size", 11)
		if is_hero:
			if bool(r.get("isDuplicate", false)):
				detail_lbl.text = "🔄 Trùng: +1 Thiên Mệnh"
				detail_lbl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.35))
			else:
				var h_inst: Dictionary = r.get("hero", {}) if r.get("hero") is Dictionary else {}
				var h_cls := str(h_inst.get("classCode", r.get("classCode", "")))
				if not h_cls.is_empty():
					detail_lbl.text = "✨ Hệ: %s" % h_cls
				else:
					detail_lbl.text = "✨ Mới thu nhận"
				detail_lbl.add_theme_color_override("font_color", Color(0.45, 0.92, 0.55))
		else:
			detail_lbl.text = "Vật phẩm doanh trại"
			detail_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		cv.add_child(detail_lbl)

		grid.add_child(item_card)

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

func _on_back_hub_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/hub/main_hub.tscn")
