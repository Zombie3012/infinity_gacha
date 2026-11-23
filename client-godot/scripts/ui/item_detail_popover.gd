class_name ItemDetailPopover
extends Control

## Floating Item Detail & Quick-Action Popover
## Appears on hover (PC) or tap/click (Mobile) next to a UniversalItemCard.
## Displays Name, Rarity (1★-7★), Stats/Description, Origin, Quantity Split, and Actions (Use, Equip/Unequip, Split, Drop).

signal action_requested(action_code: String, item_data: Dictionary, quantity: int)
signal closed

const RarityStyleScript = preload("res://scripts/ui/rarity_style.gd")

var item_data: Dictionary = {}
var context_mode: int = 0
var _panel: PanelContainer
var _qty_spin: SpinBox
var _split_row: HBoxContainer
var _hover_close_timer: Timer
var _pointer_inside_card: bool = true
var _pointer_inside_panel: bool = false
var _pinned_by_touch: bool = false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200

func setup(data: Dictionary, anchor_rect: Rect2, mode: int = 0, pinned: bool = false) -> void:
	item_data = data.duplicate(true)
	context_mode = mode
	_pinned_by_touch = pinned
	_build_ui(anchor_rect)

func set_card_hovered(hovered: bool) -> void:
	_pointer_inside_card = hovered
	if hovered:
		_cancel_hover_close()
	elif not _pinned_by_touch:
		_schedule_hover_close()

func _schedule_hover_close() -> void:
	if _hover_close_timer == null:
		_hover_close_timer = Timer.new()
		_hover_close_timer.one_shot = true
		_hover_close_timer.wait_time = 0.18
		_hover_close_timer.timeout.connect(func():
			if not _pointer_inside_card and not _pointer_inside_panel and not _pinned_by_touch:
				close_popover()
		)
		add_child(_hover_close_timer)
	_hover_close_timer.start()

func _cancel_hover_close() -> void:
	if _hover_close_timer != null and not _hover_close_timer.is_stopped():
		_hover_close_timer.stop()

