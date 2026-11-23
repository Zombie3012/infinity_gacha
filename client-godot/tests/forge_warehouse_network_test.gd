extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FORGE_WAREHOUSE: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("FW_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("FW_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("FW_TEST_MASTER")
	await run_flow()
	print("FORGE_WAREHOUSE_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	await GameState.refresh_profile()
	await GameState.refresh_heroes()
	await GameState.refresh_inventory()
	await GameState.refresh_crafting()

	var recipes: Array = GameState.crafting_overview.get("recipes", [])
	expect(not recipes.is_empty(), "Crafting overview returns recipes")
	if recipes.is_empty(): return

	var recipe: Dictionary = recipes[0]
	for r in recipes:
		if r is Dictionary and bool(r.get("canCraft", false)):
			recipe = r
			break
	var recipe_code := str(recipe.get("code", ""))
	var crafted_ids: Array[String] = []
	for i in range(3):
		var c_res := await ApiClient.post_req("/api/crafting/craft", {"recipeCode": recipe_code})
		if not c_res.get("ok", false):
			push_error("CRAFT ERR: " + str(c_res))
		expect(c_res.get("ok", false), "Craft equipment #%d succeeds" % (i + 1))
		if c_res.get("ok", false) and c_res.get("data") is Dictionary:
			crafted_ids.append(str(c_res["data"].get("instanceId", "")))

	if crafted_ids.size() >= 1:
		var enh_res := await ApiClient.post_req("/api/crafting/equipment/%s/enhance" % crafted_ids[0], {})
		expect(enh_res.get("ok", false), "Enhance crafted equipment succeeds")

	var hero_id := OS.get_environment("FW_TEST_HERO")
	if crafted_ids.size() >= 1 and not hero_id.is_empty():
		var eq_res := await ApiClient.put_req("/api/equipment/%s/equip" % crafted_ids[0], {"heroId": hero_id})
		expect(eq_res.get("ok", false), "Equip item to hero succeeds")
		var uneq_res := await ApiClient.post_req("/api/equipment/%s/unequip" % crafted_ids[0], {})
		expect(uneq_res.get("ok", false), "Unequip item back to warehouse succeeds")
		var qeq_res := await ApiClient.put_req("/api/equipment/heroes/%s/quick-equip" % hero_id, {})
		expect(qeq_res.get("ok", false), "Quick equip hero succeeds")
		var quneq_res := await ApiClient.post_req("/api/equipment/heroes/%s/quick-unequip" % hero_id, {})
		expect(quneq_res.get("ok", false), "Quick unequip hero succeeds")

	var tmpl_code := str(recipe.get("templateCode", ""))
	if crafted_ids.size() == 3 and not tmpl_code.is_empty():
		var fuse_res := await ApiClient.post_req("/api/crafting/fuse", {"templateCode": tmpl_code, "starLevel": 1})
		expect(fuse_res.get("ok", false), "Fuse 3x 1-star copies into 2-star succeeds")

	var drops_res := await ApiClient.get_req("/api/equipment/floor-drops")
	expect(drops_res.get("ok", false), "Fetch floor drops succeeds")

	var sell_res := await ApiClient.post_req("/api/inventory/items/SAMPLE_TRASH_DULL_SHARD/sell", {"quantity": 5})
	if not sell_res.get("ok", false):
		push_error("SELL ERR: " + str(sell_res))
	expect(sell_res.get("ok", false), "Sell inventory material succeeds")

	await GameState.refresh_inventory()
	await GameState.refresh_crafting()

	var forge = load("res://scripts/ui/forge_modal.gd").new()
	add_child(forge)
	forge.setup({"id": OS.get_environment("FW_TEST_FORGE"), "level": 3, "status": "READY"})
	await get_tree().process_frame
	expect(forge._enh_browser != null, "ForgeModal initializes ItemGridBrowser")
	forge.queue_free()

	var wh = load("res://scripts/ui/gear_warehouse_modal.gd").new()
	add_child(wh)
	await get_tree().process_frame
	expect(wh.browser.all_items.size() > 0, "GearWarehouseModal loads unified items from API")
	wh.queue_free()
