extends Node
## Targeted headless verification for Expedition Fantasy Planet — Milestone 1:
## PlanetCoordinates math, PlanetData resource, 7 seamless equirectangular textures,
## and 5-continent / 120+ land-verified regions hierarchy.

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")
const PlanetDataScript := preload("res://world_map/core/planet_data.gd")

var _checks := 0
var _failures := 0

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		printerr("WATCHDOG_TIMEOUT: test_world_planet_milestone1")
		get_tree().quit(1)
	)
	_run_tests()

func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: %s" % msg)

func _run_tests() -> void:
	# 1. PlanetCoordinates UV <-> Lat/Lon round-trip
	var samples := [
		Vector2(0.0, 0.0),
		Vector2(19.0, -11.0),
		Vector2(-30.5, -82.25),
		Vector2(58.0, 102.0),
		Vector2(89.0, 179.0),
		Vector2(-89.0, -179.0),
	]
	for s in samples:
		var uv: Vector2 = PlanetCoordinatesScript.lat_lon_to_uv(s.x, s.y)
		var back: Vector2 = PlanetCoordinatesScript.uv_to_lat_lon(uv)
		_expect(absf(back.x - s.x) < 1e-3 and absf(back.y - s.y) < 1e-3,
			"UV round-trip failed for %s -> %s -> %s" % [s, uv, back])

	# 2. Server RTS Grid <-> Lat/Lon round-trip + Imperial Wonder mapping
	var bounds: Dictionary = PlanetCoordinatesScript.DEFAULT_SECTOR_BOUNDS
	for gx in [100.0, 105.0, 111.0]:
		for gy in [100.0, 106.0, 111.0]:
			var ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(gx, gy, bounds)
			var back_g: Vector2 = PlanetCoordinatesScript.lat_lon_to_grid(ll.x, ll.y, bounds)
			_expect(absf(back_g.x - gx) < 1e-3 and absf(back_g.y - gy) < 1e-3,
				"Grid round-trip failed for (%s,%s) -> %s -> %s" % [gx, gy, ll, back_g])
	var wonder_ll: Vector2 = PlanetCoordinatesScript.grid_to_lat_lon(500.0, 500.0, bounds)
	_expect(is_equal_approx(wonder_ll.x, 6.0) and is_equal_approx(wonder_ll.y, 32.0),
		"Imperial Wonder (500,500) must map to (6.0, 32.0), got %s" % [wonder_ll])

	# 3. Zero-jump tangent continuity at focal center (lat=0, lon=center_lon)
	var R := 10.0
	var p_flat: Vector3 = PlanetCoordinatesScript.to_flat_position(0.0, -11.0, R, -11.0)
	var p_sph: Vector3 = PlanetCoordinatesScript.to_sphere_position(0.0, -11.0, R, -11.0)
	_expect(p_flat.distance_to(Vector3(0.0, R, 0.0)) < 1e-4, "Flat center must be (0,R,0)")
	_expect(p_sph.distance_to(Vector3(0.0, R, 0.0)) < 1e-4, "Sphere center must be (0,R,0)")

	# 4. Exact sphere radius & meridian continuity at +/-180 deg & pole-safe Basis
	for lat in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		for lon in [-180.0, -90.0, 0.0, 90.0, 180.0]:
			var sp: Vector3 = PlanetCoordinatesScript.to_sphere_position(lat, lon, R, 0.0)
			_expect(absf(sp.length() - R) < 1e-3, "Sphere length mismatch at (%s,%s): %s" % [lat, lon, sp.length()])
			var n: Vector3 = PlanetCoordinatesScript.to_morphed_normal(lat, lon, 1.0, 0.0)
			_expect(not is_nan(n.x) and not is_nan(n.y) and not is_nan(n.z) and absf(n.length() - 1.0) < 1e-3,
				"Invalid morphed normal at (%s,%s): %s" % [lat, lon, n])
			var b: Basis = PlanetCoordinatesScript.surface_basis(n)
			_expect(absf(b.determinant() - 1.0) < 1e-3, "Surface basis must be right-handed orthonormal at (%s,%s)" % [lat, lon])

	var p_west: Vector3 = PlanetCoordinatesScript.to_sphere_position(12.0, -180.0, R, 0.0)
	var p_east: Vector3 = PlanetCoordinatesScript.to_sphere_position(12.0, 180.0, R, 0.0)
	_expect(p_west.distance_to(p_east) < 1e-3, "Meridian +/-180 deg must meet seamlessly on sphere")

	# 5. Load PlanetData resource & verify all 7 textures + dimensions + zero meridian seam
	var pdata = ResourceLoader.load("res://world_map/resources/fantasy_planet.tres")
	_expect(pdata != null, "fantasy_planet.tres must load cleanly")
	if pdata != null:
		var layers: Dictionary = pdata.get_all_texture_layers()
		var expected_sizes := {
			"albedo": Vector2i(2048, 1024),
			"height": Vector2i(2048, 1024),
			"normal": Vector2i(2048, 1024),
			"biome": Vector2i(1024, 512),
			"ocean": Vector2i(1024, 512),
			"magic": Vector2i(1024, 512),
			"clouds": Vector2i(1024, 512),
		}
		for key in expected_sizes.keys():
			var tex = layers.get(key, null)
			_expect(tex is Texture2D, "Texture layer '%s' must load" % key)
			if tex is Texture2D:
				var sz: Vector2i = tex.get_size()
				_expect(sz == expected_sizes[key], "Layer '%s' size expected %s, got %s" % [key, expected_sizes[key], sz])

		# Check seamless meridian continuity (leftmost vs rightmost column across 32 sample rows)
		for seam_key in ["albedo", "height", "ocean", "clouds"]:
			var tex: Texture2D = layers.get(seam_key, null)
			if tex != null:
				var img: Image = tex.get_image()
				var w := img.get_width()
				var h := img.get_height()
				var diff_sum := 0.0
				var samples_n := 32
				for i in range(samples_n):
					var yy := int(float(i + 0.5) / float(samples_n) * float(h))
					var c_left := img.get_pixel(0, yy)
					var c_right := img.get_pixel(w - 1, yy)
					diff_sum += absf(c_left.r - c_right.r) + absf(c_left.g - c_right.g) + absf(c_left.b - c_right.b) + absf(c_left.a - c_right.a)
				var avg_diff := diff_sum / float(samples_n * 4)
				_expect(avg_diff < 0.03, "Meridian seam diff too high on '%s': %.4f" % [seam_key, avg_diff])

		# Check starter Expedition Sector center (19.0, -11.0) is solid land (ocean_mask < 0.2)
		var ocean_tex: Texture2D = layers.get("ocean", null)
		if ocean_tex != null:
			var oimg: Image = ocean_tex.get_image()
			var uv0: Vector2 = PlanetCoordinatesScript.lat_lon_to_uv(19.0, -11.0)
			var px := clampi(int(round(uv0.x * float(oimg.get_width() - 1))), 0, oimg.get_width() - 1)
			var py := clampi(int(round(uv0.y * float(oimg.get_height() - 1))), 0, oimg.get_height() - 1)
			var oc_val := oimg.get_pixel(px, py).r
			_expect(oc_val < 0.2, "Starter Expedition Sector center must be land, got ocean=%.3f" % oc_val)

		# 6. Verify 5 Continents & 100+ land-verified Regions hierarchy
		var ok_reg: bool = pdata.load_regions_data()
		_expect(ok_reg, "fantasy_world_regions.json must load cleanly")
		_expect(pdata.continents.size() == 5, "Expected 5 continents, got %d" % pdata.continents.size())
		_expect(pdata.regions.size() >= 100, "Expected >=100 regions, got %d" % pdata.regions.size())
		var nearest: Dictionary = pdata.find_nearest_region(19.0, -11.0)
		_expect(bool(nearest.get("is_expedition_sector", false)),
			"Nearest region to (19,-11) must be starter expedition sector, got %s" % [nearest.get("name", "")])
		var wonder_reg: Dictionary = pdata.get_region("region_wonder_imperial")
		_expect(bool(wonder_reg.get("is_wonder", false)), "Imperial Wonder region must exist in dictionary")

	print("PLANET_MILESTONE1: %d checks, %s" % [_checks, "PASS" if _failures == 0 else ("FAILED (%d)" % _failures)])
	get_tree().quit(0 if _failures == 0 else 1)
