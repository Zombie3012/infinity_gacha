class_name PlanetFogManager
extends RefCounted
## Dual-Resolution Soft Planetary Fog-of-War Mask Generator (P1).
##
## Produces two ultra-lightweight FORMAT_R8 ImageTextures:
## 1. local_fog_tex  (128x128 = 16 KB): covers ~1.6 deg x 1.6 deg around the active Expedition Sector
##    for razor-sharp soft misty cloud edges around every 0.06-deg tile.
## 2. global_fog_tex (360x180 = 64 KB): covers the entire 360x180 deg Fantasy Planet so unexplored
##    continents rest beneath swirling mist while explored regions & Imperial Wonder glow through.
##
## Pixel encoding (R channel in [0, 1]):
##   0.0 = Unexplored (dense swirling cloud mist)
##   0.35..0.55 = Faint mythic landmark / discovered province silhouette
##   1.0 = Clear live vision (Base, Scout 1h trail, Garrison, Active Fleets)

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

const LOCAL_W := 192
const LOCAL_H := 192
const GLOBAL_W := 360
const GLOBAL_H := 180

var local_fog_image: Image
var local_fog_tex: ImageTexture
var global_fog_image: Image
var global_fog_tex: ImageTexture

# Vector4(lat_min, lat_max, lon_min, lon_max) of local_fog_tex window
var local_fog_bounds: Vector4 = Vector4(18.20, 19.80, -11.80, -10.20)
var _local_buf: PackedByteArray
var _global_buf: PackedByteArray

func _init() -> void:
	_local_buf = PackedByteArray()
	_local_buf.resize(LOCAL_W * LOCAL_H)
	_global_buf = PackedByteArray()
	_global_buf.resize(GLOBAL_W * GLOBAL_H)

	_local_buf.fill(0)
	_global_buf.fill(0)
	local_fog_image = Image.create_from_data(LOCAL_W, LOCAL_H, false, Image.FORMAT_R8, _local_buf)
	global_fog_image = Image.create_from_data(GLOBAL_W, GLOBAL_H, false, Image.FORMAT_R8, _global_buf)
	local_fog_tex = ImageTexture.create_from_image(local_fog_image)
	global_fog_tex = ImageTexture.create_from_image(global_fog_image)

