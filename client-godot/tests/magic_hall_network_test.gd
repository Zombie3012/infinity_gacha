extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("MAGIC_HALL: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("MAGIC_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("MAGIC_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("MAGIC_TEST_MASTER")
	await run_flow()
	print("MAGIC_HALL_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var modal = load("res://scripts/ui/magic_hall_modal.gd").new()
	modal.setup({"id": OS.get_environment("MAGIC_TEST_HALL")})
	add_child(modal)
	var deadline := Time.get_ticks_msec() + 15000
	while not modal._data_ready and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	expect(modal._data_ready, "Dedicated modal loads real Hall")
	if not modal._data_ready: return
	await get_tree().process_frame
	expect(modal._tabs.size() == 3, "Three function tabs")
	expect(modal._panel.get_global_rect().get_center().distance_to(get_viewport().get_visible_rect().get_center()) < 3, "Window centered")
	var id := OS.get_environment("MAGIC_TEST_HERO")
	await modal._select_hero(GameState.get_hero_by_id(id))
	expect(GameState.is_hero_alive(modal._selected), "Living selection")
	modal._pick_hero()
	var picker = modal.get_child(modal.get_child_count() - 1)
	expect(picker.browser.all_items.size() == 2, "Picker excludes dead Heroes")
	picker.close_modal()
	await modal._select_tab(1)
	expect(modal._tab == 1 and modal._body.get_child_count() == 5, "Alchemy sections render")
	await modal._heal()
	expect(int(GameState.materials.get("MEDICINE", 0)) == 0, "Medicine consumed")
	expect(int(modal._selected.get("hp", 0)) > 300, "Medicine heals selected Hero")
	await modal._act("/api/base/buildings/%s/collect" % modal._hall.id, {}, "Collected")
	expect(int(GameState.materials.get("ENHANCEMENT_STONE", 0)) >= 5, "Collect production into inventory")
	await modal._select_tab(0)
	await modal._toggle_worker()
	expect(GameState.get_worker_assignment_map().has(id), "Assign shared worker")
	await modal._study()
	expect(int(modal._selected.get("exp", 0)) > 0, "Mage study awards EXP")
	await modal._toggle_worker()
	expect(not GameState.get_worker_assignment_map().has(id), "Remove worker")
	await modal._use_book("SAMPLE_HERO_EXP_100")
	expect(int(GameState.materials.get("SAMPLE_HERO_EXP_100", 0)) == 0, "Consumed book disappears")
	GameState.materials["STALE_DYNAMIC_ITEM"] = 1
	await GameState.refresh_inventory()
	expect(not GameState.materials.has("STALE_DYNAMIC_ITEM"), "Inventory removes absent dynamic items")
	await modal._select_tab(2)
	expect(not modal._preview.is_empty(), "Research loads awakening preview")
	expect(modal._selected.get("classChangeOptions", null) is Array, "API supplies class eligibility")
	var rank := int(modal._preview.get("hero", {}).get("currentRank", 0))
	if bool(modal._preview.get("canAwaken", false)):
		await modal._awaken()
		expect(int(modal._preview.get("hero", {}).get("currentRank", 0)) == rank + 1, "Awakening updates preview")
	else:
		expect(false, "Fixture can awaken: " + str(modal._preview))
	await modal._select_hero(GameState.get_hero_by_id(OS.get_environment("MAGIC_TEST_RECRUIT")))
	expect(modal._selected.get("classChangeOptions", []).has("MAGE"), "Research offers eligible target class")
	await modal._change_class("MAGE")
	expect(modal._selected.get("classCode") == "MAGE", "Class change persists")
	expect(int(GameState.materials.get("CLASS_CHANGE_TOKEN", 0)) == 0, "Last class token removed from inventory")
	await modal._select_tab(0)
	var learned := false
	for skill in modal._selected.get("skills", []):
		if bool(skill.get("canUnlock", false)) and not bool(skill.get("isUnlocked", false)):
			await modal._skill(str(skill.code), false)
			for updated in modal._selected.get("skills", []):
				if updated.code == skill.code: learned = bool(updated.get("isUnlocked", false))
			await modal._skill(str(skill.code), true)
			expect(int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0)) == 0, "Skill upgrade consumes last skill book")
			break
	expect(learned, "Library unlocks eligible class skill")
	await modal._act("/api/alchemy/research", {"code": "ALCHEMY_FOUNDATION"}, "Foundation")
	await modal._act("/api/alchemy/research", {"code": "ALCHEMY_MANA"}, "Mana research")
	expect(modal._alchemy.get("technologies", []).filter(func(t): return t.get("researched", false)).size() == 2, "Research tree persists two unlocks")
	await modal._act("/api/alchemy/craft", {"code": "MANA_POTION", "quantity": 2}, "Crafted")
	expect(int(GameState.materials.get("MANA_POTION", 0)) == 2, "Alchemy UI crafts real mana potions")
	var editor = load("res://scripts/ui/pve_consumable_editor.gd").new()
	add_child(editor)
	expect(editor._types.size() == 5 and editor._counts[0].max_value == 4, "Loadout UI has five slots with four-item stacks")
	editor.queue_free()
	modal._busy = true
	modal._render()
	expect(modal._tabs[0].disabled and modal._action_buttons[0].disabled, "Pending action prevents duplicate submission")
	modal._busy = false
	modal.queue_free()
	await get_tree().process_frame
