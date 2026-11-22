extends Node
var checks := 0
var failed := false
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("POTION_UI: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("POTION_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("POTION_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("POTION_TEST_MASTER")
	await GameState.refresh_heroes()
	await PveState.activate()
	PveState.selected_battle_id = OS.get_environment("POTION_TEST_BATTLE")
	var arena = load("res://scenes/pve/isometric_pve_arena_3d.tscn").instantiate()
	add_child(arena)
	var limit := Time.get_ticks_msec() + 5000
	var live: Control
	while live == null and Time.get_ticks_msec() < limit:
		await get_tree().create_timer(0.05).timeout
		for node in arena.get_node("HUD").get_children():
			if node.get_script() == load("res://scripts/ui/pve_live_battle_modal.gd"): live = node
	expect(live != null, "Arena opens actual manual battle controls")
	if live != null:
		while live._busy and Time.get_ticks_msec() < limit: await get_tree().create_timer(0.05).timeout
		expect(bool(live.battle.get("live", false)), "Battle remains pending on server")
		expect(live._body.find_children("*", "GridContainer", true, false).size() == 2, "Both 3x3 sides rendered")
		var deadline: float = float(live.battle.get("deadline", 0))
		await live._send({"itemId": "MANA_POTION"})
		expect(float(live.battle.get("deadline", 0)) == deadline, "Using potion does not extend deadline")
		expect(live.battle.get("report", {}).get("log", []).any(func(l): return l.get("action") == "MANA_POTION"), "Mana use appears in replay log")
		await live._send({"itemId": "STRENGTH_POTION"})
		expect(live.battle.get("report", {}).get("log", []).filter(func(l): return l.get("actionType") == "ITEM").size() == 2, "Two distinct potion types allowed")
		await live._send({"action": "BASIC"})
		expect(live.battle.get("report", {}).get("log", []).any(func(l): return l.get("actionType") == "BASIC"), "Manual basic attack executes")
		await live._send({"action": "SKILL", "skillCode": "SAMPLE_SKILL_WARRIOR_HEAVY_STRIKE"})
		expect(live.battle.get("report", {}).get("log", []).any(func(l): return l.get("actionType") == "SKILL"), "Manual skill executes with server MP and cooldown checks")
		await live._send({"watching": false})
		expect(not bool(live.battle.get("live", false)), "Leaving control completes battle with AI")
		expect(not live.battle.get("settlement", {}).is_empty(), "Server settlement returned")
		var field = load("res://scripts/ui/pve_field_items_modal.gd").new()
		field.squad_id = str(live.battle.get("squadId", ""))
		add_child(field)
		var hero_id := str(GameState.heroes[0].get("id", ""))
		await field._use(hero_id, 1, "STRENGTH_POTION")
		expect(field._notice.text.contains("Đã sử dụng"), "Field UI uses reserved potion after combat")
		field.queue_free()
	PveState.polling_enabled = false
	arena.queue_free()
	await get_tree().process_frame
	print("PVE_CONSUMABLE_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
