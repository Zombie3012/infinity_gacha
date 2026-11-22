extends Node3D
class_name UnitActor3D

## Shared 3D Unit Actor for both Isometric Base (Lobby Wander/Work/Injured/Dragged) and Isometric PvE (Combat v2)
## Can use procedural capsule/armor mesh out-of-the-box or load any .glb/.gltf 3D character rig.

enum ActorMode {
	BASE_WANDER,
	BASE_WORKING,
	BASE_INJURED,
	BASE_DRAGGED,
	PVE_COMBAT
}

@export var mode: ActorMode = ActorMode.PVE_COMBAT
@export var unit_id: String = ""
@export var unit_name: String = "Hero"
@export var side: String = "HERO" # "HERO" or "ENEMY"
@export var star_rating: int = 1
@export var class_code: String = "WARRIOR"

@onready var visual_root: Node3D = $VisualRoot
@onready var body_mesh: MeshInstance3D = $VisualRoot/BodyMesh
@onready var weapon_mesh: MeshInstance3D = $VisualRoot/WeaponMesh
@onready var speech_label: Label3D = $SpeechBubbleLabel3D
@onready var name_label: Label3D = $NameplateLabel3D
@onready var hp_label: Label3D = $HpBarLabel3D
@onready var click_body: StaticBody3D = $ClickBody

var hero_raw_data: Dictionary = {}
var home_position: Vector3 = Vector3.ZERO
var work_look_target: Vector3 = Vector3.ZERO
var assigned_building_id: String = ""
var assigned_building_name: String = ""
var is_in_active_party: bool = false
var floor_index: int = 1
var terrace_center: Vector3 = Vector3.ZERO
var max_walk_radius: float = 5.8
var is_on_active_floor: bool = true
var _current_actor_transparency: float = 0.0
var _floor_focus_tween: Tween = null

var current_hp: int = 100
var max_hp: int = 100
var current_mp: int = 0
var max_mp: int = 100
var is_alive: bool = true
var _death_tween: Tween

# Base wander / work / speech state
var _wander_target: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _walk_bob_time: float = 0.0
var _speech_timer: float = 4.0
var _speech_hide_timer: float = 0.0
var _prev_base_mode: ActorMode = ActorMode.BASE_WANDER

const IDLE_SPEECH_LINES := [
	"💬 Bầu trời ở Căn cứ hôm nay yên bình thật...",
	"💬 Master đang nhìn kìa, phải tập luyện chăm chỉ hơn!",
	"💬 Không biết tầng Tháp tiếp theo có quái vật gì...",
	"💬 Ước gì tối nay Bếp Quân Lương có thêm khẩu phần thịt!",
	"💬 Nghe đồn được Thăng Sao sẽ mạnh lên gấp bội!",
	"💬 Chỉ cần còn sống trở về từ Tháp là tốt rồi."
]

const PARTY_SPEECH_LINES := [
	"⚔️ Vũ khí đã mài sắc! Sẵn sàng tiến vào Cổng Tháp!",
	"⚔️ Đội hình xuất kích đã sẵn sàng chờ lệnh Master!",
	"⚔️ Lần chinh phạt này nhất định sẽ vượt tầng!"
]

const WORK_SPEECH_LINES := [
	"🔨 Cố lên nào, kho tài nguyên sắp đầy rồi!",
	"🪵 Làm việc ở công trình cũng giúp rèn thể lực đấy!",
	"⚒️ Thêm một mẻ nguyên liệu nữa cho Căn cứ!"
]

const INJURED_SPEECH_LINES := [
	"🩹 Vết thương từ trận trước vẫn còn hơi nhói...",
	"💤 Nghỉ ngơi ở Bệnh Xá một lát sẽ hồi phục thôi."
]

const DRAGGED_SPEECH_LINES := [
	"😲 Ơ kìa Master?! Ngài nhấc tôi đi đâu thế?!",
	"🙌 Khoan đã Master! Đừng ném tôi vào lò rèn!",
	"🌀 Đi làm việc ở Xưởng hay vào Cổng Tháp đây Ngài?!"
]

func _ready() -> void:
	home_position = global_position
	_wander_target = home_position
	if click_body != null:
		click_body.set_meta("interactable_type", "HERO")
		click_body.set_meta("hero_node", self)
	_speech_timer = randf_range(2.5, 9.0)
	_apply_team_material()
	_refresh_labels()

