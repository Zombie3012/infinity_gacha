extends Control
const Ui = preload("res://scripts/ui/pve_ui.gd")
var squad_id := ""
var _body: VBoxContainer
var _notice: Label
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.9)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.panel(center, 650)
	Ui.label(panel, "VẬT PHẨM ĐỘI • NGOÀI TRẬN", 21, Ui.GOLD)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 420)
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_notice = Ui.label(panel, "", 13)
	Ui.button(panel, "Đóng", queue_free)
	_render()

func _render() -> void:
	Ui.clear(_body)
	var squad := PveState.squad_by_id(squad_id)
	for bag in PveState.snapshot.get("loadouts", []):
		if bag.get("squadId") != squad_id: continue
		var hero_id := str(bag.get("heroId", ""))
		var hero := GameState.get_hero_by_id(hero_id)
		Ui.label(_body, str(hero.get("name", "Hero")), 17, Ui.GOLD)
		Ui.label(_body, "HP %d/%d • MP %d/%d" % [int(hero.get("hp", 0)), int(hero.get("maxHp", 0)), int(hero.get("mp", 0)), int(hero.get("maxMp", 0))], 13)
		for index in range(5):
			var slot: Variant = bag.get("config", {}).get("slots", [])[index]
			if not slot is Dictionary:
				Ui.label(_body, "Ô %d • Trống" % [index + 1], 13, Ui.MUTED)
				continue
			var code := str(slot.get("itemId", ""))
			var names := {"MEDICINE": "Thuốc điều trị", "MANA_POTION": "Thuốc ma lực", "STRENGTH_POTION": "Thuốc cường lực"}
			var button := Ui.button(_body, "Ô %d • %s ×%d • Sử dụng" % [index + 1, names.get(code, code), int(slot.get("quantity", 0))], func(): _use(hero_id, index, code))
			button.disabled = _busy or squad.get("status") == "FIGHTING"

func _use(hero_id: String, index: int, code: String) -> void:
	if _busy: return
	_busy = true
	_render()
	var result: Dictionary = await PveState.send_command("/api/pve/consumables/use", {"heroId": hero_id, "slotIndex": index, "itemId": code})
	if not is_inside_tree(): return
	await PveState.refresh()
	await GameState.refresh_heroes()
	if not is_inside_tree(): return
	_busy = false
	_notice.text = "Đã sử dụng." if result.get("ok", false) else PveState.error_message(str(result.get("error", "Không thể sử dụng")))
	_render()
