class_name TacticalGroundProps3D
extends Node3D
## Lightweight GPU-Instanced 3D Stylized Ground Landscape for Level 1 Tactical View.
## Renders real 3D Castle Citadel, Forest Clusters, Snow-Capped Mountains, Rolling Hills,
## Ancient Ruin Pillars, and Glowing Dungeon Portals on visible tiles using MultiMeshInstance3D
## (only ~6 tiny draw calls, strictly active when zoom_level >= 0.66 and culled at 0 cost otherwise!).
## Moves in O(1) per frame via a single root transform offset synced to focus_lon!

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

const DUNGEON_RANK_COLORS := {
	"D": Color(0.36, 0.90, 0.48),
	"C": Color(0.24, 0.80, 1.0),
	"B": Color(0.76, 0.44, 1.0),
	"A": Color(1.0, 0.56, 0.18),
	"S": Color(1.0, 0.22, 0.28),
}

var _planet_radius: float = 10.0
var _sector_center_lat: float = 19.0
var _sector_center_lon: float = -11.0
var _tile_world_size: float = 0.01047

var _trunk_mm: MultiMeshInstance3D
var _canopy_mm: MultiMeshInstance3D
var _mountain_mm: MultiMeshInstance3D
var _snow_mm: MultiMeshInstance3D
var _hill_mm: MultiMeshInstance3D
var _ruin_mm: MultiMeshInstance3D
var _base_citadel: Node3D
var _other_citadels_root: Node3D
var _dungeons_root: Node3D

var _built := false
var _prop_count := 0
var render_distance_tiles: int = 16
var props_density_scale: float = 1.0
var props_cull_zoom: float = 0.60

func apply_graphics_settings(cfg: Dictionary) -> void:
	render_distance_tiles = clampi(int(cfg.get("world_render_radius", 16)), 8, 36)
	props_density_scale = clampf(float(cfg.get("props_density", 1.0)), 0.5, 1.5)
	props_cull_zoom = clampf(float(cfg.get("props_cull_zoom", 0.60)), 0.40, 0.72)

func setup(planet_radius: float = 10.0) -> void:
	_planet_radius = maxf(1.0, planet_radius)
	if _built:
		return
	_create_multimeshes()
	_base_citadel = _build_citadel_model("BaseCitadel3D", Color(0.14, 0.56, 0.94), Color(0.28, 0.92, 1.0))
	_base_citadel.visible = false
	add_child(_base_citadel)
	_other_citadels_root = Node3D.new()
	_other_citadels_root.name = "OtherPlayerCitadels3D"
	add_child(_other_citadels_root)
	_dungeons_root = Node3D.new()
	_dungeons_root.name = "DungeonPortals3D"
	add_child(_dungeons_root)
	visible = false
	_built = true

