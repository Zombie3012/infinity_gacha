extends Node

var checks := 0
var failed := false

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("CHRONICLE: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("CHRONICLE_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("CHRONICLE_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("CHRONICLE_TEST_MASTER")
	await run_flow()
	print("CHRONICLE_NETWORK_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	expect(await GameState.refresh_profile(), "Load profile")
	expect(await GameState.refresh_heroes(), "Load Heroes")
	var plot: Node3D = load("res://scenes/base/base_plot_3d.tscn").instantiate()
	plot.setup_plot(1, true, {"buildingType": "HERO_CHRONICLE", "typeName": "Sử Điện Anh Hùng", "level": 1, "status": "READY", "maxWorkers": 0})
	add_child(plot)
	plot.set_hovered(true)
	expect(plot.structure_root.get_child_count() >= 7, "Chronicle building renders its columns, roof and memorial book")
	expect(plot.sub_label.text.contains("Tiểu sử"), "Building identifies its purpose")
	plot.queue_free()
	var hero_id := OS.get_environment("CHRONICLE_TEST_HERO")
	var hero: Dictionary = GameState.get_hero_by_id(hero_id)
	expect(not GameState.is_hero_alive(hero), "Casualty starts unavailable")
	var modal: Control = load("res://scripts/ui/hero_chronicle_modal.gd").new()
	add_child(modal)
	var deadline := Time.get_ticks_msec() + 10000
	while modal._records.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	expect(modal._records.size() == 2, "Both instances have records")
	expect(modal._gems == 1, "Seven-star gem stock is shown")
	for record in modal._records:
		if str(record.get("id", "")) == hero_id: modal._select_record(record)
	expect(modal._detail.text.contains("7★") and modal._detail.text.contains("HÀNH TRÌNH"), "Seven-star biography and timeline render")
	expect(not modal._revive.disabled, "Dead Hero can use the gem")
	var biography: String = str(modal._selected.get("biography", ""))
	await modal._resurrect()
	expect(modal._notice.text.contains("100% HP"), "Successful resurrection is displayed")
	expect(modal._gems == 0 and modal._revive.disabled, "Stock consumed; repeat action disabled")
	hero = GameState.get_hero_by_id(hero_id)
	expect(GameState.is_hero_alive(hero) and int(hero.get("hp", 0)) == int(hero.get("maxHp", 1)), "Roster immediately receives full-HP living Hero")
	expect(str(modal._selected.get("biography", "")) == biography, "Biography persists after resurrection")
	expect(modal._detail.text.contains("Được hồi sinh"), "Timeline receives resurrection event")
	modal._status = "DEAD"
	await modal._load_records()
	expect(modal._records.is_empty() and modal._revive.disabled, "Dead filter updates after resurrection")
	modal.queue_free()
	await get_tree().process_frame
	var card: Control = load("res://scripts/ui/universal_item_card.gd").new()
	add_child(card)
	card.setup({"itemId": "RESURRECTION_GEM_7", "name": "Ngọc hồi sinh", "rarity": 7, "quantity": 1})
	expect(card._star_label.text.length() == 7, "Material card displays all seven stars")
	card.queue_free()
	var banners: Control = load("res://scripts/ui/summon_banner_modal.gd").new()
	add_child(banners)
	var banner := {"id": "star-test", "name": "Star test", "bannerType": "SPECIAL", "maxHeroRarity": 7, "rates": {"sevenStarHeroPercent": 2.5, "sixStarHeroPercent": 5.0, "materialPercent": 92.5}}
	banners.setup([banner])
	var labels: Array = banners.find_children("*", "Label", true, false)
	expect(labels.any(func(label): return label.text.contains("7★: 2.50%")), "Banner list shows configured seven-star rate")
	banners._render_banner_detail(banner)
	labels = banners.find_children("*", "Label", true, false)
	expect(labels.any(func(label): return label.text == "Hero 7★:"), "Banner detail includes seven-star rewards")
	banners.queue_free()
