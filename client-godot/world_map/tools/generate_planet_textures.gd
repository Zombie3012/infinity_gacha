extends SceneTree
## Deterministic Fantasy Stylized Equirectangular Planet Generator (Milestone 1).
## Run via:
##   godot --headless --path client-godot --script res://world_map/tools/generate_planet_textures.gd
##
## Evaluates all continent masks & noise directly on the 3D unit sphere
##   p = (cos(lat)*cos(lon), sin(lat), cos(lat)*sin(lon))
## guaranteeing ZERO seam at +/-180 deg meridian and ZERO polar pinch at +/-90 deg.
##
## Outputs:
## - res://world_map/textures/fantasy_planet/{albedo,height,normal}.png (2048x1024)
## - res://world_map/textures/fantasy_planet/{biome,ocean,magic,clouds}.png (1024x512)
## - res://world_map/data/regions/fantasy_world_regions.json (5 continents + 121 regions)
## - res://world_map/resources/fantasy_planet.tres (PlanetData resource)

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")
const PlanetDataScript := preload("res://world_map/core/planet_data.gd")

const OUT_TEX_DIR := "res://world_map/textures/fantasy_planet"
const OUT_REGIONS_PATH := "res://world_map/data/regions/fantasy_world_regions.json"
const OUT_PLANET_RES_PATH := "res://world_map/resources/fantasy_planet.tres"

const HI_W := 2048
const HI_H := 1024
const LO_W := 1024
const LO_H := 512

const SEA_LEVEL := 0.48

# 5 Major Continents + 1 Central Imperial Wonder Sanctuary
# Lobes: [lat_deg, lon_deg, radius_deg, weight, continent_idx]
# continent_idx: 0=Emerald Reach, 1=Crystal Wastes, 2=Frostspire Crown,
#                3=Skyshard Isles, 4=Ashen Rift, 5=Imperial Wonder
const CONTINENT_META := [
	{
		"id": "emerald_reach",
		"name": "Lục Địa Lục Bảo",
		"en_name": "Emerald Reach",
		"primary_biome": "magic_forest",
		"latitude": 19.0,
		"longitude": -11.0,
		"accent_hex": "#34c97a",
		"description": "Lục địa khởi đầu trù phú với đồng bằng xanh thẳm, rừng cổ thụ ma thuật và chiến khu viễn chinh.",
	},
	{
		"id": "crystal_wastes",
		"name": "Sa Mạc Pha Lê",
		"en_name": "Crystal Wastes",
		"primary_biome": "crystal_desert",
		"latitude": -14.0,
		"longitude": 62.0,
		"accent_hex": "#e8a84a",
		"description": "Vùng sa mạc hoàng kim rải rác mỏ pha lê tím phát sáng và các phế tích cổ đại.",
	},
	{
		"id": "frostspire_crown",
		"name": "Vương Quốc Băng Phong",
		"en_name": "Frostspire Crown",
		"primary_biome": "glacial_peaks",
		"latitude": 58.0,
		"longitude": 102.0,
		"accent_hex": "#72d4ff",
		"description": "Đỉnh băng cực bắc vĩnh cửu với các ngọn tháp băng ma thuật và hầm ngục hàn băng.",
	},
	{
		"id": "skyshard_isles",
		"name": "Quần Đảo Lưu Vân",
		"en_name": "Skyshard Isles",
		"primary_biome": "arcane_archipelago",
		"latitude": 14.0,
		"longitude": -120.0,
		"accent_hex": "#3de0d0",
		"description": "Quần đảo ngọc lam nối liền bởi các mạch năng lượng thiên không và đảo đá nổi.",
	},
	{
		"id": "ashen_rift",
		"name": "Vùng Đất Nguyền Rủa",
		"en_name": "Ashen Rift",
		"primary_biome": "cursed_volcanic",
		"latitude": -28.0,
		"longitude": -80.0,
		"accent_hex": "#c946d6",
		"description": "Cao nguyên núi lửa hắc diện thạch bị xé toạc bởi các khe nứt ma năng đỏ tím.",
	},
]

