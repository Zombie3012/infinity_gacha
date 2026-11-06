extends Node3D

## Isometric 3D PvE Arena & Dungeon Room Scene (Option 1)
## Uses the exact same IsometricCameraRig and UnitActor3D as the Base Lobby,
## adding Dynamic Action Camera Zoom on Skills/Crits and Turn-by-Turn Combat v2 Replay.

const UNIT_ACTOR_SCENE := preload("res://scenes/common/unit_actor_3d.tscn")

# Tactical Isometric Formation Slots (Bottom-Left Heroes vs Top-Right Enemies)
const HERO_SLOTS: Array[Vector3] = [
	Vector3(-2.2, 0.0, 1.2),  # Slot 0: Frontline Left
	Vector3(-1.0, 0.0, 2.4),  # Slot 1: Frontline Right
	Vector3(-4.2, 0.0, 2.0),  # Slot 2: Backline Left
	Vector3(-3.0, 0.0, 3.2),  # Slot 3: Backline Center
	Vector3(-1.8, 0.0, 4.4),  # Slot 4: Backline Right
]

const ENEMY_SLOTS: Array[Vector3] = [
	Vector3(2.2, 0.0, -1.2),  # Slot 0: Frontline Left
	Vector3(1.0, 0.0, -2.4),  # Slot 1: Frontline Right
	Vector3(3.6, 0.0, -2.6),  # Slot 2: Backline Center
	Vector3(2.4, 0.0, -3.8),  # Slot 3: Backline Right
	Vector3(4.6, 0.0, -1.4),  # Slot 4: Flank
]

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
var _is_replaying: bool = false
var _playback_speed: float = 1.0
var _dynamic_cam_enabled: bool = true
var _current_room: int = 1

func _ready() -> void:
	start_battle_btn.pressed.connect(_on_start_battle_pressed)
	speed_toggle_btn.pressed.connect(_on_speed_toggle_pressed)
	camera_mode_btn.pressed.connect(_on_camera_mode_pressed)
	back_base_btn.pressed.connect(_on_back_base_pressed)

	_setup_initial_formation()

func _setup_initial_formation() -> void:
	for child in units_root.get_children():
		child.queue_free()
	_actors_by_id.clear()

	var party_data: Array = []
	if GameState.heroes.size() > 0:
		for i in range(mini(5, GameState.heroes.size())):
			var h: Dictionary = GameState.heroes[i]
			party_data.append({
				"id": str(h.get("id", "hero-" + str(i))),
				"name": str(h.get("name", "Hero " + str(i + 1))),
				"side": "HERO",
				"rarity": int(h.get("rarity", 3)),
				"classCode": str(h.get("classCode", "WARRIOR")),
				"hp": int(h.get("maxHp", 1200)),
				"maxHp": int(h.get("maxHp", 1200)),
			})
	else:
		party_data = [
			{ "id": "demo-hero-1", "name": "Han Islat", "side": "HERO", "rarity": 4, "classCode": "WARRIOR", "hp": 1850, "maxHp": 1850 },
			{ "id": "demo-hero-2", "name": "Jenna", "side": "HERO", "rarity": 3, "classCode": "THIEF", "hp": 1320, "maxHp": 1320 },
			{ "id": "demo-hero-3", "name": "Eolka", "side": "HERO", "rarity": 4, "classCode": "MAGE", "hp": 1180, "maxHp": 1180 },
		]

	var enemy_data: Array = [
		{ "id": "foe-orc-1", "name": "Orc Vanguard", "side": "ENEMY", "rarity": 3, "classCode": "WARRIOR", "hp": 1500, "maxHp": 1500 },
		{ "id": "foe-shaman-2", "name": "Goblin Shaman", "side": "ENEMY", "rarity": 3, "classCode": "MAGE", "hp": 1050, "maxHp": 1050 },
		{ "id": "foe-boss-3", "name": "Floor Guardian", "side": "ENEMY", "rarity": 4, "classCode": "SPEARMAN", "hp": 2200, "maxHp": 2200 },
	]

	_spawn_side_actors(party_data, HERO_SLOTS, Vector3(1, 0, -1))
	_spawn_side_actors(enemy_data, ENEMY_SLOTS, Vector3(-1, 0, 1))

	floor_title_label.text = "🗼 Tháp Thử Thách — Tầng 1 · Phòng #%d (Isometric 3D Combat v2)" % _current_room
	turn_banner_label.text = "Đội hình sẵn sàng (%d Tướng vs %d Quái). Bấm 'Bắt Đầu Giao Tranh'!" % [party_data.size(), enemy_data.size()]

