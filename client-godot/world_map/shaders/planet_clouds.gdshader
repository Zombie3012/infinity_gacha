shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back;

// Morph-synchronized drifting stylized Cloud Layer (Milestone 2).
// Curves smoothly alongside planet_surface_morph.gdshader from flat 2D sky to 3D globe shell.

uniform float planet_radius = 10.0;
uniform float cloud_altitude = 0.22;
uniform float morph_factor : hint_range(0.0, 1.0) = 0.0;
uniform float center_lon_rad = 0.0;

uniform sampler2D cloud_map : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 cloud_tint : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform float cloud_speed = 0.006;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.45;

varying vec2 v_cloud_uv;

void vertex() {
	float t = smoothstep(0.0, 1.0, clamp(morph_factor, 0.0, 1.0));
	float r = planet_radius + cloud_altitude;

	float lon_rel = (UV.x - 0.5) * 6.28318530718;
	float lat = (0.5 - UV.y) * 3.14159265359;

	float center_u = center_lon_rad / 6.28318530718;
	v_cloud_uv = vec2(UV.x + center_u + TIME * cloud_speed, clamp(UV.y, 0.002, 0.998));

	float cl = cos(lat);
	float sl = sin(lat);
	float c_lon = cos(lon_rel);
	float s_lon = sin(lon_rel);

	vec3 p_flat = vec3(
		planet_radius * lon_rel,
		r,
		-planet_radius * lat
	);

	vec3 p_sphere = vec3(
		r * cl * s_lon,
		r * cl * c_lon,
		-r * sl
	);

	VERTEX = mix(p_flat, p_sphere, t);
	NORMAL = normalize(mix(vec3(0.0, 1.0, 0.0), normalize(p_sphere), t));
}

void fragment() {
	vec4 c = texture(cloud_map, v_cloud_uv);
	ALBEDO = c.rgb * cloud_tint.rgb;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
	ALPHA = c.a * cloud_opacity;
}