const LAND_LOBES := [
	# 0: Emerald Reach (covers starter Expedition Sector lat 8..30, lon -22..0 solidly)
	[19.0, -11.0, 26.0, 1.05, 0],
	[31.0, 6.0, 20.0, 0.85, 0],
	[8.0, -25.0, 16.0, 0.72, 0],
	[36.0, -18.0, 16.0, 0.75, 0],
	# 1: Crystal Wastes
	[-12.0, 58.0, 27.0, 0.98, 1],
	[-26.0, 84.0, 21.0, 0.85, 1],
	[4.0, 74.0, 16.0, 0.72, 1],
	# 2: Frostspire Crown
	[58.0, 96.0, 24.0, 0.96, 2],
	[63.0, 142.0, 21.0, 0.86, 2],
	[48.0, 122.0, 16.0, 0.72, 2],
	# 3: Skyshard Isles (archipelago)
	[16.0, -116.0, 19.0, 0.90, 3],
	[3.0, -142.0, 16.0, 0.84, 3],
	[28.0, -98.0, 14.0, 0.78, 3],
	[12.0, -162.0, 13.0, 0.74, 3],
	# 4: Ashen Rift
	[-30.0, -82.0, 24.0, 0.98, 4],
	[-16.0, -64.0, 18.0, 0.82, 4],
	[-42.0, -104.0, 16.0, 0.76, 4],
	# 5: Central Imperial Wonder Island (lat 6, lon 32)
	[6.0, 32.0, 8.5, 0.95, 5],
]

const REGION_PREFIXES := {
	"emerald_reach": ["Thảo Nguyên", "Rừng Ngàn Năm", "Thung Lũng", "Cao Nguyên", "Hồ Ngọc", "Đồi Gió", "Cổ Trấn", "Bến Sương"],
	"crystal_wastes": ["Đồi Cát", "Hẻm Pha Lê", "Ốc Đảo", "Bình Nguyên Đá", "Thánh Điện Cát", "Mỏ Tử Tinh", "Vực Hoàng Kim", "Cổng Mặt Trời"],
	"frostspire_crown": ["Đỉnh Tuyết", "Sông Băng", "Rừng Thông Băng", "Pháo Đài Hàn", "Thung Lũng Sương", "Vách Băng", "Hồ Đông Cứng", "Ngọn Tháp Trắng"],
	"skyshard_isles": ["Đảo Lưu Vân", "Vịnh San Hô", "Đá Mây", "Rừng Ngọc Lam", "Cảng Gió", "Quần Đảo Mơ", "Eo Biển Sao", "Đỉnh Thiên Không"],
	"ashen_rift": ["Khe Nứt Tro", "Núi Hắc Diện", "Đầm Lầy Tím", "Vực Dung Nham", "Phế Tích Nguyền", "Cao Nguyên Khói", "Đền Hư Không", "Bờ Đá Đen"],
}

const REGION_SUFFIXES := [
	"Bắc", "Nam", "Đông", "Tây", "Trung Tâm", "Thượng", "Hạ", "Cổ Đại",
	"Ánh Trăng", "Bình Minh", "Hoàng Hôn", "Tinh Tú", "Huyền Bí", "Rực Rỡ",
	"Sâu Thẳm", "Vĩnh Hằng", "Bão Tố", "Lặng Lẽ", "Ngọc Bích", "Thiên Giới",
	"Huyết Nguyệt", "Mây Trắng", "Băng Giá", "Lửa Thiêng",
]

var _noise_cont: FastNoiseLite
var _noise_detail: FastNoiseLite
var _noise_ridge: FastNoiseLite
var _noise_warp_a: FastNoiseLite
var _noise_warp_b: FastNoiseLite
var _noise_magic: FastNoiseLite
var _noise_cloud_a: FastNoiseLite
var _noise_cloud_b: FastNoiseLite

