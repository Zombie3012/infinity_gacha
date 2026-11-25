extends Node3D

## Read-only playback of a server-settled private PvE encounter.
## Rewards and squad movement never depend on watching or finishing this replay.
const UNIT_ACTOR_SCENE := preload("res://scenes/common/unit_actor_3d.tscn")
const MAP_SCENE := "res://scenes/pve/pve_map.tscn"
@onready var camera_rig: IsometricCameraRig = $IsometricCameraRig
@onready var units_root: Node3D = $UnitsRoot
@onready var floor_title_label: Label = %FloorTitleLabel
@onready var turn_banner_label: Label = %TurnBannerLabel
@onready var combat_log_label: RichTextLabel = %CombatLogLabel
@onready var start_battle_btn: Button = %StartBattleBtn
@onready var speed_toggle_btn: Button = %SpeedToggleBtn
@onready var camera_mode_btn: Button = %CameraModeBtn
@onready var back_base_btn: Button = %BackBaseBtn

var _actors_by_id: Dictionary = {}
var _battle: Dictionary = {}
var _report: Dictionary = {}
var _is_replaying: bool = false
var _cancelled: bool = false
var _playback_speed: float = 1.0
var _dynamic_cam_enabled: bool = true

func _ready() -> void:
	start_battle_btn.text = "Xem diễn biến trận đấu"
	start_battle_btn.disabled = true
	back_base_btn.text = "Về bản đồ chinh phạt"
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	speed_toggle_btn.pressed.connect(_on_speed_toggle_pressed)
	camera_mode_btn.pressed.connect(_on_camera_mode_pressed)
	back_base_btn.pressed.connect(func(): SceneTransition.change_scene(MAP_SCENE, "🗺️ Đang quay về Bản Đồ PvE..."))
	_draw_formation_cells()
	PveState.battle_completed.connect(func(battle_id: String):
		if battle_id != PveState.selected_battle_id:
			_append_log("[color=#8ce6b8]Một đội khác vừa kết thúc giao chiến. Trở về map để xem chiến báo mới.[/color]")
	)
	turn_banner_label.text = "Đang tải chiến báo đã lưu..."
	if PveState.selected_battle_id.is_empty():
		turn_banner_label.text = "Chọn một chiến báo từ bản đồ để xem lại trận đấu."
		return
	PveState.polling_enabled = true
	var response: Dictionary = await ApiClient.get_req("/api/pve/battles/" + PveState.selected_battle_id.uri_encode())
	if _cancelled:
		return
	if not response.get("ok", false) or not (response.get("data") is Dictionary):
		turn_banner_label.text = "Không tải được chiến báo. Về bản đồ để thử lại."
		return
	_battle = response["data"]
	_report = _battle.get("report", {})
	if bool(_report.get("ambush", false)):
		_append_log("[color=#ffb49a]Bị phục kích: quái hành động trong pha mở màn trước hiệp 1.[/color]")
	if not _valid_report(_report):
		turn_banner_label.text = "Chiến báo chưa đủ dữ liệu để phát lại. Kết quả vẫn được giữ trên server."
		return
	_setup_actors()
	if bool(_battle.get("live", false)):
		var live = preload("res://scripts/ui/pve_live_battle_modal.gd").new()
		live.battle_id = PveState.selected_battle_id
		live.battle = _battle
		live.closed.connect(func(): SceneTransition.change_scene(MAP_SCENE, "🗺️ Đang quay về Bản Đồ PvE..."))
		$HUD.add_child(live)
		return
	start_battle_btn.disabled = false
	_show_summary()

func _exit_tree() -> void:
	_cancelled = true

static func _valid_report(report: Dictionary) -> bool:
	return report.get("log") is Array and report.get("units") is Array and report.get("initialUnits") is Array

static func formation_position(side: String, cell: int) -> Vector3:
	var row: int = clampi(cell, 0, 8) / 3
	var column: int = clampi(cell, 0, 8) % 3
	var forward := Vector3(1, 0, -1).normalized()
	var right := Vector3(1, 0, 1).normalized()
	if side == "ENEMY":
		forward = -forward
		right = -right
	var center := Vector3(-3.2, 0, 3.2) if side == "HERO" else Vector3(3.2, 0, -3.2)
	return center + forward * float(1 - row) * 1.9 + right * float(column - 1) * 1.9

func _draw_formation_cells() -> void:
	for side in ["HERO", "ENEMY"]:
		for cell in range(9):
			var marker := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(1.65, 0.04, 1.65)
			marker.mesh = mesh
			marker.position = formation_position(side, cell) + Vector3(0, 0.02, 0)
			marker.rotation.y = PI / 4.0
			var material := StandardMaterial3D.new()
			material.albedo_color = Color(0.16, 0.30, 0.42) if side == "HERO" else Color(0.40, 0.22, 0.24)
			marker.material_override = material
			add_child(marker)

