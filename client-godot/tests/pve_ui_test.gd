extends Node

## Engine-level regression checks: runs real scenes and signals without any network calls.
var _checks: int = 0
var _failures: int = 0

class RecoveryFixture extends "res://scripts/ui/recovery_center_modal.gd":
	func refresh_facility_data() -> void:
		_update_hero_list(GameState.heroes)

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
	var tower_scene: PackedScene = load("res://scenes/pve/pve_tower.tscn")
	var tower_screen: Control = tower_scene.instantiate()
	PveState.snapshot = {"currentFloor": 3, "food": 120, "teleportStones": 2, "map": null}
	add_child(tower_screen)
	await get_tree().process_frame
	tower_screen._render()
	expect(tower_screen._floors_box.get_child_count() == 100, "Tower exterior renders 100 preview floors")
	tower_screen._selected_floor = 1
	tower_screen._render()
	expect(not tower_screen._enter_btn.disabled and tower_screen._enter_btn.text.contains("VÀO LẠI TẦNG 1"), "Cleared floor can be re-selected")
	expect(tower_screen._detail_info.text.contains("Cho phép rút lui: Có") and tower_screen._detail_info.text.contains("Chi phí tham gia"), "Normal floor shows retreat allowed and entry cost")
	expect(tower_screen._detail_objectives.text.contains("Hạ Boss") and tower_screen._detail_objectives.text.contains("Toàn đội còn sống"), "Objectives list 5-star floor clear goals")
	tower_screen._selected_floor = 5
	tower_screen._render()
	expect(tower_screen._enter_btn.disabled and tower_screen._detail_title.text.contains("ĐẶC BIỆT") and tower_screen._detail_info.text.contains("Cho phép rút lui: Không"), "Special floor 5 is highlighted and disallows retreat")
	tower_screen.queue_free()
	await get_tree().process_frame

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
	PveState.snapshot["devToolsEnabled"] = true
	PveState.snapshot["teleportStones"] = 1
	PveState.snapshot["squads"][0]["canRecall"] = false
	PveState.snapshot["squads"][0]["recallBlockReason"] = "ERR_PVE_RECALL_LOCKED"
	PveState.snapshot["map"]["recallPolicy"] = "UNTIL_COMPLETE"
	map_screen._render_state()
	expect(map_screen._recall.disabled and not map_screen._auto.disabled, "Floor recall lock does not disable auto commands")
	expect(map_screen._stone.disabled and map_screen._reset_tower.visible, "Locked floor blocks stone placement while dev reset remains available")
	PveState.snapshot["map"]["recallPolicy"] = "FREE"
	PveState.snapshot["squads"][0]["canRecall"] = true
	PveState.snapshot["squads"][0]["atRecallPoint"] = true
	PveState.snapshot["squads"][0]["pursued"] = true
	map_screen._render_state()
	expect(not map_screen._recall.disabled and map_screen._stone.disabled, "A point on an ordinary floor permits pursued recall without another stone")
	PveState.snapshot["devToolsEnabled"] = false
	PveState.snapshot["squads"][0].erase("canRecall")
	PveState.snapshot["squads"][0].erase("atRecallPoint")
	PveState.snapshot["squads"][0].erase("pursued")
	map_screen._render_state()
	expect(not map_screen._reset_tower.visible, "Production server capability hides the developer reset")
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
	PveState.connected = true
	PveState.snapshot["squads"][0]["status"] = "IDLE"
	PveState.snapshot["squads"][0]["areaId"] = "region:0"
	PveState.snapshot["squads"][0]["pursued"] = true
	var region_tiles: Array = []
	for index in range(400):
		region_tiles.append({"id": index, "x": index % 20, "y": index / 20, "kind": "EMPTY"})
	PveState.snapshot["areas"] = [
		{"id": "floor", "name": "Tầng", "parentAreaId": null, "width": 12, "height": 12, "tiles": tiles},
		{"id": "region:0", "name": "Khu vực", "parentAreaId": "floor", "width": 20, "height": 20, "metersPerTile": 50, "tiles": region_tiles,
			"portals": [{"id": "exit", "x": 0, "y": 0, "label": "Ra ngoài"}]}]
	PveState.snapshot["objective"] = {"type": "DEFEAT_BOSS", "progress": 0, "required": 1, "status": "ACTIVE"}
	PveState.snapshot_changed.emit()
	expect(map_screen._tiles.size() == 400 and map_screen._grid.columns == 20, "Detail map changes dimensions to 20 by 20")
	expect(map_screen._breadcrumbs.get_child_count() == 2, "Detail map shows parent navigation")
	expect(map_screen._portal_actions.get_child_count() == 1, "Standing at a portal provides an explicit action")
	expect(map_screen._recall.disabled and not map_screen._auto.disabled, "Pursuit blocks recall while auto remains controllable")
	map_screen._view_area_id = "floor"
	map_screen._render_state()
	expect(map_screen._tiles.all(func(button): return button.disabled), "Browsing another area cannot issue movement there")
	map_screen._toggle_party_drawer(false)
	expect(not map_screen._party_drawer.visible, "Party drawer can be collapsed")
	map_screen._toggle_report_drawer(true)
	expect(map_screen._report_drawer.visible, "Report drawer can be expanded")
	map_screen._set_map_zoom(1.25)
	expect(is_equal_approx(map_screen._map_zoom, 1.25) and map_screen._zoom_label.text == "125%", "Map zoom updates zoom state and label")
	map_screen._set_map_zoom(1.0)
	PveState.snapshot["areas"].append({"id": "interior:0", "name": "Công trình", "parentAreaId": "region:0", "width": 8, "height": 8, "metersPerTile": 5, "tiles": []})
	PveState.snapshot["squads"][0]["areaId"] = "interior:0"
	PveState.snapshot_changed.emit()
	expect(map_screen._tiles.size() == 64 and map_screen._breadcrumbs.get_child_count() == 3, "Selected squad entering a building follows to its 8 by 8 interior")
	PveState.snapshot["squads"] = []
	PveState.connected = true
	map_screen.queue_free()
	await get_tree().process_frame

	var editor_script: Script = load("res://scripts/ui/pve_party_editor.gd")
	var items_modal: Control = load("res://scripts/ui/pve_field_items_modal.gd").new()
	items_modal.squad_id = "ui-squad"
	PveState.snapshot["loadouts"] = [{"squadId": "ui-squad", "heroId": "ui-hero-0", "config": {"slots": [{"itemId": "MEDICINE", "quantity": 2}, null, null, null, null]}}]
	add_child(items_modal)
	await get_tree().process_frame
	expect(items_modal.find_children("*", "ProgressBar", true, false).size() == 2, "Field items modal displays HP and MP progress bars")
	items_modal.queue_free()
	var live_modal: Control = load("res://scripts/ui/pve_live_battle_modal.gd").new()
	live_modal.battle_id = "ui-battle"
	live_modal.battle = {"live": true, "deadline": 0, "report": {"units": [{"id": "ui-hero-0", "name": "Hero 0", "side": "HERO", "slotIndex": 0, "hp": 300, "maxHp": 500, "mp": 50, "maxMp": 100, "alive": true}], "log": [], "pending": {}}}
	add_child(live_modal)
	await get_tree().process_frame
	expect(live_modal._clock_bar != null and live_modal.find_children("*", "GridContainer", true, false).size() == 2, "Live battle modal renders turn bar and both formation grids")
	live_modal.queue_free()
	await get_tree().process_frame
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
	expect(arena._floating_numbers_spawned >= 3, "Arena spawns floating combat numbers for crit, revive, heal, and damage")
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
	expect(dorm._hero_browser.extra_action_box.get_child_count() == 5, "Preconfigured facility action buttons remain attached and visible")
	expect(dorm._hero_browser.header_title_label.text.contains("Nghỉ"), "Browser initialization preserves a preconfigured facility heading")
	dorm.queue_free()
	await get_tree().process_frame
	var recovery: Control = RecoveryFixture.new()
	var injured := {"id": "medical-alive", "name": "Injured", "state": "INJURED", "hp": 30, "maxHp": 100}
	var dead := {"id": "medical-dead", "name": "Dead", "state": "DEAD", "hp": 0, "maxHp": 100}
	var disabled := {"id": "medical-disabled", "name": "Disabled", "state": "DISABLED", "hp": 0, "maxHp": 100}
	GameState.heroes = [injured, dead, disabled, GameState.heroes[0]]
	add_child(recovery)
	await get_tree().process_frame
	expect(recovery.browser.all_items.size() == 1 and recovery.browser.all_items[0]["id"] == "medical-alive", "Recovery excludes dead, disabled and deployed Heroes")
	recovery._on_auto_select_pressed()
	expect(recovery.browser.get_selected_items().size() == 1, "Recovery auto-select chooses only a living eligible Hero")
	injured["state"] = "DEAD"
	injured["hp"] = 0
	EventBus.heroes_updated.emit(GameState.heroes)
	expect(recovery.browser.all_items.is_empty() and recovery.browser.get_selected_items().is_empty(), "A new death removes the Hero and stale selection from an open Recovery Center")
	expect(recovery.browser.confirm_action_btn.disabled, "Recovery treatment is disabled after the selected Hero dies")
	await recovery._finish_treatment_batch({"admitted": ["hero-a", "hero-b"], "queued": ["hero-c"], "errors": []})
	expect(recovery.banner_label.text.contains("2 Hero vào giường") and recovery.banner_label.text.contains("1 Hero vào hàng chờ"), "Treatment result counts API arrays without casting them to int")
	await recovery._finish_treatment_batch({"admitted": [], "queued": [], "errors": [{"heroId": "hero-d", "message": "Hero đã tử trận"}]})
	expect(recovery.banner_label.text.contains("0 Hero vào giường") and recovery.banner_label.text.contains("Hero đã tử trận"), "A failed batch shows the server reason after refreshing")
	await recovery._finish_treatment_batch({"healed": ["hero-a", "hero-b"], "errors": []}, true)
	expect(recovery.banner_label.text.contains("100% HP cho 2 Hero") and recovery.banner_label.text.contains("2 Bình Thuốc"), "Quick Heal reads healed IDs and the one-medicine-per-success contract")
	await recovery._finish_treatment_batch({"healed": ["hero-a"], "errors": [{"heroId": "hero-b", "message": "Thiếu thuốc"}]}, true)
	expect(recovery.banner_label.text.contains("1 Bình Thuốc") and recovery.banner_label.text.contains("Thiếu thuốc"), "Partial Quick Heal counts only successful treatments and retains failures")
	recovery.queue_free()
	await get_tree().process_frame
	PveState.pending_command = {"masterId": "old-account", "key": "pending"}
	PveState.selected_battle_id = "old-report"
	PveState.deactivate()
	expect(PveState.snapshot.is_empty() and PveState.pending_command.is_empty(), "Account reset clears transient map and command state")
	expect(PveState.selected_battle_id.is_empty() and not PveState.connected, "Account reset cannot reopen another account's report")
