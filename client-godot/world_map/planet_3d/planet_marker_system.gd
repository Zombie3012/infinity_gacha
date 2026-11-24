class_name PlanetMarkerSystem
extends Node3D
## 3D Surface Marker System glued to the Fantasy Planet across 2D <-> 3D morphing (Milestone 5).
## Uses PlanetCoordinates.to_morphed_position + pole-safe surface_basis so markers never detach
## or flip at poles, and pools fleet beacons instead of spawning per-region Node3D trees.

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

const MAX_FLEET_BEACONS := 16

var _planet_radius: float = 10.0
var _player_lat: float = 19.0
var _player_lon: float = -11.0
var _wonder_lat: float = 6.0
var _wonder_lon: float = 32.0
var _fleet_points: Array = []

var player_marker: Node3D
var _player_core_mesh: MeshInstance3D
var _player_ring_mesh: MeshInstance3D
var _player_ring_mat: StandardMaterial3D

var wonder_marker: Node3D
var _fleet_nodes: Array[MeshInstance3D] = []
var _fleet_mats: Array[StandardMaterial3D] = []

func setup(planet_radius: float = 10.0) -> void:
	_planet_radius = maxf(1.0, planet_radius)
	_build_player_marker()
	_build_wonder_marker()
	_build_fleet_pool()

func _build_player_marker() -> void:
	if player_marker != null:
		return
	player_marker = Node3D.new()
	player_marker.name = "PlayerMarker"
	add_child(player_marker)

	# Luminous pulsing Player Position Dot on the planet surface
	var core_sphere := SphereMesh.new()
	core_sphere.radius = 0.22
	core_sphere.height = 0.44
	core_sphere.radial_segments = 16
	core_sphere.rings = 10

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.55, 0.96, 1.0, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.28, 0.90, 1.0)
	core_mat.emission_energy_multiplier = 2.6

	_player_core_mesh = MeshInstance3D.new()
	_player_core_mesh.name = "PlayerDotCore"
	_player_core_mesh.mesh = core_sphere
	_player_core_mesh.material_override = core_mat
	_player_core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player_marker.add_child(_player_core_mesh)

	# Tangent-plane radar halo ring around player dot
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.34
	ring_mesh.outer_radius = 0.44
	ring_mesh.rings = 24
	ring_mesh.ring_segments = 10

	_player_ring_mat = StandardMaterial3D.new()
	_player_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_player_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_player_ring_mat.albedo_color = Color(0.35, 0.92, 1.0, 0.85)
	_player_ring_mat.emission_enabled = true
	_player_ring_mat.emission = Color(0.35, 0.92, 1.0)
	_player_ring_mat.emission_energy_multiplier = 2.0

	_player_ring_mesh = MeshInstance3D.new()
	_player_ring_mesh.name = "PlayerRadarRing"
	_player_ring_mesh.mesh = ring_mesh
	_player_ring_mesh.material_override = _player_ring_mat
	_player_ring_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player_marker.add_child(_player_ring_mesh)

func _build_wonder_marker() -> void:
	if wonder_marker != null:
		return
	wonder_marker = Node3D.new()
	wonder_marker.name = "WonderMarker"
	add_child(wonder_marker)

	var spire := CylinderMesh.new()
	spire.top_radius = 0.02
	spire.bottom_radius = 0.20
	spire.height = 0.52
	spire.radial_segments = 8

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.88, 0.36, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.22)
	mat.emission_energy_multiplier = 2.0

	var mi := MeshInstance3D.new()
	mi.mesh = spire
	mi.position = Vector3(0.0, 0.24, 0.0)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wonder_marker.add_child(mi)

func _build_fleet_pool() -> void:
	if not _fleet_nodes.is_empty():
		return
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.13
	dot_mesh.height = 0.26
	dot_mesh.radial_segments = 10
	dot_mesh.rings = 6

	for i in range(MAX_FLEET_BEACONS):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.92, 0.36)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.92, 0.36)
		mat.emission_energy_multiplier = 1.9

		var mi := MeshInstance3D.new()
		mi.name = "FleetBeacon_%d" % i
		mi.mesh = dot_mesh
		mi.material_override = mat
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_fleet_nodes.append(mi)
		_fleet_mats.append(mat)

func set_player_lat_lon(lat_deg: float, lon_deg: float) -> void:
	_player_lat = clampf(lat_deg, -90.0, 90.0)
	_player_lon = PlanetCoordinatesScript.normalize_lon(lon_deg)

func set_wonder_lat_lon(lat_deg: float, lon_deg: float) -> void:
	_wonder_lat = clampf(lat_deg, -90.0, 90.0)
	_wonder_lon = PlanetCoordinatesScript.normalize_lon(lon_deg)

