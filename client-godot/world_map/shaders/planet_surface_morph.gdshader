shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Fantasy Stylized Planet Surface + Seamless 2D-to-3D Morph Shader (Milestone 2).
// Locked mathematically to PlanetCoordinates.to_morphed_position / to_morphed_normal.

uniform float planet_radius = 10.0;
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;
uniform float center_lon_rad = 0.0;
uniform float height_scale : hint_range(0.0, 1.0) = 0.14;

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D biome_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D ocean_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D magic_mask : filter_linear_mipmap, repeat_enable;
uniform sampler2D global_fog_mask : filter_linear, repeat_enable;
uniform sampler2D cloud_map : filter_linear_mipmap, repeat_enable;

uniform vec4 ocean_tint : source_color = vec4(0.06, 0.24, 0.46, 1.0);
uniform vec4 land_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 magic_color : source_color = vec4(0.58, 0.34, 1.0, 1.0);
uniform vec4 rim_color : source_color = vec4(0.32, 0.78, 1.0, 1.0);

uniform float normal_strength : hint_range(0.0, 2.0) = 0.72;
uniform float magic_strength : hint_range(0.0, 4.0) = 1.15;
uniform float biome_blend : hint_range(0.0, 0.5) = 0.12;
uniform float ocean_roughness : hint_range(0.05, 1.0) = 0.28;
uniform float land_roughness : hint_range(0.1, 1.0) = 0.88;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.38;
uniform float fog_opacity : hint_range(0.0, 1.0) = 0.38;
uniform float use_fog_mask : hint_range(0.0, 1.0) = 0.0;

varying vec2 v_sample_uv;
varying float v_morph_smooth;

void vertex() {
	float t = smoothstep(0.0, 1.0, clamp(morph_factor, 0.0, 1.0));
	v_morph_smooth = t;

	// Relative longitude in [-PI, +PI], latitude in [+PI/2 (North), -PI/2 (South)]
	float lon_rel = (UV.x - 0.5) * 6.28318530718;
	float lat = (0.5 - UV.y) * 3.14159265359;

	// Unwrapped horizontal sample UV for seamless GPU repeat_enable mipmaps
	float center_u = center_lon_rad / 6.28318530718;
	vec2 sample_uv = vec2(UV.x + center_u, clamp(UV.y, 0.001, 0.999));
	v_sample_uv = sample_uv;

	float cl = cos(lat);
	float sl = sin(lat);
	float c_lon = cos(lon_rel);
	float s_lon = sin(lon_rel);

	vec3 p_flat = vec3(
		planet_radius * lon_rel,
		planet_radius,
		-planet_radius * lat
	);

	vec3 p_sphere = vec3(
		planet_radius * cl * s_lon,
		planet_radius * cl * c_lon,
		-planet_radius * sl
	);

	// Analytic East (+U) and North (-V) tangents blended identically to PlanetCoordinates
	vec3 d_flat_lon = vec3(1.0, 0.0, 0.0);
	vec3 d_flat_lat = vec3(0.0, 0.0, -1.0);
	vec3 d_sph_lon = vec3(cl * c_lon, -cl * s_lon, 0.0);
	vec3 d_sph_lat = vec3(-sl * s_lon, -sl * c_lon, -cl);

	vec3 tangent_east = mix(d_flat_lon, d_sph_lon, t);
	vec3 tangent_north = mix(d_flat_lat, d_sph_lat, t);

	vec3 out_normal;
	if (abs(lat) > 1.562) {
		vec3 pole_n = vec3(0.0, 0.0, lat > 0.0 ? -1.0 : 1.0);
		out_normal = normalize(mix(vec3(0.0, 1.0, 0.0), pole_n, t));
		tangent_east = vec3(c_lon, -s_lon, 0.0);
	} else {
		vec3 cross_n = cross(tangent_east, tangent_north);
		float len_sq = dot(cross_n, cross_n);
		out_normal = len_sq > 1e-6 ? normalize(cross_n) : normalize(p_sphere);
	}

	// Subtle relief displacement above sea level (0.48) so ocean stays smooth
	float h = textureLod(height_map, sample_uv, 0.0).r;
	float land_relief = max(0.0, h - 0.48) * height_scale;

	VERTEX = mix(p_flat, p_sphere, t) + out_normal * land_relief;
	NORMAL = out_normal;
	TANGENT = normalize(tangent_east);
	BINORMAL = normalize(-tangent_north);
}

void fragment() {
	vec2 uv = v_sample_uv;

	vec3 albedo_tex = texture(albedo_map, uv).rgb;
	vec3 biome_tex = texture(biome_map, uv).rgb;
	float ocean = texture(ocean_mask, uv).r;
	float magic = texture(magic_mask, uv).r;
	vec3 normal_tex = texture(normal_map, uv).rgb;

	// Blend stylized land & ocean tones while preserving shallow coastal gradients
	vec3 land_col = albedo_tex * land_tint.rgb;
	land_col *= mix(vec3(1.0), biome_tex * 1.15, biome_blend);

	float wave = sin(uv.x * 90.0 + TIME * 0.45) * cos(uv.y * 55.0 - TIME * 0.35) * 0.025;
	vec3 water_col = mix(albedo_tex, ocean_tint.rgb, 0.22) + vec3(wave * 0.4, wave * 0.7, wave);

	vec3 base_col = mix(land_col, water_col, ocean);

	// Subtle stylized planet rim light that fades in smoothly as sphere forms
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.4);
	float rim_factor = fresnel * rim_strength * smoothstep(0.25, 0.95, v_morph_smooth);

	// Animated fantasy arcane pulse on magic ley lines & Wonder Sanctuary
	float magic_pulse = 0.85 + 0.15 * sin(TIME * 2.1 + uv.x * 18.0 + uv.y * 12.0);
	vec3 magic_glow = mix(magic_color.rgb, biome_tex, 0.35) * magic * magic_strength * magic_pulse;

	// Planetary Soft Cloud Fog-of-War (dense mist at regional zoom, ~35% mythic veil in 3D orbit so 5 continents stay gorgeous)
	float eff_fog = 0.0;
	vec3 fog_col = vec3(0.08, 0.13, 0.24);
	if (use_fog_mask > 0.01) {
		float rev = texture(global_fog_mask, uv).r;
		float cloud_wisp = texture(cloud_map, vec2(uv.x + TIME * 0.004, uv.y)).a;
		float fog_raw = clamp(1.0 - smoothstep(0.12, 0.75, rev + (cloud_wisp - 0.45) * 0.22), 0.0, 1.0);
		eff_fog = fog_raw * fog_opacity * use_fog_mask;
		fog_col = mix(vec3(0.055, 0.09, 0.17), vec3(0.18, 0.26, 0.40), cloud_wisp);
	}

	vec3 final_col = mix(base_col, fog_col, eff_fog);
	ALBEDO = final_col + rim_color.rgb * rim_factor * 0.35;
	NORMAL_MAP = normal_tex;
	NORMAL_MAP_DEPTH = mix(normal_strength, normal_strength * 0.12, max(ocean, eff_fog));
	ROUGHNESS = mix(mix(land_roughness, ocean_roughness, ocean), 0.95, eff_fog);
	METALLIC = 0.0;
	SPECULAR = mix(mix(0.22, 0.62, ocean), 0.10, eff_fog);
	EMISSION = magic_glow * (1.0 - eff_fog * 0.55) + rim_color.rgb * rim_factor * 0.45;
}
