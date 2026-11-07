extends Node3D
class_name BasePlot3D

## Represents one of the 18 Building Plots across the 6 Vertically Stacked Floors in the Isometric 3D Base.
## Renders procedural 3D architecture for the authentic Pick Me Up building catalogue:
## - HOUSE (Dormitory) & PARTY_MANSION (Lv.30 upgrade)
## - WAREHOUSE (Storage)
## - TRAINING_CENTER (Hero Training)
## - FORGE (Equipment Crafting / Enhancement / Fusion)
## - KITCHEN (Ration Cooking)
## - MEDICAL (Infirmary)
## - HALL_OF_MAGIC (with 3 sub-wings: LIBRARY, ALCHEMY_WORKSHOP, MAGIC_RESEARCH_LAB)

@export var plot_index: int = 1
@export var zone_index: int = 1 # Floor number (1..6)
const PLOTS_PER_FLOOR := 8

@onready var pad_mesh: MeshInstance3D = $PadMesh
@onready var border_mesh: MeshInstance3D = $BorderMesh
@onready var structure_root: Node3D = $StructureRoot
@onready var title_label: Label3D = $TitleLabel3D
@onready var sub_label: Label3D = $SubLabel3D
@onready var harvest_badge: Label3D = $HarvestBadge3D
@onready var click_body: StaticBody3D = $ClickBody

var is_unlocked: bool = true
var building_data: Dictionary = {}
var is_hovered: bool = false
var is_selected: bool = false
var is_on_active_floor: bool = true
var _current_mesh_transparency: float = 0.0
var _focus_tween: Tween = null
var _bob_time: float = 0.0
var _last_rendered_signature: String = ""

# Animated 3D Facility Props
var _anim_hammer_pivot: Node3D = null
var _anim_dummies: Array[Node3D] = []
var _anim_magic_rings: Array[Node3D] = []
var _anim_floating_prop: Node3D = null
var _anim_floating_base_y: float = 2.4
var _facility_lights: Array[OmniLight3D] = []

func _ready() -> void:
	zone_index = int((maxi(1, plot_index) - 1) / PLOTS_PER_FLOOR) + 1
	click_body.set_meta("interactable_type", "PLOT")
	click_body.set_meta("plot_index", plot_index)
	click_body.set_meta("plot_node", self)
	_apply_pad_material()
	_refresh_visuals(true)

func _process(delta: float) -> void:
	_bob_time += delta * 3.2
	if harvest_badge.visible:
		harvest_badge.position.y = 3.75 + sin(_bob_time) * 0.16

	if not is_on_active_floor:
		return

	# 1. FORGE: Rhythmic blacksmith hammer striking the anvil
	if _anim_hammer_pivot != null and is_instance_valid(_anim_hammer_pivot):
		var strike_wave := sin(_bob_time * 1.8)
		_anim_hammer_pivot.rotation.z = lerpf(-0.55, 0.35, clampf(strike_wave * 1.4, 0.0, 1.0))

	# 2. TRAINING_CENTER: Spinning / swaying wooden training dummies
	for idx in range(_anim_dummies.size()):
		var d_node := _anim_dummies[idx]
		if d_node != null and is_instance_valid(d_node):
			d_node.rotation.y += delta * (1.8 if idx % 2 == 0 else -1.5)
			d_node.rotation.z = sin(_bob_time * 2.1 + float(idx)) * 0.12

	# 3. HALL_OF_MAGIC & SUB-WINGS: Counter-rotating 3D arcane rune rings
	for idx in range(_anim_magic_rings.size()):
		var ring_node := _anim_magic_rings[idx]
		if ring_node != null and is_instance_valid(ring_node):
			ring_node.rotate_y(delta * (1.1 if idx % 2 == 0 else -0.85))
			ring_node.rotate_x(delta * 0.45 * (1.0 if idx == 0 else -1.0))

	# 4. Floating Crest / Arcane Crystal / Healing Cross / Grimoire
	if _anim_floating_prop != null and is_instance_valid(_anim_floating_prop):
		_anim_floating_prop.position.y = _anim_floating_base_y + sin(_bob_time * 0.9) * 0.14
		_anim_floating_prop.rotate_y(delta * 1.25)

func setup_plot(idx: int, unlocked: bool, b_data: Dictionary) -> void:
	plot_index = idx
	zone_index = int((maxi(1, plot_index) - 1) / PLOTS_PER_FLOOR) + 1
	is_unlocked = unlocked
	building_data = b_data
	if is_node_ready():
		click_body.set_meta("plot_index", plot_index)
		_refresh_visuals(false)

