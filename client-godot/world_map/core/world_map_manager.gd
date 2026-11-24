class_name WorldMapManager
extends Node
## Unified Facade connecting WorldRtsMap (Expedition Gameplay HUD) with WorldMap3D
## (PlanetData, PlanetCoordinates, PlanetCameraController, PlanetLODController, PlanetMarkerSystem).

signal view_state_changed(zoom_level: float, morph_factor: float, lod_tier: int)

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")
const PlanetFogManagerScript := preload("res://world_map/core/planet_fog_manager.gd")
const TacticalTerrainSplatScript := preload("res://world_map/core/tactical_terrain_splat.gd")

var world_3d: Node3D
var planet_data: Resource
var planet_renderer: Node3D
var camera_controller: Node
var lod_controller: Node
var marker_system: Node3D
var tactical_props: Node3D
var fog_manager: RefCounted
var terrain_splat: RefCounted

var _sector_bounds: Dictionary = PlanetCoordinatesScript.DEFAULT_SECTOR_BOUNDS.duplicate()
var _base_grid := Vector2(100.0, 100.0)
var _base_lat_lon := Vector2(19.0, -11.0)
var _pulse_time := 0.0
var _camera_stepped_this_frame := false

# Dirty-hash caches to prevent redundant 128x128 splat / 192x192 fog / 3D prop rebuilds on 3s polls
var _last_splat_sig := ""
var _last_fog_sig := ""
var _last_props_sig := ""
var splat_rebuild_count := 0
var fog_rebuild_count := 0
var props_rebuild_count := 0

static func compute_live_fleet_ratio(f: Dictionary, elapsed_sec: float) -> float:
	var st := str(f.get("status", "TRAVELING"))
	if st == "STRANDED" or st == "GARRISONED":
		return 1.0
	var base_ratio := clampf(float(f.get("progressRatio", 0.0)), 0.0, 1.0)
	if elapsed_sec <= 0.0:
		return base_ratio
	var total_dur := float(f.get("totalDurationSeconds", 0.0))
	if total_dur > 0.5:
		return clampf(base_ratio + (elapsed_sec / total_dur), 0.0, 1.0)
	var rem := float(f.get("secondsRemaining", 0.0))
	if rem > 0.1 and base_ratio < 0.999:
		return clampf(base_ratio + (1.0 - base_ratio) * (elapsed_sec / rem), 0.0, 1.0)
	return base_ratio

func setup(world_3d_scene: Node3D) -> void:
	world_3d = world_3d_scene
	if world_3d == null:
		return
	if world_3d.has_method("initialize_world"):
		world_3d.call("initialize_world")
	world_3d.set("external_camera_step", true)
	planet_data = world_3d.get("planet_data")
	planet_renderer = world_3d.get("planet_renderer")
	camera_controller = world_3d.get("camera_controller")
	lod_controller = world_3d.get("lod_controller")
	marker_system = world_3d.get("marker_system")
	tactical_props = world_3d.get("tactical_props")
	fog_manager = PlanetFogManagerScript.new()
	terrain_splat = TacticalTerrainSplatScript.new()

	if planet_data != null and planet_data.has_method("get_sector_bounds"):
		_sector_bounds = planet_data.call("get_sector_bounds")

	if camera_controller != null and not camera_controller.view_changed.is_connected(_on_camera_view_changed):
		camera_controller.view_changed.connect(_on_camera_view_changed)

	set_player_base_grid(_base_grid.x, _base_grid.y)
	if marker_system != null:
		marker_system.call(
			"set_wonder_lat_lon",
			float(_sector_bounds.get("wonder_lat", 6.0)),
			float(_sector_bounds.get("wonder_lon", 32.0))
		)
	rebuild_fog({})

## Synchronously advance 3D camera & markers BEFORE 2D tactical canvas draws -> strict 0-frame lag!
func step_camera(delta: float) -> void:
	_camera_stepped_this_frame = true
	_pulse_time += delta * 3.4
	if camera_controller != null:
		camera_controller.call("step_update", delta)
		_sync_3d_overlays()

func _process(delta: float) -> void:
	if _camera_stepped_this_frame:
		_camera_stepped_this_frame = false
		return
	_pulse_time += delta * 3.4
	if camera_controller != null:
		camera_controller.call("step_update", delta)
		_sync_3d_overlays()

func _sync_3d_overlays() -> void:
	if camera_controller == null:
		return
	var morph := float(camera_controller.get("morph_factor"))
	var flon := float(camera_controller.get("focus_lon"))
	var zlvl := float(camera_controller.get("zoom_level"))
	if marker_system != null:
		marker_system.call("sync_to_view", morph, flon, zlvl, _pulse_time)
	if tactical_props != null:
		tactical_props.call("sync_to_view", flon, zlvl, morph)

