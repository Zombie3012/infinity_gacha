extends RefCounted

const NAMES := {"HOUSE": "Nhà ở", "PARTY_MANSION": "Biệt thự tổ đội", "WAREHOUSE": "Nhà kho", "TRAINING_CENTER": "Khu huấn luyện", "FORGE": "Xưởng rèn", "KITCHEN": "Nhà bếp", "MEDICAL": "Trung tâm hồi phục", "HALL_OF_MAGIC": "Đại sảnh ma thuật", "LIBRARY": "Thư viện", "ALCHEMY_WORKSHOP": "Xưởng giả kim", "MAGIC_RESEARCH_LAB": "Phòng nghiên cứu", "HERO_CHRONICLE": "Sử Điện Anh Hùng", "SHOP_AIRSHIP": "Thương thuyền", "ALLIANCE_HALL": "Liên minh", "AIRSHIP_PORT": "Bến Thiên Hành"}
static var _font: SystemFont

static func apply(label: Label3D, size: int) -> void:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
		_font.font_weight = 700
	label.font = _font
	label.font_size = size
	label.pixel_size = 0.006
	label.outline_size = 10
	label.outline_modulate = Color(0.025, 0.035, 0.05, 0.98)
	label.modulate = Color(1.0, 0.98, 0.92)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true

static func fit(label: Label3D, camera: Camera3D, pixels: float) -> float:
	if not is_instance_valid(label) or not label.is_inside_tree() or label.is_queued_for_deletion(): return 1.0
	if not is_instance_valid(camera) or not camera.is_inside_tree() or camera.is_queued_for_deletion(): return 1.0
	var point := label.global_position
	var pixels_per_meter := camera.unproject_position(point).distance_to(camera.unproject_position(point + camera.global_basis.y))
	if pixels_per_meter > 0.01:
		label.pixel_size = pixels / (label.font_size * pixels_per_meter)
	return maxf(pixels_per_meter, 0.01)
