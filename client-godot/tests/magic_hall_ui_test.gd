extends Node

class MagicBaseFixture extends "res://scenes/base/isometric_base_3d.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var checks := 0
var failed := false

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("MAGIC HALL: " + message)

func texts(root: Node) -> String:
	var result := ""
	for node in root.find_children("*", "Label", true, false): result += node.text + "\n"
	for node in root.find_children("*", "Button", true, false): result += node.text + "\n"
	return result

func _ready() -> void:
	GameState.heroes = [{"id": "mage", "name": "Mage", "rarity": 3, "level": 20, "classCode": "MAGE", "state": "HEALTHY", "hp": 100, "maxHp": 100}]
	GameState.materials = {"SAMPLE_HERO_EXP_100": 3, "ENHANCEMENT_STONE": 5}
	GameState.base_overview = {"buildings": [{"id": "hall", "buildingType": "HALL_OF_MAGIC", "level": 3, "magicProduction": [{"wing": "LIBRARY", "stored": 10, "capacity": 150, "ratePerHour": 15}, {"wing": "ALCHEMY_WORKSHOP", "stored": 20, "capacity": 600, "ratePerHour": 60}]}]}
	var base: Node3D = load("res://scenes/base/isometric_base_3d.tscn").instantiate()
	base.set_script(MagicBaseFixture)
	add_child(base)
	base.inspector_panel.visible = true
	for tab in range(3):
		base._clear_inspector_actions()
		await get_tree().process_frame
		base._facility_subtab = tab
		base._render_hall_of_magic_subwings("hall", 3)
		await get_tree().process_frame
		var content := texts(base.inspector_action_container)
		expect(content.contains("Thư Viện") and content.contains("Giả Kim") and content.contains("Nghiên Cứu"), "All three function tabs remain inside the Hall")
		expect(content.contains("Thu hoạch sản phẩm của đại sảnh"), "Hall owns the production collection action")
		if tab == 0: expect(content.contains("Tu Luyện Ma Pháp") and content.contains("Đọc Sách EXP"), "Library study and EXP-book actions are preserved")
		elif tab == 1: expect(content.contains("Điều Chế Bình Thuốc") and content.contains("Đá Cường Hóa"), "Alchemy functions remain available")
		else: expect(content.contains("Chuyển Chức") and content.contains("Thức Tỉnh"), "Research/class-change/awakening actions remain available")
	base.queue_free()
	await get_tree().process_frame
	print("MAGIC_HALL_UI_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