func set_active_fleet_coords(fleet_points: Array) -> void:
	_fleet_points = fleet_points

func get_player_world_position(morph_factor: float, center_lon_deg: float) -> Vector3:
	var pos: Vector3 = PlanetCoordinatesScript.to_morphed_position(
		_player_lat, _player_lon, _planet_radius, morph_factor, center_lon_deg
	)
	var normal: Vector3 = PlanetCoordinatesScript.to_morphed_normal(
		_player_lat, _player_lon, morph_factor, center_lon_deg
	)
	return pos + normal * 0.16

func sync_to_view(morph_factor: float, center_lon_deg: float, zoom_level: float, pulse_time: float) -> void:
	var pulse := 0.5 + 0.5 * sin(pulse_time)
	var globe_emphasis := clampf(1.0 - (zoom_level - 0.15) / 0.45, 0.0, 1.0)

	# 1. Player Position Dot (always locked to exact surface coordinates; prominent in Continental & 3D Globe views)
	if player_marker != null:
		var p_surf: Vector3 = PlanetCoordinatesScript.to_morphed_position(
			_player_lat, _player_lon, _planet_radius, morph_factor, center_lon_deg
		)
		var p_norm: Vector3 = PlanetCoordinatesScript.to_morphed_normal(
			_player_lat, _player_lon, morph_factor, center_lon_deg
		)
		var height_off := lerpf(0.04, 0.18, globe_emphasis)
		var dot_scale := lerpf(0.24, 1.35, globe_emphasis)
		player_marker.transform = Transform3D(
			PlanetCoordinatesScript.surface_basis(p_norm).scaled(Vector3.ONE * dot_scale),
			p_surf + p_norm * height_off
		)
		# Appears as soon as the 12x12 tactical valley shrinks into a continent point (< 0.72)
		player_marker.visible = zoom_level < 0.72
		if _player_ring_mesh != null and _player_ring_mat != null:
			var ring_s := 0.95 + pulse * 0.65
			_player_ring_mesh.scale = Vector3(ring_s, 1.0, ring_s)
			_player_ring_mat.albedo_color.a = lerpf(0.88, 0.22, pulse)

	# 2. Central Imperial Wonder Beacon
	if wonder_marker != null:
		var w_surf: Vector3 = PlanetCoordinatesScript.to_morphed_position(
			_wonder_lat, _wonder_lon, _planet_radius, morph_factor, center_lon_deg
		)
		var w_norm: Vector3 = PlanetCoordinatesScript.to_morphed_normal(
			_wonder_lat, _wonder_lon, morph_factor, center_lon_deg
		)
		var w_scale := lerpf(0.45, 1.15, globe_emphasis)
		wonder_marker.transform = Transform3D(
			PlanetCoordinatesScript.surface_basis(w_norm).scaled(Vector3.ONE * w_scale),
			w_surf + w_norm * 0.08
		)
		wonder_marker.visible = zoom_level < 0.72

	# 3. Pooled Active Fleet Beacons (overlaps 2D fleet_overlay_alpha across 0.24..0.42 -> ZERO dead-zone!)
	var show_beacons := zoom_level < 0.42
	var beacon_vis := clampf((0.42 - zoom_level) / 0.16, 0.0, 1.0)
	for i in range(_fleet_nodes.size()):
		var mi := _fleet_nodes[i]
		if not show_beacons or i >= _fleet_points.size():
			mi.visible = false
			continue
		var fp: Dictionary = _fleet_points[i]
		var fl_lat := float(fp.get("lat", _player_lat))
		var fl_lon := float(fp.get("lon", _player_lon))
		var col: Color = fp.get("color", Color(1.0, 0.92, 0.36))
		var is_sos := bool(fp.get("is_sos", false))

		var f_surf: Vector3 = PlanetCoordinatesScript.to_morphed_position(
			fl_lat, fl_lon, _planet_radius, morph_factor, center_lon_deg
		)
		var f_norm: Vector3 = PlanetCoordinatesScript.to_morphed_normal(
			fl_lat, fl_lon, morph_factor, center_lon_deg
		)
		var s := lerpf(0.55, 1.15, globe_emphasis) * lerpf(0.45, 1.0, beacon_vis) * (1.25 + pulse * 0.35 if is_sos else 1.0)
		mi.position = f_surf + f_norm * 0.16
		mi.scale = Vector3.ONE * s
		var mat := _fleet_mats[i]
		mat.albedo_color = col
		mat.emission = col
		mi.visible = true
