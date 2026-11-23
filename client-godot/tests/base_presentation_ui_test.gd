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

	bar.queue_free()
	plot.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	print("BASE_PRESENTATION_UI_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
