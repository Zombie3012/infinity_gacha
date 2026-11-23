class_name RarityStyle
extends RefCounted

## Shared 1★–7★ Rarity Color & 7★ Animated Rainbow Border Utility
## Order:
##   1★ Silver | 2★ Green | 3★ Blue | 4★ Purple | 5★ Gold | 6★ Red | 7★ Rainbow

const RAINBOW_SHADER_CODE := """
shader_type canvas_item;

uniform vec2 box_size = vec2(92.0, 92.0);
uniform float thickness = 3.0;
uniform float corner_radius = 8.0;
uniform float speed = 0.65;

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float rounded_box_sdf(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 pos = (UV - vec2(0.5)) * box_size;
	vec2 half_s = box_size * 0.5;
	float dist = rounded_box_sdf(pos, half_s, corner_radius);
	if (dist > 0.0 || dist < -thickness) {
		discard;
	}
	float angle = atan(pos.y, pos.x) / 6.2831853 + 0.5;
	float hue = fract(angle + TIME * speed);
	vec3 rgb = hsv2rgb(vec3(hue, 0.92, 1.0));
	COLOR = vec4(rgb, 1.0);
}
"""

static var _cached_shader: Shader = null

static func color_for_star(star: int) -> Color:
	match clampi(star, 1, 7):
		1:
			return Color("c4cdd9") # 1★ Bạc
		2:
			return Color("3cd070") # 2★ Xanh lá
		3:
			return Color("3898ff") # 3★ Xanh dương
		4:
			return Color("b55cff") # 4★ Tím
		5:
			return Color("ffd23f") # 5★ Vàng
		6:
			return Color("ff4757") # 6★ Đỏ
		_:
			return Color("ff73e6") # 7★ Rainbow

static func star_name(star: int) -> String:
	match clampi(star, 1, 7):
		1: return "1★ Bạc"
		2: return "2★ Xanh lá"
		3: return "3★ Xanh dương"
		4: return "4★ Tím"
		5: return "5★ Vàng"
		6: return "6★ Đỏ"
		_: return "7★ Rainbow"

static func attach_rainbow_border(target: Control, corner_radius: float = 8.0, thickness: float = 3.0) -> Control:
	if target == null or not is_instance_valid(target):
		return null
	var existing := target.get_node_or_null("RainbowBorder")
	if existing != null:
		existing.queue_free()

	if _cached_shader == null:
		_cached_shader = Shader.new()
		_cached_shader.code = RAINBOW_SHADER_CODE

	var rect := ColorRect.new()
	rect.name = "RainbowBorder"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mat := ShaderMaterial.new()
	mat.shader = _cached_shader
	var initial_size := target.size if target.size.x > 1.0 and target.size.y > 1.0 else target.custom_minimum_size
	mat.set_shader_parameter("box_size", initial_size)
	mat.set_shader_parameter("thickness", thickness)
	mat.set_shader_parameter("corner_radius", corner_radius)
	rect.material = mat

	target.resized.connect(func():
		if is_instance_valid(rect) and is_instance_valid(target):
			mat.set_shader_parameter("box_size", target.size)
	)
	target.add_child(rect)
	return rect
