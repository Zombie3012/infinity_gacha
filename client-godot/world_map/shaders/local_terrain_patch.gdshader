shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Floating-Origin Local Terrain Clipmap Shader (Ground Clarity Upgrade).
// Uses tile-unit coordinates (tile_uv = deg / 0.06) + 512x512 seamless ground detail albedo/normal
// + server Terrain Splatting (PLAINS/FOREST/HILLS/MOUNTAIN/MARSH/RUINS/BASE)
// + high-frequency sculpted Fantasy Fog Clouds with ground shadow rim (ZERO blurry haze on revealed ground!).

uniform float planet_radius = 10.0;
uniform float focus_lat_rad = 0.3316;
uniform float focus_lon_rad = -0.1920;
uniform float patch_half_x = 1.0;
uniform float patch_half_z = 1.0;
uniform float patch_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float detail_strength : hint_range(0.0, 1.0) = 1.0;
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.88;
uniform float tile_deg_size = 0.06;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D biome_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ocean_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D magic_mask : filter_linear_mipmap, repeat_enable;

uniform sampler2D ground_detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_detail_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D terrain_splat_map : filter_nearest, repeat_disable;
uniform vec4 terrain_splat_bounds = vec4(18.64, 19.36, -11.36, -10.64);
uniform float use_terrain_splat : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D local_fog_mask : filter_linear, repeat_disable;
uniform sampler2D global_fog_mask : filter_linear, repeat_enable;
uniform vec4 local_fog_bounds = vec4(16.67, 21.33, -13.33, -8.67);

