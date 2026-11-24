class_name PlanetCameraController
extends Node
## Unified Solar-Scale Logarithmic Camera Controller (600:1 continuous zoom range!).
##
## zoom_level in [0.0, 1.0]:
##   0.78 .. 1.00 : Chiến khu 12x12 (0.66 deg tactical valley, LocalTerrainPatch 1 Draw Call)
##   0.54 .. 0.78 : Tỉnh / Vùng (1..12 deg, LocalTerrainPatch -> PlanetSurface crossfade)
##   0.24 .. 0.54 : Đại lục (12..180 deg, Global PlanetSurface + Clouds)
##   0.00 .. 0.24 : Morph liền mạch -> Hành tinh 3D xoay 360 deg + Khí quyển + Mây

signal view_changed(zoom_level: float, morph_factor: float, focus_lat: float, focus_lon: float)

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

@export var planet_radius: float = 10.0
@export var min_flat_altitude: float = 0.085
@export var max_flat_altitude: float = 36.0
@export var globe_orbit_distance: float = 32.5
@export var morph_start_zoom: float = 0.24
@export var morph_end_zoom: float = 0.03
@export var zoom_smooth_speed: float = 13.5
@export var pan_smooth_speed: float = 14.0
@export var orbit_damping: float = 8.5
@export var max_tactical_tilt_deg: float = 22.0

var camera: Camera3D
var renderer: Node3D

var zoom_level: float = 0.85
var target_zoom: float = 0.85
var morph_factor: float = 0.0

var focus_lat: float = 19.0
var focus_lon: float = -11.0
var target_lat: float = 19.0
var target_lon: float = -11.0

var _orbit_vel_lat: float = 0.0
var _orbit_vel_lon: float = 0.0
var _fly_active: bool = false

func setup(cam: Camera3D, planet_renderer: Node3D, radius: float = 10.0) -> void:
	camera = cam
	renderer = planet_renderer
	planet_radius = maxf(1.0, radius)
	if camera != null:
		camera.fov = 42.0
		camera.near = 0.01
		camera.far = planet_radius * 45.0
	apply_immediate()

## Adjust tactical floor altitude smoothly when switching between legacy 0.06-deg sector & 600x300 (0.60-deg) full planet.
func set_tile_deg_size(tile_deg: float) -> void:
	var target_min_alt := clampf(tile_deg * 1.42, 0.085, 1.25)
	if not is_equal_approx(min_flat_altitude, target_min_alt):
		min_flat_altitude = target_min_alt
		apply_immediate()

func set_focus_immediate(lat_deg: float, lon_deg: float, new_zoom: float = -1.0) -> void:
	focus_lat = clampf(lat_deg, -82.0, 82.0)
	focus_lon = PlanetCoordinatesScript.normalize_lon(lon_deg)
	target_lat = focus_lat
	target_lon = focus_lon
	_orbit_vel_lat = 0.0
	_orbit_vel_lon = 0.0
	_fly_active = false
	if new_zoom >= 0.0:
		zoom_level = clampf(new_zoom, 0.0, 1.0)
		target_zoom = zoom_level
	apply_immediate()

func fly_to_lat_lon(lat_deg: float, lon_deg: float, dest_zoom: float = -1.0) -> void:
	target_lat = clampf(lat_deg, -82.0, 82.0)
	target_lon = PlanetCoordinatesScript.normalize_lon(lon_deg)
	if dest_zoom >= 0.0:
		target_zoom = clampf(dest_zoom, 0.0, 1.0)
	_orbit_vel_lat = 0.0
	_orbit_vel_lon = 0.0
	_fly_active = true

func zoom_by_step(delta_zoom: float) -> void:
	target_zoom = clampf(target_zoom + delta_zoom, 0.0, 1.0)

func set_zoom_target(new_target_zoom: float) -> void:
	target_zoom = clampf(new_target_zoom, 0.0, 1.0)

func toggle_3d_planet_view() -> void:
	if target_zoom < 0.20:
		target_zoom = 0.85
	else:
		target_zoom = 0.0
	_fly_active = true

func is_planet_3d_mode() -> bool:
	return morph_factor >= 0.55

func apply_screen_drag(delta_px: Vector2, viewport_size: Vector2) -> void:
	_fly_active = false
	var vp_h := maxf(240.0, viewport_size.y)
	if morph_factor >= 0.55:
		var deg_per_px := 170.0 / vp_h
		var d_lon := -delta_px.x * deg_per_px
		var d_lat := delta_px.y * deg_per_px
		target_lon = PlanetCoordinatesScript.normalize_lon(target_lon + d_lon)
		target_lat = clampf(target_lat + d_lat, -82.0, 82.0)
		_orbit_vel_lon = clampf(d_lon * 2.5, -120.0, 120.0)
		_orbit_vel_lat = clampf(d_lat * 2.5, -90.0, 90.0)
	else:
		var alt := compute_flat_altitude(zoom_level)
		var fov_rad := deg_to_rad(camera.fov if camera != null else 42.0)
		var world_h := 2.0 * alt * tan(fov_rad * 0.5)
		var world_per_px := world_h / vp_h
		var d_lon := rad_to_deg((-delta_px.x * world_per_px) / planet_radius)
		var d_lat := rad_to_deg((delta_px.y * world_per_px) / planet_radius)
		target_lon = PlanetCoordinatesScript.normalize_lon(target_lon + d_lon)
		target_lat = clampf(target_lat + d_lat, -78.0, 78.0)
		_orbit_vel_lat = 0.0
		_orbit_vel_lon = 0.0