func set_hovered(hovered: bool) -> void:
	if is_hovered == hovered:
		return
	is_hovered = hovered
	_apply_pad_material()

func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	_apply_pad_material()

func set_grid_rotation_deg(rot_deg: int) -> void:
	if structure_root != null:
		structure_root.rotation_degrees.y = float(rot_deg)

## Seamless 2-Tier Castle: All constructed buildings remain 100% visible at all times (no split rendering).
## Empty plot slots are hidden in the 3D world and only appear when a building is constructed on the grid.
func set_floor_focus_state(_active_floor: bool, _is_above_active: bool, _animate: bool = true, _travel_dir: int = 0) -> void:
	is_on_active_floor = true
	var has_b := not building_data.is_empty()
	if click_body != null and click_body.has_node("CollisionShape3D"):
		var shape: CollisionShape3D = click_body.get_node("CollisionShape3D")
		shape.disabled = not has_b

	if _focus_tween and _focus_tween.is_valid():
		_focus_tween.kill()

	visible = has_b
	process_mode = Node.PROCESS_MODE_INHERIT if has_b else Node.PROCESS_MODE_DISABLED
	if has_b:
		_apply_mesh_transparency(0.0)
		scale = Vector3.ONE
		title_label.visible = true
		sub_label.visible = true
		title_label.modulate.a = 1.0
		sub_label.modulate.a = 1.0
		harvest_badge.modulate.a = 1.0

func _apply_mesh_transparency(val: float) -> void:
	_current_mesh_transparency = val
	if pad_mesh != null:
		pad_mesh.transparency = val
	if border_mesh != null:
		border_mesh.transparency = val
	if structure_root != null:
		for node in structure_root.find_children("*", "GeometryInstance3D", true, false):
			if node is GeometryInstance3D:
				(node as GeometryInstance3D).transparency = val
	for lgt in _facility_lights:
		if lgt != null and is_instance_valid(lgt):
			lgt.light_energy = clampf(1.0 - val * 1.15, 0.0, 1.0) * float(lgt.get_meta("base_energy", 1.2))

func has_ready_harvest() -> bool:
	if building_data.is_empty():
		return false
	return float(building_data.get("stored", 0.0)) >= 1.0 and str(building_data.get("status", "READY")) == "READY"

func can_accept_worker() -> bool:
	if building_data.is_empty():
		return false
	if str(building_data.get("status", "")) != "READY":
		return false
	var max_w := int(building_data.get("maxWorkers", 0))
	var cur_w: Array = building_data.get("workers", [])
	return max_w > 0 and cur_w.size() < max_w

func get_worker_slot_global_position(slot_idx: int) -> Vector3:
	var offsets := [
		Vector3(-1.25, 0.0, 1.25),
		Vector3(1.25, 0.0, 1.25),
		Vector3(0.0, 0.0, 1.45),
		Vector3(-1.35, 0.0, -1.15)
	]
	var local_offset: Vector3 = offsets[slot_idx % offsets.size()]
	return global_position + local_offset

func _refresh_visuals(force_rebuild: bool) -> void:
	_apply_pad_material()

	var b_type := str(building_data.get("buildingType", ""))
	var b_lvl := int(building_data.get("level", 0))
	var b_status := str(building_data.get("status", ""))
	var sig := "%s:%d:%s:%d:%s" % [str(is_unlocked), plot_index, b_type, b_lvl, b_status]

	if force_rebuild or sig != _last_rendered_signature:
		_last_rendered_signature = sig
		_rebuild_structure_mesh(b_type, b_lvl, b_status)
		_apply_mesh_transparency(_current_mesh_transparency)

	set_floor_focus_state(true, false, false, 0)
	if building_data.is_empty():
		harvest_badge.visible = false
		return

	var type_name := str(building_data.get("typeName", b_type))
	var max_lvl := int(building_data.get("maxLevel", 3))
	title_label.text = "%s %s (Lv.%d/%d)" % [_icon_for_type(b_type), type_name, b_lvl, max_lvl]
	title_label.modulate = Color(1.0, 0.92, 0.58)

	var workers: Array = building_data.get("workers", [])
	var max_w := int(building_data.get("maxWorkers", 0))
	var stored := float(building_data.get("stored", 0.0))
	var cap := int(building_data.get("capacity", 0))
	var rate := float(building_data.get("ratePerHour", 0.0))
	var res_type := str(building_data.get("resourceType", ""))

	if b_status == "CONSTRUCTING":
		sub_label.text = "🔨 Đang xây dựng..."
		sub_label.modulate = Color(0.98, 0.78, 0.32)
		harvest_badge.visible = false
	elif b_status == "UPGRADING":
		sub_label.text = "⬆️ Đang nâng cấp..."
		sub_label.modulate = Color(0.45, 0.85, 1.0)
		harvest_badge.visible = false
	else:
		var parts: Array[String] = []
		parts.append(_role_subtitle_for_type(b_type, b_lvl))
		if cap > 0 and res_type != "":
			parts.append("%s %d/%d (+%.1f/h)" % [_icon_for_resource(res_type), int(floor(stored)), cap, rate])
		if max_w > 0:
			parts.append("👷 %d/%d" % [workers.size(), max_w])
		sub_label.text = " | ".join(parts)
		sub_label.modulate = Color(0.85, 0.94, 1.0)

		if stored >= 1.0:
			harvest_badge.visible = true
			harvest_badge.text = "🌾 THU HOẠCH +%d %s!" % [int(floor(stored)), _icon_for_resource(res_type)]
		else:
			harvest_badge.visible = false

