extends SceneTree
## Generates 100% seamlessly tileable 512x512 Ground Detail Albedo & Tangent-Space Normal Maps
## for crisp tactical ground rendering (grass blades, soil grain, pebbles, micro-relief).
## Run via:
##   godot --headless --path client-godot --script res://world_map/tools/generate_ground_detail_textures.gd

const OUT_DIR := "res://world_map/textures/fantasy_planet"
const TEX_SIZE := 512

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var h_buf := PackedFloat32Array()
	h_buf.resize(TEX_SIZE * TEX_SIZE)
	var albedo_bytes := PackedByteArray()
	albedo_bytes.resize(TEX_SIZE * TEX_SIZE * 3)

	for y in range(TEX_SIZE):
		var v := float(y) / float(TEX_SIZE)
		var row := y * TEX_SIZE
		for x in range(TEX_SIZE):
			var u := float(x) / float(TEX_SIZE)
			# Periodic multi-octave stylized grass/earth/pebble texture (mathematically 100% tileable!)
			var n1 := _pnoise(u, v, 8, 101)
			var n2 := _pnoise(u, v, 16, 211)
			var n3 := _pnoise(u, v, 32, 307)
			var n4 := _pnoise(u, v, 64, 409)
			var n5 := _pnoise(u, v, 128, 521)
			# Subtle directional grass-blade micro-streaks
			var blades := _pnoise_aniso(u, v, 96, 32, 733)

			var h := n1 * 0.28 + n2 * 0.22 + n3 * 0.20 + n4 * 0.14 + n5 * 0.08 + blades * 0.08
			h_buf[row + x] = h

			# Neutral-centered high-contrast micro-albedo around 0.50 (multiplied over biome base in shader)
			var val := clampf(0.32 + h * 0.36 + (blades - 0.5) * 0.14, 0.12, 0.92)
			var warm := (n2 - 0.5) * 0.06
			var b3 := (row + x) * 3
			albedo_bytes[b3] = int(clampf((val + warm) * 255.0, 0.0, 255.0))
			albedo_bytes[b3 + 1] = int(clampf((val + 0.02) * 255.0, 0.0, 255.0))
			albedo_bytes[b3 + 2] = int(clampf((val - warm * 0.8) * 255.0, 0.0, 255.0))

	# Bake crisp tangent-space normal map with full periodic wrapping
	var normal_bytes := PackedByteArray()
	normal_bytes.resize(TEX_SIZE * TEX_SIZE * 3)
	var strength := 4.8
	for y in range(TEX_SIZE):
		var yu := (y - 1 + TEX_SIZE) % TEX_SIZE
		var yd := (y + 1) % TEX_SIZE
		var rc := y * TEX_SIZE
		var ru := yu * TEX_SIZE
		var rd := yd * TEX_SIZE
		for x in range(TEX_SIZE):
			var xl := (x - 1 + TEX_SIZE) % TEX_SIZE
			var xr := (x + 1) % TEX_SIZE
			var dx := (h_buf[rc + xr] - h_buf[rc + xl]) * strength
			var dy := (h_buf[rd + x] - h_buf[ru + x]) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			var b3 := (rc + x) * 3
			normal_bytes[b3] = int(clampf((n.x * 0.5 + 0.5) * 255.0, 0.0, 255.0))
			normal_bytes[b3 + 1] = int(clampf((n.y * 0.5 + 0.5) * 255.0, 0.0, 255.0))
			normal_bytes[b3 + 2] = int(clampf((n.z * 0.5 + 0.5) * 255.0, 0.0, 255.0))

	var img_a := Image.create_from_data(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8, albedo_bytes)
	var err_a := img_a.save_png(ProjectSettings.globalize_path(OUT_DIR + "/ground_detail_albedo.png"))
	assert(err_a == OK, "Failed to save ground_detail_albedo.png")

	var img_n := Image.create_from_data(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGB8, normal_bytes)
	var err_n := img_n.save_png(ProjectSettings.globalize_path(OUT_DIR + "/ground_detail_normal.png"))
	assert(err_n == OK, "Failed to save ground_detail_normal.png")

	print("[GroundDetailGen] Saved 512x512 seamless ground detail textures in %d ms!" % (Time.get_ticks_msec() - t0))
	quit(0)

static func _hash_int(ix: int, iy: int, seed_v: int) -> float:
	var n := (ix * 374761393 + iy * 668265263 + seed_v * 1442695041) & 0x7fffffff
	n = (n ^ (n >> 13)) * 1274126177
	n = (n ^ (n >> 16)) & 0x7fffffff
	return float(n) / 2147483647.0

static func _pnoise(u: float, v: float, period: int, seed_v: int) -> float:
	return _pnoise_aniso(u, v, period, period, seed_v)

static func _pnoise_aniso(u: float, v: float, px: int, py: int, seed_v: int) -> float:
	var fx := u * float(px)
	var fy := v * float(py)
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var x0 := ((ix % px) + px) % px
	var x1 := (x0 + 1) % px
	var y0 := ((iy % py) + py) % py
	var y1 := (y0 + 1) % py
	var a := _hash_int(x0, y0, seed_v)
	var b := _hash_int(x1, y0, seed_v)
	var c := _hash_int(x0, y1, seed_v)
	var d := _hash_int(x1, y1, seed_v)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