varying vec2 v_deg_coord; // (lon_deg, lat_deg)
varying vec2 v_global_uv;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm4(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p = rot * p * 2.05 + vec2(17.3, 9.2);
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	float wx = VERTEX.x * patch_half_x;
	float wz_rel = VERTEX.z * patch_half_z;

	float lat_rad = clamp(focus_lat_rad - (wz_rel / planet_radius), -1.565, 1.565);
	float lon_rad = focus_lon_rad + (wx / planet_radius);

	vec2 guv = vec2(lon_rad / 6.28318530718 + 0.5, clamp(0.5 - lat_rad / 3.14159265359, 0.001, 0.999));
	v_global_uv = guv;
	v_deg_coord = vec2(lon_rad * 57.295779513, lat_rad * 57.295779513);

	// Keep ground plane strictly flush at y=0 in tactical mode so 3D Castle/Forest/Mountain props sit solidly with zero sink!
	float h = textureLod(height_map, guv, 0.0).r;
	float relief = max(0.0, h - 0.48) * 0.14 * (1.0 - detail_strength);

	VERTEX = vec3(wx, relief, wz_rel);
	NORMAL = vec3(0.0, 1.0, 0.0);
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 guv = v_global_uv;
	vec2 deg = v_deg_coord;
	// Tile-unit UV: 1.0 = exactly 1 tactical tile (0.06 deg) -> razor-sharp detail at every zoom!
	vec2 tile_uv = deg / max(0.005, tile_deg_size);

	vec2 texel = vec2(1.0 / 2048.0, 1.0 / 1024.0) * 1.4;
	vec3 macro_albedo = (
		texture(albedo_map, guv).rgb * 0.40 +
		texture(albedo_map, guv + vec2(texel.x, 0.0)).rgb * 0.15 +
		texture(albedo_map, guv - vec2(texel.x, 0.0)).rgb * 0.15 +
		texture(albedo_map, guv + vec2(0.0, texel.y)).rgb * 0.15 +
		texture(albedo_map, guv - vec2(0.0, texel.y)).rgb * 0.15
	);
	float macro_ocean = texture(ocean_mask, guv).r;
	vec3 biome_tex = texture(biome_map, guv).rgb;
	float magic = texture(magic_mask, guv).r;

	// Crisp 512x512 seamless ground detail texture (2 scales to eliminate any visual repetition!)
	vec2 d_uv_fine = tile_uv * 2.35;
	vec2 d_uv_mid = tile_uv * 0.68 + vec2(0.37, 0.71);
	vec3 det_fine = texture(ground_detail_albedo, d_uv_fine).rgb;
	vec3 det_mid = texture(ground_detail_albedo, d_uv_mid).rgb;
	vec3 det_albedo = mix(det_mid, det_fine, 0.62);
	// Contrast centered around 1.0 (0.68..1.32) for crisp grass blades, earth specks & stone grain
	vec3 det_mult = mix(vec3(1.0), 0.62 + det_albedo * 0.78, detail_strength);

	vec3 n_fine = texture(ground_detail_normal, d_uv_fine).rgb;
	vec3 n_mid = texture(ground_detail_normal, d_uv_mid).rgb;
	vec3 ground_n_map = mix(n_mid, n_fine, 0.65);

	// Natural meadow/woodland breakup in tile space (no blurry 100px blobs!)
	float patch_var = fbm4(tile_uv * 0.48 + vec2(3.2, -5.7));
	float micro_speck = vnoise(tile_uv * 5.5);

	// Fractal coastline sharpening
	float coast_perturb = (fbm4(deg * 4.5) - 0.5) * 0.22;
	float is_water = smoothstep(0.44, 0.56, macro_ocean + coast_perturb * detail_strength);
	float shoreline = smoothstep(0.34, 0.50, macro_ocean + coast_perturb * detail_strength) * (1.0 - is_water);

	// Vibrant base temperate emerald land (replaces washed-out blurry macro tint)
	float valley_lush = smoothstep(0.32, 0.72, biome_tex.g - biome_tex.r * 0.35);
	vec3 meadow_a = vec3(0.24, 0.52, 0.19);
	vec3 meadow_b = vec3(0.16, 0.41, 0.17);
	vec3 land_col = mix(macro_albedo, mix(meadow_b, meadow_a, smoothstep(0.28, 0.74, patch_var)), valley_lush * 0.78 * detail_strength);
	land_col = mix(land_col, vec3(0.76, 0.68, 0.44), shoreline * 0.80 * detail_strength);

	// Per-Tile Server Terrain Splatting (PLAINS / FOREST / HILLS / MOUNTAIN / MARSH / RUINS / BASE)
	float surf_rough = 0.90;
	float surf_spec = 0.16;
	float n_depth = 1.15 * detail_strength;

	if (use_terrain_splat > 0.01 && detail_strength > 0.15) {
		vec2 s_uv = vec2(
			(deg.x - terrain_splat_bounds.z) / max(1e-4, terrain_splat_bounds.w - terrain_splat_bounds.z),
			(terrain_splat_bounds.y - deg.y) / max(1e-4, terrain_splat_bounds.y - terrain_splat_bounds.x)
		);
		if (s_uv.x > 0.0 && s_uv.x < 1.0 && s_uv.y > 0.0 && s_uv.y < 1.0) {
			// Organic edge jitter (1/12 of a tile) so tile terrain transitions look natural instead of hard squares!
			vec2 jitter = (vec2(fbm4(tile_uv * 2.2), fbm4(tile_uv * 2.2 + vec2(9.1, 4.3))) - 0.5) * 0.014;
			vec4 sp = texture(terrain_splat_map, clamp(s_uv + jitter, vec2(0.002), vec2(0.998)));
			float code = sp.r;
			float center_w = sp.g;
			float cov = sp.b * detail_strength;

			vec3 tile_col = land_col;
			if (code > 0.95) {
				// BASE: Warm sunlit royal stone courtyard with cobblestone paving
				float stone_grid = step(0.08, fract(tile_uv.x * 6.0)) * step(0.08, fract(tile_uv.y * 6.0));
				vec3 cobble = mix(vec3(0.46, 0.44, 0.42), vec3(0.68, 0.64, 0.56), stone_grid * 0.7 + micro_speck * 0.3);
				tile_col = mix(vec3(0.26, 0.52, 0.22), cobble, smoothstep(0.18, 0.62, center_w));
				surf_rough = 0.78;
				n_depth = 1.35 * detail_strength;
			} else if (code > 0.83) {
				// RUINS: Ancient mossy lavender-slate flagstones + cracked stonework
				vec3 ruin_stone = mix(vec3(0.36, 0.33, 0.42), vec3(0.54, 0.50, 0.60), micro_speck);
				tile_col = mix(vec3(0.20, 0.36, 0.22), ruin_stone, smoothstep(0.15, 0.65, center_w + patch_var * 0.25));
				n_depth = 1.45 * detail_strength;
			} else if (code > 0.68) {
				// MARSH: Deep glistening teal bog water + mossy reed banks
				float bog_pool = smoothstep(0.24, 0.68, center_w + (patch_var - 0.5) * 0.35);
				float ripple = vnoise(tile_uv * 10.0 + vec2(TIME * 0.5, -TIME * 0.35));
				vec3 bog_water = mix(vec3(0.08, 0.28, 0.30), vec3(0.16, 0.44, 0.44), ripple);
				tile_col = mix(vec3(0.16, 0.34, 0.22), bog_water, bog_pool);
				surf_rough = mix(0.88, 0.22, bog_pool);
				surf_spec = mix(0.16, 0.68, bog_pool);
			} else if (code > 0.52) {
				// MOUNTAIN: Crisp dark granite scree + alpine ridge rock
				vec3 granite = mix(vec3(0.26, 0.28, 0.34), vec3(0.46, 0.48, 0.54), smoothstep(0.25, 0.75, det_fine.r));
				tile_col = mix(vec3(0.24, 0.36, 0.24), granite, smoothstep(0.12, 0.58, center_w + 0.18));
				n_depth = 1.65 * detail_strength;
			} else if (code > 0.36) {
				// HILLS: Warm sunlit olive-gold highland meadows + rocky earth shelves
				vec3 hill_grass = mix(vec3(0.36, 0.50, 0.21), vec3(0.54, 0.48, 0.28), smoothstep(0.35, 0.78, patch_var));
				tile_col = hill_grass;
				n_depth = 1.30 * detail_strength;
			} else if (code > 0.20) {
				// FOREST: Rich deep mossy woodland floor + dappled sunlight
				tile_col = mix(vec3(0.09, 0.28, 0.14), vec3(0.16, 0.39, 0.18), patch_var * 0.7 + micro_speck * 0.3);
			} else if (code > 0.08) {
				// PLAINS: Bright sunlit emerald grass + subtle golden meadow tufts
				tile_col = mix(vec3(0.22, 0.52, 0.20), vec3(0.36, 0.62, 0.24), smoothstep(0.32, 0.76, patch_var));
			} else {
				// OCEAN: Deep glistening fantasy sapphire sea water (no grass!)
				is_water = max(is_water, cov);
				tile_col = mix(vec3(0.05, 0.20, 0.42), vec3(0.08, 0.32, 0.56), smoothstep(0.25, 0.75, patch_var));
			}

			land_col = mix(land_col, tile_col, cov);
		}
	}

	// Apply crisp 512x512 grass/soil/stone grain contrast!
	land_col *= det_mult;

	// Ocean ripples & sparkling coastal surf
	float wave_a = vnoise(tile_uv * 2.8 + vec2(TIME * 0.42, -TIME * 0.28));
	float wave_b = vnoise(tile_uv * 6.5 + vec2(-TIME * 0.34, TIME * 0.48));
	vec3 water_col = macro_albedo + vec3(0.05, 0.10, 0.14) * ((wave_a + wave_b) - 1.0) * detail_strength;
	vec3 surface_col = mix(land_col, water_col, is_water);

	// Subtle crisp arcane magic veins
	float magic_pulse = 0.85 + 0.15 * sin(TIME * 2.2 + deg.x * 2.0);
	vec3 magic_glow = mix(vec3(0.58, 0.34, 1.0), biome_tex, 0.45) * magic * 0.72 * magic_pulse;

	// Unified Dual-Resolution Fog Mask (ZERO vertical seam!)
	float g_rev = texture(global_fog_mask, guv).r;
	float reveal = g_rev;
	vec2 l_uv = vec2(
		(deg.x - local_fog_bounds.z) / max(1e-4, local_fog_bounds.w - local_fog_bounds.z),
		(local_fog_bounds.y - deg.y) / max(1e-4, local_fog_bounds.y - local_fog_bounds.x)
	);
	if (l_uv.x > 0.0 && l_uv.x < 1.0 && l_uv.y > 0.0 && l_uv.y < 1.0) {
		float l_rev = texture(local_fog_mask, l_uv).r;
		float edge_fade = smoothstep(0.0, 0.14, l_uv.x) * smoothstep(1.0, 0.86, l_uv.x)
			* smoothstep(0.0, 0.14, l_uv.y) * smoothstep(1.0, 0.86, l_uv.y);
		reveal = mix(g_rev, l_rev, edge_fade);
	}

	// HIGH-FREQUENCY Sculpted Cumulus Fog Clouds in tile_uv space (12x sharper than deg space!)
	vec2 cloud_drift = vec2(TIME * 0.08, TIME * 0.035);
	float c_base = fbm4(tile_uv * 0.42 + cloud_drift);
	float c_billow = fbm4(tile_uv * 1.15 - cloud_drift * 0.7);
	float c_fine = vnoise(tile_uv * 2.8 + cloud_drift * 1.2);
	float cloud_h = c_base * 0.55 + c_billow * 0.32 + c_fine * 0.13;

	// Crisp cloud bank edge: 100% ZERO fog on revealed ground, sharp sculpted cloud wall on unexplored tiles!
	float fog_edge = reveal + (cloud_h - 0.5) * 0.16;
	float fog_factor = clamp(1.0 - smoothstep(0.22, 0.52, fog_edge), 0.0, 1.0);
	float eff_fog = fog_factor * fog_opacity;

	// Cast soft cloud-shadow rim onto adjacent ground right beneath the cloud wall for clear depth separation!
	float cloud_shadow = smoothstep(0.45, 0.72, reveal) * (1.0 - smoothstep(0.72, 0.92, reveal)) * fog_opacity * 0.32;
	surface_col *= (1.0 - cloud_shadow);

	// Sculpted Fantasy Cloud Lighting (sunlit cool-silver tops + deep navy twilight bases)
	float c_sun = fbm4((tile_uv + vec2(-0.18, -0.18)) * 0.42 + cloud_drift);
	float cloud_lit = clamp(0.45 + (cloud_h - c_sun) * 2.8 + (cloud_h - 0.48) * 0.8, 0.0, 1.0);
	vec3 fog_shadow_col = vec3(0.04, 0.068, 0.14);
	vec3 fog_mid_col = vec3(0.11, 0.165, 0.28);
	vec3 fog_top_col = vec3(0.24, 0.32, 0.46);
	vec3 fog_col = mix(fog_shadow_col, fog_mid_col, smoothstep(0.15, 0.62, cloud_lit));
	fog_col = mix(fog_col, fog_top_col, smoothstep(0.58, 0.94, cloud_lit));

	ALBEDO = mix(surface_col, fog_col, eff_fog);
	NORMAL_MAP = ground_n_map;
	NORMAL_MAP_DEPTH = mix(n_depth, 0.08, max(is_water, eff_fog));
	ROUGHNESS = mix(mix(surf_rough, 0.26, is_water), 0.96, eff_fog);
	METALLIC = 0.0;
	SPECULAR = mix(mix(surf_spec, 0.62, is_water), 0.04, eff_fog);
	EMISSION = magic_glow * (1.0 - eff_fog * 0.85);
	ALPHA = patch_alpha;
}