func apply_directional_move(move_dir: Vector2, delta: float) -> void:
	if move_dir == Vector2.ZERO:
		return
	_fly_active = false
	# Scale pan speed proportionally to current visible span so WASD feels natural at both 0.6 deg and 180 deg!
	var vis_span := get_visible_lat_lon_half_span()
	var speed_deg := clampf(vis_span.x * 1.15, 0.35, 65.0)
	target_lon = PlanetCoordinatesScript.normalize_lon(target_lon + move_dir.x * speed_deg * delta)
	target_lat = clampf(target_lat - move_dir.y * speed_deg * delta, -78.0, 78.0)

func step_update(delta: float) -> void:
	if delta <= 0.0:
		return
	if not _fly_active and morph_factor >= 0.55:
		if absf(_orbit_vel_lon) > 0.05 or absf(_orbit_vel_lat) > 0.05:
			target_lon = PlanetCoordinatesScript.normalize_lon(target_lon + _orbit_vel_lon * delta)
			target_lat = clampf(target_lat + _orbit_vel_lat * delta, -82.0, 82.0)
			var damp := exp(-orbit_damping * delta)
			_orbit_vel_lon *= damp
			_orbit_vel_lat *= damp

	var z_alpha := 1.0 - exp(-zoom_smooth_speed * delta)
	var p_alpha := 1.0 - exp(-pan_smooth_speed * delta)

	zoom_level = lerpf(zoom_level, target_zoom, z_alpha)
	if absf(zoom_level - target_zoom) < 0.0005:
		zoom_level = target_zoom

	var lon_diff := PlanetCoordinatesScript.normalize_lon(target_lon - focus_lon)
	focus_lon = PlanetCoordinatesScript.normalize_lon(focus_lon + lon_diff * p_alpha)
	focus_lat = lerpf(focus_lat, target_lat, p_alpha)

	if _fly_active and absf(lon_diff) < 0.03 and absf(target_lat - focus_lat) < 0.03 and absf(target_zoom - zoom_level) < 0.002:
		_fly_active = false

	apply_immediate()

func apply_immediate() -> void:
	morph_factor = compute_morph_for_zoom(zoom_level)
	var flat_alt := compute_flat_altitude(zoom_level)
	if renderer != null:
		if renderer.has_method("set_morph_factor"):
			renderer.call("set_morph_factor", morph_factor)
		if renderer.has_method("set_center_lon_deg"):
			renderer.call("set_center_lon_deg", focus_lon)

	if camera != null:
		_apply_camera_transform()

	view_changed.emit(zoom_level, morph_factor, focus_lat, focus_lon)

	if renderer != null and renderer.has_method("sync_local_clipmap"):
		var fov_deg := camera.fov if camera != null else 42.0
		renderer.call("sync_local_clipmap", focus_lat, focus_lon, flat_alt, fov_deg, zoom_level)

func compute_morph_for_zoom(z: float) -> float:
	if z >= morph_start_zoom:
		return 0.0
	if z <= morph_end_zoom:
		return 1.0
	var raw := (morph_start_zoom - z) / maxf(1e-4, morph_start_zoom - morph_end_zoom)
	return clampf(raw, 0.0, 1.0)

func compute_flat_altitude(z: float) -> float:
	var t := clampf((z - morph_start_zoom) / maxf(1e-4, 1.0 - morph_start_zoom), 0.0, 1.0)
	return exp(lerpf(log(max_flat_altitude), log(min_flat_altitude), t))

func get_visible_lat_lon_half_span() -> Vector2:
	if morph_factor >= 0.45:
		return Vector2(88.0, 95.0)
	var alt := compute_flat_altitude(zoom_level)
	var fov_deg := camera.fov if camera != null else 42.0
	var half_world_z := alt * tan(deg_to_rad(fov_deg * 0.5)) * 1.25
	var half_lat := clampf(rad_to_deg(half_world_z / planet_radius), 0.15, 90.0)
	var half_lon := clampf(half_lat * 1.85, 0.25, 180.0)
	return Vector2(half_lat, half_lon)