func setup_combat_unit(data: Dictionary) -> void:
	mode = ActorMode.PVE_COMBAT
	hero_raw_data = data
	unit_id = str(data.get("id", ""))
	unit_name = str(data.get("name", "Unit"))
	side = str(data.get("side", "HERO"))
	star_rating = int(data.get("rarity", 3))
	class_code = str(data.get("classCode", "WARRIOR"))
	max_hp = maxi(1, int(data.get("maxHp", 100)))
	current_hp = clampi(int(data.get("hp", max_hp)), 0, max_hp)
	max_mp = maxi(0, int(data.get("maxMp", 100)))
	current_mp = clampi(int(data.get("mp", 0)), 0, max_mp)
	is_alive = current_hp > 0
	home_position = global_position
	if speech_label != null:
		speech_label.visible = false
	_apply_team_material()
	_refresh_labels()

func setup_base_resident(data: Dictionary, spawn_pos: Vector3, worker_info: Dictionary = {}, in_party: bool = false, infirmary_pos: Vector3 = Vector3(5.5, 0.0, 4.5), t_center: Vector3 = Vector3.ZERO) -> void:
	hero_raw_data = data
	unit_id = str(data.get("id", ""))
	unit_name = str(data.get("name", "Hero"))
	side = "HERO"
	star_rating = int(data.get("rarity", 1))
	class_code = str(data.get("classCode", data.get("heroClass", "UNCLASSIFIED")))
	max_hp = maxi(1, int(data.get("maxHp", 100)))
	current_hp = clampi(int(data.get("hp", max_hp)), 0, max_hp)
	is_in_active_party = in_party
	terrace_center = t_center
	max_walk_radius = 6.6 if floor_index <= 1 else 5.8

	var hero_state := str(data.get("state", "IDLE"))
	if not worker_info.is_empty():
		mode = ActorMode.BASE_WORKING
		_prev_base_mode = ActorMode.BASE_WORKING
		var b: Dictionary = worker_info.get("building", {})
		assigned_building_id = str(b.get("id", ""))
		assigned_building_name = str(b.get("typeName", b.get("buildingType", "Công trình")))
		home_position = worker_info.get("stationPos", spawn_pos)
		work_look_target = worker_info.get("buildingCenter", home_position)
		global_position = home_position
		_wander_target = home_position
	elif hero_state == "INJURED" or hero_state == "RESTING" or current_hp < int(max_hp * 0.5):
		mode = ActorMode.BASE_INJURED
		_prev_base_mode = ActorMode.BASE_INJURED
		assigned_building_id = ""
		assigned_building_name = ""
		home_position = infirmary_pos + Vector3(randf_range(-1.6, 1.6), 0.0, randf_range(-1.4, 1.4))
		global_position = home_position
		_wander_target = home_position
	else:
		mode = ActorMode.BASE_WANDER
		_prev_base_mode = ActorMode.BASE_WANDER
		assigned_building_id = ""
		assigned_building_name = ""
		home_position = spawn_pos
		global_position = spawn_pos
		_wander_target = spawn_pos

	_apply_team_material()
	_refresh_base_labels()

## Isolates Hero actors on the active floor and completely hides/disables them on other floors to eliminate lag
func set_floor_focus_state(active_floor: bool, animate: bool = true) -> void:
	is_on_active_floor = active_floor
	if click_body != null and click_body.has_node("CollisionShape3D"):
		var shape: CollisionShape3D = click_body.get_node("CollisionShape3D")
		shape.disabled = not active_floor

	if _floor_focus_tween and _floor_focus_tween.is_valid():
		_floor_focus_tween.kill()

	if not active_floor:
		visible = false
		set_process(false)
		set_physics_process(false)
		if speech_label != null:
			speech_label.visible = false
		name_label.visible = false
		hp_label.visible = false
	else:
		visible = true
		set_process(true)
		set_physics_process(true)
		_apply_actor_transparency(0.0)
		name_label.visible = true
		hp_label.visible = true
		name_label.modulate.a = 1.0
		hp_label.modulate.a = 1.0

func _apply_actor_transparency(val: float) -> void:
	_current_actor_transparency = val
	if body_mesh != null:
		body_mesh.transparency = val
	if weapon_mesh != null:
		weapon_mesh.transparency = val

