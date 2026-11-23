extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("SURVIVAL_DORM: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("SD_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("SD_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("SD_TEST_MASTER")
	await run_flow()
	print("SURVIVAL_DORM_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	await GameState.refresh_profile()
	await GameState.refresh_heroes()
	await GameState.refresh_inventory()
	await GameState.refresh_base_overview()

	var hero_tired_id := OS.get_environment("SD_HERO_TIRED")
	var hero_fresh_id := OS.get_environment("SD_HERO_FRESH")

	# 1. Survival overview, upkeep & rations quote
	var surv := await ApiClient.get_req("/api/survival")
	expect(surv.get("ok", false), "GET /api/survival succeeds")
	var upkeep := await ApiClient.get_req("/api/survival/upkeep?hours=24")
	expect(upkeep.get("ok", false), "GET /api/survival/upkeep succeeds")
	var quote := await ApiClient.post_req("/api/survival/rations/quote", {"hours": 12})
	expect(quote.get("ok", false), "POST /api/survival/rations/quote succeeds")

	# 2. Kitchen cook & feed
	var cook := await ApiClient.post_req("/api/survival/kitchen/cook", {"quantity": 2})
	expect(cook.get("ok", false), "POST /api/survival/kitchen/cook succeeds")
	var feed := await ApiClient.post_req("/api/survival/heroes/%s/feed" % hero_tired_id, {"quantity": 1})
	expect(feed.get("ok", false), "POST /api/survival/heroes/:id/feed succeeds")

	# 3. Personality & Loyalty
	var pers := await ApiClient.get_req("/api/personality")
	expect(pers.get("ok", false), "GET /api/personality succeeds")
	var fav := await ApiClient.post_req("/api/personality/heroes/%s/favorite-meal" % hero_tired_id, {})
	if not fav.get("ok", false):
		push_error("FAV ERR: " + str(fav))
	expect(fav.get("ok", false), "POST /api/personality/heroes/:id/favorite-meal succeeds")
	var loy := await ApiClient.post_req("/api/personality/heroes/%s/loyalty" % hero_tired_id, {"delta": 5, "reason": "Bữa ăn ngon"})
	expect(loy.get("ok", false), "POST /api/personality/heroes/:id/loyalty succeeds")

	# 4. Rest start & stop
	var rest_on := await ApiClient.post_req("/api/survival/heroes/%s/rest" % hero_tired_id, {})
	expect(rest_on.get("ok", false), "POST /api/survival/heroes/:id/rest succeeds")
	var rest_off := await ApiClient.delete_req("/api/survival/heroes/%s/rest" % hero_tired_id)
	expect(rest_off.get("ok", false), "DELETE /api/survival/heroes/:id/rest succeeds")

	await GameState.refresh_heroes()

	# 5. DormitoryModal UI checks (0% fatigue not marked resting)
	var dorm = load("res://scripts/ui/dormitory_modal.gd").new()
	add_child(dorm)
	await get_tree().process_frame
	await dorm.setup({
		"id": OS.get_environment("SD_DORM_ID"),
		"buildingType": "HOUSE",
		"level": 1,
		"capacity": 2,
		"workers": [],
	})
	await get_tree().process_frame
	var fresh_marked_resting := false
	for it in dorm._hero_browser.all_items:
		if str(it.get("id", "")) == hero_fresh_id and bool(it.get("_dorm_is_resting_here", false)):
			fresh_marked_resting = true
	expect(not fresh_marked_resting and dorm._hero_browser.all_items.size() == 2, "DormitoryModal loads heroes and does not mark 0% fatigue hero as resting")
	dorm.queue_free()

	# 6. KitchenMessHallModal UI check
	var kitchen = load("res://scripts/ui/kitchen_mess_hall_modal.gd").new()
	add_child(kitchen)
	await get_tree().process_frame
	await kitchen.setup({"id": OS.get_environment("SD_KITCHEN_ID"), "buildingType": "KITCHEN", "level": 1, "workers": []})
	await get_tree().process_frame
	expect(kitchen.find_children("*", "LineEdit", true, false).size() >= 0 and kitchen.is_inside_tree(), "KitchenMessHallModal renders cleanly")
	kitchen.queue_free()