func _on_camera_view_changed(zoom_lvl: float, morph: float, _lat: float, _lon: float) -> void:
	var tier := int(lod_controller.get("current_tier")) if lod_controller != null else 0
	view_state_changed.emit(zoom_lvl, morph, tier)

func get_sector_bounds() -> Dictionary:
	return _sector_bounds

func apply_graphics_settings(cfg: Dictionary) -> void:
	if world_3d != null and world_3d.has_method("apply_graphics_settings"):
		world_3d.call("apply_graphics_settings", cfg)
	_last_props_sig = ""
	_sync_3d_overlays()

func is_full_planet_grid() -> bool:
	return int(_sector_bounds.get("world_grid_width", 0)) > 0 and int(_sector_bounds.get("world_grid_height", 0)) > 0

func apply_world_grid_config(world_grid: Dictionary) -> void:
	var w := int(world_grid.get("width", 0))
	var h := int(world_grid.get("height", 0))
	if w > 0 and h > 0:
		_sector_bounds["world_grid_width"] = w
		_sector_bounds["world_grid_height"] = h
	else:
		_sector_bounds.erase("world_grid_width")
		_sector_bounds.erase("world_grid_height")
	if camera_controller != null and camera_controller.has_method("set_tile_deg_size"):
		camera_controller.call("set_tile_deg_size", PlanetCoordinatesScript.get_tile_deg_size(_sector_bounds))

func grid_to_lat_lon(gx: float, gy: float) -> Vector2:
	return PlanetCoordinatesScript.grid_to_lat_lon(gx, gy, _sector_bounds)

func lat_lon_to_grid(lat_deg: float, lon_deg: float) -> Vector2:
	return PlanetCoordinatesScript.lat_lon_to_grid(lat_deg, lon_deg, _sector_bounds)

func set_player_base_grid(gx: float, gy: float) -> void:
	_base_grid = Vector2(gx, gy)
	_base_lat_lon = grid_to_lat_lon(gx, gy)
	if marker_system != null:
		marker_system.call("set_player_lat_lon", _base_lat_lon.x, _base_lat_lon.y)

func get_player_base_lat_lon() -> Vector2:
	return _base_lat_lon

func update_active_fleets(active_fleets: Array, mission_colors: Dictionary, elapsed_sec: float = 0.0) -> void:
	if marker_system == null:
		return
	var pts: Array = []
	for f in active_fleets:
		if not (f is Dictionary):
			continue
		var ratio := compute_live_fleet_ratio(f, elapsed_sec)
		var gx := lerpf(float(f.get("fromX", _base_grid.x)), float(f.get("toX", _base_grid.x)), ratio)
		var gy := lerpf(float(f.get("fromY", _base_grid.y)), float(f.get("toY", _base_grid.y)), ratio)
		var ll := grid_to_lat_lon(gx, gy)
		var st := str(f.get("status", "TRAVELING"))
		var m := str(f.get("mission", "SCOUT"))
		var col: Color = mission_colors.get("RETURNING" if st == "RETURNING" else m, Color(1.0, 0.92, 0.36))
		if st == "STRANDED":
			col = Color(0.98, 0.22, 0.26)
		pts.append({
			"lat": ll.x,
			"lon": ll.y,
			"color": col,
			"is_sos": st == "STRANDED",
		})
	marker_system.call("set_active_fleet_coords", pts)

func set_focus_grid_immediate(gx: float, gy: float, new_zoom: float = 0.85) -> void:
	if camera_controller == null:
		return
	var ll := grid_to_lat_lon(gx, gy)
	camera_controller.call("set_focus_immediate", ll.x, ll.y, new_zoom)

func fly_to_grid(gx: float, gy: float, dest_zoom: float = 0.85) -> void:
	if camera_controller == null:
		return
	var ll := grid_to_lat_lon(gx, gy)
	camera_controller.call("fly_to_lat_lon", ll.x, ll.y, dest_zoom)

func fly_to_lat_lon(lat_deg: float, lon_deg: float, dest_zoom: float = -1.0) -> void:
	if camera_controller == null:
		return
	camera_controller.call("fly_to_lat_lon", lat_deg, lon_deg, dest_zoom)

func zoom_by_step(delta_zoom: float) -> void:
	if camera_controller != null:
		camera_controller.call("zoom_by_step", delta_zoom)

func set_zoom_target(new_zoom: float) -> void:
	if camera_controller != null:
		camera_controller.call("set_zoom_target", new_zoom)