func _role_subtitle_for_type(b_type: String, b_lvl: int = 1) -> String:
	var lvl := clampi(b_lvl, 1, 3)
	match b_type:
		"FORGE":
			return "⚒️ Rèn & Cường Hóa Trang Bị"
		"TRAINING_CENTER":
			var w_cap := 3 if lvl == 1 else (5 if lvl == 2 else 7)
			return "🥋 Huấn Luyện (Tối đa %d Hero)" % w_cap
		"HALL_OF_MAGIC":
			return "🔮 3 Phân Khu (Tổng 6 Hero)"
		"LIBRARY":
			return "📚 Thư Viện Ma Thuật (Chỉ MAGE • 2 người)"
		"ALCHEMY_WORKSHOP":
			var s_rate := 15 if lvl == 1 else (30 if lvl == 2 else 60)
			return "⚗️ Xưởng Giả Kim (%d Đá/h)" % s_rate
		"MAGIC_RESEARCH_LAB":
			return "✨ Phòng Nghiên Cứu (Công Nghệ • Chuyển Chức • Thức Tỉnh)"
		"WAREHOUSE":
			return "📦 Nhà Kho (+%d Slot Ô Đồ)" % (lvl * 100)
		"HOUSE":
			var r_cap := 5 if lvl == 1 else (7 if lvl == 2 else 10)
			var r_mult := "1.0x" if lvl == 1 else ("1.5x" if lvl == 2 else "2.0x")
			return "🏠 Dormitory (%d người • Hồi %s)" % [r_cap, r_mult]
		"PARTY_MANSION":
			return "🏰 Biệt Thự Tổ Đội (5 người • Hồi 4.0x = x2 Lv.3)"
		"KITCHEN":
			var f_rate := 20 if lvl == 1 else (40 if lvl == 2 else 80)
			return "🍖 Bếp (%d FOOD/h & Món Buff)" % f_rate
		"MEDICAL":
			return "✚ Recovery Center (%d Slot Chữa Trị)" % (lvl * 2)
		_:
			return "Sẵn sàng hoạt động"

func _apply_pad_material() -> void:
	if not is_node_ready():
		return
	var pad_mat := StandardMaterial3D.new()
	var border_mat := StandardMaterial3D.new()

	if not is_unlocked:
		pad_mat.albedo_color = Color(0.14, 0.15, 0.19)
		border_mat.albedo_color = Color(0.32, 0.22, 0.25)
	elif building_data.is_empty():
		pad_mat.albedo_color = Color(0.20, 0.30, 0.24)
		border_mat.albedo_color = Color(0.32, 0.55, 0.38)
	else:
		pad_mat.albedo_color = Color(0.26, 0.28, 0.34)
		border_mat.albedo_color = Color(0.55, 0.48, 0.32)

	if is_selected:
		border_mat.albedo_color = Color(1.0, 0.84, 0.22)
		border_mat.emission_enabled = true
		border_mat.emission = Color(0.85, 0.65, 0.12)
	elif is_hovered:
		border_mat.albedo_color = Color(0.38, 0.88, 1.0)
		border_mat.emission_enabled = true
		border_mat.emission = Color(0.22, 0.65, 0.88)

	pad_mat.roughness = 0.85
	border_mat.roughness = 0.55
	pad_mesh.material_override = pad_mat
	border_mesh.material_override = border_mat

