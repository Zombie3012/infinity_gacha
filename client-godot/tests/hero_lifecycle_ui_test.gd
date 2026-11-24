extends Node

var checks: int = 0
var failed: bool = false

class RosterFixture extends "res://scenes/heroes/hero_roster.gd":
	func _sync_all_roster_data(preserve_hero_id: String = "") -> void:
		_refresh_hero_list(preserve_hero_id)

class KitchenFixture extends "res://scripts/ui/kitchen_mess_hall_modal.gd":
	func refresh_kitchen_data() -> void:
		pass

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("HERO LIFECYCLE: " + description)

func texts(root: Node) -> String:
	var result := ""
	for label in root.find_children("*", "Label", true, false):
		result += str(label.text) + "\n"
	return result

func _ready() -> void:
	var watchdog := get_tree().create_timer(20.0)
	watchdog.timeout.connect(func(): push_error("HERO LIFECYCLE: Timed out"); get_tree().quit(1))
	await run_checks()
	print("HERO_LIFECYCLE_UI_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_checks() -> void:
	var alive := {"id": "alive", "name": "Living Hero", "hp": 30, "maxHp": 100, "state": "INJURED", "rarity": 3, "level": 1, "classCode": "MAGE"}
	var dead := {"id": "dead", "name": "Fallen Hero", "hp": 0, "maxHp": 100, "state": "DEAD", "category": "NORMAL", "rarity": 3, "level": 1}
	var disabled := {"id": "disabled", "name": "Awaiting Hero", "hp": 0, "maxHp": 100, "state": "DISABLED", "category": "SPECIAL", "rarity": 5, "level": 1}
	var invalid := {"id": "zero", "name": "Zero Hero", "hp": 0, "maxHp": 100, "state": "INJURED", "rarity": 3, "level": 1}
	GameState.heroes = [alive, dead, disabled, invalid]
	expect(GameState.owned_hero_count() == 3, "Permanent deaths do not inflate the owned-Hero count")
	expect(GameState.is_hero_alive(alive) and not GameState.is_hero_alive(dead) and not GameState.is_hero_alive(disabled) and not GameState.is_hero_alive(invalid), "Lifecycle checks both status and positive HP")
	var card: Control = load("res://scripts/ui/universal_hero_card.gd").new()
	add_child(card)
	card.setup(disabled, 1, true)
	expect(texts(card).contains("TỬ TRẬN") and not texts(card).contains("THƯƠNG NẶNG") and not texts(card).contains("Bị thương"), "Disabled Hero is awaiting resurrection, never a severe-injury label")
	expect(not card.selectable, "A disabled card cannot be selected for a facility action")
	card.setup(dead, 1, true)
	expect(texts(card).contains("TỬ TRẬN") and not card.selectable, "Permanent death takes precedence over injury context")
	card.setup(invalid, 1, true)
	expect(texts(card).contains("KHÔNG THỂ HOẠT ĐỘNG") and not card.selectable, "Unclassified zero HP cannot masquerade as a treatable injury")
	var picker: Control = load("res://scripts/ui/hero_picker_modal.gd").new()
	add_child(picker)
	var dorm: Control = load("res://scripts/ui/dormitory_modal.gd").new()
	add_child(dorm)
	var training: Control = load("res://scripts/ui/training_center_modal.gd").new()
	add_child(training)
	var floor_modal: Control = load("res://scripts/ui/floor_hero_modal.gd").new()
	add_child(floor_modal)
	var kitchen: Control = KitchenFixture.new()
	add_child(kitchen)
	kitchen.setup({"level": 1})
	kitchen._switch_tab(1)
	var gear: Control = load("res://scripts/ui/gear_warehouse_modal.gd").new()
	gear.setup("dead")
	add_child(gear)
	expect(gear.target_hero_id == "alive", "Equipment target never defaults to a casualty")
	var editor: Control = load("res://scripts/ui/pve_party_editor.gd").new()
	editor.configure({"members": [{"heroId": "alive"}, {"heroId": "dead"}, {"heroId": "disabled"}]})
	add_child(editor)
	expect(editor._hero_ids == ["alive"] and editor._hero_checks.size() == 1, "Party editor prunes dead and disabled saved members")
	var profile: Control = load("res://scripts/ui/player_profile_modal.gd").new()
	expect(profile._get_active_or_top_party_heroes().size() == 1, "Profile party preview cannot fall back to deceased Heroes")
	profile.free()
	await get_tree().process_frame
	for browser in [picker.browser, dorm._hero_browser, training._hero_browser, floor_modal.browser, kitchen.browser]:
		expect(browser.all_items.size() == 1 and browser.all_items[0]["id"] == "alive", "Facility browser excludes dead, disabled and zero-HP Heroes")
		browser.select_items_by_ids(["alive", "dead", "disabled"])
		expect(browser.get_selected_items().size() == 1, "Invalid/stale IDs cannot be selected")
	var actor: Node3D = load("res://scenes/common/unit_actor_3d.tscn").instantiate()
	add_child(actor)
	actor.setup_base_resident(dead, Vector3.ZERO)
	actor.set_floor_focus_state(true, false)
	expect(not actor.visible and not actor.is_alive, "Floor focus cannot display a deceased base resident")

	# P2-10: Personality & Loyalty card in UniversalHeroCard and GameState
	GameState.personality_map["alive"] = {"heroId": "alive", "coreTrait": "Kiên định", "socialTrait": "Ôn hòa", "favoriteFood": "Súp Nấm", "loyaltyScore": 85, "loyaltyState": "LOYAL"}
	expect(GameState.get_hero_personality("alive").get("favoriteFood", "") == "Súp Nấm", "GameState.get_hero_personality returns synced personality data")
	card.setup({"id": "alive", "name": "Living Hero", "hp": 30, "maxHp": 100, "rarity": 3, "level": 1, "loyaltyScore": 85}, 0, false)
	expect(texts(card).contains("Trung thành"), "UniversalHeroCard displays loyalty badge for loyal hero")
	var roster: Control = load("res://scenes/heroes/hero_roster.tscn").instantiate()
	roster.set_script(RosterFixture)
	add_child(roster)
	await get_tree().process_frame
	expect(roster._filtered_heroes.size() == 1 and roster._filtered_heroes[0]["id"] == "alive", "Barracks default list contains living Heroes only")

	# Hero Detail UI Unification checks: TopBar hidden, stable 3-column widths across 4 tabs, no nested ScrollContainer
	var top_bar: Control = roster.get_node("MarginContainer/VBoxContainer/TopBar")
	expect(top_bar.visible and not roster.status_label.visible, "TopBar is visible in Hero Roster grid view and redundant StatusLabel is hidden")
	expect(roster._filter_option_btn != null and roster._sort_option_btn != null, "Filter and sort use compact dropdown boxes on the right")
	roster._open_hero_detail(alive)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(not top_bar.visible, "Redundant TopBar hides in Hero Detail view")
	var base_ped_w: float = roster._pedestal_card.size.x
	var base_right_w: float = roster._right_card.size.x
	var widths_stable := true
	var no_nested_scroll := true
	for t_idx in [1, 2, 3, 0]:
		roster._active_profile_tab = t_idx
		roster._render_active_profile_tab()
		await get_tree().process_frame
		await get_tree().process_frame
		if absf(roster._pedestal_card.size.x - base_ped_w) > 2.0 or absf(roster._right_card.size.x - base_right_w) > 2.0:
			widths_stable = false
		if not roster._tab_content_vbox.find_children("*", "ScrollContainer", true, false).is_empty():
			no_nested_scroll = false
	expect(widths_stable, "Pedestal and Right Panel widths stay stable when switching across all 4 tabs")
	expect(no_nested_scroll, "No nested ScrollContainer exists inside _tab_content_vbox on any tab")
	expect(roster._tab_content_scroll.scroll_vertical == 0, "Tab switch resets scroll position to top")
	roster._close_hero_detail()
	await get_tree().process_frame
	expect(top_bar.visible, "TopBar reappears when returning to Hero Roster grid view")
	roster._roster_filter_mode = 4
	roster._refresh_hero_list()
	expect(roster._filtered_heroes.size() == 2, "Resurrection candidates have their own roster filter")
	roster._selected_hero = disabled
	roster._render_active_profile_tab()
	expect(texts(roster._tab_content_vbox).contains("7★") and roster._tab_content_vbox.find_children("*", "Button", true, false).is_empty(), "Disabled profile is read-only")
	roster._roster_filter_mode = 5
	roster._refresh_hero_list()
	expect(roster._filtered_heroes.size() == 1 and roster._filtered_heroes[0]["id"] == "dead", "Permanent deaths appear only in the explicit archive filter")
	roster._roster_filter_mode = 0
	roster._refresh_hero_list()
	alive["state"] = "DEAD"
	alive["hp"] = 0
	EventBus.heroes_updated.emit(GameState.heroes)
	await get_tree().process_frame
	for browser in [picker.browser, dorm._hero_browser, training._hero_browser, floor_modal.browser, kitchen.browser]:
		expect(browser.all_items.is_empty() and browser.get_selected_items().is_empty() and browser.confirm_action_btn.disabled, "Open facilities drop a newly dead Hero and stale selection")
	expect(training.selected_hero.is_empty() and training._stat_buttons.values().all(func(button): return button.disabled), "Death clears the selected training workbench")
	expect(gear.target_hero_id.is_empty(), "An open equipment window drops a newly dead target")
	expect(editor._hero_ids.is_empty() and editor._hero_checks.is_empty(), "An open party editor drops newly dead members and formation slots")
	expect(roster._filtered_heroes.is_empty(), "An open barracks immediately removes the new casualty from its default list")
	for node in [card, picker, dorm, training, floor_modal, kitchen, actor, roster, gear, editor]:
		node.queue_free()
	await get_tree().process_frame
