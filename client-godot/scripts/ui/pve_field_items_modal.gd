extends Control
const Ui = preload("res://scripts/ui/pve_ui.gd")
const RarityStyleScript = preload("res://scripts/ui/rarity_style.gd")
var squad_id := ""
var _body: VBoxContainer
var _notice: Label
var _busy := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.04, 0.90)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			queue_free()
	)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := Ui.glass_panel(center, Ui.GOLD, 14, 18, 16)
	panel.get_parent().custom_minimum_size.x = 760

	var hdr := HBoxContainer.new()
	panel.add_child(hdr)
	var title := Ui.label(hdr, "🎒 VẬT PHẨM ĐỘI • NGOÀI TRẬN", 20, Ui.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Ui.button(hdr, "✕", queue_free, false, "ghost").custom_minimum_size = Vector2(36, 32)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)

	_notice = Ui.label(panel, "", 13, Ui.TEAL)
	Ui.button(panel, "Đóng", queue_free, false, "ghost")
	_render()

func _render() -> void:
	Ui.clear(_body)
	var squad := PveState.squad_by_id(squad_id)
	var found_any := false
	for bag in PveState.snapshot.get("loadouts", []):
		if bag.get("squadId") != squad_id: continue
		found_any = true
		var hero_id := str(bag.get("heroId", ""))
		var hero := GameState.get_hero_by_id(hero_id)
		var hero_card := Ui.card(_body, Ui.CARD, Ui.BORDER)

		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 12)
		hero_card.add_child(top)
		var name_lbl := Ui.label(top, str(hero.get("name", "Hero")), 16, Ui.GOLD)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hp := int(hero.get("hp", 0))
		var max_hp := maxi(1, int(hero.get("maxHp", 1)))
		var mp := int(hero.get("mp", 0))
		var max_mp := maxi(1, int(hero.get("maxMp", 1)))
		Ui.label(top, "HP %d/%d  •  MP %d/%d" % [hp, max_hp, mp, max_mp], 12, Ui.TEXT)

		var bars := HBoxContainer.new()
		bars.add_theme_constant_override("separation", 8)
		hero_card.add_child(bars)
		var hp_bar := Ui.progress_bar(bars, float(hp), float(max_hp), Ui.SUCCESS, 6)
		hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mp_bar := Ui.progress_bar(bars, float(mp), float(max_mp), Color("53a8ff"), 6)
		mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var slots_row := HBoxContainer.new()
		slots_row.add_theme_constant_override("separation", 8)
		hero_card.add_child(slots_row)
		var slots: Array = bag.get("config", {}).get("slots", [])
		for index in range(5):
			var slot: Variant = slots[index] if index < slots.size() else null
			var slot_col := Ui.card(slots_row, Color(0.06, 0.10, 0.17, 0.9), Ui.BORDER_SOFT, 8)
			slot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if not slot is Dictionary:
				Ui.label(slot_col, "Ô %d\nTrống" % [index + 1], 12, Ui.MUTED)
				continue
			var code := str(slot.get("itemId", ""))
			var star_map := {"MEDICINE": 2, "MANA_POTION": 2, "STRENGTH_POTION": 3}
			var slot_star := int(star_map.get(code, 1))
			var slot_style: StyleBox = slot_col.get_parent().get_theme_stylebox("panel")
			if slot_style is StyleBoxFlat:
				(slot_style as StyleBoxFlat).border_color = RarityStyleScript.color_for_star(slot_star)
			var names := {"MEDICINE": "🧪 Điều trị", "MANA_POTION": "🔷 Ma lực", "STRENGTH_POTION": "💪 Cường lực"}
			Ui.label(slot_col, "%s (%d★)\n×%d" % [names.get(code, code), slot_star, int(slot.get("quantity", 0))], 12, RarityStyleScript.color_for_star(slot_star))
			var button := Ui.button(slot_col, "Dùng", func(): _use(hero_id, index, code), true, "accent")
			button.custom_minimum_size.y = 28
			button.disabled = _busy or squad.get("status") == "FIGHTING"
	if not found_any:
		Ui.label(_body, "Đội này chưa có túi vật phẩm nào được cấu hình.", 13, Ui.MUTED)

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