func _make_mat(col: Color, roughness := 0.85, emission_col := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = roughness
	m.metallic = 0.0
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission_col
		m.emission_energy_multiplier = emission_energy
	return m

func _create_mm_node(node_name: String, mesh: Mesh, mat: Material, use_colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = use_colors
	mm.mesh = mesh
	mm.instance_count = 0

	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.extra_cull_margin = 2.0
	add_child(inst)
	return inst

func _create_multimeshes() -> void:
	# 1. Tree Trunks (brown cylinder)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.06
	trunk.bottom_radius = 0.09
	trunk.height = 0.42
	trunk.radial_segments = 6
	_trunk_mm = _create_mm_node("ForestTrunksMM", trunk, _make_mat(Color(0.32, 0.21, 0.13), 0.92))

	# 2. Stylized Pine Canopy (cone with per-instance emerald shade variation!)
	var canopy := CylinderMesh.new()
	canopy.top_radius = 0.01
	canopy.bottom_radius = 0.34
	canopy.height = 0.82
	canopy.radial_segments = 7
	var canopy_mat := _make_mat(Color(1.0, 1.0, 1.0), 0.86)
	canopy_mat.vertex_color_use_as_albedo = true
	_canopy_mm = _create_mm_node("ForestCanopiesMM", canopy, canopy_mat, true)

	# 3. Faceted Stylized Mountain Peaks (dark granite pyramid cone)
	var mtn := CylinderMesh.new()
	mtn.top_radius = 0.02
	mtn.bottom_radius = 0.56
	mtn.height = 0.96
	mtn.radial_segments = 6
	_mountain_mm = _create_mm_node("MountainPeaksMM", mtn, _make_mat(Color(0.34, 0.36, 0.44), 0.92))

	# 4. Crisp Mountain Snow Caps
	var snow := CylinderMesh.new()
	snow.top_radius = 0.02
	snow.bottom_radius = 0.24
	snow.height = 0.36
	snow.radial_segments = 6
	_snow_mm = _create_mm_node("MountainSnowMM", snow, _make_mat(Color(0.92, 0.95, 1.0), 0.78))

	# 5. Rolling Stylized Hills (flattened dome)
	var hill := SphereMesh.new()
	hill.radius = 0.46
	hill.height = 0.52
	hill.radial_segments = 10
	hill.rings = 5
	var hill_mat := _make_mat(Color(1.0, 1.0, 1.0), 0.90)
	hill_mat.vertex_color_use_as_albedo = true
	_hill_mm = _create_mm_node("HillsMM", hill, hill_mat, true)

	# 6. Ancient Ruin Marble Columns
	var col_mesh := BoxMesh.new()
	col_mesh.size = Vector3(0.14, 0.62, 0.14)
	_ruin_mm = _create_mm_node("RuinsPillarsMM", col_mesh, _make_mat(Color(0.72, 0.68, 0.78), 0.84))

func _build_citadel_model(node_name: String, roof_col: Color, gate_col: Color) -> Node3D:
	var citadel := Node3D.new()
	citadel.name = node_name

	var stone_mat := _make_mat(Color(0.82, 0.86, 0.92), 0.78)
	var roof_mat := _make_mat(roof_col, 0.55)
	var gold_mat := _make_mat(Color(1.0, 0.84, 0.30), 0.35, Color(1.0, 0.80, 0.25), 0.65)
	var gate_mat := _make_mat(gate_col, 0.2, gate_col, 2.2)

	# Octagonal raised stone base platform
	var plinth := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.44; pm.bottom_radius = 0.50; pm.height = 0.12; pm.radial_segments = 8
	plinth.mesh = pm; plinth.position = Vector3(0, 0.06, 0); plinth.material_override = _make_mat(Color(0.54, 0.58, 0.66), 0.88)
	citadel.add_child(plinth)

	# Curtain walls
	var wall := MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(0.58, 0.26, 0.58)
	wall.mesh = wm; wall.position = Vector3(0, 0.22, 0); wall.material_override = stone_mat
	citadel.add_child(wall)

	# 4 Corner Turrets
	var tur_m := CylinderMesh.new()
	tur_m.top_radius = 0.09; tur_m.bottom_radius = 0.10; tur_m.height = 0.42; tur_m.radial_segments = 8
	var tr_m := CylinderMesh.new()
	tr_m.top_radius = 0.01; tr_m.bottom_radius = 0.13; tr_m.height = 0.22; tr_m.radial_segments = 8
	for sx in [-0.28, 0.28]:
		for sz in [-0.28, 0.28]:
			var t := MeshInstance3D.new()
			t.mesh = tur_m; t.position = Vector3(sx, 0.32, sz); t.material_override = stone_mat
			citadel.add_child(t)
			var r := MeshInstance3D.new()
			r.mesh = tr_m; r.position = Vector3(sx, 0.63, sz); r.material_override = roof_mat
			citadel.add_child(r)

	# Central Tall Keep + Spire + Gold Finial
	var keep := MeshInstance3D.new()
	var km := BoxMesh.new()
	km.size = Vector3(0.28, 0.62, 0.28)
	keep.mesh = km; keep.position = Vector3(0, 0.42, 0); keep.material_override = stone_mat
	citadel.add_child(keep)

	var spire := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.01; sm.bottom_radius = 0.23; sm.height = 0.40; sm.radial_segments = 4
	spire.mesh = sm; spire.position = Vector3(0, 0.92, 0); spire.rotation_degrees.y = 45.0; spire.material_override = roof_mat
	citadel.add_child(spire)

	var orb := MeshInstance3D.new()
	var om := SphereMesh.new()
	om.radius = 0.06; om.height = 0.12
	orb.mesh = om; orb.position = Vector3(0, 1.15, 0); orb.material_override = gold_mat
	citadel.add_child(orb)

	# Glowing Castle Gate Portal facing South (+Z toward strategic tilted camera!)
	var gate := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.16, 0.20, 0.05)
	gate.mesh = gm; gate.position = Vector3(0, 0.20, 0.29); gate.material_override = gate_mat
	citadel.add_child(gate)
	return citadel

func rebuild_from_snapshot(snapshot: Dictionary, sector_bounds: Dictionary) -> void:
	if not _built:
		setup(_planet_radius)

	var use_full_planet := int(sector_bounds.get("world_grid_width", 0)) > 0
	var tile_deg: float = PlanetCoordinatesScript.get_tile_deg_size(sector_bounds)
	_tile_world_size = _planet_radius * deg_to_rad(tile_deg)

	if use_full_planet:
		var base: Dictionary = snapshot.get("base", {"x": 300, "y": 150})
		var cc: Dictionary = snapshot.get("chunkCenter", base)
		var cc_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(
			float(cc.get("x", base.get("x", 300))),
			float(cc.get("y", base.get("y", 150))),
			sector_bounds
		)
		_sector_center_lat = cc_ll.x
		_sector_center_lon = cc_ll.y
	else:
		var lat_min := float(sector_bounds.get("lat_min", 18.67))
		var lat_max := float(sector_bounds.get("lat_max", 19.33))
		var lon_min := float(sector_bounds.get("lon_min", -11.33))
		var lon_max := float(sector_bounds.get("lon_max", -10.67))
		_sector_center_lat = (lat_min + lat_max) * 0.5
		_sector_center_lon = (lon_min + lon_max) * 0.5

	var trunk_xf: Array[Transform3D] = []
	var canopy_xf: Array[Transform3D] = []
	var canopy_cols: Array[Color] = []
	var mtn_xf: Array[Transform3D] = []
	var snow_xf: Array[Transform3D] = []
	var hill_xf: Array[Transform3D] = []
	var hill_cols: Array[Color] = []
	var ruin_xf: Array[Transform3D] = []

	for c in _dungeons_root.get_children():
		c.queue_free()
	for c in _other_citadels_root.get_children():
		c.queue_free()
	_base_citadel.visible = false

	var S := _tile_world_size
	var ref_base: Dictionary = snapshot.get("base", {"x": 100, "y": 100})
	var ref_cc: Dictionary = snapshot.get("chunkCenter", ref_base)
	var center_gx := int(ref_cc.get("x", ref_base.get("x", 100)))
	var center_gy := int(ref_cc.get("y", ref_base.get("y", 100)))
	var trees_per_tile := clampi(int(round(6.0 * props_density_scale)), 3, 9)
	var other_player_coords: Dictionary = {}
	for np in snapshot.get("nearbyPlayers", []):
		if not (np is Dictionary) or not bool(np.get("visible", false)):
			continue
		var npx := float(np.get("x", 0))
		var npy := float(np.get("y", 0))
		other_player_coords["%d,%d" % [int(npx), int(npy)]] = true
		var nll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(npx, npy, sector_bounds)
		var nlx := _planet_radius * deg_to_rad(PlanetCoordinatesScript.normalize_lon(nll.y - _sector_center_lon))
		var nlz := -_planet_radius * deg_to_rad(nll.x - _sector_center_lat)
		var rival := _build_citadel_model("RivalCitadel_%d_%d" % [int(npx), int(npy)], Color(0.86, 0.22, 0.26), Color(1.0, 0.62, 0.22))
		rival.position = Vector3(nlx, 0.0, nlz)
		rival.scale = Vector3.ONE * (S * 0.88)
		_other_citadels_root.add_child(rival)

	var tiles: Array = snapshot.get("tiles", [])
	for t in tiles:
		if not (t is Dictionary):
			continue
		if not bool(t.get("visible", false)):
			continue
		var gx := float(t.get("x", 100))
		var gy := float(t.get("y", 100))
		var is_base := bool(t.get("isBase", false))
		if use_full_planet and not is_base:
			if absi(int(gx) - center_gx) > render_distance_tiles or absi(int(gy) - center_gy) > render_distance_tiles:
				continue
		var ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(gx, gy, sector_bounds)
		var lx := _planet_radius * deg_to_rad(PlanetCoordinatesScript.normalize_lon(ll.y - _sector_center_lon))
		var lz := -_planet_radius * deg_to_rad(ll.x - _sector_center_lat)
		var tile_pos := Vector3(lx, 0.0, lz)

		var seed_i := int(gx) * 73856093 ^ int(gy) * 19349663
		var dungeon = t.get("dungeon", null)

		if is_base:
			_base_citadel.position = tile_pos
			_base_citadel.scale = Vector3.ONE * (S * 0.92)
			_base_citadel.visible = true
			continue

		if other_player_coords.has("%d,%d" % [int(gx), int(gy)]):
			continue

		if dungeon is Dictionary:
			var rank := str(dungeon.get("rank", "D"))
			_spawn_dungeon_portal_3d(tile_pos, S, rank)
			continue

		var terrain := str(t.get("terrain", "PLAINS"))
		if terrain == "OCEAN":
			continue
		match terrain:
			"FOREST":
				# Cluster of stylized layered pine trees scaled by props_density_scale (3..9 trees/tile)
				var ang_step := TAU / float(maxi(1, trees_per_tile))
				for k in range(trees_per_tile):
					var ang := float(k) * ang_step + float((seed_i + k * 17) & 255) * 0.02
					var rad := (0.14 + float((seed_i + k * 31) & 127) / 127.0 * 0.24) * S
					var tp := tile_pos + Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
					var ts := S * (0.48 + float((seed_i + k * 43) & 63) / 63.0 * 0.34)
					trunk_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * ts), tp + Vector3(0.0, 0.21 * ts, 0.0)))
					canopy_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * ts), tp + Vector3(0.0, 0.62 * ts, 0.0)))
					var g_var := float((seed_i + k * 13) & 31) / 31.0
					canopy_cols.append(Color(lerpf(0.08, 0.16, g_var), lerpf(0.32, 0.50, g_var), lerpf(0.14, 0.22, g_var)))
			"MOUNTAIN":
				# 2-3 faceted mountain peaks with snow caps
				var offsets := [Vector3(-0.14 * S, 0, -0.06 * S), Vector3(0.16 * S, 0, 0.10 * S), Vector3(0.02 * S, 0, -0.18 * S)]
				var scales := [0.88 * S, 0.66 * S, 0.58 * S]
				for k in range(3):
					var mp: Vector3 = tile_pos + offsets[k]
					var ms: float = scales[k]
					var rot := Basis(Vector3.UP, float((seed_i + k * 29) & 255) * 0.024).scaled(Vector3.ONE * ms)
					mtn_xf.append(Transform3D(rot, mp + Vector3(0.0, 0.46 * ms, 0.0)))
					snow_xf.append(Transform3D(rot, mp + Vector3(0.0, 0.78 * ms, 0.0)))
			"HILLS":
				# 2 gentle lush sunlit hill domes
				for k in range(2):
					var hp := tile_pos + Vector3((-0.16 if k == 0 else 0.17) * S, 0.0, (-0.10 if k == 0 else 0.12) * S)
					var hs := S * (0.68 if k == 0 else 0.52)
					hill_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(hs * 1.15, hs * 0.65, hs * 1.05)), hp + Vector3(0.0, 0.08 * hs, 0.0)))
					hill_cols.append(Color(0.30, 0.54, 0.24) if k == 0 else Color(0.38, 0.52, 0.26))
			"RUINS":
				# 4 weathered broken stone columns arranged as an ancient temple square
				for k in range(4):
					var rx := (-0.22 if (k % 2 == 0) else 0.22) * S
					var rz := (-0.20 if k < 2 else 0.20) * S
					var rh := S * (0.45 + float((seed_i + k * 23) & 31) / 31.0 * 0.40)
					var rot := Basis(Vector3.UP, float(k) * 0.4).scaled(Vector3(S * 0.62, rh, S * 0.62))
					ruin_xf.append(Transform3D(rot, tile_pos + Vector3(rx, 0.30 * rh, rz)))

	_fill_mm(_trunk_mm, trunk_xf)
	_fill_mm(_canopy_mm, canopy_xf, canopy_cols)
	_fill_mm(_mountain_mm, mtn_xf)
	_fill_mm(_snow_mm, snow_xf)
	_fill_mm(_hill_mm, hill_xf, hill_cols)
	_fill_mm(_ruin_mm, ruin_xf)

	_prop_count = trunk_xf.size() + mtn_xf.size() + hill_xf.size() + ruin_xf.size() + (1 if _base_citadel.visible else 0) + _other_citadels_root.get_child_count() + _dungeons_root.get_child_count()

