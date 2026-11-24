class_name PlanetCoordinates
extends RefCounted
## Single source of truth for Expedition Fantasy Planet coordinate transforms.
##
## Locked conventions (shared identically by GDScript & planet_surface_morph.gdshader):
## - Equirectangular UV:
##     u in [0, 1] -> longitude in [-180 deg, +180 deg] (West -> East, +X)
##     v in [0, 1] -> latitude  in [+90 deg,  -90 deg] (North at top v=0 -> South at bottom v=1)
## - Tangent-top local planet space (planet center at (0, 0, 0), radius R):
##     Flat map lies on the horizontal tangent plane y = +R with North = -Z, East = +X.
##     At (lat = 0, lon = center_lon): P_flat == P_sphere == (0, +R, 0), with identical tangent
##     vectors and outward normal +Y so morphing 0.0 -> 1.0 curves seamlessly with zero jump.

const VIRTUAL_RADIUS_KM := 696000.0 # Sun-scale virtual planet radius for epic continent scale

const DEFAULT_SECTOR_BOUNDS := {
	"grid_origin_x": 100.0,
	"grid_origin_y": 100.0,
	"grid_span_x": 11.0,
	"grid_span_y": 11.0,
	# Solar-scale tactical valley: 0.66 deg x 0.66 deg (0.06 deg/tile) inside Emerald Reach (~48 deg wide)
	"lat_min": 18.67,
	"lat_max": 19.33,
	"lon_min": -11.33,
	"lon_max": -10.67,
	"wonder_grid_x": 500.0,
	"wonder_grid_y": 500.0,
	"wonder_lat": 6.0,
	"wonder_lon": 32.0,
}

static func compute_virtual_altitude_km(cam_dist_to_surface: float, render_radius: float = 10.0, virtual_radius_km: float = VIRTUAL_RADIUS_KM) -> float:
	var ratio := maxf(0.0, cam_dist_to_surface) / maxf(0.1, render_radius)
	# Nonlinear cosmetic curve so tactical level reads ~80-400 km while full orbit reaches ~1.5M km
	return pow(ratio, 1.38) * virtual_radius_km * 0.72

static func format_altitude_km(km: float) -> String:
	if km >= 1000000.0:
		return "%.2fM km" % (km / 1000000.0)
	if km >= 10000.0:
		return "%dK km" % int(round(km / 1000.0))
	if km >= 1000.0:
		return "%.1fK km" % (km / 1000.0)
	return "%d km" % maxi(10, int(round(km)))

static func normalize_lon(lon_deg: float) -> float:
	var wrapped := fmod(lon_deg + 180.0, 360.0)
	if wrapped < 0.0:
		wrapped += 360.0
	var res := wrapped - 180.0
	# Preserve +180.0 only when caller passes exact +180; otherwise canonical [-180, 180)
	if is_equal_approx(lon_deg, 180.0):
		return 180.0
	return res

static func clamp_lat(lat_deg: float) -> float:
	return clampf(lat_deg, -90.0, 90.0)