func _setup_actors() -> void:
	for child in units_root.get_children():
		units_root.remove_child(child)
		child.queue_free()
	_actors_by_id.clear()
	for unit_value in _report.get("initialUnits", []):
		if not (unit_value is Dictionary):
			continue
		var unit: Dictionary = unit_value
		var actor: UnitActor3D = UNIT_ACTOR_SCENE.instantiate()
		units_root.add_child(actor)
		var side := str(unit.get("side", "HERO"))
		actor.global_position = formation_position(side, int(unit.get("slotIndex", 0)))
		var actor_data: Dictionary = unit.duplicate(true)
		var hero: Dictionary = GameState.get_hero_by_id(str(unit.get("id", "")))
		actor_data["classCode"] = str(hero.get("classCode", "WARRIOR"))
		actor_data["rarity"] = int(hero.get("rarity", 3))
		actor.setup_combat_unit(actor_data)
		var facing := Vector3(1, 0, -1) if side == "HERO" else Vector3(-1, 0, 1)
		actor.visual_root.look_at(actor.global_position + facing, Vector3.UP)
		_actors_by_id[str(unit.get("id", ""))] = actor

func _on_start_battle_pressed() -> void:
	if _is_replaying or _report.is_empty():
		return
	_is_replaying = true
	start_battle_btn.disabled = true
	combat_log_label.clear()
	if bool(_report.get("ambush", false)):
		_append_log("[color=#ffb49a]Bị phục kích: quái hành động trước hiệp 1.[/color]")
	_setup_actors()
	for entry_value in _report.get("log", []):
		if _cancelled:
			return
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var actor_id := str(entry.get("actorId", ""))
		var target_id := str(entry.get("targetId", ""))
		var actor: UnitActor3D = _actors_by_id.get(actor_id)
		var target: UnitActor3D = _actors_by_id.get(target_id)
		var action := str(entry.get("action", "BASIC"))
		var round_number := int(entry.get("round", 1))
		var heal := int(entry.get("heal", 0))
		var hp_after := int(entry.get("targetHp", 0))
		var actor_name := str(entry.get("actorName", actor.unit_name if is_instance_valid(actor) else "Hero"))
		var target_name := str(entry.get("targetName", target.unit_name if is_instance_valid(target) else "Mục tiêu"))
		if str(entry.get("actionType", "")) == "ITEM":
			if is_instance_valid(actor): actor.set_combat_resources(hp_after, int(entry.get("actorMp", actor.current_mp)))
			_append_log("%s used %s" % [_escape(actor_name), action])
		elif action == "REVIVE":
			turn_banner_label.text = "Hiệp %d · %s hồi sinh" % [round_number, actor_name]
			if is_instance_valid(actor):
				actor.play_revive_feedback(hp_after)
				actor.set_combat_resources(hp_after, int(entry.get("actorMp", actor.current_mp)))
				_spawn_floating_combat_number(actor.global_position, "✨ REVIVE +%d" % heal, Color(1.0, 0.88, 0.32), 46)
				if _dynamic_cam_enabled:
					camera_rig.focus_action_unit(actor.global_position, 8.2, 0.2 / _playback_speed)
			_append_log("[color=#ffc873]%s hồi sinh: +%d HP[/color]" % [_escape(actor_name), heal])
		else:
			turn_banner_label.text = "Phục kích · %s → %s" % [actor_name, target_name] if round_number == 0 else "Hiệp %d · %s → %s" % [round_number, actor_name, target_name]
			if heal > 0:
				if is_instance_valid(target):
					target.apply_heal_feedback(heal, hp_after)
					_spawn_floating_combat_number(target.global_position, "+%d HP" % heal, Color(0.35, 1.0, 0.52), 42)
				_append_log("%s hồi %d HP cho %s" % [_escape(actor_name), heal, _escape(target_name)])
			else:
				var skill := str(entry.get("actionType", "")) == "SKILL" or action != "BASIC"
				var critical := bool(entry.get("crit", false))
				var missed := not bool(entry.get("hit", true))
				if is_instance_valid(actor) and is_instance_valid(target):
					if _dynamic_cam_enabled and (skill or critical):
						camera_rig.focus_action_unit((actor.global_position + target.global_position) * 0.5, 8.8, 0.16 / _playback_speed)
					await actor.perform_attack_lunge(target.global_position, skill, _playback_speed)
					if _cancelled:
						return
					var dmg_val := int(entry.get("damage", 0))
					target.apply_hit_feedback(dmg_val, critical, missed, bool(entry.get("blocked", false)), hp_after)
					if missed:
						_spawn_floating_combat_number(target.global_position, "💨 NÉ!", Color(0.65, 0.88, 1.0), 38)
					elif critical:
						_spawn_floating_combat_number(target.global_position, "💥 CRIT -%d" % dmg_val, Color(1.0, 0.78, 0.18), 52)
					else:
						_spawn_floating_combat_number(target.global_position, "-%d" % dmg_val, Color(1.0, 0.38, 0.38), 40)
					if _dynamic_cam_enabled and critical:
						camera_rig.shake(0.2, 0.15)
					await actor.return_to_slot(_playback_speed)
					if _cancelled:
						return
				var outcome := "Né tránh" if missed else "-%d HP" % int(entry.get("damage", 0))
				_append_log("Hiệp %d · %s → %s: %s%s" % [round_number, _escape(actor_name), _escape(target_name), "CRIT " if critical else "", outcome])
			if is_instance_valid(actor):
				var prev_mp := actor.current_mp
				var next_mp := int(entry.get("actorMp", actor.current_mp))
				actor.set_combat_resources(int(entry.get("actorHp", actor.current_hp)), next_mp)
				if next_mp > prev_mp:
					_spawn_floating_combat_number(actor.global_position + Vector3(0.4, 0.0, 0.0), "+%d MP" % (next_mp - prev_mp), Color(0.42, 0.78, 1.0), 34)
		await get_tree().create_timer(0.25 / _playback_speed).timeout
		if _cancelled:
			return
		if _dynamic_cam_enabled:
			camera_rig.focus_overview(Vector3.ZERO, 0.2 / _playback_speed)
	for unit in _report.get("units", []):
		var actor: UnitActor3D = _actors_by_id.get(str(unit.get("id", "")))
		if is_instance_valid(actor):
			actor.set_combat_resources(int(unit.get("hp", 0)), int(unit.get("mp", 0)))
	_is_replaying = false
	start_battle_btn.disabled = false
	start_battle_btn.text = "Phát lại chiến báo"
	camera_rig.focus_overview(Vector3.ZERO, 0.3)
	_show_summary()

