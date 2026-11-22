extends Node

## Launched by scripts/test-godot-pve.mjs --integration with a disposable account.
## Uses real HTTP and the real one-second movement clock; never calls the demo login.
var _checks: int = 0
var _failed: bool = false
var _hero_ids: Array = []

func expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("PVE NETWORK: " + description)

func wait_until(predicate: Callable, description: String, timeout: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	var passed: bool = predicate.call()
	expect(passed, description)
	return passed

func _ready() -> void:
	if OS.get_environment("PVE_TEST_API_URL").is_empty():
		push_error("Use npm run test:godot:pve -- --integration to prepare fixtures.")
		get_tree().quit(1)
		return
	ApiClient.base_url = OS.get_environment("PVE_TEST_API_URL")
	ApiClient.set_auth_token(OS.get_environment("PVE_TEST_ACCESS_TOKEN"))
	GameState.master_id = OS.get_environment("PVE_TEST_MASTER_ID")
	PveState.message_changed.connect(func(message: String, is_error: bool):
		if is_error:
			print("PVE_NETWORK_MESSAGE: " + message)
	)
	_hero_ids = JSON.parse_string(OS.get_environment("PVE_TEST_HERO_IDS"))
	await get_tree().process_frame
	await _run()
	print("PVE_NETWORK_TESTS: %d checks, %s" % [_checks, "FAILED" if _failed else "PASS"])
	get_tree().quit(1 if _failed else 0)

func _run() -> void:
	expect(await GameState.refresh_profile(), "Authenticated profile is loaded")
	expect(await GameState.refresh_heroes(), "Live Hero collection is loaded")
	var map_screen: Control = load("res://scenes/pve/pve_map.tscn").instantiate()
	get_tree().root.add_child(map_screen)
	get_tree().current_scene = map_screen # Keep this test controller alive across replay scene changes.
	if not await wait_until(func(): return PveState.connected and PveState.snapshot.get("map") is Dictionary, "Map UI loads a persisted map"):
		return
	expect(map_screen._tiles.size() == 144, "Live map renders 12 by 12 cells")
	var party_ids: Array[String] = []
	for index in range(2):
		map_screen._open_editor({})
		await get_tree().process_frame
		var editor: Control = map_screen._editor
		var editor_ref: WeakRef = weakref(editor)
		editor._name_input.text = "Network Squad %d" % index
		editor._hero_checks[str(_hero_ids[index])].button_pressed = true
		editor._save_button.pressed.emit()
		if not await wait_until(func(): return editor_ref.get_ref() == null, "Party editor saves through the idempotent API"):
			return
		party_ids.append(PveState.selected_party_id)
		map_screen._deploy.pressed.emit()
		if not await wait_until(func(): return PveState.active_squads().size() == index + 1 and not PveState.command_busy, "Party deploys through the map UI"):
			return
	var squads: Array = PveState.active_squads()
	var first_id := str(squads[0]["id"])
	var second_id := str(squads[1]["id"])
	PveState.selected_squad_id = second_id
	map_screen._render_state()
	map_screen._auto.pressed.emit()
	if not await wait_until(func(): return bool(PveState.squad_by_id(second_id).get("autoExplore", false)) and not PveState.command_busy, "Auto button enables exploration through the server"):
		return
	map_screen._auto.pressed.emit()
	if not await wait_until(func(): return not bool(PveState.squad_by_id(second_id).get("autoExplore", true)) and not PveState.command_busy, "Auto button stops the squad's route"):
		return
	PveState.selected_squad_id = first_id
	map_screen._render_state()
	map_screen._tiles[1].pressed.emit()
	if not await wait_until(func(): return str(PveState.squad_by_id(first_id).get("status", "")) == "MOVING", "Clicking a frontier cell starts movement"):
		return
	expect(int(PveState.squad_by_id(first_id).get("x", -1)) == 0, "Movement is not an immediate client teleport")
	if not await wait_until(func(): return int(PveState.squad_by_id(first_id).get("x", -1)) == 1, "Server clock settles the resource arrival"):
		return
	await wait_until(func(): return int(GameState.materials.get("WOOD", 0)) == 23, "Resource reward refreshes the inventory")
	map_screen._tiles[2].pressed.emit()
	await wait_until(func(): return str(PveState.squad_by_id(first_id).get("status", "")) == "MOVING", "Second movement order is accepted")
	if not await wait_until(func(): return not PveState.optional_id(PveState.squad_by_id(first_id).get("lastBattleId")).is_empty(), "Encounter auto-resolves and produces a report"):
		return
	var report_id: String = PveState.optional_id(PveState.squad_by_id(first_id).get("lastBattleId"))
	expect(map_screen._status.text.contains("chiến thắng"), "An auto battle produces a visible map notification")
	var response: Dictionary = await ApiClient.get_req("/api/pve/battles/" + report_id)
	expect(response.get("ok", false) and str(response.get("data", {}).get("report", {}).get("winner", "")) == "HERO", "Report contains the server's victory")
	PveState.selected_squad_id = second_id
	map_screen._render_state()
	map_screen._tiles[1].pressed.emit()
	await wait_until(func(): return not PveState.command_busy and str(PveState.squad_by_id(second_id).get("status", "")) == "MOVING", "Another squad can receive an independent order")
	map_screen._watch_report(report_id)
	if not await wait_until(func(): return get_tree().current_scene is Node3D and not get_tree().current_scene.start_battle_btn.disabled, "Battle report opens in the 3D arena"):
		return
	var arena: Node3D = get_tree().current_scene
	arena._playback_speed = 4.0
	arena.start_battle_btn.pressed.emit()
	await wait_until(func(): return int(PveState.squad_by_id(second_id).get("x", -1)) == 1, "Other squad continues moving while a report is open")
	await wait_until(func(): return not arena._is_replaying, "Real server log completes playback")
	arena.back_base_btn.pressed.emit()
	if not await wait_until(func(): return get_tree().current_scene is Control and get_tree().current_scene.name == "PveMap", "Replay returns to the strategic map"):
		return
	map_screen = get_tree().current_scene
	await wait_until(func(): return PveState.connected and not PveState.command_busy, "Map state survives the scene transition")
	map_screen._watch_report(report_id)
	if not await wait_until(func(): return get_tree().current_scene is Node3D and not get_tree().current_scene.start_battle_btn.disabled, "Saved report can be reopened without starting another encounter"):
		return
	arena = get_tree().current_scene
	arena._playback_speed = 1.0
	arena.start_battle_btn.pressed.emit()
	await get_tree().create_timer(0.05).timeout
	expect(arena._is_replaying, "Cancellation happens during an active replay")
	arena.back_base_btn.pressed.emit()
	if not await wait_until(func(): return get_tree().current_scene is Control and get_tree().current_scene.name == "PveMap", "Player can leave midway through playback"):
		return
	await get_tree().create_timer(1.0).timeout
	map_screen = get_tree().current_scene
	expect(PveState.connected and PveState.active_squads().size() == 2, "Leaving replay preserves both deployed squads")
	PveState.selected_squad_id = first_id
	map_screen._render_state()
	map_screen._tiles[3].pressed.emit()
	if not await wait_until(func(): return str(PveState.snapshot.get("map", {}).get("status", "")) == "CLEARED", "Boss victory completes the map"):
		return
	expect(PveState.active_squads().is_empty(), "Boss victory withdraws every surviving squad")
	map_screen._enter.pressed.emit()
	await wait_until(func(): return int(PveState.snapshot.get("map", {}).get("floor", 0)) == 2, "Player explicitly enters the next floor")
	PveState.polling_enabled = false
