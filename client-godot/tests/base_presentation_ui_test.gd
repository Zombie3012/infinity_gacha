extends Node

var checks := 0
var failed := false

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("BASE PRESENTATION: " + message)

func texts(node: Node) -> String:
	var result := ""
	for child in node.find_children("*", "Label", true, false): result += child.text + "\n"
	for child in node.find_children("*", "Button", true, false): result += child.text + "\n"
	return result

func mouse(point: Vector2, pressed: bool) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(event, true)

func _ready() -> void:
	var watchdog := get_tree().create_timer(20.0)
	watchdog.timeout.connect(func(): push_error("BASE PRESENTATION: Timed out"); get_tree().quit(1))
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 38
	add_child(camera)
	camera.position = Vector3(10, 12, 14)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	var plot: Node3D = load("res://scenes/base/base_plot_3d.tscn").instantiate()
	var building := {"buildingType": "KITCHEN", "typeName": "Kitchen – Nhà bếp", "level": 2, "maxLevel": 3, "status": "READY", "ratePerHour": 40, "capacity": 400, "resourceType": "FOOD", "stored": 10}
	plot.setup_plot(1, true, building)
	add_child(plot)
	plot._fit_caption_to_camera()
	expect(plot.title_label.visible and plot.title_label.text == "Nhà bếp", "Nameplate uses a short localised building name")
	expect(plot.sub_label.text == "Cấp 2", "Unselected building shows just its level")
	var point: Vector3 = plot.title_label.global_position
	var density := camera.unproject_position(point).distance_to(camera.unproject_position(point + camera.global_basis.y))
	expect(absf(plot.title_label.pixel_size * plot.title_label.font_size * density - 18.0) < 0.1, "Nameplate is readable at normal zoom")
	camera.size = 90
	plot._fit_caption_to_camera()
	expect(not plot.title_label.visible, "Distant unselected labels are hidden before they crowd the overview")
	plot.set_selected(true)
	expect(plot.title_label.visible and plot.sub_label.text.contains("40.0/h"), "Selected building shows its name and details at distant zoom")
	point = plot.title_label.global_position
	density = camera.unproject_position(point).distance_to(camera.unproject_position(point + camera.global_basis.y))
	expect(absf(plot.title_label.pixel_size * plot.title_label.font_size * density - 20.0) < 0.1, "Focused name remains readable when zoomed out")
	var bar: Control = load("res://scripts/ui/building_action_bar.gd").new()
	add_child(bar)
	bar.show_building(building)
	expect(not texts(bar).contains("Đóng") and texts(bar).contains("Nâng cấp"), "Building dock keeps useful actions and removes Close")
	bar.show_landmark("TEST", "Landmark", "Ready")
	expect(not texts(bar).contains("Đóng"), "Landmark dock removes Close too")
	bar._close()
	await get_tree().create_timer(0.2).timeout
	expect(not bar.visible, "Existing dismissal still closes the dock")
	var summon: Control = load("res://scripts/ui/summon_banner_modal.gd").new()
	add_child(summon)
	summon.setup([{"id": "normal", "name": "Normal test", "bannerType": "NORMAL", "rates": {"oneStarHeroPercent": 50, "materialPercent": 50}}, {"id": "special", "name": "Special test", "bannerType": "SPECIAL", "rates": {"fiveStarHeroPercent": 50, "materialPercent": 50}}])
	await get_tree().process_frame
	await get_tree().process_frame
	expect(not texts(summon).contains("Vào Giao Diện Banner"), "Banner list no longer has entry buttons")
	var card: Control = summon.find_children("*", "PanelContainer", true, false).filter(func(panel): return panel.tooltip_text == "Mở banner Normal test")[0]
	var title: Label = card.find_children("*", "Label", true, false).filter(func(label): return label.text == "Normal test")[0]
	var click := title.get_global_rect().get_center()
	mouse(click, true)
	mouse(click, false)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(summon._selected_banner.get("id") == "normal", "Clicking banner title enters the correct banner")
	summon._render_banner_list()
	await get_tree().process_frame
	await get_tree().process_frame
	card = summon.find_children("*", "PanelContainer", true, false).filter(func(panel): return panel.tooltip_text == "Mở banner Normal test")[0]
	click = card.get_global_rect().get_center()
	mouse(click, true)
	mouse(click + Vector2(30, 0), false)
	await get_tree().process_frame
	expect(summon._selected_banner.is_empty(), "Dragging inside a banner does not accidentally enter it")
	card.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	get_viewport().push_input(key)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(summon._selected_banner.get("id") == "normal", "Focused banner also opens with Enter")
	summon.queue_free()

	var previous_floor := GameState.current_floor
	var mode_script = load("res://scripts/ui/pve_mode_modal.gd")
	for floor_progress in [1, 25, 26]:
		GameState.current_floor = floor_progress
		var gated_modal: Control = mode_script.new()
		add_child(gated_modal)
		gated_modal.setup()
		var expedition: Dictionary = gated_modal._modes.filter(func(m): return m.get("id") == "EXPEDITION")[0]
		var available: bool = floor_progress > 25
		expect(bool(expedition["available"]) == available,
			"Expedition card follows the floor-25 boundary at floor %d" % floor_progress)
		expect(str(expedition["requirement"]).contains("25"), "Expedition card explains the floor requirement")
		gated_modal._render_mode_detail(expedition)
		var enter: Button = gated_modal.find_children("*", "Button", true, false).filter(func(b): return b.text == expedition["enter_label"])[0]
		expect(enter.disabled == not available,
			"Expedition Enter button is disabled below floor 25, current floor %d" % floor_progress)
		gated_modal.queue_free()
		await get_tree().process_frame
	GameState.current_floor = previous_floor

	var pve_modal: Control = mode_script.new()
	add_child(pve_modal)
	pve_modal.setup()
	await get_tree().process_frame
	await get_tree().process_frame
	var tower_card: Control = pve_modal.find_children("*", "PanelContainer", true, false).filter(func(panel): return panel.tooltip_text == "Xem chế độ Tháp Thử Thách (PvE Tower)")[0]
	expect(is_equal_approx(tower_card.size.x, 429.0) and pve_modal._mode_scroll.size.x <= 880.0, "PvE mode carousel shows 2 cards per viewport")
	var next_btn: Button = pve_modal.find_children("*", "Button", true, false).filter(func(btn): return btn.text == "▶")[0]
	next_btn.pressed.emit()
	await get_tree().create_timer(0.28).timeout
	expect(pve_modal._mode_scroll.scroll_horizontal == pve_modal.CARD_STEP, "Advancing carousel scrolls first card out of view")
	var prev_btn: Button = pve_modal.find_children("*", "Button", true, false).filter(func(btn): return btn.text == "◀")[0]
	prev_btn.pressed.emit()
	await get_tree().create_timer(0.28).timeout
	expect(pve_modal._mode_scroll.scroll_horizontal == 0, "Stepping back returns to the first two cards")
	var tower_click := tower_card.get_global_rect().get_center()
	mouse(tower_click, true)
	mouse(tower_click + Vector2(30, 0), false)
	await get_tree().process_frame
	expect(pve_modal._selected_mode.is_empty(), "Dragging inside a PvE mode card does not accidentally enter it")
	mouse(tower_click, true)
	mouse(tower_click, false)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(pve_modal._selected_mode.get("id") == "TOWER", "Clicking PvE Tower card opens Tower detail view")
	var selected_modes: Array[String] = []
	pve_modal.mode_selected.connect(func(mode_id: String): selected_modes.append(mode_id))
	var enter_btn: Button = pve_modal.find_children("*", "Button", true, false).filter(func(btn): return btn.text.contains("Tiến Vào Tháp PvE"))[0]
	enter_btn.pressed.emit()
	await get_tree().process_frame
	expect(selected_modes == ["TOWER"], "Clicking Enter Tower emits TOWER mode selection")

	var rarity_script = load("res://scripts/ui/rarity_style.gd")
	expect(rarity_script.color_for_star(1) == Color("c4cdd9"), "1-star rarity color is Silver")
	expect(rarity_script.color_for_star(2) == Color("3cd070"), "2-star rarity color is Green")
	expect(rarity_script.color_for_star(3) == Color("3898ff"), "3-star rarity color is Blue")
	expect(rarity_script.color_for_star(4) == Color("b55cff"), "4-star rarity color is Purple")
	expect(rarity_script.color_for_star(5) == Color("ffd23f"), "5-star rarity color is Gold")
	expect(rarity_script.color_for_star(6) == Color("ff4757"), "6-star rarity color is Red")

	var item_card: Control = load("res://scripts/ui/universal_item_card.gd").new()
	add_child(item_card)
	item_card.setup({"id": "itm-7", "name": "Thánh Kiếm Cầu Vồng", "starLevel": 7, "slot": "WEAPON", "quantity": 957, "source": "Tháp PvE Tầng 10"}, 0, false)
	await get_tree().process_frame
	expect(item_card.custom_minimum_size == Vector2(92, 92) and item_card.get_node_or_null("RainbowBorder") != null, "7-star UniversalItemCard is compact 92x92 with RainbowBorder")
	expect(item_card._qty_label.text == "957", "Item card displays stack quantity at bottom-right")

	var hero_card: Control = load("res://scripts/ui/universal_hero_card.gd").new()
	add_child(hero_card)
	hero_card.setup({"id": "h-7", "name": "Lucifer", "rarity": 7, "level": 10, "maxLevel": 20, "classCode": "MAGE"}, 0, false)
	await get_tree().process_frame
	expect(hero_card.get_node_or_null("RainbowBorder") != null, "7-star UniversalHeroCard attaches RainbowBorder")

	var pop: Control = load("res://scripts/ui/item_detail_popover.gd").new()
	add_child(pop)
	pop.setup({"id": "itm-7", "name": "Thánh Kiếm Cầu Vồng", "starLevel": 7, "slot": "POTION", "quantity": 5, "source": "Xưởng Giả Kim"}, Rect2(100, 100, 92, 92), 0, true)
	await get_tree().process_frame
	expect(texts(pop).contains("Nguồn gốc: Xưởng Giả Kim") and texts(pop).contains("Dùng") and texts(pop).contains("Chia") and texts(pop).contains("Bỏ"), "ItemDetailPopover shows origin, use, split and drop actions")
	var pop_actions: Array = []
	pop.action_requested.connect(func(code: String, _d: Dictionary, qty: int): pop_actions.append([code, qty]))
	var split_btn: Button = pop.find_children("*", "Button", true, false).filter(func(b): return b.text.contains("Chia"))[0]
	pop._qty_spin.value = 3
	split_btn.pressed.emit()
	await get_tree().process_frame
	expect(pop_actions.size() == 1 and pop_actions[0] == ["SPLIT", 3], "ItemDetailPopover emits split action with selected quantity")
	item_card.queue_free()
	hero_card.queue_free()

	# Warehouse unified categories & per-category filters
	GameState.equipment_list = [
		{"id": "eq-1", "name": "Kiếm Thép", "slot": "WEAPON", "starLevel": 3, "atkBonus": 25},
	]
	GameState.inventory_items = [
		{"id": "inv-wood", "itemId": "WOOD", "name": "Gỗ Sồi", "category": "MATERIAL", "rarity": 1, "quantity": 120},
		{"id": "inv-enh", "itemId": "ENHANCEMENT_STONE", "name": "Đá Cường Hóa", "category": "MATERIAL", "rarity": 2, "quantity": 15},
		{"id": "inv-exp", "itemId": "SAMPLE_HERO_EXP_100", "name": "Sách EXP Sơ Cấp", "category": "DEVELOPMENT", "rarity": 2, "quantity": 8, "canUse": true},
		{"id": "inv-seal", "itemId": "SAMPLE_HERO_PROMOTION_SEAL", "name": "Ấn Thăng Bậc", "category": "DEVELOPMENT", "rarity": 3, "quantity": 2},
		{"id": "inv-pot", "itemId": "POTION_HP_SMALL", "name": "Thuốc Hồi Máu Nhỏ", "category": "CONSUMABLE", "rarity": 2, "quantity": 5, "canUse": true},
		{"id": "inv-food", "itemId": "FOOD", "name": "Lương Thực Khô", "category": "CONSUMABLE", "rarity": 1, "quantity": 50},
	]
	GameState.summon_scrolls_list = [
		{"id": "SCROLL_NORMAL", "itemId": "SCROLL_NORMAL", "name": "Thiên Thư Triệu Hồi Thường", "category": "TICKET", "rarity": 3, "starLevel": 3, "slot": "SCROLL", "quantity": 4},
	]
	var warehouse: Control = load("res://scripts/ui/gear_warehouse_modal.gd").new()
	add_child(warehouse)
	await get_tree().process_frame
	expect(warehouse.browser.filtered_items.size() == 8, "Warehouse ALL category displays all 8 mixed items (gear, materials, dev, consumables, food, scrolls)")
	warehouse.select_category("DEVELOPMENT")
	await get_tree().process_frame
	expect(warehouse.browser.filtered_items.size() == 2, "Warehouse DEVELOPMENT category shows only 2 dev items")
	var exp_pill: Button = warehouse.browser.find_children("*", "Button", true, false).filter(func(b): return b.text == "Sách EXP")[0]
	exp_pill.pressed.emit()
	await get_tree().process_frame
	expect(warehouse.browser.filtered_items.size() == 1 and str(warehouse.browser.filtered_items[0].get("itemId", "")) == "SAMPLE_HERO_EXP_100", "Per-category filter 'Sách EXP' inside DEVELOPMENT filters to EXP book only")
	warehouse.select_category("MATERIAL")
	await get_tree().process_frame
	var raw_pill: Button = warehouse.browser.find_children("*", "Button", true, false).filter(func(b): return b.text == "Gỗ & Đá & Sắt")[0]
	raw_pill.pressed.emit()
	await get_tree().process_frame
	expect(warehouse.browser.filtered_items.size() == 1 and str(warehouse.browser.filtered_items[0].get("itemId", "")) == "WOOD", "Per-category filter 'Gỗ & Đá & Sắt' inside MATERIAL filters to raw resource only")
	expect(not ("hệ phái" in warehouse.browser.search_input.placeholder_text) and not warehouse.browser.bottom_action_container.visible, "Warehouse ItemGridBrowser uses item placeholder and hides bottom action bar")
	warehouse.select_category("CONSUMABLE")
	await get_tree().process_frame
	expect(warehouse.browser.current_filter_pill_idx == 0, "Switching warehouse category resets filter pill index to 0")
	warehouse.select_category("ALL")
	await get_tree().process_frame
	warehouse.browser.filter_btn.pressed.emit()
	await get_tree().process_frame
	expect(str(warehouse.browser.filtered_items[0].get("itemId", "")) == "WOOD", "ItemGridBrowser sort mode 1 sorts by Quantity descending (WOOD=120 first)")
	warehouse.queue_free()

	var item_browser: Control = load("res://scripts/ui/item_grid_browser.gd").new()
	add_child(item_browser)
	item_browser.configure_header("Forge Test", ["Tất cả", "Chưa đạt +15", "Đạt +15"])
	item_browser.set_items([
		{"id": "eq-low", "name": "Kiếm +5", "enhanceLevel": 5, "starLevel": 2},
		{"id": "eq-max", "name": "Kiếm +15", "enhanceLevel": 15, "starLevel": 5},
	])
	await get_tree().process_frame
	var max_pill: Button = item_browser.find_children("*", "Button", true, false).filter(func(b): return b.text == "Đạt +15")[0]
	max_pill.pressed.emit()
	await get_tree().process_frame
	expect(item_browser.filtered_items.size() == 1 and str(item_browser.filtered_items[0].get("id", "")) == "eq-max", "ItemGridBrowser Forge filter 'Đạt +15' filters to +15 gear only")
	item_browser.queue_free()

	# Main Screen HUD layout & controls verification
	var base_scene: Node3D = load("res://scenes/base/isometric_base_3d.tscn").instantiate()
	add_child(base_scene)
	expect(base_scene.floor_elevator_panel != null and not base_scene.floor_elevator_panel.visible, "Build tools drawer is hidden by default to keep 3D center clear")
	expect(base_scene.view_cycle_btn != null and base_scene.view_cycle_btn.text.contains("Tầng 1"), "Single view cycle button starts at Floor 1")
	base_scene.view_cycle_btn.pressed.emit()
	expect(base_scene._current_lobby_floor == 2 and not base_scene._panorama_mode and base_scene.view_cycle_btn.text.contains("Tầng 2"), "First click on view cycle button switches to Floor 2")
	base_scene.view_cycle_btn.pressed.emit()
	expect(base_scene._panorama_mode and base_scene.view_cycle_btn.text.contains("Toàn Cảnh"), "Second click on view cycle button switches to Panorama mode")
	base_scene.view_cycle_btn.pressed.emit()
	expect(base_scene._current_lobby_floor == 1 and not base_scene._panorama_mode and base_scene.view_cycle_btn.text.contains("Tầng 1"), "Third click on view cycle button cycles back to Floor 1")
	base_scene.build_drawer_btn.pressed.emit()
	expect(base_scene.floor_elevator_panel.visible, "Clicking Build Drawer button opens build tools drawer")
	base_scene.build_drawer_btn.pressed.emit()
	expect(not base_scene.floor_elevator_panel.visible, "Clicking Build Drawer button again hides build tools drawer")
	expect(base_scene.event_buttons_box != null and base_scene.event_buttons_box.visible, "Event strip below top-right resources is visible by default")
	base_scene.event_strip_toggle_btn.pressed.emit()
	expect(not base_scene.event_buttons_box.visible, "Event strip toggle collapses event buttons")

	# P2-01: Red-Dot Badges & StatusToastPanel Queue
	GameState.set_badge_count("mailbox", 3)
	GameState.set_badge_count("events", 2)
	GameState.set_badge_count("friends", 5)
	GameState.set_badge_count("chat", 120)
	await get_tree().process_frame
	expect(base_scene.mailbox_event_btn.get_node("RedDotBadge").visible and base_scene.mailbox_event_btn.get_node("RedDotBadge/CountLabel").text == "3", "Mailbox button displays red-dot badge count 3")
	expect(base_scene.quest_event_btn.get_node("RedDotBadge").visible and base_scene.quest_event_btn.get_node("RedDotBadge/CountLabel").text == "2", "Events button displays red-dot badge count 2")
	expect(base_scene.friends_btn != null and base_scene.friends_btn.get_node("RedDotBadge").visible and base_scene.friends_btn.get_node("RedDotBadge/CountLabel").text == "5", "Friends button displays red-dot badge count 5")
	expect(base_scene.chat_btn.get_node("RedDotBadge").visible and base_scene.chat_btn.get_node("RedDotBadge/CountLabel").text == "99+", "Chat button caps red-dot badge at 99+")
	GameState.set_badge_count("mailbox", 0)
	await get_tree().process_frame
	expect(not base_scene.mailbox_event_btn.get_node("RedDotBadge").visible, "Mailbox red-dot badge hides when count is 0")

	base_scene.show_status_toast("Toast 1", "success", 0.4)
	base_scene.show_status_toast("Toast 2", "error", 0.4)
	await get_tree().process_frame
	expect(base_scene.status_banner_label.text == "Toast 1" and base_scene._toast_queue.size() == 1, "StatusToastPanel shows first toast and queues second toast")

	# P2-13: Layout Presets (3 slots) & Smart Collect All Button
	GameState.base_overview = {"buildings": [{"id": "b1", "stored": 0}]}
	base_scene._refresh_hud()
	expect(not base_scene.collect_all_btn.visible, "Collect All button hides when no building has stored >= 1")
	GameState.base_overview = {"buildings": [{"id": "b1", "stored": 5}]}
	base_scene._refresh_hud()
	expect(base_scene.collect_all_btn.visible and base_scene.collect_all_btn.text.contains("(1)"), "Collect All button shows count when building has stored >= 1")
	base_scene._grid_roads["99,99"] = true
	expect(base_scene.save_layout_preset(1), "Layout Preset 1 saves cleanly")
	base_scene._grid_roads.erase("99,99")
	expect(base_scene.load_layout_preset(1) and base_scene._grid_roads.has("99,99"), "Layout Preset 1 restores saved roads")

	# Regression fixes: CollectAllBtn does not overlap BottomLeftDock, Floor hero assignment excludes unselected heroes, Codex in Avatar
	await get_tree().process_frame
	var left_dock_rect: Rect2 = base_scene.get_node("HUD/BottomLeftDock").get_global_rect()
	var collect_rect: Rect2 = base_scene.collect_all_btn.get_global_rect()
	expect(not left_dock_rect.intersects(collect_rect), "CollectAllBtn floats above BottomBar without overlapping BottomLeftDock")

	GameState.heroes = [
		{"id": "h-sel-1", "name": "Selected", "rarity": 3, "hp": 100, "maxHp": 100, "state": "HEALTHY"},
		{"id": "h-unsel-2", "name": "Unselected", "rarity": 3, "hp": 100, "maxHp": 100, "state": "HEALTHY"},
	]
	GameState.floor_assigned_hero_ids = {1: ["h-sel-1"], 2: []}
	base_scene._spawn_resident_heroes()
	expect(base_scene._hero_actors.has("h-sel-1") and not base_scene._hero_actors.has("h-unsel-2"), "Unselected hero does not spawn in castle when floor is customized")
	GameState.floor_assigned_hero_ids.clear()
	GameState.heroes.clear()

	var prof_modal: Control = load("res://scripts/ui/player_profile_modal.gd").new()
	add_child(prof_modal)
	await get_tree().process_frame
	expect(texts(prof_modal).contains("Bách Khoa"), "PlayerProfileModal (Avatar) includes Codex tab")
	prof_modal.queue_free()

	# P3-05, P3-06, P3-08: SceneTransition, HUD Tooltips, Graphics Quality
	expect(SceneTransition != null and SceneTransition.has_method("change_scene"), "P3-05 SceneTransition autoload is ready")
	expect(not base_scene.gems_pill.tooltip_text.is_empty() and not base_scene.enter_pve_btn.tooltip_text.is_empty(), "P3-06 HUD pills and CTA have Vietnamese tooltips")
	GameState.set_graphics_quality("LOW")
	expect(GameState.graphics_quality == "LOW" and not base_scene.dir_light.shadow_enabled, "P3-08 Graphics quality LOW disables directional shadows")
	GameState.set_graphics_quality("HIGH")
	expect(GameState.graphics_quality == "HIGH" and base_scene.dir_light.shadow_enabled, "P3-08 Graphics quality HIGH enables directional shadows")

	base_scene.queue_free()

	# P2-05: GameState removes fake hardcoded defaults and uses is_synced
	GameState.clear()
	expect(not GameState.is_synced and GameState.silver_coins == 0 and GameState.gem_stones == 0, "GameState defaults to 0 and is_synced=false when cleared")

	# P2-07: Hero Daily Routine AI goal selection
	var unit_script = load("res://scripts/actors/unit_actor_3d.gd")
	expect(unit_script.compute_routine_goal({"hp": 100, "maxHp": 100}, true) == "WORK", "Worker hero gets WORK routine goal")
	expect(unit_script.compute_routine_goal({"hp": 70, "maxHp": 100}, false) == "INJURED", "Hero below 80% HP gets INJURED routine goal")
	expect(unit_script.compute_routine_goal({"hp": 100, "maxHp": 100, "hunger": 60}, false) == "HUNGRY", "Hero with hunger >= 55% gets HUNGRY routine goal")
	expect(unit_script.compute_routine_goal({"hp": 100, "maxHp": 100, "hunger": 20, "fatigue": 65}, false) == "TIRED", "Hero with fatigue >= 55% gets TIRED routine goal")
	expect(unit_script.compute_routine_goal({"hp": 100, "maxHp": 100, "hunger": 10, "fatigue": 10}, false) == "IDLE", "Healthy rested hero gets IDLE routine goal")

	# P2-08: HeroDialogueBank & Status Icon Zoom Visibility
	var bank_script = load("res://scripts/actors/hero_dialogue_bank.gd")
	expect(bank_script.status_icon_for("HUNGRY") == "🍖" and bank_script.status_icon_for("TIRED") == "💤" and bank_script.status_icon_for("INJURED") == "🩹", "HeroDialogueBank maps need goals to status icons")
	var pair_lines: Array = bank_script.pick_social_pair("Aaron", "Jenna")
	expect(pair_lines.size() == 2 and not str(pair_lines[0]).is_empty() and not str(pair_lines[1]).is_empty(), "HeroDialogueBank generates 2-turn social dialogue")
	var actor_a: Node3D = load("res://scenes/common/unit_actor_3d.tscn").instantiate()
	add_child(actor_a)
	actor_a.setup_base_resident({"id": "h-soc-1", "name": "Aaron", "rarity": 4, "hunger": 70, "hp": 100, "maxHp": 100}, Vector3.ZERO)
	actor_a.set_floor_focus_state(true, false)
	camera.size = 38.0
	actor_a.update_status_icon_visibility(camera)
	expect(actor_a._status_icon_label != null and actor_a._status_icon_label.visible and actor_a._status_icon_label.text == "🍖", "Status icon is visible at normal zoom")
	camera.size = 90.0
	actor_a.update_status_icon_visibility(camera)
	expect(not actor_a._status_icon_label.visible, "Status icon hides when zoomed out far")
	actor_a.queue_free()

	# P2-09: HeroQuickInteractPopup
	var qpop: Control = load("res://scripts/ui/hero_quick_interact_popup.gd").new()
	qpop.setup({"id": "h-q1", "name": "Aaron", "rarity": 4, "hp": 90, "maxHp": 100, "hunger": 40, "fatigue": 20, "mood": "Vui vẻ", "loyalty": 85, "favoriteFood": "Thịt Nướng"}, Vector2(300, 300))
	add_child(qpop)
	await get_tree().process_frame
	expect(texts(qpop).contains("Cho ăn nhanh") and texts(qpop).contains("Tặng món yêu thích") and texts(qpop).contains("Cho đi nghỉ") and texts(qpop).contains("Mở Hồ Sơ Chi Tiết"), "HeroQuickInteractPopup renders all 4 quick actions")
	var feed_emitted := []
	qpop.feed_requested.connect(func(hid: String, _hn: String): feed_emitted.append(hid))
	var feed_btn: Button = qpop.find_children("*", "Button", true, false).filter(func(b): return b.text.contains("Cho ăn nhanh"))[0]
	feed_btn.pressed.emit()
	await get_tree().process_frame
	expect(feed_emitted == ["h-q1"], "HeroQuickInteractPopup emits feed_requested on tap")

	# P2-11: Day/Night Hero routine & 3D floating resource text
	var actor_n: Node3D = load("res://scenes/common/unit_actor_3d.tscn").instantiate()
	add_child(actor_n)
	actor_n.setup_base_resident({"id": "h-night", "name": "NightHero", "rarity": 3, "hp": 100, "maxHp": 100}, Vector3.ZERO)
	actor_n.set_time_of_day(2, Vector3(12, 0, 12), Vector3(-5, 0, -5))
	expect(actor_n.time_of_day_mode == 2 and actor_n.home_position.distance_to(Vector3(12, 0, 12)) <= 4.0, "At night, idle hero gathers around Central Bonfire")
	actor_n.queue_free()

	# P2-15: BaseCardBrowser 200-item pagination & 0.15s search debounce
	var perf_browser: Control = load("res://scripts/ui/item_grid_browser.gd").new()
	add_child(perf_browser)
	var many_items: Array = []
	for idx in range(200):
		many_items.append({"id": "perf-%d" % idx, "name": "Vật Phẩm #%d" % idx, "starLevel": (idx % 5) + 1, "quantity": idx + 1})
	perf_browser.set_items(many_items)
	await get_tree().process_frame
	expect(perf_browser.grid_container.get_child_count() == 80 and perf_browser._load_more_btn.visible, "BaseCardBrowser paginates 200 items to 80 cards initially with Load More button")
	perf_browser._load_more_btn.pressed.emit()
	await get_tree().process_frame
	expect(perf_browser.grid_container.get_child_count() == 160, "Clicking Load More renders next 80 cards (160 total)")
	perf_browser.search_input.text = "#199"
	perf_browser.search_input.text_changed.emit("#199")
	await get_tree().create_timer(0.22).timeout
	expect(perf_browser.filtered_items.size() == 1 and perf_browser.grid_container.get_child_count() == 1, "Search debounce 0.15s filters 200 items cleanly")
	perf_browser.queue_free()

	# M01: RarityStyle & UniversalItemCard consistency in hero_roster, pve_field_items, magic_hall
	var roster_script = load("res://scenes/heroes/hero_roster.gd")
	expect(roster_script != null, "hero_roster.gd compiles cleanly with RarityStyleScript")
	var field_modal: Control = load("res://scripts/ui/pve_field_items_modal.gd").new()
	add_child(field_modal)
	await get_tree().process_frame
	expect(field_modal != null, "pve_field_items_modal.gd instantiates cleanly with RarityStyle")
	field_modal.queue_free()

	bar.queue_free()
	plot.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	print("BASE_PRESENTATION_UI_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