func _apply_camera_transform() -> void:
	var t: float = PlanetCoordinatesScript.smooth_morph(morph_factor)
	var lat_rad := deg_to_rad(focus_lat)
	var cl := cos(lat_rad)
	var sl := sin(lat_rad)

	var flat_alt := compute_flat_altitude(zoom_level)
	var p_flat_focus := Vector3(0.0, planet_radius, -planet_radius * lat_rad)
	# Smooth 22-deg strategic perspective tilt in Tactical Chiến Khu view (auto-flattens to 0 deg for Continent / 3D Globe)
	var tilt_raw := clampf((zoom_level - 0.72) / 0.18, 0.0, 1.0)
	var tilt_smooth := tilt_raw * tilt_raw * (3.0 - 2.0 * tilt_raw)
	var tilt_rad := deg_to_rad(max_tactical_tilt_deg) * tilt_smooth * (1.0 - t)
	var flat_pos := p_flat_focus + Vector3(0.0, flat_alt * cos(tilt_rad), flat_alt * sin(tilt_rad))
	var flat_up := Vector3(0.0, sin(tilt_rad), -cos(tilt_rad)).normalized()

	var radial_dir := Vector3(0.0, cl, -sl).normalized()
	var north_dir := Vector3(0.0, -sl, -cl).normalized()
	var globe_dist := lerpf(globe_orbit_distance, globe_orbit_distance * 0.88, clampf(zoom_level / maxf(0.01, morph_start_zoom), 0.0, 1.0))
	var globe_pos := radial_dir * globe_dist

	var cam_pos := flat_pos.lerp(globe_pos, t)
	var cam_target := p_flat_focus.lerp(Vector3.ZERO, t)
	var cam_up := flat_up.lerp(north_dir, t).normalized()

	camera.fov = lerpf(42.0, 44.0, t)
	var look_dir := (cam_target - cam_pos)
	if look_dir.length_squared() > 1e-6:
		var z_axis := (-look_dir).normalized()
		var x_axis := cam_up.cross(z_axis)
		if x_axis.length_squared() < 1e-6:
			x_axis = Vector3.RIGHT
		else:
			x_axis = x_axis.normalized()
		var y_axis := z_axis.cross(x_axis).normalized()
		camera.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), cam_pos)

func get_camera_distance_to_surface() -> float:
	if camera == null:
		return compute_flat_altitude(zoom_level)
	if morph_factor >= 0.5:
		return maxf(0.05, camera.global_position.length() - planet_radius)
	return maxf(0.05, camera.global_position.y - planet_radius)

func get_virtual_altitude_km(virtual_radius_km: float = PlanetCoordinatesScript.VIRTUAL_RADIUS_KM) -> float:
	return PlanetCoordinatesScript.compute_virtual_altitude_km(
		get_camera_distance_to_surface(), planet_radius, virtual_radius_km
	)

func project_lat_lon_to_screen(lat_deg: float, lon_deg: float) -> Dictionary:
	if camera == null:
		return {"pos": Vector2.ZERO, "visible": false, "world_pos": Vector3.ZERO, "normal": Vector3.UP}

	var world_pos: Vector3 = PlanetCoordinatesScript.to_morphed_position(
		lat_deg, lon_deg, planet_radius, morph_factor, focus_lon
	)
	var normal: Vector3 = PlanetCoordinatesScript.to_morphed_normal(
		lat_deg, lon_deg, morph_factor, focus_lon
	)
	var behind := camera.is_position_behind(world_pos)
	var front_facing := true
	if morph_factor > 0.35:
		var to_cam := (camera.global_position - world_pos).normalized()
		front_facing = normal.dot(to_cam) > 0.04

	var screen_pos := camera.unproject_position(world_pos)
	return {
		"pos": screen_pos,
		"visible": (not behind) and front_facing,
		"world_pos": world_pos,
		"normal": normal,
	}

func pick_lat_lon_at_screen(screen_pos: Vector2) -> Dictionary:
	if camera == null:
		return {"hit": false, "lat": 0.0, "lon": 0.0}

	var ray_o := camera.project_ray_origin(screen_pos)
	var ray_d := camera.project_ray_normal(screen_pos).normalized()

	if morph_factor < 0.40:
		if absf(ray_d.y) < 1e-5:
			return {"hit": false, "lat": 0.0, "lon": 0.0}
		var s := (planet_radius - ray_o.y) / ray_d.y
		if s <= 0.0:
			return {"hit": false, "lat": 0.0, "lon": 0.0}
		var hit_p := ray_o + ray_d * s
		var lat_deg := clampf(-rad_to_deg(hit_p.z / planet_radius), -90.0, 90.0)
		var lon_deg := PlanetCoordinatesScript.normalize_lon(focus_lon + rad_to_deg(hit_p.x / planet_radius))
		return {"hit": true, "lat": lat_deg, "lon": lon_deg, "world_pos": hit_p}
	else:
		var b := ray_o.dot(ray_d)
		var c := ray_o.dot(ray_o) - planet_radius * planet_radius
		var disc := b * b - c
		if disc < 0.0:
			return {"hit": false, "lat": 0.0, "lon": 0.0}
		var s := -b - sqrt(disc)
		if s <= 0.0:
			return {"hit": false, "lat": 0.0, "lon": 0.0}
		var hit_p := ray_o + ray_d * s
		var u := hit_p / planet_radius
		var lat_deg := rad_to_deg(asin(clampf(-u.z, -1.0, 1.0)))
		var lon_rel_deg := rad_to_deg(atan2(u.x, u.y))
		var lon_deg := PlanetCoordinatesScript.normalize_lon(focus_lon + lon_rel_deg)
		return {"hit": true, "lat": lat_deg, "lon": lon_deg, "world_pos": hit_p}
