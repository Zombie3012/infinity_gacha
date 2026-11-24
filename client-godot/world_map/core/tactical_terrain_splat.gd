class_name TacticalTerrainSplat
extends RefCounted
## Encodes streamed server RTS tile terrains (OCEAN, PLAINS, FOREST, HILLS, MOUNTAIN, MARSH, RUINS, BASE)
## into a compact 128x128 RGBA8 texture aligned dynamically to the active chunk bounding box
## (supports both legacy 12x12 sector & full-planet 600x300 sliding chunks!).
##
## Channel encoding:
##   R = terrain class ID (0.04=OCEAN, 0.12=PLAINS, 0.28=FOREST, 0.44=HILLS, 0.60=MOUNTAIN, 0.76=MARSH, 0.90=RUINS, 1.0=BASE)
##   G = tile interior radial weight (1.0 at tile center -> 0.0 at tile border, for ponds/courtyards/clearings)
##   B = chunk coverage mask (1.0 inside active tiles, smoothly fading at chunk edge)
##   A = 1.0

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

const TEX_W := 128
const TEX_H := 128

const TERRAIN_CODE := {
	"OCEAN": 12,    # ~0.047
	"PLAINS": 32,   # ~0.125
	"FOREST": 72,   # ~0.282
	"HILLS": 112,   # ~0.439
	"MOUNTAIN": 154,# ~0.604
	"MARSH": 194,   # ~0.761
	"RUINS": 228,   # ~0.894
	"WONDER": 255,
	"BASE": 255,    # 1.0
}

var splat_image: Image
var splat_tex: ImageTexture
# Vector4(lat_min, lat_max, lon_min, lon_max) spanning active chunk edges
var splat_bounds: Vector4 = Vector4(18.64, 19.36, -11.36, -10.64)
var _buf: PackedByteArray

func _init() -> void:
	_buf = PackedByteArray()
	_buf.resize(TEX_W * TEX_H * 4)
	_buf.fill(0)
	splat_image = Image.create_from_data(TEX_W, TEX_H, false, Image.FORMAT_RGBA8, _buf)
	splat_tex = ImageTexture.create_from_image(splat_image)

func rebuild_from_snapshot(snapshot: Dictionary, sector_bounds: Dictionary) -> void:
	var tile_deg: float = PlanetCoordinatesScript.get_tile_deg_size(sector_bounds)
	var half_deg := tile_deg * 0.5
	var tiles: Array = snapshot.get("tiles", [])

	var min_x := 999999
	var max_x := -999999
	var min_y := 999999
	var max_y := -999999
	var has_any := false

	# Keep chunk bbox tight around chunkCenter (ignores distant expedition target outliers!)
	var chunk_center: Dictionary = snapshot.get("chunkCenter", {})
	var base: Dictionary = snapshot.get("base", {})
	var use_full_planet := int(sector_bounds.get("world_grid_width", 0)) > 0
	var cx_ref := int(chunk_center.get("x", base.get("x", 105)))
	var cy_ref := int(chunk_center.get("y", base.get("y", 105)))
	var max_rad := maxi(16, int(chunk_center.get("radius", 12)) + 2)

	for t in tiles:
		if not (t is Dictionary):
			continue
		var tx := int(t.get("x", 0))
		var ty := int(t.get("y", 0))
		if use_full_planet and (absi(tx - cx_ref) > max_rad or absi(ty - cy_ref) > max_rad):
			continue
		min_x = mini(min_x, tx)
		max_x = maxi(max_x, tx)
		min_y = mini(min_y, ty)
		max_y = maxi(max_y, ty)
		has_any = true

	if not has_any:
		min_x = int(round(float(sector_bounds.get("grid_origin_x", 100.0))))
		min_y = int(round(float(sector_bounds.get("grid_origin_y", 100.0))))
		max_x = min_x + int(round(float(sector_bounds.get("grid_span_x", 11.0))))
		max_y = min_y + int(round(float(sector_bounds.get("grid_span_y", 11.0))))

	var cols := clampi(max_x - min_x + 1, 1, 48)
	var rows := clampi(max_y - min_y + 1, 1, 48)
	max_x = min_x + cols - 1
	max_y = min_y + rows - 1

	var tl_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(float(min_x), float(min_y), sector_bounds)
	var br_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(float(max_x), float(max_y), sector_bounds)
	var lat_min := minf(tl_ll.x, br_ll.x) - half_deg
	var lat_max := maxf(tl_ll.x, br_ll.x) + half_deg
	var lon_min := minf(tl_ll.y, br_ll.y) - half_deg
	var lon_max := maxf(tl_ll.y, br_ll.y) + half_deg
	splat_bounds = Vector4(lat_min, lat_max, lon_min, lon_max)

	var grid_codes := PackedInt32Array()
	grid_codes.resize(cols * rows)
	grid_codes.fill(32) # Default PLAINS
	var has_tile := PackedByteArray()
	has_tile.resize(cols * rows)
	has_tile.fill(0)

	for t in tiles:
		if not (t is Dictionary):
			continue
		var gx := int(t.get("x", min_x)) - min_x
		var gy := int(t.get("y", min_y)) - min_y
		if gx < 0 or gx >= cols or gy < 0 or gy >= rows:
			continue
		var code := int(TERRAIN_CODE.get(str(t.get("terrain", "PLAINS")), 32))
		if bool(t.get("isBase", false)):
			code = 255
		grid_codes[gy * cols + gx] = code
		has_tile[gy * cols + gx] = 1

	var cell_w := float(TEX_W) / float(cols)
	var cell_h := float(TEX_H) / float(rows)

	for py in range(TEX_H):
		var fy := float(py) / cell_h
		var gy := clampi(int(floor(fy)), 0, rows - 1)
		var ly := (fy - float(gy)) - 0.5
		for px in range(TEX_W):
			var fx := float(px) / cell_w
			var gx := clampi(int(floor(fx)), 0, cols - 1)
			var lx := (fx - float(gx)) - 0.5
			var gidx := gy * cols + gx

			var code := grid_codes[gidx]
			var dist := clampf(sqrt(lx * lx + ly * ly) * 2.0, 0.0, 1.0)
			var center_w := int(clampf((1.0 - dist) * 255.0, 0.0, 255.0))
			var edge_x := minf(float(px), float(TEX_W - 1 - px)) / 3.0
			var edge_y := minf(float(py), float(TEX_H - 1 - py)) / 3.0
			var mask_f := clampf(minf(edge_x, edge_y), 0.0, 1.0) * (1.0 if has_tile[gidx] == 1 else 0.0)

			var b4 := (py * TEX_W + px) * 4
			_buf[b4] = code
			_buf[b4 + 1] = center_w
			_buf[b4 + 2] = int(clampf(mask_f * 255.0, 0.0, 255.0))
			_buf[b4 + 3] = 255

	splat_image.set_data(TEX_W, TEX_H, false, Image.FORMAT_RGBA8, _buf)
	splat_tex.update(splat_image)