func _refresh_base_labels() -> void:
	if not is_node_ready():
		return
	var lvl := int(hero_raw_data.get("level", 1))
	name_label.text = "★".repeat(clampi(star_rating, 1, 7)) + " %s (Lv.%d)" % [unit_name, lvl]
	if mode == ActorMode.BASE_WORKING:
		hp_label.text = "👷 Đang làm: %s" % assigned_building_name
		hp_label.modulate = Color(1.0, 0.86, 0.35)
	elif mode == ActorMode.BASE_INJURED:
		hp_label.text = "🩹 Nghỉ dưỡng tại Bệnh Xá"
		hp_label.modulate = Color(0.98, 0.55, 0.55)
	elif is_in_active_party:
		hp_label.text = "⚔️ [Đội Hình Chinh Phạt] • %s" % class_code
		hp_label.modulate = Color(0.45, 0.98, 0.62)
	else:
		hp_label.text = "[%s]" % class_code
		hp_label.modulate = Color(0.75, 0.85, 1.0)

## Pick Me Up style: Master grabs and lifts the Hero in 3D space
func start_drag_lift() -> void:
	if mode == ActorMode.PVE_COMBAT:
		return
	if mode != ActorMode.BASE_DRAGGED:
		_prev_base_mode = mode
	mode = ActorMode.BASE_DRAGGED
	var line: String = DRAGGED_SPEECH_LINES[randi() % DRAGGED_SPEECH_LINES.size()]
	show_speech_bubble(line, 3.5)

func update_drag_ground_position(world_ground_pos: Vector3) -> void:
	global_position = world_ground_pos

func end_drag_drop(new_ground_pos: Vector3) -> void:
	if mode != ActorMode.BASE_DRAGGED:
		return
	mode = _prev_base_mode

	# Clamp drop position relative to terrace center
	var rel := new_ground_pos - terrace_center
	var horiz := Vector2(rel.x, rel.z)
	if horiz.length() > max_walk_radius:
		horiz = horiz.normalized() * (max_walk_radius - 0.3)
	var safe_pos := terrace_center + Vector3(horiz.x, 0.0, horiz.y)

	home_position = safe_pos
	_wander_target = safe_pos
	global_position = safe_pos
	visual_root.position.y = 0.0
	visual_root.rotation_degrees = Vector3(0.0, visual_root.rotation_degrees.y, 0.0)
	_refresh_base_labels()

func show_speech_bubble(text: String, duration: float = 3.2) -> void:
	if speech_label == null or not is_on_active_floor:
		return
	speech_label.text = text
	speech_label.visible = true
	_speech_hide_timer = duration

func _process(delta: float) -> void:
	if mode == ActorMode.PVE_COMBAT:
		return

	# Speech bubble countdown & periodic ambient lines
	if _speech_hide_timer > 0.0:
		_speech_hide_timer -= delta
		if _speech_hide_timer <= 0.0 and speech_label != null:
			speech_label.visible = false
	else:
		_speech_timer -= delta
		if _speech_timer <= 0.0:
			_speech_timer = randf_range(7.0, 15.0)
			_trigger_ambient_speech()

	match mode:
		ActorMode.BASE_WANDER:
			_process_base_wander(delta)
		ActorMode.BASE_WORKING:
			_process_base_working(delta)
		ActorMode.BASE_INJURED:
			_process_base_injured(delta)
		ActorMode.BASE_DRAGGED:
			_process_base_dragged(delta)

func _trigger_ambient_speech() -> void:
	if randf() > 0.55:
		return
	match mode:
		ActorMode.BASE_WORKING:
			show_speech_bubble(WORK_SPEECH_LINES[randi() % WORK_SPEECH_LINES.size()], 3.2)
		ActorMode.BASE_INJURED:
			show_speech_bubble(INJURED_SPEECH_LINES[randi() % INJURED_SPEECH_LINES.size()], 3.2)
		ActorMode.BASE_WANDER:
			if is_in_active_party:
				show_speech_bubble(PARTY_SPEECH_LINES[randi() % PARTY_SPEECH_LINES.size()], 3.2)
			else:
				show_speech_bubble(IDLE_SPEECH_LINES[randi() % IDLE_SPEECH_LINES.size()], 3.2)