var _lobe_dirs: PackedVector3Array = PackedVector3Array()
var _lobe_rad_rad: PackedFloat32Array = PackedFloat32Array()
var _lobe_weights: PackedFloat32Array = PackedFloat32Array()
var _lobe_cidx: PackedInt32Array = PackedInt32Array()

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("[PlanetGen] Starting deterministic Fantasy Planet texture & region generation...")
	_ensure_dirs()
	_setup_noises_and_lobes()

	# 1. Generate high-res (2048x1024) albedo, height, normal
	var height_f32 := PackedFloat32Array()
	height_f32.resize(HI_W * HI_H)
	var albedo_bytes := PackedByteArray()
	albedo_bytes.resize(HI_W * HI_H * 3)
	var height_bytes := PackedByteArray()
	height_bytes.resize(HI_W * HI_H * 3)

	var lo_biome_bytes := PackedByteArray()
	lo_biome_bytes.resize(LO_W * LO_H * 3)
	var lo_ocean_bytes := PackedByteArray()
	lo_ocean_bytes.resize(LO_W * LO_H * 3)
	var lo_magic_bytes := PackedByteArray()
	lo_magic_bytes.resize(LO_W * LO_H * 3)
	var lo_cloud_bytes := PackedByteArray()
	lo_cloud_bytes.resize(LO_W * LO_H * 4)

	# Precompute trig tables for HI_W x HI_H
	var cos_lon := PackedFloat32Array()
	var sin_lon := PackedFloat32Array()
	cos_lon.resize(HI_W)
	sin_lon.resize(HI_W)
	for x in range(HI_W):
		var u := (float(x) + 0.5) / float(HI_W)
		var lon_rad := (u - 0.5) * TAU
		cos_lon[x] = cos(lon_rad)
		sin_lon[x] = sin(lon_rad)

	var cos_lat := PackedFloat32Array()
	var sin_lat := PackedFloat32Array()
	cos_lat.resize(HI_H)
	sin_lat.resize(HI_H)
	for y in range(HI_H):
		var v := (float(y) + 0.5) / float(HI_H)
		var lat_rad := (0.5 - v) * PI
		cos_lat[y] = cos(lat_rad)
		sin_lat[y] = sin(lat_rad)

	var lobe_count := _lobe_dirs.size()
	var sector_center := PlanetCoordinatesScript.lat_lon_to_unit_sphere_yup(19.0, -11.0)
	var wonder_center := PlanetCoordinatesScript.lat_lon_to_unit_sphere_yup(6.0, 32.0)

	for y in range(HI_H):
		var cl := cos_lat[y]
		var sl := sin_lat[y]
		var abs_lat_norm := absf(sl) # 0 at equator, 1 at poles
		var row_off := y * HI_W
		var is_lo_y := (y & 1) == 0
		var lo_row_off := (y >> 1) * LO_W

		for x in range(HI_W):
			var px := cl * cos_lon[x]
			var py := sl
			var pz := cl * sin_lon[x]

			# 3D Spherical Domain Warping for organic jagged fantasy coastlines, bays & peninsulas
			var w1 := _noise_warp_a.get_noise_3d(px * 2.6, py * 2.6, pz * 2.6)
			var w2 := _noise_warp_b.get_noise_3d(px * 2.6 + 4.3, py * 2.6 - 2.1, pz * 2.6 + 1.7)
			var w3 := _noise_warp_a.get_noise_3d(px * 2.6 - 3.7, py * 2.6 + 5.1, pz * 2.6 - 2.9)
			var warp_amp := 0.24
			var wv := Vector3(px + w1 * warp_amp, py + w2 * warp_amp, pz + w3 * warp_amp).normalized()

			# Evaluate continent influence on warped 3D unit sphere (zero seam / zero pole distortion)
			var cont_val := 0.0
			var dom_cidx := 0
			var best_inf := 0.0
			for li in range(lobe_count):
				var ld := _lobe_dirs[li]
				var dot_v := clampf(wv.x * ld.x + wv.y * ld.y + wv.z * ld.z, -1.0, 1.0)
				var rad := _lobe_rad_rad[li]
				var min_dot := cos(rad * 1.55)
				if dot_v > min_dot:
					var ang := acos(dot_v)
					var norm_d := ang / rad
					if norm_d < 1.45:
						var falloff := clampf(1.0 - norm_d * norm_d * 0.52, 0.0, 1.0)
						var inf := falloff * falloff * _lobe_weights[li]
						cont_val = maxf(cont_val, inf)
						if inf > best_inf:
							best_inf = inf
							dom_cidx = _lobe_cidx[li]

			var n_cont := _noise_cont.get_noise_3d(wv.x * 2.8, wv.y * 2.8, wv.z * 2.8) * 0.5 + 0.5
			var n_det := _noise_detail.get_noise_3d(px * 9.0, py * 9.0, pz * 9.0) * 0.5 + 0.5
			var n_moist := _noise_warp_b.get_noise_3d(px * 5.2, py * 5.2, pz * 5.2) * 0.5 + 0.5
			var n_ridge := 1.0 - absf(_noise_ridge.get_noise_3d(wv.x * 5.6, wv.y * 5.6, wv.z * 5.6))
			n_ridge = pow(clampf(n_ridge, 0.0, 1.0), 2.4)

			# Smooth organic land boost under starter Expedition Sector (no circular seam in normal map!)
			var d_sector := clampf(wv.x * sector_center.x + wv.y * sector_center.y + wv.z * sector_center.z, -1.0, 1.0)
			var sector_mask := smoothstep_f(0.91, 0.985, d_sector)

			# Polar ice shelf contribution (organic noisy polar caps)
			var polar_cap := smoothstep_f(0.87, 0.96, abs_lat_norm + (n_det - 0.5) * 0.10)

			var base_land := cont_val * 0.54 + n_cont * 0.36 + (n_det - 0.5) * 0.16 + sector_mask * 0.14

			var elev := base_land
			if elev > SEA_LEVEL:
				var coast_t := smoothstep_f(SEA_LEVEL, SEA_LEVEL + 0.16, elev)
				# Ridged mountain chains run across inland areas instead of round center blobs
				var ridge_h := n_ridge * coast_t * (0.34 if dom_cidx != 0 else 0.24)
				ridge_h *= (1.0 - sector_mask * 0.55) # Keep starter tactical zone verdant plains/forests/hills
				elev = SEA_LEVEL + (elev - SEA_LEVEL) * 0.62 + ridge_h
			elev = clampf(maxf(elev, polar_cap * 0.60), 0.0, 1.0)

			var idx := row_off + x
			height_f32[idx] = elev
			var h_byte := int(clampf(elev * 255.0, 0.0, 255.0))
			var b3 := idx * 3
			height_bytes[b3] = h_byte
			height_bytes[b3 + 1] = h_byte
			height_bytes[b3 + 2] = h_byte

			var is_ocean := elev < SEA_LEVEL
			var col_r := 0.0
			var col_g := 0.0
			var col_b := 0.0
			var bio_r := 0.5
			var bio_g := 0.5
			var bio_b := 0.5
			var magic_val := 0.0

			if is_ocean:
				var depth := clampf((SEA_LEVEL - elev) / SEA_LEVEL, 0.0, 1.0)
				var shallow := smoothstep_f(0.28, 0.0, depth)
				var foam := smoothstep_f(0.045, 0.0, depth)
				var ocean_var := (n_det - 0.5) * 0.05
				col_r = lerpf(0.03, 0.10, 1.0 - depth) + shallow * 0.12 + foam * 0.18 + ocean_var
				col_g = lerpf(0.11, 0.30, 1.0 - depth) + shallow * 0.36 + foam * 0.24 + ocean_var
				col_b = lerpf(0.26, 0.52, 1.0 - depth) + shallow * 0.26 + foam * 0.18 + ocean_var
				bio_r = 0.08; bio_g = 0.28; bio_b = 0.55
			else:
				var lh := clampf((elev - SEA_LEVEL) / (1.0 - SEA_LEVEL), 0.0, 1.0)
				var beach_t := smoothstep_f(0.07, 0.0, lh)
				var mtn_t := smoothstep_f(0.46, 0.72, lh)
				var snow_t := smoothstep_f(0.72, 0.88, lh)
				if polar_cap > 0.52:
					col_r = lerpf(0.76, 0.94, n_det)
					col_g = lerpf(0.86, 0.97, n_det)
					col_b = lerpf(0.94, 1.00, n_det)
					bio_r = 0.86; bio_g = 0.94; bio_b = 1.0
				elif dom_cidx == 0:
					# Emerald Reach: vibrant emerald forests + sunlit meadow plains + rocky/snowy ridge spines
					var meadow_r := lerpf(0.28, 0.16, n_moist)
					var meadow_g := lerpf(0.56, 0.46, n_moist)
					var meadow_b := lerpf(0.22, 0.22, n_moist)
					var forest_r := lerpf(0.10, 0.16, n_det)
					var forest_g := lerpf(0.35, 0.44, n_det)
					var forest_b := lerpf(0.20, 0.26, n_det)
					var f_mix := smoothstep_f(0.32, 0.68, n_moist + lh * 0.25)
					col_r = lerpf(meadow_r, forest_r, f_mix)
					col_g = lerpf(meadow_g, forest_g, f_mix)
					col_b = lerpf(meadow_b, forest_b, f_mix)
					# Warm sand shore
					col_r = lerpf(col_r, 0.74, beach_t * 0.85)
					col_g = lerpf(col_g, 0.68, beach_t * 0.85)
					col_b = lerpf(col_b, 0.46, beach_t * 0.85)
					# Highland rock & alpine snow peaks only along outer ridge spines (keep starter valley lush emerald green!)
					var valley_mtn := mtn_t * (1.0 - sector_mask * 0.90)
					var valley_snow := snow_t * (1.0 - sector_mask * 0.95)
					col_r = lerpf(col_r, 0.42, valley_mtn)
					col_g = lerpf(col_g, 0.41, valley_mtn)
					col_b = lerpf(col_b, 0.44, valley_mtn)
					col_r = lerpf(col_r, 0.92, valley_snow)
					col_g = lerpf(col_g, 0.94, valley_snow)
					col_b = lerpf(col_b, 0.98, valley_snow)
					bio_r = 0.22; bio_g = 0.82; bio_b = 0.45
				elif dom_cidx == 1:
					# Crystal Wastes: golden desert dunes, crimson canyon mesas, glowing crystal ridges
					col_r = lerpf(0.86, 0.68, n_moist)
					col_g = lerpf(0.68, 0.46, n_moist)
					col_b = lerpf(0.36, 0.28, n_moist)
					var oasis_t := smoothstep_f(0.76, 0.90, n_moist) * (1.0 - mtn_t)
					col_r = lerpf(col_r, 0.28, oasis_t * 0.7)
					col_g = lerpf(col_g, 0.58, oasis_t * 0.7)
					col_b = lerpf(col_b, 0.38, oasis_t * 0.7)
					col_r = lerpf(col_r, 0.62, mtn_t)
					col_g = lerpf(col_g, 0.36, mtn_t)
					col_b = lerpf(col_b, 0.48, mtn_t)
					col_r = lerpf(col_r, 0.80, snow_t)
					col_g = lerpf(col_g, 0.64, snow_t)
					col_b = lerpf(col_b, 0.94, snow_t)
					bio_r = 0.94; bio_g = 0.72; bio_b = 0.32
				elif dom_cidx == 2:
					# Frostspire Crown: pine-slate tundra, icy glaciers, white peaks
					col_r = lerpf(0.46, 0.68, n_det)
					col_g = lerpf(0.58, 0.78, n_det)
					col_b = lerpf(0.68, 0.88, n_det)
					col_r = lerpf(col_r, 0.88, smoothstep_f(0.28, 0.65, lh))
					col_g = lerpf(col_g, 0.94, smoothstep_f(0.28, 0.65, lh))
					col_b = lerpf(col_b, 0.99, smoothstep_f(0.28, 0.65, lh))
					bio_r = 0.65; bio_g = 0.88; bio_b = 1.0
				elif dom_cidx == 3:
					# Skyshard Isles: bright coral sand -> vivid jade jungle -> azure skyshard cliffs
					col_r = lerpf(0.14, 0.24, n_det)
					col_g = lerpf(0.62, 0.48, n_moist)
					col_b = lerpf(0.44, 0.56, n_moist)
					col_r = lerpf(col_r, 0.78, beach_t)
					col_g = lerpf(col_g, 0.76, beach_t)
					col_b = lerpf(col_b, 0.54, beach_t)
					col_r = lerpf(col_r, 0.48, mtn_t)
					col_g = lerpf(col_g, 0.78, mtn_t)
					col_b = lerpf(col_b, 0.88, mtn_t)
					bio_r = 0.26; bio_g = 0.88; bio_b = 0.82
				elif dom_cidx == 4:
					# Ashen Rift: dark obsidian basalt, scorched violet ash, crimson-magenta rift ridges
					col_r = lerpf(0.20, 0.32, n_det)
					col_g = lerpf(0.16, 0.19, n_det)
					col_b = lerpf(0.24, 0.34, n_det)
					col_r = lerpf(col_r, 0.54, mtn_t)
					col_g = lerpf(col_g, 0.18, mtn_t)
					col_b = lerpf(col_b, 0.46, mtn_t)
					col_r = lerpf(col_r, 0.86, snow_t)
					col_g = lerpf(col_g, 0.28, snow_t)
					col_b = lerpf(col_b, 0.54, snow_t)
					bio_r = 0.78; bio_g = 0.28; bio_b = 0.86
				else:
					# Imperial Wonder Sanctuary: gilded marble terraces & radiant central spire
					col_r = lerpf(0.82, 0.98, lh)
					col_g = lerpf(0.70, 0.86, lh)
					col_b = lerpf(0.32, 0.52, lh)
					bio_r = 1.0; bio_g = 0.86; bio_b = 0.38

			albedo_bytes[b3] = int(clampf(col_r * 255.0, 0.0, 255.0))
			albedo_bytes[b3 + 1] = int(clampf(col_g * 255.0, 0.0, 255.0))
			albedo_bytes[b3 + 2] = int(clampf(col_b * 255.0, 0.0, 255.0))

			# Downsample 2x2 directly into 1024x512 biome, ocean, magic, clouds
			if is_lo_y and (x & 1) == 0:
				var lo_idx := lo_row_off + (x >> 1)
				var lo3 := lo_idx * 3
				var lo4 := lo_idx * 4

				lo_biome_bytes[lo3] = int(clampf(bio_r * 255.0, 0.0, 255.0))
				lo_biome_bytes[lo3 + 1] = int(clampf(bio_g * 255.0, 0.0, 255.0))
				lo_biome_bytes[lo3 + 2] = int(clampf(bio_b * 255.0, 0.0, 255.0))

				var ocean_b := 255 if is_ocean else 0
				if not is_ocean and elev < SEA_LEVEL + 0.025:
					ocean_b = int(clampf((1.0 - (elev - SEA_LEVEL) / 0.025) * 140.0, 0.0, 255.0))
				lo_ocean_bytes[lo3] = ocean_b
				lo_ocean_bytes[lo3 + 1] = ocean_b
				lo_ocean_bytes[lo3 + 2] = ocean_b

				# Magic Mask: crisp slender arcane ley-lines (avoid thick milky blotches over starter Emerald plains!)
				var n_mag := 1.0 - absf(_noise_magic.get_noise_3d(px * 6.2, py * 6.2, pz * 6.2))
				var vein := pow(clampf((n_mag - 0.85) / 0.15, 0.0, 1.0), 3.0)
				if not is_ocean:
					if dom_cidx == 4:
						# Ashen Rift: intense cursed crimson-violet fissures
						magic_val = clampf(vein * 1.10 + n_ridge * 0.18, 0.0, 1.0)
					elif dom_cidx == 1:
						# Crystal Wastes: slender amethyst crystal veins
						magic_val = clampf(vein * 0.78, 0.0, 1.0)
					elif dom_cidx == 3:
						# Skyshard Isles: subtle arcane turquoise runes
						magic_val = clampf(vein * 0.62, 0.0, 1.0)
					elif dom_cidx == 0:
						# Emerald Reach: ultra-subtle distant forest ley-lines, suppressed over starter valley
						magic_val = clampf(vein * 0.22 * (1.0 - sector_mask * 0.92), 0.0, 1.0)
					elif dom_cidx == 5:
						# Imperial Wonder Sanctuary: radiant golden core
						var d_w := clampf(px * wonder_center.x + py * wonder_center.y + pz * wonder_center.z, -1.0, 1.0)
						magic_val = clampf(0.45 + (d_w - 0.985) * 40.0, 0.35, 1.0)
					else:
						magic_val = clampf(vein * 0.28, 0.0, 1.0)
				else:
					magic_val = 0.0

				var mag_b := int(clampf(magic_val * 255.0, 0.0, 255.0))
				lo_magic_bytes[lo3] = mag_b
				lo_magic_bytes[lo3 + 1] = mag_b
				lo_magic_bytes[lo3 + 2] = mag_b

				# Stylized swirling 3D spherical cloud layer (RGBA8)
				var warp := _noise_cloud_b.get_noise_3d(px * 2.4, py * 2.4, pz * 2.4) * 0.35
				var c_val := _noise_cloud_a.get_noise_3d(px * 3.0 + warp, py * 3.8, pz * 3.0 - warp) * 0.5 + 0.5
				var c_alpha := smoothstep_f(0.50, 0.78, c_val) * (1.0 - polar_cap * 0.35)
				lo_cloud_bytes[lo4] = 248
				lo_cloud_bytes[lo4 + 1] = 250
				lo_cloud_bytes[lo4 + 2] = 255
				lo_cloud_bytes[lo4 + 3] = int(clampf(c_alpha * 225.0, 0.0, 255.0))

	print("[PlanetGen] Surface & mask synthesis done in %d ms; baking tangent-space normal map..." % (Time.get_ticks_msec() - t0))

	# 2. Bake Tangent-Space Normal Map from 2048x1024 height_f32 (horizontal wrap at +/-180 deg)
	var normal_bytes := PackedByteArray()
	normal_bytes.resize(HI_W * HI_H * 3)
	var strength := 14.0
	for y in range(HI_H):
		var y_up := maxi(0, y - 1)
		var y_dn := mini(HI_H - 1, y + 1)
		var row_c := y * HI_W
		var row_u := y_up * HI_W
		var row_d := y_dn * HI_W
		# Attenuate horizontal derivative softly near poles to prevent pinching artifacts
		var lat_scale := maxf(0.25, cos_lat[y])
		for x in range(HI_W):
			var x_l := (x - 1 + HI_W) % HI_W
			var x_r := (x + 1) % HI_W
			var h_l := height_f32[row_c + x_l]
			var h_r := height_f32[row_c + x_r]
			var h_u := height_f32[row_u + x]
			var h_d := height_f32[row_d + x]

			var dx := (h_r - h_l) * strength * lat_scale
			var dy := (h_d - h_u) * strength
			var n := Vector3(-dx, -dy, 1.0).normalized()
			var b3 := (row_c + x) * 3
			normal_bytes[b3] = int(clampf((n.x * 0.5 + 0.5) * 255.0, 0.0, 255.0))
			normal_bytes[b3 + 1] = int(clampf((n.y * 0.5 + 0.5) * 255.0, 0.0, 255.0))
			normal_bytes[b3 + 2] = int(clampf((n.z * 0.5 + 0.5) * 255.0, 0.0, 255.0))

	# 3. Save all 7 PNG textures
	_save_rgb_image(HI_W, HI_H, albedo_bytes, OUT_TEX_DIR + "/albedo.png")
	_save_rgb_image(HI_W, HI_H, height_bytes, OUT_TEX_DIR + "/height.png")
	_save_rgb_image(HI_W, HI_H, normal_bytes, OUT_TEX_DIR + "/normal.png")
	_save_rgb_image(LO_W, LO_H, lo_biome_bytes, OUT_TEX_DIR + "/biome.png")
	_save_rgb_image(LO_W, LO_H, lo_ocean_bytes, OUT_TEX_DIR + "/ocean.png")
	_save_rgb_image(LO_W, LO_H, lo_magic_bytes, OUT_TEX_DIR + "/magic.png")
	_save_rgba_image(LO_W, LO_H, lo_cloud_bytes, OUT_TEX_DIR + "/clouds.png")

	# 4. Generate 5 Continents + 121 land-verified Regions JSON
	_generate_regions_json(height_f32)

	# 5. Save PlanetData Resource (.tres)
	_save_planet_resource()

	print("[PlanetGen] ALL DONE in %d ms!" % (Time.get_ticks_msec() - t0))
	quit(0)

