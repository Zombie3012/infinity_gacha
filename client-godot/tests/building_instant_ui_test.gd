extends Node

var checks := 0
var failed := false

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("INSTANT BUILDINGS: " + message)

func texts(node: Node) -> String:
	var result := ""
	for child in node.find_children("*", "Label", true, false): result += child.text + "\n"
	for child in node.find_children("*", "Button", true, false): result += child.text + "\n"
	return result

func _ready() -> void:
	GameState.silver_coins = 100000
	GameState.materials = {"WOOD": 100, "STONE": 100}
	var building := {"id": "instant", "buildingType": "KITCHEN", "typeName": "Nhà bếp", "status": "READY", "level": 1, "maxLevel": 3}
	var bar: Control = load("res://scripts/ui/building_action_bar.gd").new()
	add_child(bar)
	bar.show_building(building)
	expect(texts(bar).contains("Nâng cấp"), "Ready building has upgrade action")
	expect(not texts(bar).contains("⏳") and not texts(bar).contains("00:"), "Action bar has no construction countdown")
	var popup: Control = load("res://scripts/ui/building_upgrade_popup.gd").new()
	popup.setup(building, 1600)
	add_child(popup)
	expect(texts(popup).contains("NÂNG CẤP LÊN CẤP 2"), "Popup offers the next level")
	expect(not texts(popup).contains("Thời gian thi công") and not texts(popup).contains("giây"), "Upgrade popup has no waiting-time label")
	var confirmed: Array = []
	popup.upgrade_confirmed.connect(func(data): confirmed.append(data.get("id")))
	var confirm_buttons := popup.find_children("*", "Button", true, false).filter(func(button): return button.text.contains("NÂNG CẤP LÊN"))
	if not confirm_buttons.is_empty(): confirm_buttons[0].pressed.emit()
	expect(confirmed == ["instant"], "Confirmation still submits the selected building")
	building["level"] = 2
	bar.show_building(building)
	expect(bar.title_label.text.contains("2/3"), "Updated level appears immediately when refreshed")
	building["level"] = 3
	bar.show_building(building)
	expect(texts(bar).contains("Cấp Tối Đa"), "Maximum-level limit is preserved")
	bar.queue_free()
	await get_tree().process_frame
	print("BUILDING_INSTANT_UI_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