func _process_base_wander(delta: float) -> void:
	var to_target := _wander_target - global_position
	to_target.y = 0.0
	if to_target.length() > 0.15:
		var dir := to_target.normalized()
		global_position += dir * 2.1 * delta
		global_position.y = home_position.y
		visual_root.look_at(global_position + dir, Vector3.UP)
		_walk_bob_time += delta * 10.0
		visual_root.position.y = absf(sin(_walk_bob_time)) * 0.12
	else:
		visual_root.position.y = lerpf(visual_root.position.y, 0.0, delta * 8.0)
		_wander_timer -= delta
		if _wander_timer <= 0.0:
			_wander_timer = randf_range(2.5, 5.5)
			# Pick a gentle offset near home_position
			var offset := Vector3(randf_range(-2.4, 2.4), 0.0, randf_range(-2.4, 2.4))
			var candidate := home_position + offset
			
			# Clamp candidate relative to terrace center
			var rel := candidate - terrace_center
			var horiz := Vector2(rel.x, rel.z)
			if horiz.length() > max_walk_radius:
				horiz = horiz.normalized() * (max_walk_radius - 0.4)
			_wander_target = terrace_center + Vector3(horiz.x, home_position.y - terrace_center.y, horiz.y)

	# Strict boundary guard: ensure global_position NEVER exits the floor terrace deck
	var cur_rel := global_position - terrace_center
	var cur_horiz := Vector2(cur_rel.x, cur_rel.z)
	if cur_horiz.length() > max_walk_radius + 0.2:
		cur_horiz = cur_horiz.normalized() * max_walk_radius
		global_position = terrace_center + Vector3(cur_horiz.x, home_position.y - terrace_center.y, cur_horiz.y)

func _process_base_working(delta: float) -> void:
	var to_station := home_position - global_position
	to_station.y = 0.0
	if to_station.length() > 0.15:
		var dir := to_station.normalized()
		global_position += dir * 2.6 * delta
		global_position.y = home_position.y
		visual_root.look_at(global_position + dir, Vector3.UP)
		_walk_bob_time += delta * 11.0
		visual_root.position.y = absf(sin(_walk_bob_time)) * 0.12
	else:
		global_position.y = home_position.y
		var look_dir := work_look_target - global_position
		look_dir.y = 0.0
		if look_dir.length() > 0.05:
			visual_root.look_at(global_position + look_dir.normalized(), Vector3.UP)
		_walk_bob_time += delta * 6.5
		visual_root.position.y = absf(sin(_walk_bob_time)) * 0.08
		weapon_mesh.rotation_degrees.x = -30.0 + sin(_walk_bob_time * 1.5) * 35.0

func _process_base_injured(delta: float) -> void:
	_walk_bob_time += delta * 2.5
	visual_root.position.y = absf(sin(_walk_bob_time)) * 0.04

func _process_base_dragged(delta: float) -> void:
	_walk_bob_time += delta * 18.0
	visual_root.position.y = lerpf(visual_root.position.y, 2.15, delta * 12.0)
	visual_root.rotation_degrees.z = sin(_walk_bob_time) * 14.0

func _apply_team_material() -> void:
	if not is_node_ready():
		return
	var mat := StandardMaterial3D.new()
	if side == "HERO":
		match class_code:
			"MAGE":
				mat.albedo_color = Color(0.32, 0.48, 0.96)
			"THIEF":
				mat.albedo_color = Color(0.58, 0.28, 0.85)
			"ARCHER":
				mat.albedo_color = Color(0.24, 0.78, 0.45)
			"SPEARMAN":
				mat.albedo_color = Color(0.22, 0.75, 0.82)
			_:
				mat.albedo_color = Color(0.25, 0.62, 0.95)
	else:
		mat.albedo_color = Color(0.88, 0.25, 0.28)
	mat.roughness = 0.45
	body_mesh.material_override = mat

func _refresh_labels() -> void:
	if not is_node_ready():
		return
	if mode != ActorMode.PVE_COMBAT:
		_refresh_base_labels()
		return
	name_label.text = unit_name
	var pct := int(round((float(current_hp) / float(maxi(1, max_hp))) * 100.0))
	hp_label.text = "HP: %d/%d (%d%%)" % [current_hp, max_hp, pct]
	if max_mp > 0:
		hp_label.text += "\nMP: %d/%d" % [current_mp, max_mp]
	if side == "HERO":
		hp_label.modulate = Color(0.35, 0.95, 0.52) if pct > 35 else Color(0.98, 0.75, 0.25)
	else:
		hp_label.modulate = Color(0.98, 0.42, 0.42)