func _rebuild_structure_mesh(b_type: String, b_lvl: int, b_status: String) -> void:
	for child in structure_root.get_children():
		child.queue_free()
	_anim_hammer_pivot = null
	_anim_dummies.clear()
	_anim_magic_rings.clear()
	_anim_floating_prop = null
	_facility_lights.clear()

	if not is_unlocked:
		var lock_pillar := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.35
		cyl.bottom_radius = 0.5
		cyl.height = 0.9
		lock_pillar.mesh = cyl
		lock_pillar.position = Vector3(0, 0.45, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.38, 0.22, 0.26)
		mat.roughness = 0.7
		lock_pillar.material_override = mat
		structure_root.add_child(lock_pillar)
		return

	if b_type == "":
		for corner in [Vector3(-1.1, 0.15, -1.1), Vector3(1.1, 0.15, -1.1), Vector3(-1.1, 0.15, 1.1), Vector3(1.1, 0.15, 1.1)]:
			var peg := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.2, 0.3, 0.2)
			peg.mesh = box
			peg.position = corner
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.45, 0.78, 0.52)
			peg.material_override = mat
			structure_root.add_child(peg)
		return

	var scale_factor := 1.0 + float(maxi(0, b_lvl - 1)) * 0.08
	var main_mesh := MeshInstance3D.new()
	var roof_mesh := MeshInstance3D.new()
	var main_mat := StandardMaterial3D.new()
	var roof_mat := StandardMaterial3D.new()

	match b_type:
		"FORGE":
			# Blacksmith stone workshop + blast furnace chimney + glowing magma core + Anvil & swinging Hammer
			var box := BoxMesh.new()
			box.size = Vector3(1.85, 1.32, 1.65) * scale_factor
			main_mesh.mesh = box
			main_mesh.position = Vector3(-0.15, box.size.y * 0.5, -0.15)
			main_mat.albedo_color = Color(0.28, 0.25, 0.29)

			var chimney := CylinderMesh.new()
			chimney.top_radius = 0.34 * scale_factor
			chimney.bottom_radius = 0.48 * scale_factor
			chimney.height = 1.25 * scale_factor
			roof_mesh.mesh = chimney
			roof_mesh.position = Vector3(-0.55, box.size.y + chimney.height * 0.5, -0.45)
			roof_mat.albedo_color = Color(0.96, 0.38, 0.12)
			roof_mat.emission_enabled = true
			roof_mat.emission = Color(0.88, 0.28, 0.06)

			# Glowing Molten Furnace Core
			var core := _make_box_part(Vector3(0.55, 0.52, 0.25), Vector3(-0.15, 0.42, 0.68 * scale_factor), Color(1.0, 0.48, 0.10), true, 1.8)
			structure_root.add_child(core)
			_add_facility_light(Vector3(0.2, 1.1, 0.8), Color(1.0, 0.52, 0.16), 1.65, 5.5)

			# 3D Blacksmith Anvil in the front right yard
			var anvil_base := _make_box_part(Vector3(0.52, 0.38, 0.34), Vector3(0.75, 0.19, 0.65), Color(0.20, 0.22, 0.26))
			var anvil_top := _make_box_part(Vector3(0.72, 0.22, 0.38), Vector3(0.75, 0.46, 0.65), Color(0.42, 0.46, 0.54))
			var hot_blade := _make_box_part(Vector3(0.48, 0.05, 0.12), Vector3(0.75, 0.60, 0.65), Color(1.0, 0.62, 0.15), true, 2.0)
			structure_root.add_child(anvil_base)
			structure_root.add_child(anvil_top)
			structure_root.add_child(hot_blade)

			# Animated Swinging Hammer Pivot
			_anim_hammer_pivot = Node3D.new()
			_anim_hammer_pivot.position = Vector3(0.42, 0.85, 0.65)
			var handle := _make_box_part(Vector3(0.46, 0.08, 0.08), Vector3(0.22, 0.0, 0.0), Color(0.55, 0.36, 0.20))
			var head := _make_box_part(Vector3(0.18, 0.26, 0.18), Vector3(0.42, 0.0, 0.0), Color(0.68, 0.72, 0.80))
			_anim_hammer_pivot.add_child(handle)
			_anim_hammer_pivot.add_child(head)
			structure_root.add_child(_anim_hammer_pivot)

		"TRAINING_CENTER":
			# Octagonal Arena Deck + Martial Aura Ring + 2 Spinning Wooden Training Dummies + Weapon Rack
			var ring := CylinderMesh.new()
			ring.top_radius = 1.38 * scale_factor
			ring.bottom_radius = 1.48 * scale_factor
			ring.height = 0.38 * scale_factor
			main_mesh.mesh = ring
			main_mesh.position = Vector3(0, ring.height * 0.5, 0)
			main_mat.albedo_color = Color(0.52, 0.38, 0.24)

			var dojo_pavilion := PrismMesh.new()
			dojo_pavilion.size = Vector3(1.55, 0.75, 1.15) * scale_factor
			roof_mesh.mesh = dojo_pavilion
			roof_mesh.position = Vector3(0.0, ring.height + 0.95, -0.55)
			roof_mat.albedo_color = Color(0.84, 0.22, 0.20)

			var pavilion_body := _make_box_part(Vector3(1.35, 0.82, 0.95) * scale_factor, Vector3(0.0, ring.height + 0.41, -0.55), Color(0.66, 0.52, 0.36))
			structure_root.add_child(pavilion_body)

			# Glowing Martial Aura Torus on the arena floor
			var aura_torus := MeshInstance3D.new()
			var tmesh := TorusMesh.new()
			tmesh.inner_radius = 1.05 * scale_factor
			tmesh.outer_radius = 1.16 * scale_factor
			aura_torus.mesh = tmesh
			aura_torus.position = Vector3(0, ring.height + 0.03, 0.15)
			var amat := StandardMaterial3D.new()
			amat.albedo_color = Color(0.98, 0.65, 0.22)
			amat.emission_enabled = true
			amat.emission = Color(0.95, 0.52, 0.12)
			aura_torus.material_override = amat
			structure_root.add_child(aura_torus)

			# 2 Animated Wooden Training Dummies
			for d_pos in [Vector3(-0.58, ring.height, 0.48), Vector3(0.58, ring.height, 0.48)]:
				var dummy_root := Node3D.new()
				dummy_root.position = d_pos
				var post := _make_cyl_part(0.14, 0.16, 1.05, Vector3(0, 0.52, 0), Color(0.65, 0.46, 0.25))
				var crossbar := _make_box_part(Vector3(0.76, 0.11, 0.11), Vector3(0, 0.72, 0), Color(0.78, 0.58, 0.32))
				var pad_target := _make_cyl_part(0.20, 0.20, 0.42, Vector3(0, 0.68, 0), Color(0.88, 0.26, 0.22))
				dummy_root.add_child(post)
				dummy_root.add_child(crossbar)
				dummy_root.add_child(pad_target)
				structure_root.add_child(dummy_root)
				_anim_dummies.append(dummy_root)

		"HALL_OF_MAGIC":
			# Central Arcane Spire + 2 Counter-Rotating Rune Rings + Floating Mana Crystal + 3 Sub-Wing Towers
			var base_cyl := CylinderMesh.new()
			base_cyl.top_radius = 0.82 * scale_factor
			base_cyl.bottom_radius = 1.18 * scale_factor
			base_cyl.height = 1.92 * scale_factor
			main_mesh.mesh = base_cyl
			main_mesh.position = Vector3(0, base_cyl.height * 0.5, 0)
			main_mat.albedo_color = Color(0.24, 0.20, 0.52)

			var spire := CylinderMesh.new()
			spire.top_radius = 0.06
			spire.bottom_radius = 0.96 * scale_factor
			spire.height = 1.18 * scale_factor
			roof_mesh.mesh = spire
			roof_mesh.position = Vector3(0, base_cyl.height + spire.height * 0.5, 0)
			roof_mat.albedo_color = Color(0.56, 0.32, 0.98)
			roof_mat.emission_enabled = true
			roof_mat.emission = Color(0.42, 0.20, 0.85)

			_add_facility_light(Vector3(0, 2.8, 0), Color(0.65, 0.42, 1.0), 1.6, 6.5)

			# Counter-rotating 3D Arcane Gyroscope Rings
			for r_idx in range(2):
				var ring_inst := MeshInstance3D.new()
				var r_torus := TorusMesh.new()
				r_torus.inner_radius = (1.15 + float(r_idx) * 0.22) * scale_factor
				r_torus.outer_radius = r_torus.inner_radius + 0.07
				ring_inst.mesh = r_torus
				ring_inst.position = Vector3(0, 1.55 + float(r_idx) * 0.35, 0)
				ring_inst.rotation_degrees = Vector3(24.0 if r_idx == 0 else -28.0, 0.0, 18.0)
				var r_mat := StandardMaterial3D.new()
				r_mat.albedo_color = Color(0.42, 0.88, 1.0) if r_idx == 0 else Color(0.95, 0.45, 0.98)
				r_mat.emission_enabled = true
				r_mat.emission = r_mat.albedo_color * 0.85
				ring_inst.material_override = r_mat
				structure_root.add_child(ring_inst)
				_anim_magic_rings.append(ring_inst)

			# Levitating Arcane Crystal above spire
			_anim_floating_base_y = base_cyl.height + spire.height + 0.45
			_anim_floating_prop = _make_box_part(Vector3(0.32, 0.48, 0.32), Vector3(0, _anim_floating_base_y, 0), Color(0.45, 0.95, 1.0), true, 2.2)
			_anim_floating_prop.rotation_degrees = Vector3(45, 45, 0)
			structure_root.add_child(_anim_floating_prop)

			# 3 Sub-Wing Towers: Library (Cyan), Alchemy Workshop (Emerald), Magic Research Lab (Magenta)
			var wing_colors := [
				Color(0.25, 0.72, 1.0),  # 1. Library
				Color(0.25, 0.92, 0.55), # 2. Alchemy Workshop
				Color(0.95, 0.42, 0.90)  # 3. Magic Research Lab
			]
			var wing_offsets := [
				Vector3(-1.02, 0.65, 0.68),
				Vector3(1.02, 0.65, 0.68),
				Vector3(0.0, 0.65, -1.08)
			]
			for w_idx in range(3):
				var wing := _make_cyl_part(0.28, 0.36, 1.3, wing_offsets[w_idx], Color(0.22, 0.24, 0.42))
				var cap := _make_cyl_part(0.04, 0.36, 0.55, wing_offsets[w_idx] + Vector3(0, 0.92, 0), wing_colors[w_idx], true, 1.4)
				structure_root.add_child(wing)
				structure_root.add_child(cap)

		"LIBRARY", "ALCHEMY_WORKSHOP", "MAGIC_RESEARCH_LAB":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.88 * scale_factor
			cyl.bottom_radius = 1.02 * scale_factor
			cyl.height = 1.55 * scale_factor
			main_mesh.mesh = cyl
			main_mesh.position = Vector3(0, cyl.height * 0.5, 0)
			main_mat.albedo_color = Color(0.24, 0.30, 0.54)

			var accent_col := Color(0.35, 0.82, 1.0) if b_type == "LIBRARY" else (Color(0.28, 0.92, 0.55) if b_type == "ALCHEMY_WORKSHOP" else Color(0.92, 0.38, 0.96))
			var dome := CylinderMesh.new()
			dome.top_radius = 0.12
			dome.bottom_radius = 0.98 * scale_factor
			dome.height = 0.88 * scale_factor
			roof_mesh.mesh = dome
			roof_mesh.position = Vector3(0, cyl.height + dome.height * 0.5, 0)
			roof_mat.albedo_color = accent_col
			roof_mat.emission_enabled = true
			roof_mat.emission = accent_col * 0.55

			# Floating Grimoire / Alchemical Orb / Astral Ring
			_anim_floating_base_y = cyl.height + dome.height + 0.42
			_anim_floating_prop = _make_box_part(Vector3(0.36, 0.36, 0.36), Vector3(0, _anim_floating_base_y, 0), accent_col, true, 1.9)
			structure_root.add_child(_anim_floating_prop)

		"WAREHOUSE":
			# Timber-framed storage hall + loading dock + stacked 3D wooden crates & golden barrels
			var box := BoxMesh.new()
			box.size = Vector3(1.95, 1.28, 1.62) * scale_factor
			main_mesh.mesh = box
			main_mesh.position = Vector3(-0.1, box.size.y * 0.5, -0.15)
			main_mat.albedo_color = Color(0.46, 0.36, 0.24)

			var roof_box := PrismMesh.new()
			roof_box.size = Vector3(2.12, 0.62, 1.78) * scale_factor
			roof_mesh.mesh = roof_box
			roof_mesh.position = Vector3(-0.1, box.size.y + roof_box.size.y * 0.5, -0.15)
			roof_mat.albedo_color = Color(0.32, 0.40, 0.48)

			# Stacked crates and barrels in the front loading dock
			for c_pos in [Vector3(0.68, 0.22, 0.68), Vector3(0.32, 0.20, 0.75), Vector3(0.52, 0.58, 0.68)]:
				var crate := _make_box_part(Vector3(0.36, 0.36, 0.36), c_pos, Color(0.68, 0.50, 0.28))
				structure_root.add_child(crate)
			var gold_chest := _make_box_part(Vector3(0.42, 0.30, 0.28), Vector3(-0.55, 0.16, 0.72), Color(0.95, 0.78, 0.22), true, 0.8)
			structure_root.add_child(gold_chest)

		"PARTY_MANSION":
			# Grand 2-Story Noble Manor + Twin Flanking Turrets + Golden Crest
			var box := BoxMesh.new()
			box.size = Vector3(2.10, 1.68, 1.75) * scale_factor
			main_mesh.mesh = box
			main_mesh.position = Vector3(0, box.size.y * 0.5, 0)
			main_mat.albedo_color = Color(0.94, 0.88, 0.74)

			var prism := PrismMesh.new()
			prism.size = Vector3(2.32, 0.95, 1.95) * scale_factor
			roof_mesh.mesh = prism
			roof_mesh.position = Vector3(0, box.size.y + prism.size.y * 0.5, 0)
			roof_mat.albedo_color = Color(0.96, 0.74, 0.18)
			roof_mat.emission_enabled = true
			roof_mat.emission = Color(0.55, 0.38, 0.08)

			for side_x in [-1.05 * scale_factor, 1.05 * scale_factor]:
				var turret := _make_cyl_part(0.34, 0.38, 1.95 * scale_factor, Vector3(side_x, 0.97 * scale_factor, 0.45), Color(0.88, 0.82, 0.68))
				var turret_roof := _make_cyl_part(0.04, 0.44, 0.65, Vector3(side_x, 2.15 * scale_factor, 0.45), Color(0.95, 0.68, 0.15), true, 0.9)
				structure_root.add_child(turret)
				structure_root.add_child(turret_roof)

			_anim_floating_base_y = box.size.y + prism.size.y + 0.42
			_anim_floating_prop = _make_box_part(Vector3(0.35, 0.35, 0.12), Vector3(0, _anim_floating_base_y, 0), Color(1.0, 0.86, 0.25), true, 2.0)
			structure_root.add_child(_anim_floating_prop)

		"KITCHEN":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.95 * scale_factor
			cyl.bottom_radius = 1.08 * scale_factor
			cyl.height = 1.32 * scale_factor
			main_mesh.mesh = cyl
			main_mesh.position = Vector3(-0.1, cyl.height * 0.5, -0.1)
			main_mat.albedo_color = Color(0.76, 0.46, 0.26)

			var dome := CylinderMesh.new()
			dome.top_radius = 0.22 * scale_factor
			dome.bottom_radius = 1.15 * scale_factor
			dome.height = 0.72 * scale_factor
			roof_mesh.mesh = dome
			roof_mesh.position = Vector3(-0.1, cyl.height + dome.height * 0.5, -0.1)
			roof_mat.albedo_color = Color(0.90, 0.66, 0.22)

			# Outdoor cauldron & warm stove glow
			var cauldron := _make_cyl_part(0.36, 0.28, 0.45, Vector3(0.68, 0.24, 0.62), Color(0.22, 0.24, 0.28))
			var soup := _make_cyl_part(0.32, 0.32, 0.08, Vector3(0.68, 0.46, 0.62), Color(1.0, 0.65, 0.18), true, 1.5)
			structure_root.add_child(cauldron)
			structure_root.add_child(soup)

		"MEDICAL":
			var box := BoxMesh.new()
			box.size = Vector3(1.82, 1.38, 1.72) * scale_factor
			main_mesh.mesh = box
			main_mesh.position = Vector3(0, box.size.y * 0.5, 0)
			main_mat.albedo_color = Color(0.85, 0.92, 0.88)

			var prism := PrismMesh.new()
			prism.size = Vector3(2.02, 0.78, 1.92) * scale_factor
			roof_mesh.mesh = prism
			roof_mesh.position = Vector3(0, box.size.y + prism.size.y * 0.5, 0)
			roof_mat.albedo_color = Color(0.22, 0.76, 0.54)

			# Floating 3D Emerald Healing Cross
			_anim_floating_base_y = box.size.y + prism.size.y + 0.42
			var cross_root := Node3D.new()
			cross_root.position = Vector3(0, _anim_floating_base_y, 0)
			cross_root.add_child(_make_box_part(Vector3(0.16, 0.52, 0.16), Vector3.ZERO, Color(0.28, 0.98, 0.62), true, 1.8))
			cross_root.add_child(_make_box_part(Vector3(0.52, 0.16, 0.16), Vector3.ZERO, Color(0.28, 0.98, 0.62), true, 1.8))
			structure_root.add_child(cross_root)
			_anim_floating_prop = cross_root

		_: # HOUSE (Dormitory) & default
			var box := BoxMesh.new()
			box.size = Vector3(1.78, 1.32, 1.62) * scale_factor
			main_mesh.mesh = box
			main_mesh.position = Vector3(0, box.size.y * 0.5, 0)
			main_mat.albedo_color = Color(0.46, 0.54, 0.70)

			var prism := PrismMesh.new()
			prism.size = Vector3(1.98, 0.82, 1.82) * scale_factor
			roof_mesh.mesh = prism
			roof_mesh.position = Vector3(0, box.size.y + prism.size.y * 0.5, 0)
			roof_mat.albedo_color = Color(0.28, 0.60, 0.88)

			# Warm lit dormitory windows
			for wx in [-0.45, 0.45]:
				var win := _make_box_part(Vector3(0.32, 0.34, 0.08), Vector3(wx, 0.72, 0.82 * scale_factor), Color(1.0, 0.86, 0.42), true, 1.4)
				structure_root.add_child(win)

	main_mesh.material_override = main_mat
	roof_mesh.material_override = roof_mat
	structure_root.add_child(main_mesh)
	structure_root.add_child(roof_mesh)

	if b_status == "CONSTRUCTING" or b_status == "UPGRADING":
		var scaffold := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = Vector3(2.25, 2.1, 2.25)
		scaffold.mesh = sbox
		scaffold.position = Vector3(0, 1.05, 0)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.95, 0.75, 0.25, 0.35)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.emission_enabled = true
		smat.emission = Color(0.85, 0.62, 0.15)
		scaffold.material_override = smat
		structure_root.add_child(scaffold)