func _ensure_dirs() -> void:
	for rel in [
		OUT_TEX_DIR,
		"res://world_map/data/regions",
		"res://world_map/resources",
	]:
		var abs_dir := ProjectSettings.globalize_path(rel)
		DirAccess.make_dir_recursive_absolute(abs_dir)

func _setup_noises_and_lobes() -> void:
	_noise_cont = FastNoiseLite.new()
	_noise_cont.seed = 20261124
	_noise_cont.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_cont.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_cont.fractal_octaves = 4
	_noise_cont.frequency = 0.65

	_noise_detail = FastNoiseLite.new()
	_noise_detail.seed = 77193
	_noise_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_detail.fractal_octaves = 3
	_noise_detail.frequency = 0.85

	_noise_ridge = FastNoiseLite.new()
	_noise_ridge.seed = 99421
	_noise_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_ridge.fractal_octaves = 3
	_noise_ridge.frequency = 0.72

	_noise_warp_a = FastNoiseLite.new()
	_noise_warp_a.seed = 41827
	_noise_warp_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_warp_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_warp_a.fractal_octaves = 4
	_noise_warp_a.frequency = 0.82

	_noise_warp_b = FastNoiseLite.new()
	_noise_warp_b.seed = 83911
	_noise_warp_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_warp_b.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_warp_b.fractal_octaves = 3
	_noise_warp_b.frequency = 0.76

	_noise_magic = FastNoiseLite.new()
	_noise_magic.seed = 51507
	_noise_magic.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_magic.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_magic.fractal_octaves = 2
	_noise_magic.frequency = 0.9

	_noise_cloud_a = FastNoiseLite.new()
	_noise_cloud_a.seed = 314159
	_noise_cloud_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_cloud_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_cloud_a.fractal_octaves = 4
	_noise_cloud_a.frequency = 0.78

	_noise_cloud_b = FastNoiseLite.new()
	_noise_cloud_b.seed = 271828
	_noise_cloud_b.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_cloud_b.fractal_octaves = 2
	_noise_cloud_b.frequency = 0.55

	for lobe in LAND_LOBES:
		_lobe_dirs.append(PlanetCoordinatesScript.lat_lon_to_unit_sphere_yup(float(lobe[0]), float(lobe[1])))
		_lobe_rad_rad.append(deg_to_rad(float(lobe[2])))
		_lobe_weights.append(float(lobe[3]))
		_lobe_cidx.append(int(lobe[4]))