func _spawn_side_actors(units: Array, slots: Array[Vector3], face_dir: Vector3) -> void:
	for i in range(mini(units.size(), slots.size())):
		var u: Dictionary = units[i]
		var actor: UnitActor3D = UNIT_ACTOR_SCENE.instantiate()
		units_root.add_child(actor)
		actor.global_position = slots[i]
		actor.setup_combat_unit(u)
		actor.visual_root.look_at(actor.global_position + face_dir.normalized(), Vector3.UP)
		_actors_by_id[actor.unit_id] = actor

func _on_start_battle_pressed() -> void:
	if _is_replaying:
		return
	_is_replaying = true
	start_battle_btn.disabled = true
	combat_log_label.clear()
	_append_log("[b][color=#62c5fc]⚔️ Bắt đầu kết nối Engine Combat v2...[/color][/b]")

	var hero_ids: Array = []
	for h in GameState.heroes.slice(0, 5):
		var hid := str(h.get("id", ""))
		if hid != "":
			hero_ids.append(hid)

	var report: Dictionary = {}
	if hero_ids.size() > 0 and ApiClient.auth_token != "":
		var res := await ApiClient.post_req("/api/combat/v2/simulate", {
			"heroIds": hero_ids,
			"maxRounds": 20
		})
		if res["ok"] and res["data"] is Dictionary:
			report = res["data"]

	if report.is_empty():
		report = _build_local_demo_report()

	await _play_combat_v2_report(report)
	_is_replaying = false
	start_battle_btn.disabled = false
	_current_room += 1

func _play_combat_v2_report(report: Dictionary) -> void:
	# Rebuild 3D actors to match exact report units if provided
	var units_list: Array = report.get("units", [])
	if units_list.size() > 0:
		for child in units_root.get_children():
			child.queue_free()
		_actors_by_id.clear()
		var heroes_u: Array = []
		var enemies_u: Array = []
		for u in units_list:
			var initial_unit := {
				"id": u.get("id", ""),
				"name": u.get("name", "Unit"),
				"side": u.get("side", "HERO"),
				"hp": u.get("maxHp", 1000),
				"maxHp": u.get("maxHp", 1000),
				"maxMp": u.get("maxMp", 100),
			}
			if str(u.get("side", "HERO")) == "HERO":
				heroes_u.append(initial_unit)
			else:
				enemies_u.append(initial_unit)
		_spawn_side_actors(heroes_u, HERO_SLOTS, Vector3(1, 0, -1))
		_spawn_side_actors(enemies_u, ENEMY_SLOTS, Vector3(-1, 0, 1))

	var entries: Array = report.get("log", [])
	for entry in entries:
		var round_num := int(entry.get("round", 1))
		var actor_id := str(entry.get("actorId", ""))
		var actor_name := str(entry.get("actorName", "Unit"))
		var target_id := str(entry.get("targetId", ""))
		var target_name := str(entry.get("targetName", "Target"))
		var action_type := str(entry.get("action", "BASIC"))
		var skill_code := str(entry.get("skillCode", ""))
		var dmg := int(entry.get("damage", 0))
		var is_crit := bool(entry.get("crit", false))
		var is_evaded := bool(entry.get("evaded", false))
		var is_blocked := bool(entry.get("blocked", false))
		var hp_after := int(entry.get("targetHpAfter", 0))

		var actor_node: UnitActor3D = _actors_by_id.get(actor_id, null)
		var target_node: UnitActor3D = _actors_by_id.get(target_id, null)

		if action_type == "REVIVE":
			turn_banner_label.text = "Hiệp %d — 🔥 %s kích hoạt PHƯỢNG HOÀNG TÁI SINH!" % [round_num, actor_name]
			_append_log("[color=#ff9e3b]Hiệp %d: 🔥 %s hồi sinh với %d HP![/color]" % [round_num, actor_name, hp_after])
			if actor_node:
				if _dynamic_cam_enabled:
					camera_rig.focus_action_unit(actor_node.global_position, 8.2, 0.22 / _playback_speed)
				camera_rig.shake(0.3, 0.25)
				actor_node.play_revive_feedback(hp_after)
				await get_tree().create_timer(0.65 / _playback_speed).timeout
				if _dynamic_cam_enabled:
					camera_rig.focus_overview(Vector3.ZERO, 0.3 / _playback_speed)
			continue

		var is_skill := action_type == "SKILL"
		var skill_tag := (" [" + skill_code + "]") if is_skill and skill_code != "" else ""
		turn_banner_label.text = "Hiệp %d — %s ➔ %s%s" % [round_num, actor_name, target_name, skill_tag]

		if actor_node and target_node:
			# Dynamic Isometric Action Zoom on Skills or Critical Strikes
			if _dynamic_cam_enabled and (is_skill or is_crit):
				var mid_point := (actor_node.global_position + target_node.global_position) * 0.5
				camera_rig.focus_action_unit(mid_point, 8.8, 0.2 / _playback_speed)

			await actor_node.perform_attack_lunge(target_node.global_position, is_skill)
			target_node.apply_hit_feedback(dmg, is_crit, is_evaded, is_blocked, hp_after)

			if is_crit:
				camera_rig.shake(0.32, 0.22)
			elif is_skill:
				camera_rig.shake(0.18, 0.16)

			await actor_node.return_to_slot()

			if _dynamic_cam_enabled and (is_skill or is_crit):
				camera_rig.focus_overview(Vector3.ZERO, 0.28 / _playback_speed)

		var outcome_str := "-%d HP" % dmg
		if is_evaded:
			outcome_str = "NÉ TRÁNH"
		elif is_crit:
			outcome_str = "💥 CRIT -%d HP" % dmg
		elif is_blocked:
			outcome_str = "🛡️ ĐỠ ĐÒN -%d HP" % dmg

		_append_log("Hiệp %d: [b]%s[/b]%s ➔ [b]%s[/b] (%s)" % [round_num, actor_name, skill_tag, target_name, outcome_str])
		await get_tree().create_timer(0.22 / _playback_speed).timeout

	camera_rig.focus_overview(Vector3.ZERO, 0.4)
	var winner := str(report.get("winner", "HERO"))
	var rounds := int(report.get("rounds", 1))
	var total_dmg := int(report.get("totalDamage", 0))
	turn_banner_label.text = "🏆 Kết thúc sau %d hiệp — Phe thắng: %s (Tổng sát thương: %d)" % [rounds, winner, total_dmg]
	_append_log("[b][color=#66f28d]🏆 Trận đấu kết thúc! Phe thắng: %s (%d hiệp)[/color][/b]" % [winner, rounds])