func rebuild_from_snapshot(snapshot: Dictionary, sector_bounds: Dictionary, regions: Array = []) -> void:
	var use_full_planet := int(sector_bounds.get("world_grid_width", 0)) > 0
	var tile_deg: float = PlanetCoordinatesScript.get_tile_deg_size(sector_bounds)
	var lat_min := float(sector_bounds.get("lat_min", 18.67))
	var lat_max := float(sector_bounds.get("lat_max", 19.33))
	var lon_min := float(sector_bounds.get("lon_min", -11.33))
	var lon_max := float(sector_bounds.get("lon_max", -10.67))

	var base: Dictionary = snapshot.get("base", {"x": 100, "y": 100})
	var base_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(
		float(base.get("x", 100)), float(base.get("y", 100)), sector_bounds
	)
	if use_full_planet:
		var cc: Dictionary = snapshot.get("chunkCenter", base)
		var cc_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(
			float(cc.get("x", base.get("x", 300))),
			float(cc.get("y", base.get("y", 150))),
			sector_bounds
		)
		var rad_deg := float(maxi(12, int(cc.get("radius", 12)))) * tile_deg
		lat_min = clampf(minf(cc_ll.x, base_ll.x) - rad_deg, -88.0, 88.0)
		lat_max = clampf(maxf(cc_ll.x, base_ll.x) + rad_deg, -88.0, 88.0)
		lon_min = minf(cc_ll.y, base_ll.y) - rad_deg
		lon_max = maxf(cc_ll.y, base_ll.y) + rad_deg

	var lat_span := maxf(0.1, lat_max - lat_min)
	var lon_span := maxf(0.1, lon_max - lon_min)
	# Generous margin guarantees global_fog_tex is 0.0 everywhere on the local_fog_bounds perimeter (ZERO seam!)
	var pad_lat := maxf(2.0, tile_deg * 4.5) if use_full_planet else maxf(2.0, lat_span * 2.5)
	var pad_lon := maxf(2.0, tile_deg * 4.5) if use_full_planet else maxf(2.0, lon_span * 2.5)
	local_fog_bounds = Vector4(lat_min - pad_lat, lat_max + pad_lat, lon_min - pad_lon, lon_max + pad_lon)

	_local_buf.fill(0)
	_global_buf.fill(0)

	# 1. Paint Imperial Wonder subtle glow (far away at lat 6, lon 32)
	var w_lat := float(sector_bounds.get("wonder_lat", 6.0))
	var w_lon := float(sector_bounds.get("wonder_lon", 32.0))
	_paint_global_disc(w_lat, w_lon, 4.0, 0.75)

	# 2. Paint Base & visible server RTS tiles onto local_fog_tex (strictly 100% clear on visible tiles!)
	var g_base_rad := maxf(0.85, tile_deg * 2.0)
	var g_tile_rad := maxf(0.55, tile_deg * 1.15)
	_paint_local_disc(base_ll.x, base_ll.y, tile_deg * 2.6, 1.0)
	_paint_global_disc(base_ll.x, base_ll.y, g_base_rad, 1.0)

	var tiles: Array = snapshot.get("tiles", [])
	for t in tiles:
		if not (t is Dictionary):
			continue
		if not bool(t.get("visible", false)):
			continue
		var ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(
			float(t.get("x", 100)), float(t.get("y", 100)), sector_bounds
		)
		_paint_local_disc(ll.x, ll.y, tile_deg * 1.42, 1.0)
		_paint_global_disc(ll.x, ll.y, g_tile_rad, 0.95)

	# 3. Paint Active Fleets live vision halos
	for f in snapshot.get("activeFleets", []):
		if not (f is Dictionary):
			continue
		var ratio := clampf(float(f.get("progressRatio", 0.0)), 0.0, 1.0)
		var gx := lerpf(float(f.get("fromX", 100)), float(f.get("toX", 100)), ratio)
		var gy := lerpf(float(f.get("fromY", 100)), float(f.get("toY", 100)), ratio)
		var fl_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(gx, gy, sector_bounds)
		_paint_local_disc(fl_ll.x, fl_ll.y, tile_deg * 1.65, 1.0)
		_paint_global_disc(fl_ll.x, fl_ll.y, maxf(0.65, tile_deg * 1.4), 0.95)

	local_fog_image.set_data(LOCAL_W, LOCAL_H, false, Image.FORMAT_R8, _local_buf)
	local_fog_tex.update(local_fog_image)
	global_fog_image.set_data(GLOBAL_W, GLOBAL_H, false, Image.FORMAT_R8, _global_buf)
	global_fog_tex.update(global_fog_image)

func _paint_local_disc(lat_deg: float, lon_deg: float, radius_deg: float, peak: float) -> void:
	var lat_min := local_fog_bounds.x
	var lat_max := local_fog_bounds.y
	var lon_min := local_fog_bounds.z
	var lon_max := local_fog_bounds.w
	var lat_span := maxf(1e-4, lat_max - lat_min)
	var lon_span := maxf(1e-4, lon_max - lon_min)

	var u_c := (lon_deg - lon_min) / lon_span
	var v_c := (lat_max - lat_deg) / lat_span
	var rx_px := (radius_deg / lon_span) * float(LOCAL_W)
	var ry_px := (radius_deg / lat_span) * float(LOCAL_H)
	var cx := u_c * float(LOCAL_W - 1)
	var cy := v_c * float(LOCAL_H - 1)

	var x0 := maxi(0, int(floor(cx - rx_px - 1.0)))
	var x1 := mini(LOCAL_W - 1, int(ceil(cx + rx_px + 1.0)))
	var y0 := maxi(0, int(floor(cy - ry_px - 1.0)))
	var y1 := mini(LOCAL_H - 1, int(ceil(cy + ry_px + 1.0)))
	if x0 > x1 or y0 > y1:
		return

	var inv_rx := 1.0 / maxf(0.5, rx_px)
	var inv_ry := 1.0 / maxf(0.5, ry_px)
	for y in range(y0, y1 + 1):
		var dy := (float(y) - cy) * inv_ry
		var dy2 := dy * dy
		var row := y * LOCAL_W
		for x in range(x0, x1 + 1):
			var dx := (float(x) - cx) * inv_rx
			var d := sqrt(dx * dx + dy2)
			if d >= 1.0:
				continue
			# Smooth soft cloud falloff: flat bright core out to 0.55, feathery edge 0.55 -> 1.0
			var edge := clampf((1.0 - d) / 0.45, 0.0, 1.0)
			var val := edge * edge * (3.0 - 2.0 * edge) * peak
			var byte_v := int(clampf(val * 255.0, 0.0, 255.0))
			var idx := row + x
			if byte_v > _local_buf[idx]:
				_local_buf[idx] = byte_v

