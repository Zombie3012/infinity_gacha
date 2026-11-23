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

	var pve_modal: Control = load("res://scripts/ui/pve_mode_modal.gd").new()
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
	base_scene.queue_free()

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
