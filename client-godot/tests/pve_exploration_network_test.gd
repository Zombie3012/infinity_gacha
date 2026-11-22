extends Node

var checks: int = 0
var failed: bool = false

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("PVE EXPLORATION: " + description)

func wait_for(predicate: Callable, description: String) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	expect(predicate.call(), description)
	return predicate.call()

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("PVE_TEST_API_URL")
	ApiClient.set_auth_token(OS.get_environment("PVE_TEST_ACCESS_TOKEN"))
	GameState.master_id = OS.get_environment("PVE_TEST_MASTER_ID")
	await run_flow()
	print("PVE_EXPLORATION_NETWORK_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	expect(await GameState.refresh_profile(), "Authenticated profile")
	expect(await GameState.refresh_heroes(), "Authenticated roster")
	var screen: Control = load("res://scenes/pve/pve_map.tscn").instantiate()
	add_child(screen)
	if not await wait_for(func(): return PveState.connected, "Initial map loaded"):
		return
	var hero_ids: Array = JSON.parse_string(OS.get_environment("PVE_TEST_HERO_IDS"))
	var ids: Array[String] = []
	for i in range(2):
		var saved: Dictionary = await PveState.send_command("/api/pve/parties", {"name": "Area Squad %d" % i, "heroIds": [hero_ids[i]]})
		expect(saved.get("ok", false), "Party created")
		var deployed: Dictionary = await PveState.send_command("/api/pve/parties/%s/deploy" % saved.get("data", {}).get("partyId", ""))
		expect(deployed.get("ok", false), "Party deployed")
		ids.append(str(deployed.get("data", {}).get("squadId", "")))
	PveState.selected_squad_id = ids[0]
	screen._render_state()
	expect(screen._tiles.size() == 144, "Floor renders 12 by 12")
	expect(not screen._stone.disabled, "Inventory enables stone use on an ordinary floor")
	screen._stone.pressed.emit()
	if not await wait_for(func(): return int(PveState.snapshot.get("teleportStones", -1)) == 0 and not PveState.command_busy, "Stone is consumed through the map UI"):
		return
	expect(PveState.snapshot.get("map", {}).get("recallPoints", []).size() == 1, "Created recall point persists in the map snapshot")
	expect(bool(PveState.squad_by_id(ids[1]).get("atRecallPoint", false)), "Another squad shares the created point")
	screen._portal_actions.get_child(0).pressed.emit()
	if not await wait_for(func(): return str(PveState.squad_by_id(ids[0]).get("areaId", "")) == "region:0", "Server completes timed regional entry"):
		return
	expect(screen._tiles.size() == 400 and screen._breadcrumbs.get_child_count() == 2, "Regional map and navigation rendered")
	screen._tiles[1].pressed.emit()
	if not await wait_for(func(): return int(PveState.squad_by_id(ids[0]).get("x", 0)) == 1 and not PveState.command_busy, "Walk to the building doorway"):
		return
	screen._portal_actions.get_child(0).pressed.emit()
	if not await wait_for(func(): return str(PveState.squad_by_id(ids[0]).get("areaId", "")) == "interior:2", "Server completes interior entry"):
		return
	expect(screen._tiles.size() == 64 and screen._breadcrumbs.get_child_count() == 3, "Building interior and three-level navigation rendered")
	expect(screen._tiles[0].get_children().any(func(child): return child is TextureRect and child.texture != null), "Leader avatar survives area changes")
	var moving: Dictionary = await PveState.send_command("/api/pve/squads/%s/move" % ids[1], {"areaId": "floor", "x": 1, "y": 0})
	expect(moving.get("ok", false), "Other squad accepts orders in the outer map")
	screen._tiles[1].pressed.emit()
	if not await wait_for(func(): return int(PveState.squad_by_id(ids[0]).get("x", 0)) == 1, "Interior resource arrival"):
		return
	expect(PveState.squad_by_id(ids[1]).get("x", 0) == 1, "Both areas advance independently")
	screen._tiles[2].pressed.emit()
	if not await wait_for(func(): return str(PveState.snapshot.get("map", {}).get("status", "")) == "CLEARED", "Designated boss completes objective"):
		return
	expect(str(PveState.snapshot.get("objective", {}).get("status", "")) == "COMPLETED", "Objective completion is authoritative")
	expect(PveState.active_squads().is_empty(), "All squads withdrawn across areas")
	var battle_id: String = str(PveState.squad_by_id(ids[0]).get("lastBattleId", ""))
	var report: Dictionary = await ApiClient.get_req("/api/pve/battles/" + battle_id)
	expect(report.get("ok", false) and report.get("data", {}).get("report", {}).get("initialUnits", []).size() > 0, "Saved combat report remains replayable")
	var old_map_id: String = str(PveState.snapshot.get("map", {}).get("id", ""))
	expect(screen._reset_tower.visible, "Developer reset is visible only with server capability")
	screen._reset_tower.pressed.emit()
	var confirmation: ConfirmationDialog
	for child in screen.get_children():
		if child is ConfirmationDialog:
			confirmation = child
	expect(confirmation != null, "Developer reset requests confirmation in the game")
	if confirmation != null:
		confirmation.confirmed.emit()
		if not await wait_for(func(): return PveState.snapshot.get("map") == null and int(PveState.snapshot.get("run", 0)) == 1 and not PveState.command_busy, "Developer reset returns to floor one in a fresh run"):
			return
		screen._enter.pressed.emit()
		await wait_for(func(): return PveState.snapshot.get("map") is Dictionary and str(PveState.snapshot["map"].get("status", "")) == "ACTIVE", "Floor one can be entered again after reset")
		expect(str(PveState.snapshot.get("map", {}).get("id", "")) != old_map_id, "Reset preserves history and creates a new map identity")
	screen.queue_free()
	PveState.deactivate()