static func smoothstep_f(edge0: float, edge1: float, x: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 1.0 if x >= edge1 else 0.0
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _save_rgb_image(w: int, h: int, bytes: PackedByteArray, res_path: String) -> void:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes)
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	assert(err == OK, "Failed to save PNG: %s (err=%d)" % [res_path, err])

func _save_rgba_image(w: int, h: int, bytes: PackedByteArray, res_path: String) -> void:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	assert(err == OK, "Failed to save RGBA PNG: %s (err=%d)" % [res_path, err])

func _sample_height(height_f32: PackedFloat32Array, lat_deg: float, lon_deg: float) -> float:
	var uv := PlanetCoordinatesScript.lat_lon_to_uv(lat_deg, lon_deg)
	var x := clampi(int(round(uv.x * float(HI_W - 1))), 0, HI_W - 1)
	var y := clampi(int(round(uv.y * float(HI_H - 1))), 0, HI_H - 1)
	return height_f32[y * HI_W + x]

func _generate_regions_json(height_f32: PackedFloat32Array) -> void:
	var regions: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261124

	# 24 regions per continent = 120 continent regions + 1 Imperial Wonder = 121 regions total
	var region_seq := 1
	for ci in range(CONTINENT_META.size()):
		var cmeta: Dictionary = CONTINENT_META[ci]
		var cid: String = cmeta["id"]
		var clat: float = float(cmeta["latitude"])
		var clon: float = float(cmeta["longitude"])
		var prefixes: Array = REGION_PREFIXES[cid]
		var placed := 0
		var attempts := 0

		# Guarantee first region of Emerald Reach is the active Expedition Frontier Sector
		if cid == "emerald_reach":
			var elev0 := _sample_height(height_f32, 19.0, -11.0)
			regions.append({
				"id": "region_%03d" % region_seq,
				"continent_id": cid,
				"name": "Chiến Khu Khởi Đầu (Lục Bảo)",
				"biome": "magic_forest",
				"latitude": 19.0,
				"longitude": -11.0,
				"elevation": int(round(elev0 * 2400.0)),
				"tier": 1,
				"is_expedition_sector": true,
				"explored": true,
			})
			region_seq += 1
			placed += 1

		while placed < 24 and attempts < 800:
			attempts += 1
			var angle := rng.randf_range(0.0, TAU)
			var dist_deg := sqrt(rng.randf()) * 26.0
			var lat := clampf(clat + sin(angle) * dist_deg * 0.85, -76.0, 76.0)
			var lon := PlanetCoordinatesScript.normalize_lon(clon + cos(angle) * dist_deg * 1.15)
			var elev := _sample_height(height_f32, lat, lon)
			if elev < SEA_LEVEL + 0.02:
				continue

			# Keep minimum spacing of 3.2 deg between regions on same continent
			var too_close := false
			for prev in regions:
				if str(prev.get("continent_id", "")) != cid:
					continue
				if PlanetCoordinatesScript.great_circle_distance_deg(lat, lon, float(prev["latitude"]), float(prev["longitude"])) < 3.2:
					too_close = true
					break
			if too_close:
				continue

			var pname: String = prefixes[placed % prefixes.size()]
			var sname: String = REGION_SUFFIXES[(placed + ci * 5) % REGION_SUFFIXES.size()]
			regions.append({
				"id": "region_%03d" % region_seq,
				"continent_id": cid,
				"name": "%s %s" % [pname, sname],
				"biome": cmeta["primary_biome"],
				"latitude": snappedf(lat, 0.01),
				"longitude": snappedf(lon, 0.01),
				"elevation": int(round(elev * 2400.0)),
				"tier": 1 + (placed % 5),
				"is_expedition_sector": false,
				"explored": (cid == "emerald_reach" and placed < 5),
			})
			region_seq += 1
			placed += 1

	# Add the iconic Central Imperial Wonder Sanctuary region
	var w_elev := _sample_height(height_f32, 6.0, 32.0)
	regions.append({
		"id": "region_wonder_imperial",
		"continent_id": "emerald_reach",
		"name": "Thánh Địa Kỳ Quan Hoàng Đế",
		"biome": "imperial_wonder",
		"latitude": 6.0,
		"longitude": 32.0,
		"elevation": int(round(w_elev * 2600.0)),
		"tier": 5,
		"is_wonder": true,
		"explored": true,
	})

	var payload := {
		"planet_id": "aethelgard_01",
		"planet_name": "Aethelgard — Hành Tinh Viễn Chinh",
		"sea_level": SEA_LEVEL,
		"continents": CONTINENT_META,
		"regions": regions,
	}
	var json_str := JSON.stringify(payload, "  ")
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_REGIONS_PATH), FileAccess.WRITE)
	assert(f != null, "Failed to write regions JSON")
	f.store_string(json_str)
	f.close()
	print("[PlanetGen] Exported %d continents and %d land-verified regions." % [CONTINENT_META.size(), regions.size()])

func _save_planet_resource() -> void:
	var data := PlanetDataScript.new()
	data.planet_id = "aethelgard_01"
	data.planet_name = "Aethelgard — Hành Tinh Viễn Chinh"
	data.planet_radius = 10.0
	var err := ResourceSaver.save(data, OUT_PLANET_RES_PATH)
	assert(err == OK, "Failed to save fantasy_planet.tres (err=%d)" % err)
	print("[PlanetGen] Saved %s" % OUT_PLANET_RES_PATH)