static func smooth_morph(morph_factor: float) -> float:
	var t := clampf(morph_factor, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Convert geographic (lat_deg, lon_deg) -> Equirectangular UV in [0, 1]^2.
static func lat_lon_to_uv(lat_deg: float, lon_deg: float) -> Vector2:
	var lon := normalize_lon(lon_deg)
	var lat := clamp_lat(lat_deg)
	var u := clampf((lon / 360.0) + 0.5, 0.0, 1.0)
	var v := clampf(0.5 - (lat / 180.0), 0.0, 1.0)
	return Vector2(u, v)

## Convert Equirectangular UV in [0, 1]^2 -> Vector2(lat_deg, lon_deg).
static func uv_to_lat_lon(uv: Vector2) -> Vector2:
	var lon_deg := (uv.x - 0.5) * 360.0
	var lat_deg := (0.5 - uv.y) * 180.0
	return Vector2(clamp_lat(lat_deg), normalize_lon(lon_deg))

## Standard Y-up unit sphere vector for seamless 3D spherical noise sampling.
static func lat_lon_to_unit_sphere_yup(lat_deg: float, lon_deg: float) -> Vector3:
	var lat := deg_to_rad(clamp_lat(lat_deg))
	var lon := deg_to_rad(normalize_lon(lon_deg))
	var cl := cos(lat)
	return Vector3(cl * cos(lon), sin(lat), cl * sin(lon))

## Convert server RTS grid (gx, gy) -> Vector2(lat_deg, lon_deg).
static func grid_to_lat_lon(gx: float, gy: float, bounds: Dictionary = DEFAULT_SECTOR_BOUNDS) -> Vector2:
	var wx := float(bounds.get("wonder_grid_x", 500.0))
	var wy := float(bounds.get("wonder_grid_y", 500.0))
	if absf(gx - wx) < 0.5 and absf(gy - wy) < 0.5:
		return Vector2(
			float(bounds.get("wonder_lat", 6.0)),
			float(bounds.get("wonder_lon", 32.0))
		)
	var gw := int(bounds.get("world_grid_width", 0))
	var gh := int(bounds.get("world_grid_height", 0))
	if gw > 0 and gh > 0:
		var lon_deg := normalize_lon((((gx + 0.5) / float(gw)) - 0.5) * 360.0)
		var lat_deg := clamp_lat((0.5 - ((gy + 0.5) / float(gh))) * 180.0)
		return Vector2(lat_deg, lon_deg)

	var ox := float(bounds.get("grid_origin_x", 100.0))
	var oy := float(bounds.get("grid_origin_y", 100.0))
	var sx := maxf(1.0, float(bounds.get("grid_span_x", 11.0)))
	var sy := maxf(1.0, float(bounds.get("grid_span_y", 11.0)))
	var lat_min := float(bounds.get("lat_min", 18.67))
	var lat_max := float(bounds.get("lat_max", 19.33))
	var lon_min := float(bounds.get("lon_min", -11.33))
	var lon_max := float(bounds.get("lon_max", -10.67))

	var tx := (gx - ox) / sx
	var ty := (gy - oy) / sy
	# Smaller Y is North (higher lat), larger X is East (higher lon)
	var lat_deg := clamp_lat(lerpf(lat_max, lat_min, ty))
	var lon_deg := normalize_lon(lerpf(lon_min, lon_max, tx))
	return Vector2(lat_deg, lon_deg)

## Convert Vector2(lat_deg, lon_deg) -> server RTS grid Vector2(gx, gy).
static func lat_lon_to_grid(lat_deg: float, lon_deg: float, bounds: Dictionary = DEFAULT_SECTOR_BOUNDS) -> Vector2:
	var gw := int(bounds.get("world_grid_width", 0))
	var gh := int(bounds.get("world_grid_height", 0))
	if gw > 0 and gh > 0:
		var gx := ((normalize_lon(lon_deg) / 360.0) + 0.5) * float(gw) - 0.5
		var gy := (0.5 - (clamp_lat(lat_deg) / 180.0)) * float(gh) - 0.5
		return Vector2(gx, gy)

	var ox := float(bounds.get("grid_origin_x", 100.0))
	var oy := float(bounds.get("grid_origin_y", 100.0))
	var sx := maxf(1.0, float(bounds.get("grid_span_x", 11.0)))
	var sy := maxf(1.0, float(bounds.get("grid_span_y", 11.0)))
	var lat_min := float(bounds.get("lat_min", 18.67))
	var lat_max := float(bounds.get("lat_max", 19.33))
	var lon_min := float(bounds.get("lon_min", -11.33))
	var lon_max := float(bounds.get("lon_max", -10.67))

	var lon_span := lon_max - lon_min
	var lat_span := lat_max - lat_min
	var tx := (normalize_lon(lon_deg) - lon_min) / (lon_span if absf(lon_span) > 1e-5 else 1.0)
	var ty := (lat_max - clamp_lat(lat_deg)) / (lat_span if absf(lat_span) > 1e-5 else 1.0)
	return Vector2(ox + tx * sx, oy + ty * sy)

## Angular size (degrees) of 1 tactical tile under current sector/world grid bounds.
static func get_tile_deg_size(bounds: Dictionary = DEFAULT_SECTOR_BOUNDS) -> float:
	var gw := int(bounds.get("world_grid_width", 0))
	if gw > 0:
		return 360.0 / float(gw)
	var lon_span := absf(float(bounds.get("lon_max", -10.67)) - float(bounds.get("lon_min", -11.33)))
	var sx := maxf(1.0, float(bounds.get("grid_span_x", 11.0)))
	return lon_span / sx

## Position on the flat tangent map plane (y = +radius, North = -Z, East = +X).
static func to_flat_position(lat_deg: float, lon_deg: float, radius: float, center_lon_deg: float = 0.0) -> Vector3:
	var lon_rel := deg_to_rad(normalize_lon(lon_deg - center_lon_deg))
	var lat_rad := deg_to_rad(clamp_lat(lat_deg))
	return Vector3(radius * lon_rel, radius, -radius * lat_rad)

## Position on the 3D sphere centered at (0, 0, 0) where (lat=0, lon=center_lon) is at (0, +radius, 0).
static func to_sphere_position(lat_deg: float, lon_deg: float, radius: float, center_lon_deg: float = 0.0) -> Vector3:
	var lon_rel := deg_to_rad(normalize_lon(lon_deg - center_lon_deg))
	var lat_rad := deg_to_rad(clamp_lat(lat_deg))
	var cl := cos(lat_rad)
	return Vector3(
		radius * cl * sin(lon_rel),
		radius * cl * cos(lon_rel),
		-radius * sin(lat_rad)
	)

## Seamless morphed 3D position matching planet_surface_morph.gdshader exactly.
static func to_morphed_position(
	lat_deg: float,
	lon_deg: float,
	radius: float,
	morph_factor: float,
	center_lon_deg: float = 0.0
) -> Vector3:
	var t := smooth_morph(morph_factor)
	var p_flat := to_flat_position(lat_deg, lon_deg, radius, center_lon_deg)
	var p_sphere := to_sphere_position(lat_deg, lon_deg, radius, center_lon_deg)
	return p_flat.lerp(p_sphere, t)

## Analytic outward unit normal at (lat_deg, lon_deg) for any morph_factor in [0, 1].
static func to_morphed_normal(
	lat_deg: float,
	lon_deg: float,
	morph_factor: float,
	center_lon_deg: float = 0.0
) -> Vector3:
	var t := smooth_morph(morph_factor)
	if t <= 1e-5:
		return Vector3.UP
	var clamped_lat := clamp_lat(lat_deg)
	if absf(clamped_lat) >= 89.5:
		var pole_n := Vector3(0.0, 0.0, -1.0 if clamped_lat > 0.0 else 1.0)
		return Vector3.UP.lerp(pole_n, t).normalized()

	var lon_rel := deg_to_rad(normalize_lon(lon_deg - center_lon_deg))
	var lat_rad := deg_to_rad(clamped_lat)
	var cl := cos(lat_rad)
	var sl := sin(lat_rad)
	var c_lon := cos(lon_rel)
	var s_lon := sin(lon_rel)

	var d_flat_lon := Vector3(1.0, 0.0, 0.0)
	var d_flat_lat := Vector3(0.0, 0.0, -1.0)
	var d_sph_lon := Vector3(cl * c_lon, -cl * s_lon, 0.0)
	var d_sph_lat := Vector3(-sl * s_lon, -sl * c_lon, -cl)

	var tangent_east := d_flat_lon.lerp(d_sph_lon, t)
	var tangent_north := d_flat_lat.lerp(d_sph_lat, t)
	var n := tangent_east.cross(tangent_north)
	if n.length_squared() < 1e-8:
		return to_sphere_position(clamped_lat, lon_deg, 1.0, center_lon_deg).normalized()
	return n.normalized()

## Pole-safe orthonormal surface Basis whose +Y axis aligns with `normal`.
static func surface_basis(normal: Vector3) -> Basis:
	var y_axis := normal.normalized()
	if y_axis.length_squared() < 1e-6:
		return Basis.IDENTITY
	var ref := Vector3.FORWARD if absf(y_axis.y) > 0.98 else Vector3.UP
	var x_axis := ref.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)

## Great-circle angular distance in degrees between two (lat, lon) points.
static func great_circle_distance_deg(lat1_deg: float, lon1_deg: float, lat2_deg: float, lon2_deg: float) -> float:
	var p1 := lat_lon_to_unit_sphere_yup(lat1_deg, lon1_deg)
	var p2 := lat_lon_to_unit_sphere_yup(lat2_deg, lon2_deg)
	return rad_to_deg(acos(clampf(p1.dot(p2), -1.0, 1.0)))