func _build_ui(anchor_rect: Rect2) -> void:
	for c in get_children():
		if c != _hover_close_timer:
			c.queue_free()

	if _pinned_by_touch:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var catch_bg := ColorRect.new()
		catch_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		catch_bg.color = Color(0.01, 0.02, 0.04, 0.35)
		catch_bg.mouse_filter = Control.MOUSE_FILTER_STOP
		catch_bg.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				close_popover()
		)
		add_child(catch_bg)

	var star := int(item_data.get("starLevel", item_data.get("rarity", 1)))
	var rarity_col := RarityStyleScript.color_for_star(star)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(310, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.06, 0.08, 0.13, 0.98)
	pstyle.set_border_width_all(2)
	pstyle.border_color = rarity_col
	pstyle.set_corner_radius_all(10)
	pstyle.shadow_size = 14
	pstyle.shadow_color = Color(0, 0, 0, 0.75)
	_panel.add_theme_stylebox_override("panel", pstyle)
	_panel.mouse_entered.connect(func():
		_pointer_inside_panel = true
		_cancel_hover_close()
	)
	_panel.mouse_exited.connect(func():
		_pointer_inside_panel = false
		if not _pinned_by_touch:
			_schedule_hover_close()
	)
	add_child(_panel)

	if star >= 7:
		RarityStyleScript.attach_rainbow_border(_panel, 10.0, 2.5)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	margin.add_child(vb)

	# Header: Icon + Name + Rarity Stars
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 10)
	vb.add_child(hdr)

	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(46, 46)
	var ib_style := StyleBoxFlat.new()
	ib_style.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	ib_style.set_border_width_all(2)
	ib_style.border_color = rarity_col
	ib_style.set_corner_radius_all(8)
	icon_box.add_theme_stylebox_override("panel", ib_style)
	hdr.add_child(icon_box)

	var icon_lbl := Label.new()
	var slot_str := str(item_data.get("slotType", item_data.get("slot", item_data.get("itemType", item_data.get("category", "MATERIAL"))))).to_upper()
	icon_lbl.text = _slot_icon(slot_str)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 24)
	icon_box.add_child(icon_lbl)

	var title_vb := VBoxContainer.new()
	title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_vb.add_theme_constant_override("separation", 2)
	hdr.add_child(title_vb)

	var name_lbl := Label.new()
	var enh := int(item_data.get("enhanceLevel", 0))
	var base_name := str(item_data.get("name", item_data.get("targetName", "Vật phẩm")))
	name_lbl.text = ("%s +%d" % [base_name, enh]) if enh > 0 else base_name
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", rarity_col)
	title_vb.add_child(name_lbl)

	var star_lbl := Label.new()
	star_lbl.text = "%s  (%s)" % ["★".repeat(clampi(star, 1, 7)), RarityStyleScript.star_name(star)]
	star_lbl.add_theme_font_size_override("font_size", 11)
	star_lbl.add_theme_color_override("font_color", rarity_col)
	title_vb.add_child(star_lbl)

	if _pinned_by_touch:
		var close_btn := Button.new()
		close_btn.text = "✕"
		close_btn.custom_minimum_size = Vector2(28, 28)
		close_btn.pressed.connect(close_popover)
		hdr.add_child(close_btn)

	vb.add_child(HSeparator.new())

	# Stats / Description
	var desc_lbl := Label.new()
	desc_lbl.text = _build_stats_and_desc()
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.86, 0.92, 0.98))
	vb.add_child(desc_lbl)

	# Origin / Source
	var source_lbl := Label.new()
	source_lbl.text = "📍 Nguồn gốc: %s" % _resolve_source()
	source_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source_lbl.add_theme_font_size_override("font_size", 11)
	source_lbl.add_theme_color_override("font_color", Color(0.68, 0.80, 0.92))
	vb.add_child(source_lbl)

	# Quantity & Split controls
	var qty := maxi(1, int(item_data.get("quantity", item_data.get("count", 1))))
	if qty > 1:
		_split_row = HBoxContainer.new()
		_split_row.add_theme_constant_override("separation", 6)
		vb.add_child(_split_row)

		var q_lbl := Label.new()
		q_lbl.text = "Số lượng:"
		q_lbl.add_theme_font_size_override("font_size", 12)
		q_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
		_split_row.add_child(q_lbl)

		_qty_spin = SpinBox.new()
		_qty_spin.min_value = 1
		_qty_spin.max_value = qty
		_qty_spin.value = 1
		_qty_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_split_row.add_child(_qty_spin)

		var max_btn := Button.new()
		max_btn.text = "Tối đa (%d)" % qty
		max_btn.custom_minimum_size.y = 28
		max_btn.pressed.connect(func():
			if _qty_spin != null:
				_qty_spin.value = qty
		)
		_split_row.add_child(max_btn)

	# Action Buttons Row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vb.add_child(btn_row)

	var is_equip := slot_str in ["WEAPON", "HELMET", "HEAD", "ARMOR", "CHEST", "BOOTS", "FEET", "RING", "AMULET", "NECK", "MAIN_HAND", "OFF_HAND", "SHIELD"]
	var is_usable := not is_equip or slot_str in ["POTION", "MEDICINE", "BOOK", "EXP_BOOK", "CONSUMABLE", "CHEST_BOX"]

	if is_usable:
		var use_btn := Button.new()
		use_btn.text = "✨ Dùng"
		use_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		use_btn.modulate = Color(0.45, 0.95, 0.72)
		use_btn.pressed.connect(func(): _emit_action("USE"))
		btn_row.add_child(use_btn)

	if is_equip:
		var equipped_id := str(item_data.get("equippedHeroId", ""))
		var eq_btn := Button.new()
		eq_btn.text = "↩️ Gỡ" if not equipped_id.is_empty() else "🛡️ Trang bị"
		eq_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eq_btn.modulate = Color(0.45, 0.85, 1.0)
		eq_btn.pressed.connect(func(): _emit_action("UNEQUIP" if not equipped_id.is_empty() else "EQUIP"))
		btn_row.add_child(eq_btn)

	if qty > 1:
		var split_btn := Button.new()
		split_btn.text = "✂️ Chia"
		split_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		split_btn.modulate = Color(1.0, 0.86, 0.42)
		split_btn.pressed.connect(func(): _emit_action("SPLIT"))
		btn_row.add_child(split_btn)

	var drop_btn := Button.new()
	drop_btn.text = "🗑️ Bỏ"
	drop_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drop_btn.modulate = Color(1.0, 0.55, 0.50)
	drop_btn.pressed.connect(func(): _emit_action("DROP"))
	btn_row.add_child(drop_btn)

	_position_near(anchor_rect)