func _make_box_part(sz: Vector3, pos: Vector3, col: Color, emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = sz
	inst.mesh = box
	inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.65
	if emissive:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
	inst.material_override = mat
	return inst

func _make_cyl_part(top_r: float, bot_r: float, h: float, pos: Vector3, col: Color, emissive: bool = false, energy: float = 1.0) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bot_r
	cyl.height = h
	inst.mesh = cyl
	inst.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.65
	if emissive:
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = energy
	inst.material_override = mat
	return inst

func _add_facility_light(pos: Vector3, col: Color, energy: float, rng: float) -> void:
	var lgt := OmniLight3D.new()
	lgt.position = pos
	lgt.light_color = col
	lgt.light_energy = energy
	lgt.omni_range = rng
	lgt.set_meta("base_energy", energy)
	structure_root.add_child(lgt)
	_facility_lights.append(lgt)

func _icon_for_type(b_type: String) -> String:
	match b_type:
		"FORGE":
			return "⚒️"
		"TRAINING_CENTER":
			return "🥋"
		"HALL_OF_MAGIC":
			return "🔮"
		"LIBRARY":
			return "📚"
		"ALCHEMY_WORKSHOP":
			return "⚗️"
		"MAGIC_RESEARCH_LAB":
			return "✨"
		"WAREHOUSE":
			return "📦"
		"HOUSE":
			return "🏠"
		"PARTY_MANSION":
			return "🏰"
		"KITCHEN":
			return "🍖"
		"MEDICAL":
			return "✚"
		_:
			return "🏛️"

func _icon_for_resource(res_type: String) -> String:
	match res_type:
		"FOOD", "RATION":
			return "🍖"
		"FOOD_RAW", "RAW_FOOD":
			return "🌾"
		"SAMPLE_HERO_EXP_100":
			return "📘 Sách Sơ Cấp"
		"SAMPLE_HERO_EXP_1000":
			return "📗 Sách Trung Cấp"
		"SAMPLE_HERO_EXP_10000":
			return "📙 Sách Cao Cấp"
		"ENHANCEMENT_STONE":
			return "💎"
		"WOOD":
			return "🪵"
		"STONE":
			return "🪨"
		"IRON":
			return "⛓️"
		"SILVER":
			return "🪙"
		_:
			return "📦"