func _build_local_demo_report() -> Dictionary:
	var h_keys := _actors_by_id.keys().filter(func(k): return _actors_by_id[k].side == "HERO")
	var e_keys := _actors_by_id.keys().filter(func(k): return _actors_by_id[k].side == "ENEMY")
	if h_keys.is_empty() or e_keys.is_empty():
		return { "winner": "HERO", "rounds": 1, "totalDamage": 0, "log": [] }

	var log_entries: Array = []
	var total_dmg := 0
	for r in range(1, 4):
		for hid in h_keys:
			var h_actor: UnitActor3D = _actors_by_id[hid]
			var target_id: String = e_keys[r % e_keys.size()]
			var t_actor: UnitActor3D = _actors_by_id[target_id]
			var is_skill := (r == 2)
			var is_crit := (r == 3)
			var dmg := 480 if not is_crit else 860
			t_actor.current_hp = maxi(0, t_actor.current_hp - dmg)
			total_dmg += dmg
			log_entries.append({
				"round": r,
				"actorId": hid,
				"actorName": h_actor.unit_name,
				"targetId": target_id,
				"targetName": t_actor.unit_name,
				"action": "SKILL" if is_skill else "BASIC",
				"skillCode": "CLEAVE_STRIKE" if is_skill else "",
				"damage": dmg,
				"crit": is_crit,
				"evaded": false,
				"blocked": false,
				"targetHpAfter": t_actor.current_hp
			})
		for eid in e_keys:
			var e_actor: UnitActor3D = _actors_by_id[eid]
			var target_id: String = h_keys[0]
			var t_actor: UnitActor3D = _actors_by_id[target_id]
			var dmg := 190
			t_actor.current_hp = maxi(120, t_actor.current_hp - dmg)
			log_entries.append({
				"round": r,
				"actorId": eid,
				"actorName": e_actor.unit_name,
				"targetId": target_id,
				"targetName": t_actor.unit_name,
				"action": "BASIC",
				"damage": dmg,
				"crit": false,
				"evaded": (r == 2 and eid == e_keys[0]),
				"blocked": (r == 1),
				"targetHpAfter": t_actor.current_hp
			})
	# Restore initial HP before playback starts
	for k in _actors_by_id:
		var a: UnitActor3D = _actors_by_id[k]
		a.current_hp = a.max_hp
	return {
		"winner": "HERO",
		"rounds": 3,
		"totalDamage": total_dmg,
		"log": log_entries
	}

func _append_log(bbcode_line: String) -> void:
	combat_log_label.append_text(bbcode_line + "\n")

func _on_speed_toggle_pressed() -> void:
	_playback_speed = 2.0 if _playback_speed == 1.0 else 1.0
	speed_toggle_btn.text = "⏩ Tốc Độ: %dx" % int(_playback_speed)

func _on_camera_mode_pressed() -> void:
	_dynamic_cam_enabled = not _dynamic_cam_enabled
	camera_mode_btn.text = "🎥 Action Cam: BẬT" if _dynamic_cam_enabled else "🎥 Action Cam: TẮT"

func _on_back_base_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")