## Lunge toward target, strike, and return to formation slot
func perform_attack_lunge(target_pos: Vector3, is_skill: bool = false, playback_speed: float = 1.0) -> void:
	var dir := (target_pos - home_position)
	dir.y = 0.0
	if dir.length() > 0.01:
		visual_root.look_at(home_position + dir.normalized(), Vector3.UP)
	var stop_pos := target_pos - dir.normalized() * 1.15
	stop_pos.y = home_position.y

	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", stop_pos, 0.22 / maxf(1.0, playback_speed))
	if is_skill:
		tween.tween_property(visual_root, "scale", Vector3(1.25, 1.25, 1.25), 0.12 / maxf(1.0, playback_speed))
		tween.tween_property(visual_root, "scale", Vector3.ONE, 0.12 / maxf(1.0, playback_speed))
	else:
		tween.tween_property(visual_root, "position:y", 0.35, 0.08 / maxf(1.0, playback_speed))
		tween.tween_property(visual_root, "position:y", 0.0, 0.08 / maxf(1.0, playback_speed))
	await tween.finished

func return_to_slot(playback_speed: float = 1.0) -> void:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", home_position, 0.22 / maxf(1.0, playback_speed))
	await tween.finished

## Apply damage/evade/block visual feedback and floating combat text
func apply_hit_feedback(damage: int, is_crit: bool, is_evaded: bool, is_blocked: bool, target_hp_after: int) -> void:
	current_hp = maxi(0, target_hp_after)
	_refresh_labels()

	if is_evaded:
		spawn_floating_text("NÉ TRÁNH!", Color(0.55, 0.88, 1.0), 1.1)
		var dodge_tween := create_tween()
		dodge_tween.tween_property(visual_root, "position:x", 0.45, 0.08)
		dodge_tween.tween_property(visual_root, "position:x", 0.0, 0.12)
		return

	var txt := "-%d" % damage
	var col := Color(1.0, 0.92, 0.85)
	var scale_mult := 1.0
	if is_crit:
		txt = "💥 CRIT -%d!" % damage
		col = Color(1.0, 0.78, 0.15)
		scale_mult = 1.45
	elif is_blocked:
		txt = "🛡️ ĐỠ -%d" % damage
		col = Color(0.68, 0.82, 0.98)

	spawn_floating_text(txt, col, scale_mult)

	# Hit flash & knockback recoil
	var hit_tween := create_tween()
	hit_tween.tween_property(visual_root, "scale", Vector3(1.18, 0.82, 1.18), 0.07)
	hit_tween.tween_property(visual_root, "scale", Vector3.ONE, 0.12)

	if current_hp <= 0 and is_alive:
		is_alive = false
		_death_tween = create_tween()
		_death_tween.tween_property(visual_root, "rotation_degrees:x", -85.0, 0.25)
		hp_label.text = "ĐÃ HẠ GỤC"
		hp_label.modulate = Color(0.55, 0.55, 0.55)

func play_revive_feedback(hp_restored: int) -> void:
	if is_instance_valid(_death_tween):
		_death_tween.kill()
	is_alive = true
	current_hp = maxi(1, hp_restored)
	visual_root.rotation_degrees = Vector3.ZERO
	_refresh_labels()
	spawn_floating_text("🔥 PHƯỢNG HOÀNG TÁI SINH +%d HP" % current_hp, Color(1.0, 0.55, 0.12), 1.35)

func apply_heal_feedback(amount: int, hp_after: int) -> void:
	current_hp = clampi(hp_after, 0, max_hp)
	_refresh_labels()
	spawn_floating_text("+%d HP" % amount, Color(0.40, 0.95, 0.65), 1.05)

func set_combat_resources(hp_value: int, mp_value: int) -> void:
	current_hp = clampi(hp_value, 0, max_hp)
	current_mp = clampi(mp_value, 0, max_mp)
	is_alive = current_hp > 0
	_refresh_labels()

func spawn_floating_text(text: String, color: Color, scale_mult: float = 1.0) -> void:
	var floater := Label3D.new()
	floater.text = text
	floater.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	floater.no_depth_test = true
	floater.modulate = color
	floater.font_size = int(28.0 * scale_mult)
	floater.outline_size = 6
	floater.position = Vector3(0.0, 2.3, 0.0)
	add_child(floater)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(floater, "position:y", 3.6, 0.75)
	tween.tween_property(floater, "modulate:a", 0.0, 0.75)
	await tween.finished
	floater.queue_free()
