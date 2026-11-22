extends Node

var checks := 0
var failed := false

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("AIRSHIP SHOP: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("SHOP_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("SHOP_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("SHOP_TEST_MASTER")
	await run_flow()
	print("AIRSHIP_SHOP_NETWORK_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func select_item(modal: Control, code: String) -> void:
	for item in modal._items:
		if str(item.get("code", "")) == code:
			modal._selected = item
			modal._render_detail()
			return
	expect(false, "Missing shop item: " + code)

func run_flow() -> void:
	var plot: Node3D = load("res://scenes/base/base_plot_3d.tscn").instantiate()
	plot.setup_plot(1, true, {"buildingType": "SHOP_AIRSHIP", "typeName": "Thương Thuyền Khinh Khí", "level": 1, "maxLevel": 1, "status": "READY", "maxWorkers": 0})
	add_child(plot)
	plot.set_hovered(true)
	expect(plot._airship_root != null and plot._airship_root.get_child_count() >= 10, "Balloon, basket, ropes and bands are present")
	expect(plot.sub_label.text.contains("Cửa hàng"), "Airship is identifiable as shop")
	plot._process(0.1)
	expect(plot._airship_root.position.y > 0.0, "Airship floats above its mooring")
	plot.queue_free()
	var modal: Control = load("res://scripts/ui/airship_shop_modal.gd").new()
	add_child(modal)
	var deadline := Time.get_ticks_msec() + 10000
	while (modal._items.is_empty() or modal._busy) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	expect(modal._items.size() > 20, "Real shop catalogue loads")
	expect(modal._items.all(func(item): return str(item.get("priceSilver", "")) == "1"), "Every temporary price is one Silver")
	expect(not modal._items.any(func(item): return item.get("itemId") in ["DIVINE_TEAR", "STAMINA_POTION"]), "Unusable legacy goods are hidden")
	expect(modal._balance.text.contains("50"), "Balance comes from actual profile")
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_rect: Rect2 = modal._panel.get_global_rect()
	expect(panel_rect.get_center().distance_to(modal.get_viewport_rect().get_center()) < 1.0, "Airship shop window is centred in the viewport")
	expect(panel_rect.position.x > 0 and panel_rect.end.x < modal.get_viewport_rect().size.x, "Shop has balanced side margins")
	modal._search.text = "Ngọc hồi sinh"
	modal._render_items()
	expect(modal._grid.get_child_count() == 1, "Search finds resurrection gem")
	if modal._grid.get_child_count() != 1:
		modal.queue_free()
		return
	var card: Control = modal._grid.get_child(0)
	card.item_clicked.emit(card.item_data)
	expect(modal._selected.get("code") == "RESURRECTION_GEM_7", "Item card selects the intended goods")
	expect(modal._description.text.contains("★★★★★★★"), "Seven-star gem rarity is visible")
	modal._quantity.value = 3
	expect(modal._buy_button.text.contains("3 bạc"), "Quantity updates total price")
	# Proxy commits this purchase then drops its first response.
	await modal._purchase()
	expect(not modal._pending_purchase.is_empty(), "Unconfirmed purchase retains its original key")
	expect(modal._buy_button.text.contains("Kiểm tra lại") and not modal._quantity.editable, "Unconfirmed transaction offers safe retry and locks quantity")
	await modal._purchase()
	expect(modal._pending_purchase.is_empty() and modal._notice.text.contains("Đã mua 3"), "Retry resolves the committed transaction")
	expect(GameState.silver_coins == 47, "Retry spends only three Silver once")
	modal._search.text = ""
	modal._render_items()
	select_item(modal, OS.get_environment("SHOP_TEST_GEAR"))
	modal._quantity.value = 1
	await modal._purchase()
	expect(GameState.silver_coins == 46, "Equipment costs one Silver")
	select_item(modal, "SHOP_SCROLL_NORMAL")
	modal._quantity.value = 2
	var scrolls_before: int = GameState.normal_scrolls
	await modal._purchase()
	expect(GameState.silver_coins == 44, "Two scrolls cost two Silver")
	expect(GameState.normal_scrolls == scrolls_before + 2, "Purchased scrolls refresh the summoning balance")
	modal._quantity.value = 99
	expect(modal._buy_button.disabled, "Unaffordable purchase is disabled")
	modal.queue_free()
	await get_tree().process_frame
	var chronicle: Control = load("res://scripts/ui/hero_chronicle_modal.gd").new()
	add_child(chronicle)
	deadline = Time.get_ticks_msec() + 10000
	while (chronicle._records.is_empty() or chronicle._busy) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	for record in chronicle._records:
		if str(record.get("id", "")) == OS.get_environment("SHOP_TEST_HERO"): chronicle._select_record(record)
	expect(chronicle._gems == 3 and not chronicle._revive.disabled, "Bought gems are available in Hero Chronicle")
	await chronicle._resurrect()
	var revived: Dictionary = GameState.get_hero_by_id(OS.get_environment("SHOP_TEST_HERO"))
	expect(GameState.is_hero_alive(revived) and int(revived.get("hp", 0)) == int(revived.get("maxHp", 1)), "Bought gem revives Hero to full HP")
	expect(chronicle._gems == 2 and GameState.silver_coins == 44, "Revival consumes one gem without extra Silver")
	chronicle.queue_free()
