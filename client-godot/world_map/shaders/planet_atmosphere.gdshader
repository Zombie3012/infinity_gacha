shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

// Stylized Fantasy Planetary Atmosphere Rim Glow (Milestone 2).
// Stays transparent at center so continents remain crisp, glowing softly around the limb.

uniform vec4 atmosphere_color : source_color = vec4(0.24, 0.72, 1.0, 1.0);
uniform vec4 twilight_color : source_color = vec4(0.56, 0.32, 0.96, 1.0);
uniform vec3 sun_direction = vec3(0.55, 0.62, 0.56);
uniform float rim_power : hint_range(1.0, 8.0) = 3.2;
uniform float intensity : hint_range(0.0, 3.0) = 1.25;
uniform float atmosphere_alpha : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_normal;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndotv, rim_power);
	// Softly taper outermost silhouette pixel so halo never looks hard-edged
	float outer_soft = smoothstep(0.0, 0.22, ndotv);
	float halo = rim * (0.35 + 0.65 * outer_soft);

	float sun_lit = clamp(dot(normalize(v_world_normal), normalize(sun_direction)) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(twilight_color.rgb, atmosphere_color.rgb, smoothstep(0.15, 0.85, sun_lit));
	float lit_boost = mix(0.45, 1.15, sun_lit);

	ALBEDO = col * intensity * lit_boost;
	ALPHA = clamp(halo * atmosphere_alpha, 0.0, 1.0);
}
