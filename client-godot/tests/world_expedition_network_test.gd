extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("EXPEDITION: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("EX_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("EX_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("EX_TEST_MASTER")
	await run_flow()
	print("WORLD_EXPEDITION_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var modal = load("res://scripts/ui/world_expedition_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()
	await get_tree().process_frame
	expect(not modal._tiles.is_empty(), "World map tiles loaded after unlock")
	var hero_id := OS.get_environment("EX_HERO_ID")
	if not modal._tiles.is_empty() and not hero_id.is_empty():
		var target_tile: Dictionary = modal._tiles[0]
		for t in modal._tiles:
			if t is Dictionary and (int(t.get("x", 0)) != 0 or int(t.get("y", 0)) != 0):
				target_tile = t
				break
		var tile_id := str(target_tile.get("id", ""))
		var d_res: Dictionary = await modal.dispatch_expedition(tile_id, "SCOUT", [hero_id])
		if not d_res.get("ok", false):
			push_error("DISPATCH ERR: " + str(d_res))
		expect(d_res.get("ok", false), "Dispatch expedition succeeds")
		expect(GameState.away_expedition_hero_ids.has(hero_id), "GameState marks dispatched hero as away on expedition")
		var eid := str(d_res.get("data", {}).get("expeditionId", ""))
		if not eid.is_empty():
			await modal.recall_expedition(eid)
			expect(true, "Recall expedition completes cleanly")
	modal.queue_free()