func _compute_snapshot_signatures(snapshot: Dictionary) -> Dictionary:
	var gw := int(_sector_bounds.get("world_grid_width", 0))
	var gh := int(_sector_bounds.get("world_grid_height", 0))
	var base: Dictionary = snapshot.get("base", {})
	var cc: Dictionary = snapshot.get("chunkCenter", {})
	var header := "%d:%d|%d,%d|%d,%d,%d" % [
		gw, gh,
		int(base.get("x", 0)), int(base.get("y", 0)),
		int(cc.get("x", 0)), int(cc.get("y", 0)), int(cc.get("radius", 0)),
	]
	var tiles: Array = snapshot.get("tiles", [])
	var splat_parts := PackedStringArray([header, str(tiles.size())])
	var vis_parts := PackedStringArray([header])
	var prop_parts := PackedStringArray([header])

	if tiles.size() > 0:
		var t_first = tiles[0]
		var t_last = tiles[tiles.size() - 1]
		if t_first is Dictionary:
			splat_parts.append("%s:%s" % [str(t_first.get("id", "")), str(t_first.get("terrain", ""))])
		if t_last is Dictionary:
			splat_parts.append("%s:%s" % [str(t_last.get("id", "")), str(t_last.get("terrain", ""))])

	for t in tiles:
		if not (t is Dictionary):
			continue
		if bool(t.get("visible", false)):
			var tid := str(t.get("id", ""))
			vis_parts.append(tid)
			var dung = t.get("dungeon", null)
			var d_id := str(dung.get("id", "")) if dung is Dictionary else ""
			prop_parts.append("%s:%s:%d:%s" % [tid, str(t.get("terrain", "")), 1 if bool(t.get("isBase", false)) else 0, d_id])

	for np in snapshot.get("nearbyPlayers", []):
		if np is Dictionary and bool(np.get("visible", false)):
			prop_parts.append("np:%s:%d,%d" % [str(np.get("masterId", "")), int(np.get("x", 0)), int(np.get("y", 0))])

	var fleet_parts := PackedStringArray()
	for f in snapshot.get("activeFleets", []):
		if not (f is Dictionary):
			continue
		var r := clampf(float(f.get("progressRatio", 0.0)), 0.0, 1.0)
		var qx := int(round(lerpf(float(f.get("fromX", 0)), float(f.get("toX", 0)), r) * 4.0))
		var qy := int(round(lerpf(float(f.get("fromY", 0)), float(f.get("toY", 0)), r) * 4.0))
		fleet_parts.append("%s:%d,%d" % [str(f.get("id", "")), qx, qy])

	var vis_str := ",".join(vis_parts)
	return {
		"splat": "|".join(splat_parts),
		"fog": "%s||%s" % [vis_str, ",".join(fleet_parts)],
		"props": ",".join(prop_parts),
	}

func rebuild_fog(snapshot: Dictionary) -> void:
	var sigs := _compute_snapshot_signatures(snapshot)
	if fog_manager != null and sigs["fog"] != _last_fog_sig:
		_last_fog_sig = sigs["fog"]
		fog_rebuild_count += 1
		fog_manager.call("rebuild_from_snapshot", snapshot, _sector_bounds, get_regions())
		if planet_renderer != null and planet_renderer.has_method("apply_fog_masks"):
			planet_renderer.call(
				"apply_fog_masks",
				fog_manager.get("local_fog_tex"),
				fog_manager.get("global_fog_tex"),
				fog_manager.get("local_fog_bounds")
			)
	if terrain_splat != null and sigs["splat"] != _last_splat_sig:
		_last_splat_sig = sigs["splat"]
		splat_rebuild_count += 1
		terrain_splat.call("rebuild_from_snapshot", snapshot, _sector_bounds)
		var tile_deg: float = PlanetCoordinatesScript.get_tile_deg_size(_sector_bounds)
		if planet_renderer != null and planet_renderer.has_method("apply_terrain_splat"):
			planet_renderer.call("apply_terrain_splat", terrain_splat.get("splat_tex"), terrain_splat.get("splat_bounds"), tile_deg)
	if tactical_props != null and sigs["props"] != _last_props_sig:
		_last_props_sig = sigs["props"]
		props_rebuild_count += 1
		tactical_props.call("rebuild_from_snapshot", snapshot, _sector_bounds)
		if camera_controller != null:
			tactical_props.call(
				"sync_to_view",
				float(camera_controller.get("focus_lon")),
				float(camera_controller.get("zoom_level")),
				float(camera_controller.get("morph_factor"))
			)

func get_global_fog_texture() -> Texture2D:
	return fog_manager.get("global_fog_tex") as Texture2D if fog_manager != null else null

func get_virtual_altitude_km() -> float:
	if camera_controller == null:
		return 120.0
	var vr := float(planet_data.get("virtual_radius_km")) if planet_data != null else PlanetCoordinatesScript.VIRTUAL_RADIUS_KM
	return float(camera_controller.call("get_virtual_altitude_km", vr))

func get_formatted_altitude_km() -> String:
	return PlanetCoordinatesScript.format_altitude_km(get_virtual_altitude_km())