func _paint_global_disc(lat_deg: float, lon_deg: float, radius_deg: float, peak: float) -> void:
	var uv: Vector2 = PlanetCoordinatesScript.lat_lon_to_uv(lat_deg, lon_deg)
	var cx := uv.x * float(GLOBAL_W)
	var cy := uv.y * float(GLOBAL_H)
	var rx_px := (radius_deg / 360.0) * float(GLOBAL_W)
	var ry_px := (radius_deg / 180.0) * float(GLOBAL_H)

	var y0 := maxi(0, int(floor(cy - ry_px - 1.0)))
	var y1 := mini(GLOBAL_H - 1, int(ceil(cy + ry_px + 1.0)))
	var x_span := int(ceil(rx_px + 1.0))
	var inv_rx := 1.0 / maxf(0.5, rx_px)
	var inv_ry := 1.0 / maxf(0.5, ry_px)
	var cx_i := int(round(cx))

	for y in range(y0, y1 + 1):
		var dy := (float(y) - cy) * inv_ry
		var dy2 := dy * dy
		var row := y * GLOBAL_W
		for dx_i in range(-x_span, x_span + 1):
			var x := (cx_i + dx_i) % GLOBAL_W
			if x < 0:
				x += GLOBAL_W
			var dx := float(dx_i) * inv_rx
			var d := sqrt(dx * dx + dy2)
			if d >= 1.0:
				continue
			var edge := clampf((1.0 - d) / 0.55, 0.0, 1.0)
			var val := edge * edge * (3.0 - 2.0 * edge) * peak
			var byte_v := int(clampf(val * 255.0, 0.0, 255.0))
			var idx := row + x
			if byte_v > _global_buf[idx]:
				_global_buf[idx] = byte_v

func sample_reveal_at_lat_lon(lat_deg: float, lon_deg: float) -> float:
	if lat_deg >= local_fog_bounds.x and lat_deg <= local_fog_bounds.y and lon_deg >= local_fog_bounds.z and lon_deg <= local_fog_bounds.w:
		var u := clampf((lon_deg - local_fog_bounds.z) / maxf(1e-4, local_fog_bounds.w - local_fog_bounds.z), 0.0, 1.0)
		var v := clampf((local_fog_bounds.y - lat_deg) / maxf(1e-4, local_fog_bounds.y - local_fog_bounds.x), 0.0, 1.0)
		var lx := clampi(int(round(u * float(LOCAL_W - 1))), 0, LOCAL_W - 1)
		var ly := clampi(int(round(v * float(LOCAL_H - 1))), 0, LOCAL_H - 1)
		return float(_local_buf[ly * LOCAL_W + lx]) / 255.0
	var uv: Vector2 = PlanetCoordinatesScript.lat_lon_to_uv(lat_deg, lon_deg)
	var gx := clampi(int(round(uv.x * float(GLOBAL_W - 1))), 0, GLOBAL_W - 1)
	var gy := clampi(int(round(uv.y * float(GLOBAL_H - 1))), 0, GLOBAL_H - 1)
	return float(_global_buf[gy * GLOBAL_W + gx]) / 255.0