func _emit_action(code: String) -> void:
	var qty := int(_qty_spin.value) if _qty_spin != null else 1
	action_requested.emit(code, item_data, maxi(1, qty))
	close_popover()

func _position_near(anchor_rect: Rect2) -> void:
	var vp_size := get_viewport_rect().size
	if vp_size.x <= 1.0:
		vp_size = Vector2(1280, 720)
	var est_size := Vector2(320, 260)
	var x := anchor_rect.end.x + 10.0
	if x + est_size.x > vp_size.x - 12.0:
		x = maxf(12.0, anchor_rect.position.x - est_size.x - 10.0)
	var y := clampf(anchor_rect.position.y, 12.0, maxf(12.0, vp_size.y - est_size.y - 12.0))
	_panel.position = Vector2(x, y)

func _build_stats_and_desc() -> String:
	var lines: PackedStringArray = []
	var atk := int(item_data.get("atkBonus", item_data.get("attack", 0)))
	var def_b := int(item_data.get("defBonus", item_data.get("defense", 0)))
	var hp_b := int(item_data.get("hpBonus", item_data.get("maxHp", 0)))
	var spd_b := int(item_data.get("spdBonus", item_data.get("speed", 0)))
	if atk > 0 or def_b > 0 or hp_b > 0 or spd_b > 0:
		var stats: PackedStringArray = []
		if atk > 0: stats.append("ATK +%d" % atk)
		if def_b > 0: stats.append("DEF +%d" % def_b)
		if hp_b > 0: stats.append("HP +%d" % hp_b)
		if spd_b > 0: stats.append("SPD +%d" % spd_b)
		lines.append("⚔️ Chỉ số: " + " · ".join(stats))
	var eq_hname := str(item_data.get("equippedHeroName", ""))
	if not eq_hname.is_empty():
		lines.append("🛡️ Đang trang bị cho: %s" % eq_hname)
	var desc := str(item_data.get("description", ""))
	if not desc.is_empty():
		lines.append(desc)
	var qty := int(item_data.get("quantity", item_data.get("count", 1)))
	lines.append("📦 Số lượng hiện có: ×%d" % qty)
	return "\n".join(lines)

func _resolve_source() -> String:
	var src := str(item_data.get("source", ""))
	if not src.is_empty():
		return src
	var slot_str := str(item_data.get("slotType", item_data.get("slot", item_data.get("itemType", item_data.get("category", ""))))).to_upper()
	match slot_str:
		"POTION", "MEDICINE", "CONSUMABLE":
			return "Xưởng Giả Kim & Cửa hàng Khinh Khí Cầu"
		"BOOK", "EXP_BOOK":
			return "Thư Viện Ma Thuật & Tháp PvE"
		"WEAPON", "HELMET", "HEAD", "ARMOR", "CHEST", "BOOTS", "FEET", "RING", "AMULET", "NECK":
			return "Lò Rèn, Tháp PvE & Hầm Ngục"
		_:
			return "Tháp PvE, Cửa hàng & Nhiệm vụ căn cứ"

func _slot_icon(slot: String) -> String:
	match slot:
		"WEAPON", "MAIN_HAND": return "⚔️"
		"OFF_HAND", "SHIELD": return "🛡️"
		"HELMET", "HEAD": return "🪖"
		"ARMOR", "CHEST": return "🦺"
		"BOOTS", "FEET": return "🥾"
		"RING": return "💍"
		"AMULET", "NECK": return "📿"
		"BOOK", "EXP_BOOK": return "📘"
		"POTION", "MEDICINE": return "🧪"
		"MATERIAL": return "🪨"
		_: return "📦"

func close_popover() -> void:
	closed.emit()
	queue_free()