func get_visible_lat_lon_half_span() -> Vector2:
	if camera_controller != null and camera_controller.has_method("get_visible_lat_lon_half_span"):
		return camera_controller.call("get_visible_lat_lon_half_span")
	return Vector2(45.0, 80.0)

func get_active_draw_calls() -> int:
	if planet_renderer != null and planet_renderer.has_method("get_active_draw_call_count"):
		return int(planet_renderer.call("get_active_draw_call_count"))
	return 1

func get_nearest_region_at_focus() -> Dictionary:
	var ll := get_focus_lat_lon()
	if planet_data != null and planet_data.has_method("find_nearest_region"):
		return planet_data.call("find_nearest_region", ll.x, ll.y)
	return {}

func get_continent_by_id(cid: String) -> Dictionary:
	if planet_data != null and planet_data.has_method("get_continent"):
		return planet_data.call("get_continent", cid)
	return {}

func toggle_3d_planet_view() -> void:
	if camera_controller != null:
		camera_controller.call("toggle_3d_planet_view")

func apply_screen_drag(delta_px: Vector2, viewport_size: Vector2) -> void:
	if camera_controller != null:
		camera_controller.call("apply_screen_drag", delta_px, viewport_size)

func apply_directional_move(move_dir: Vector2, delta: float) -> void:
	if camera_controller != null:
		camera_controller.call("apply_directional_move", move_dir, delta)

func project_grid_to_screen(gx: float, gy: float) -> Dictionary:
	var ll := grid_to_lat_lon(gx, gy)
	return project_lat_lon_to_screen(ll.x, ll.y)

func project_lat_lon_to_screen(lat_deg: float, lon_deg: float) -> Dictionary:
	if camera_controller == null:
		return {"pos": Vector2.ZERO, "visible": false, "world_pos": Vector3.ZERO, "normal": Vector3.UP}
	return camera_controller.call("project_lat_lon_to_screen", lat_deg, lon_deg)

func pick_at_screen(screen_pos: Vector2) -> Dictionary:
	if camera_controller == null:
		return {"hit": false, "lat": 0.0, "lon": 0.0, "grid": Vector2.ZERO, "nearest_region": {}}
	var res: Dictionary = camera_controller.call("pick_lat_lon_at_screen", screen_pos)
	if not bool(res.get("hit", false)):
		res["grid"] = Vector2.ZERO
		res["nearest_region"] = {}
		return res
	var lat := float(res["lat"])
	var lon := float(res["lon"])
	res["grid"] = lat_lon_to_grid(lat, lon)
	if planet_data != null and planet_data.has_method("find_nearest_region"):
		res["nearest_region"] = planet_data.call("find_nearest_region", lat, lon)
	else:
		res["nearest_region"] = {}
	return res

func get_zoom_level() -> float:
	return float(camera_controller.get("zoom_level")) if camera_controller != null else 0.78

func get_morph_factor() -> float:
	return float(camera_controller.get("morph_factor")) if camera_controller != null else 0.0

func is_planet_3d_mode() -> bool:
	return bool(camera_controller.call("is_planet_3d_mode")) if camera_controller != null else false

func get_focus_lat_lon() -> Vector2:
	if camera_controller == null:
		return _base_lat_lon
	return Vector2(float(camera_controller.get("focus_lat")), float(camera_controller.get("focus_lon")))

func get_center_grid_coord() -> Vector2i:
	var ll := get_focus_lat_lon()
	var g := lat_lon_to_grid(ll.x, ll.y)
	return Vector2i(int(round(g.x)), int(round(g.y)))

func get_lod_snapshot() -> Dictionary:
	if lod_controller != null and lod_controller.has_method("get_snapshot"):
		return lod_controller.call("get_snapshot")
	return {
		"tier": 0,
		"label": "Địa phương",
		"tactical_overlay_alpha": 1.0,
		"fleet_overlay_alpha": 1.0,
		"region_label_alpha": 0.35,
		"continent_label_alpha": 0.0,
		"show_detail_markers": true,
	}

func get_continents() -> Array:
	if planet_data != null:
		if planet_data.has_method("ensure_regions_loaded"):
			planet_data.call("ensure_regions_loaded")
		var c = planet_data.get("continents")
		if c is Array:
			return c
	return []

func get_regions() -> Array:
	if planet_data != null:
		if planet_data.has_method("ensure_regions_loaded"):
			planet_data.call("ensure_regions_loaded")
		var r = planet_data.get("regions")
		if r is Array:
			return r
	return []

func get_albedo_texture() -> Texture2D:
	if planet_data != null and planet_data.has_method("load_texture_layer"):
		return planet_data.call("load_texture_layer", str(planet_data.get("albedo_path"))) as Texture2D
	return null
