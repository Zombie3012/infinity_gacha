shader_type sky;

// Lightweight Fantasy Space Starfield Backdrop (Milestone 3).
// Keeps the 3D globe backdrop atmospheric without distracting from HUD or markers.

uniform vec3 deep_space_top : source_color = vec3(0.012, 0.018, 0.042);
uniform vec3 deep_space_mid : source_color = vec3(0.022, 0.032, 0.068);
uniform vec3 nebula_tint : source_color = vec3(0.11, 0.06, 0.22);
uniform float star_density = 180.0;
uniform float star_brightness = 0.85;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float horizon = 1.0 - abs(d.y);
	vec3 bg = mix(deep_space_top, deep_space_mid, horizon * 0.7);

	// Soft subtle cosmic nebula band
	float band = sin(d.x * 2.4 + d.z * 1.9) * cos(d.y * 2.8 - d.x * 1.2);
	bg += nebula_tint * smoothstep(0.25, 0.95, band * 0.5 + 0.5) * 0.22;

	// Crisp procedural stars on cubed spherical grid
	vec3 cell = floor(d * star_density);
	float rnd = hash31(cell);
	if (rnd > 0.992) {
		vec3 local = fract(d * star_density) - 0.5;
		float dist = length(local);
		float twinkle = 0.72 + 0.28 * sin(TIME * (1.5 + fract(rnd * 73.1) * 2.5) + rnd * 100.0);
		float star = smoothstep(0.32, 0.04, dist) * twinkle * star_brightness;
		vec3 star_col = mix(vec3(0.75, 0.88, 1.0), vec3(1.0, 0.92, 0.78), fract(rnd * 19.7));
		bg += star_col * star;
	}

	COLOR = bg;
}
