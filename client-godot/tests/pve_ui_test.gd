extends Node

## Engine-level regression checks: runs real scenes and signals without any network calls.
var _checks: int = 0
var _failures: int = 0

func expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("PVE TEST: " + description)

func _ready() -> void:
	var watchdog := get_tree().create_timer(25.0)
	watchdog.timeout.connect(func(): push_error("PvE UI tests timed out"); get_tree().quit(1))
	await get_tree().process_frame
	await _run()
	print("PVE_UI_TESTS: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)

func _run() -> void:
	PveState.polling_enabled = false
	var map_scene: PackedScene = load("res://scenes/pve/pve_map.tscn")
	var map_screen: Control = map_scene.instantiate()
	add_child(map_screen)
	await get_tree().process_frame
	expect(map_screen._tiles.size() == 144, "Map creates exactly 144 cells")
	expect(map_screen._deploy.disabled and map_screen._enter.disabled, "Disconnected map cannot issue commands")
	GameState.heroes = []
	for index in range(6):
		GameState.heroes.append({"id": "ui-hero-%d" % index, "name": "Hero %d" % index, "rarity": 3, "level": 1,
			"state": "HEALTHY", "classCode": "MAGE", "hp": 500, "maxHp": 500,
			"skills": [{"code": "FIRE", "name": "Fire", "isUnlocked": true}, {"code": "ICE", "name": "Ice", "isUnlocked": true}]})
	var tiles: Array = []
	for index in range(144):
		tiles.append({"id": index, "x": index % 12, "y": index / 12, "kind": "CAMP" if index == 0 else "UNKNOWN"})
	PveState.snapshot = {"map": {"id": "ui-map", "floor": 2, "status": "ACTIVE", "tiles": tiles}, "food": 200,
		"parties": [{"id": "ui-party", "name": "Team", "members": [{"heroId": "ui-hero-0"}]}], "events": [],
		"squads": [{"id": "ui-squad", "partyId": "ui-party", "name": "Team", "status": "IDLE", "x": 0, "y": 0, "route": [], "leaderHeroId": "ui-hero-0", "autoExplore": false,
			"nextStepAt": null, "lastBattleId": null,
			"plan": {"members": [{"heroId": "ui-hero-0", "slotIndex": 0}]}}]}
	PveState.connected = true
	PveState.snapshot_changed.emit()
	expect(map_screen._tiles[0].get_children().any(func(child): return child is TextureRect and child.texture != null), "Squad leader's Hero model appears on its server position")
	expect(not map_screen._auto.disabled and map_screen._auto.text.contains("Bật"), "Auto exploration is available for an idle squad")
	PveState.snapshot["squads"].append({"id": "ui-squad-2", "partyId": "other", "name": "Other", "status": "IDLE", "x": 0, "y": 0,
		"route": [], "nextStepAt": null, "lastBattleId": null, "leaderHeroId": "ui-hero-1", "autoExplore": true, "plan": {"members": [{"heroId": "ui-hero-1", "slotIndex": 0}]}})
	PveState.snapshot_changed.emit()
	expect(map_screen._tiles[0].get_children().filter(func(child): return child is TextureRect and child.texture != null).size() == 2, "Overlapping squads each retain their leader portrait")
	PveState.snapshot["squads"].pop_back()
	PveState.snapshot_changed.emit()
	expect(map_screen._tiles[143].text == "?", "Fog does not disclose unknown nodes")
	expect(map_screen._report_rows.is_empty(), "Null battle identifiers do not create fake reports")
	expect(map_screen._deploy.disabled and map_screen._edit.disabled, "A deployed party cannot be redeployed or edited")
	expect(not map_screen._recall.disabled, "An idle deployed squad can be recalled")
	var victory_notice: Dictionary = PveState._event_notice("BATTLE_COMPLETED", {"squadId": "ui-squad", "winner": "HERO", "silverReward": 12, "heroExpReward": 5})
	expect(str(victory_notice.get("message", "")).contains("Team") and str(victory_notice.get("message", "")).contains("12 Silver"), "Battle notices identify the squad and committed rewards")
	expect(bool(PveState._event_notice("SQUAD_EXHAUSTED", {"squadId": "ui-squad"}).get("error", false)), "Exhaustion creates a visible warning rather than a silent idle squad")
	expect(str(PveState._event_notice("MAP_CLEARED", {"floor": 2, "nextFloor": 3}).get("message", "")).contains("tầng 3"), "Boss notification points to explicit next-floor entry")
	PveState.snapshot["squads"][0]["status"] = "FIGHTING"
	PveState.snapshot_changed.emit()
	expect(map_screen._recall.disabled, "Fighting squad cannot be recalled")
	expect(map_screen._tiles.all(func(button): return button.disabled), "Fighting squad cannot receive movement orders")
	PveState.connected = false
	PveState.command_changed.emit()
	expect(map_screen._tiles.all(func(button): return button.disabled), "Disconnect disables movement controls")
	PveState.snapshot["squads"] = []
	PveState.connected = true
	map_screen.queue_free()
	await get_tree().process_frame

	var editor_script: Script = load("res://scripts/ui/pve_party_editor.gd")
	var editor: Control = editor_script.new()
	editor.configure({})
	add_child(editor)
	await get_tree().process_frame
	expect(editor._grid.get_child_count() == 9, "Party editor renders a nine-cell formation")
	for index in range(6):
		editor._hero_checks["ui-hero-%d" % index].button_pressed = true
	expect(editor._hero_ids.size() == 5, "Selecting a sixth Hero does not expand the party")
	expect(not editor._hero_checks["ui-hero-5"].button_pressed, "Rejected sixth checkbox is reset")
	expect(editor._slots.has(8), "Five-Hero default formation uses the back row")
	editor._focused_hero = "ui-hero-0"
	editor._render_skills()
	editor._move_skill(1, -1)
	expect(editor._skill_orders["ui-hero-0"][0] == "ICE", "Skill order can be changed before deployment")
	editor._name_input.text = "Engine Test Team"
	var captured: Dictionary = {}
	editor.saved.connect(func(_party_id: String, payload: Dictionary): captured["payload"] = payload)
	editor._on_save()
	expect(captured.has("payload"), "Saving the editor emits a configuration")
	if captured.has("payload"):
		expect(captured["payload"]["heroIds"].size() == 5, "Editor payload contains five Hero memberships")
		expect(captured["payload"]["plan"]["members"].size() == 5, "Editor payload contains five formation positions")
		expect(captured["payload"]["plan"]["members"].map(func(member): return int(member["slotIndex"])).max() == 8, "Payload retains the nine-slot layout")
	var draft: Dictionary = captured.get("payload", {}).duplicate(true)
	editor.set_busy(true)
	expect(not editor._name_input.editable and editor._save_button.disabled, "In-flight saves freeze the draft")
	expect(editor._hero_checks.values().all(func(check): return check.disabled), "In-flight saves freeze Hero selection")
	editor.show_error("Server rejected the name", false)
	expect(editor._name_input.editable and not editor._save_button.disabled, "Definitive errors unlock the existing draft")
	expect(not editor._hero_checks["ui-hero-0"].disabled, "Original selectable Heroes are restored after a failed save")
	editor.show_error("Connection interrupted", true)
	expect(editor._retry_button.visible and editor._save_button.disabled, "Unconfirmed saves expose retry without allowing a second draft")
	expect(editor._name_input.text == draft.get("name"), "Retry preserves the party name")
	expect(editor._hero_ids == draft.get("heroIds"), "Retry preserves Hero membership")
	expect(editor._skill_orders["ui-hero-0"][0] == "ICE", "Retry preserves tactical skill order")
	editor.set_busy(false)
	GameState.heroes[0]["name"] = "A very long Hero name that must not push the editor outside its viewport"
	GameState.heroes[0]["skills"] = []
	for index in range(20):
		GameState.heroes[0]["skills"].append({"code": "SKILL_%d" % index, "name": "Skill %d" % index, "isUnlocked": true})
	editor._render_skills()
	await get_tree().process_frame
	await get_tree().process_frame
	expect(editor._skill_box.get_parent() is ScrollContainer, "Long skill lists stay inside a scrollable panel")
	expect(editor.get_child(1).get_child(0).size.x <= 1280, "Long Hero names do not expand the editor beyond desktop width")
	editor.queue_free()
	await get_tree().process_frame

	PveState.selected_battle_id = ""
	var arena_scene: PackedScene = load("res://scenes/pve/isometric_pve_arena_3d.tscn")
	var arena: Node3D = arena_scene.instantiate()
	add_child(arena)
	await get_tree().process_frame
	expect(arena.start_battle_btn.disabled, "Arena without a server report cannot invent a battle")
	var hero_a := {"id": "ui-hero-0", "name": "Hero 0", "side": "HERO", "slotIndex": 0, "hp": 250, "maxHp": 500, "mp": 100, "maxMp": 100, "alive": true}
	var hero_b := {"id": "ui-hero-1", "name": "Hero 1", "side": "HERO", "slotIndex": 8, "hp": 500, "maxHp": 500, "mp": 100, "maxMp": 100, "alive": true}
	var foe := {"id": "enemy", "name": "Enemy", "side": "ENEMY", "slotIndex": 4, "hp": 100, "maxHp": 100, "mp": 0, "maxMp": 0, "alive": true}
	var final_a := hero_a.duplicate(); final_a["hp"] = 300; final_a["mp"] = 85
	var final_b := hero_b.duplicate(); final_b["mp"] = 80
	var final_foe := foe.duplicate(); final_foe["hp"] = 0; final_foe["alive"] = false
	arena._report = {"winner": "HERO", "rounds": 2, "totalDamage": 150,
		"initialUnits": [hero_a, hero_b, foe], "units": [final_a, final_b, final_foe], "log": [
			{"round": 1, "actorId": "ui-hero-0", "targetId": "enemy", "action": "FIRE", "actionType": "SKILL", "damage": 100, "targetHp": 0, "actorHp": 250, "actorMp": 80, "crit": true, "hit": true},
			{"round": 1, "actorId": "enemy", "targetId": "enemy", "action": "REVIVE", "heal": 50, "targetHp": 50, "actorHp": 50, "actorMp": 0},
			{"round": 1, "actorId": "ui-hero-1", "targetId": "ui-hero-0", "action": "HEAL", "actionType": "HEAL", "heal": 50, "targetHp": 300, "actorHp": 500, "actorMp": 80},
			{"round": 2, "actorId": "ui-hero-0", "targetId": "enemy", "action": "BASIC", "damage": 50, "targetHp": 0, "actorHp": 300, "actorMp": 85, "hit": true},
		]}
	arena._battle = {"settlement": {"floor": 2, "silverReward": 50, "heroExpReward": 20, "masterExpReward": 20}}
	arena._playback_speed = 100.0
	arena._dynamic_cam_enabled = false
	await arena._on_start_battle_pressed()
	expect(arena._actors_by_id.size() == 3, "Replay instantiates exactly the report's units")
	expect(arena._actors_by_id["ui-hero-0"].current_hp == 300, "Replay respects targetHp and healing")
	expect(arena._actors_by_id["ui-hero-0"].current_mp == 85, "Replay restores final MP from the report")
	expect(not arena._actors_by_id["enemy"].is_alive, "Replay ends with the authoritative death state")
	expect(arena.combat_log_label.get_parsed_text().contains("hồi sinh"), "Revive is represented in playback")
	expect(arena._actors_by_id["ui-hero-1"].home_position == arena.formation_position("HERO", 8), "Back-row Hero occupies the ninth formation cell")
	expect(not arena.start_battle_btn.disabled, "A completed replay can be watched again")
	PveState.battle_completed.emit("another-squad-report")
	expect(arena.combat_log_label.get_parsed_text().contains("Một đội khác"), "An open replay can notify the player about another squad's battle")
	arena.queue_free()
	await get_tree().process_frame
	expect(not GameState.is_hero_pve_deployed({"pveDeployment": null}), "Null deployment is an available Hero")
	expect(GameState.is_hero_pve_deployed({"pveDeployment": {"squadId": "squad"}}), "Reserved Hero DTO is recognized as deployed")
	GameState.heroes[0]["pveDeployment"] = {"squadId": "squad"}
	var dorm: Control = load("res://scripts/ui/dormitory_modal.gd").new()
	add_child(dorm)
	await get_tree().process_frame
	expect(not dorm._hero_browser.all_items.any(func(hero): return str(hero.get("id", "")) == "ui-hero-0"), "Dormitory excludes deployed Heroes from rest and feed selection")
	expect(dorm._hero_browser.extra_action_box.get_child_count() == 3, "Preconfigured facility action buttons remain attached and visible")
	expect(dorm._hero_browser.header_title_label.text.contains("Nghỉ"), "Browser initialization preserves a preconfigured facility heading")
	dorm.queue_free()
	await get_tree().process_frame
	PveState.pending_command = {"masterId": "old-account", "key": "pending"}
	PveState.selected_battle_id = "old-report"
	PveState.deactivate()
	expect(PveState.snapshot.is_empty() and PveState.pending_command.is_empty(), "Account reset clears transient map and command state")
	expect(PveState.selected_battle_id.is_empty() and not PveState.connected, "Account reset cannot reopen another account's report")