func _spawn_dungeon_portal_3d(tile_pos: Vector3, S: float, rank: String) -> void:
	var root := Node3D.new()
	root.position = tile_pos
	root.scale = Vector3.ONE * (S * 0.88)
	_dungeons_root.add_child(root)

	var col: Color = DUNGEON_RANK_COLORS.get(rank, Color(1.0, 0.55, 0.20))
	var stone_mat := _make_mat(Color(0.24, 0.22, 0.30), 0.90)
	var glow_mat := _make_mat(col, 0.2, col, 2.5)

	# Two stone archway pillars + top lintel
	var pil := BoxMesh.new()
	pil.size = Vector3(0.14, 0.68, 0.16)
	for sx in [-0.26, 0.26]:
		var p := MeshInstance3D.new()
		p.mesh = pil; p.position = Vector3(sx, 0.34, 0); p.material_override = stone_mat
		root.add_child(p)
	var lintel := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(0.72, 0.14, 0.20)
	lintel.mesh = lm; lintel.position = Vector3(0, 0.72, 0); lintel.material_override = stone_mat
	root.add_child(lintel)

	# Glowing upright portal vortex ring + bright core
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.14; rm.outer_radius = 0.22; rm.rings = 16; rm.ring_segments = 8
	ring.mesh = rm; ring.position = Vector3(0, 0.36, 0); ring.rotation_degrees.x = 90.0; ring.material_override = glow_mat
	root.add_child(ring)

func _fill_mm(inst: MultiMeshInstance3D, xforms: Array[Transform3D], cols: Array[Color] = []) -> void:
	if inst == null or inst.multimesh == null:
		return
	var mm := inst.multimesh
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
		if i < cols.size():
			mm.set_instance_color(i, cols[i])
	inst.visible = xforms.size() > 0

## O(1) per-frame synchronization: shifts the entire 3D landscape cleanly with focus_lon,
## and culls to 0 draw calls whenever zoomed out to Continent / 3D Globe!
func sync_to_view(focus_lon_deg: float, zoom_level: float, morph_factor: float) -> void:
	var show := zoom_level >= props_cull_zoom and morph_factor < 0.05 and _prop_count > 0
	visible = show
	if not show:
		return
	var lon_rel := PlanetCoordinatesScript.normalize_lon(_sector_center_lon - focus_lon_deg)
	position = Vector3(
		_planet_radius * deg_to_rad(lon_rel),
		_planet_radius + 0.0014,
		-_planet_radius * deg_to_rad(_sector_center_lat)
	)

func get_prop_count() -> int:
	return _prop_count