func _show_summary() -> void:
	var settlement: Dictionary = _battle.get("settlement", {})
	var result := {"HERO": "CHIẾN THẮNG", "ENEMY": "THẤT BẠI", "DRAW": "HÒA"}
	var outcome := str(result.get(str(_report.get("winner", "DRAW")), "KẾT THÚC"))
	floor_title_label.text = "TẦNG %d · %s · %d HIỆP" % [int(settlement.get("floor", 1)), outcome, int(_report.get("rounds", 0))]
	turn_banner_label.text = "%s · +%d Silver · +%d EXP/Hero" % [outcome,
		int(settlement.get("silverReward", 0)), int(settlement.get("heroExpReward", 0))]
	if bool(settlement.get("bossCleared", false)):
		_append_log("[color=#8ce6b8]Boss đã bị hạ. Đã mở tầng %d; các đội đã rời map.[/color]" % int(settlement.get("nextFloor", 1)))
	for death in settlement.get("deaths", []):
		_append_log("[color=#ffad98]%s · %s[/color]" % [_escape(str(death.get("name", "Hero"))),
			"Tử trận; trang bị rơi. Hồi sinh tại Sử Điện bằng Ngọc hồi sinh 7★."])
	_append_log("Kết quả đã được lưu. Bạn có thể trở về map bất cứ lúc nào.")
	if GameState.is_logged_in():
		var chat_script = load("res://scripts/ui/chat_panel_modal.gd")
		var share_msg: String = chat_script.format_battle_share(_battle, _report)
		await ApiClient.post_req("/api/chat/world", {"body": share_msg})

static func _escape(value: String) -> String:
	return value.replace("[", "[lb]")

var _floating_numbers_spawned: int = 0

func _spawn_floating_combat_number(world_pos: Vector3, text_str: String, color: Color, font_size: int = 40) -> void:
	if not is_inside_tree():
		return
	_floating_numbers_spawned += 1
	var lbl := Label3D.new()
	lbl.text = text_str
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = font_size
	lbl.outline_size = 6
	lbl.pixel_size = 0.018
	lbl.modulate = color
	lbl.position = world_pos + Vector3(randf_range(-0.35, 0.35), 2.1, 0.0)
	add_child(lbl)
	var dur := maxf(0.15, 0.85 / maxf(0.1, _playback_speed))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y + 1.8, dur).set_ease(Tween.EASE_OUT)
	tw.tween_property(lbl, "modulate:a", 0.0, dur).set_delay(dur * 0.3)
	tw.finished.connect(lbl.queue_free, CONNECT_ONE_SHOT)

func _append_log(value: String) -> void:
	combat_log_label.append_text(value + "\n")

func _on_speed_toggle_pressed() -> void:
	_playback_speed = 2.0 if _playback_speed == 1.0 else 4.0 if _playback_speed == 2.0 else 1.0
	speed_toggle_btn.text = "Tốc độ: ×%d" % int(_playback_speed)

func _on_camera_mode_pressed() -> void:
	_dynamic_cam_enabled = not _dynamic_cam_enabled
	camera_mode_btn.text = "Camera động: " + ("BẬT" if _dynamic_cam_enabled else "TẮT")
