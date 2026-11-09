class_name UniversalItemCard
extends PanelContainer

## Universal Item & Equipment Card Component for Godot 4 Client
## Unified card for Weapons, Armor, Jewelry, Consumables, Books & Materials.

signal item_clicked(item_data: Dictionary)
signal selection_toggled(item_data: Dictionary, is_selected: bool)

enum ContextMode {
	INVENTORY,     ## Warehouse / Inventory: Show stats & owner tag
	FORGE_ENHANCE, ## Forge: Show enhance level (+15) and success rate
	FORGE_FUSE,    ## Forge: Show fuse readiness (2/2)
	EQUIP_SLOT,    ## Equipment selector: Compare stats & Equip button
	ALCHEMY,       ## Alchemy Workshop: Show consumable craft / use
	MATERIAL       ## Base materials: Quantity count
}

var item_data: Dictionary = {}
var context_mode: ContextMode = ContextMode.INVENTORY
var is_selected: bool = false:
	set(value):
		is_selected = value
		_update_selection_visual()

var selectable: bool = false
var is_dimmed: bool = false

var _outer_style: StyleBoxFlat
var _badge_container: HFlowContainer
var _checkbox_icon: Label
var _name_label: Label
var _stat_label: Label
var _icon_label: Label
var _star_label: Label
var _custom_badges: Array[Dictionary] = []

func _init() -> void:
	custom_minimum_size = Vector2(170, 195)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(func(): pivot_offset = size / 2.0)

func setup(data: Dictionary, mode: ContextMode = ContextMode.INVENTORY, can_select: bool = false) -> void:
	item_data = data
	context_mode = mode
	selectable = can_select
	_custom_badges.clear()
	_rebuild_ui()

func set_selected(selected: bool) -> void:
	self.is_selected = selected

func add_badge(text: String, bg_color: Color, text_color: Color = Color.WHITE) -> void:
	_custom_badges.append({
		"text": text,
		"bg": bg_color,
		"fg": text_color
	})
	_refresh_badges()

func clear_badges() -> void:
	_custom_badges.clear()
	_refresh_badges()

func set_dimmed(dimmed: bool) -> void:
	is_dimmed = dimmed
	modulate = Color(0.6, 0.6, 0.6, 0.75) if dimmed else Color.WHITE

func _rebuild_ui() -> void:
	for c in get_children():
		c.queue_free()

	var star: int = int(item_data.get("starLevel", item_data.get("rarity", 1)))
	var rarity_col := _get_rarity_color(star)

	_outer_style = StyleBoxFlat.new()
	_outer_style.bg_color = Color(0.07, 0.09, 0.13, 0.96)
	_outer_style.border_width_left = 2
	_outer_style.border_width_top = 2
	_outer_style.border_width_right = 2
	_outer_style.border_width_bottom = 2
	_outer_style.border_color = rarity_col
	_outer_style.corner_radius_top_left = 8
	_outer_style.corner_radius_top_right = 8
	_outer_style.corner_radius_bottom_left = 8
	_outer_style.corner_radius_bottom_right = 8
	_outer_style.shadow_size = 4
	_outer_style.shadow_color = Color(0, 0, 0, 0.4)
	add_theme_stylebox_override("panel", _outer_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Header: Stars + Slot Type + Checkbox
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	vbox.add_child(header_row)

	_star_label = Label.new()
	_star_label.text = "★".repeat(clampi(star, 1, 6))
	_star_label.add_theme_font_size_override("font_size", 10)
	_star_label.add_theme_color_override("font_color", rarity_col)
	header_row.add_child(_star_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	var enh: int = int(item_data.get("enhanceLevel", 0))
	if enh > 0:
		var enh_pill := _create_mini_badge("+%d" % enh, Color(0.85, 0.65, 0.20, 0.95), Color.BLACK)
		header_row.add_child(enh_pill)

	if selectable:
		_checkbox_icon = Label.new()
		_checkbox_icon.text = "☑" if is_selected else "☐"
		_checkbox_icon.add_theme_font_size_override("font_size", 12)
		_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55) if is_selected else Color(0.6, 0.68, 0.78))
		header_row.add_child(_checkbox_icon)

	# Center Icon Box
	var icon_box := PanelContainer.new()
	icon_box.custom_minimum_size = Vector2(0, 75)
	icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ib_style := StyleBoxFlat.new()
	ib_style.bg_color = Color(0.04, 0.05, 0.07, 0.9)
	ib_style.border_width_left = 1
	ib_style.border_width_top = 1
	ib_style.border_width_right = 1
	ib_style.border_width_bottom = 1
	ib_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.25)
	ib_style.corner_radius_top_left = 6
	ib_style.corner_radius_top_right = 6
	ib_style.corner_radius_bottom_left = 6
	ib_style.corner_radius_bottom_right = 6
	icon_box.add_theme_stylebox_override("panel", ib_style)
	vbox.add_child(icon_box)

	var slot_str := str(item_data.get("slot", item_data.get("itemType", "WEAPON"))).to_upper()
	_icon_label = Label.new()
	_icon_label.text = _get_item_slot_icon(slot_str)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 28)
	_icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_box.add_child(_icon_label)

	# Name Label
	_name_label = Label.new()
	_name_label.text = str(item_data.get("name", item_data.get("targetName", "Trang bị")))
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_name_label)

	# Stat / Quantity Summary Line
	_stat_label = Label.new()
	_stat_label.add_theme_font_size_override("font_size", 10)
	_stat_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0))
	_stat_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(_stat_label)

	_apply_item_context()

	# Badges Row
	_badge_container = HFlowContainer.new()
	_badge_container.add_theme_constant_override("h_separation", 3)
	_badge_container.add_theme_constant_override("v_separation", 3)
	vbox.add_child(_badge_container)
	_refresh_badges()

	_update_selection_visual()
	_set_children_mouse_filter_ignore(self)

func _apply_item_context() -> void:
	var atk := int(item_data.get("atkBonus", item_data.get("attack", 0)))
	var def_b := int(item_data.get("defBonus", item_data.get("defense", 0)))
	var hp_b := int(item_data.get("hpBonus", item_data.get("maxHp", 0)))
	var qty := int(item_data.get("quantity", item_data.get("count", 1)))

	if atk > 0 or def_b > 0 or hp_b > 0:
		var parts: PackedStringArray = []
		if atk > 0: parts.append("+ATK %d" % atk)
		if def_b > 0: parts.append("+DEF %d" % def_b)
		if hp_b > 0: parts.append("+HP %d" % hp_b)
		_stat_label.text = ", ".join(parts)
	elif qty > 1:
		_stat_label.text = "Số lượng: ×%d" % qty
	else:
		_stat_label.text = "Vật phẩm căn cứ"

	var eq_hname := str(item_data.get("equippedHeroName", ""))
	if eq_hname != "":
		add_badge("🛡️ " + eq_hname, Color(0.20, 0.55, 0.85, 0.9))

	var enh: int = int(item_data.get("enhanceLevel", 0))
	if context_mode == ContextMode.FORGE_ENHANCE:
		if enh >= 15:
			add_badge("MAX +15", Color(0.95, 0.35, 0.35, 0.95), Color.WHITE)
		else:
			add_badge("✨ Nâng lên +%d" % (enh + 1), Color(0.85, 0.65, 0.20, 0.95), Color.BLACK)
	elif context_mode == ContextMode.FORGE_FUSE:
		var cnt := int(item_data.get("count", 1))
		if cnt >= 2:
			add_badge("🌟 Đủ 2/2 Ghép Sao", Color(0.20, 0.75, 0.45, 0.95), Color.BLACK)
		else:
			add_badge("Cần thêm 1 món (1/2)", Color(0.45, 0.50, 0.60, 0.90), Color.WHITE)

func _refresh_badges() -> void:
	if _badge_container == null:
		return
	for c in _badge_container.get_children():
		c.queue_free()

	for b_def in _custom_badges:
		var badge := _create_mini_badge(str(b_def.get("text", "")), b_def.get("bg", Color(0.2, 0.4, 0.7, 0.9)), b_def.get("fg", Color.WHITE))
		_badge_container.add_child(badge)
	_set_children_mouse_filter_ignore(self)

func _create_mini_badge(text: String, bg_col: Color, fg_col: Color = Color.WHITE) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = bg_col
	pstyle.corner_radius_top_left = 3
	pstyle.corner_radius_top_right = 3
	pstyle.corner_radius_bottom_left = 3
	pstyle.corner_radius_bottom_right = 3
	pill.add_theme_stylebox_override("panel", pstyle)

	var pm := MarginContainer.new()
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pm.add_theme_constant_override("margin_left", 4)
	pm.add_theme_constant_override("margin_right", 4)
	pm.add_theme_constant_override("margin_top", 1)
	pm.add_theme_constant_override("margin_bottom", 1)
	pill.add_child(pm)

	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", fg_col)
	pm.add_child(lbl)
	return pill

func _set_children_mouse_filter_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_children_mouse_filter_ignore(child)

func _update_selection_visual() -> void:
	if _outer_style == null:
		return
	var star: int = int(item_data.get("starLevel", item_data.get("rarity", 1)))
	var base_col := _get_rarity_color(star)

	if is_selected:
		_outer_style.border_color = Color(0.35, 1.0, 0.55, 1.0)
		_outer_style.border_width_left = 3
		_outer_style.border_width_top = 3
		_outer_style.border_width_right = 3
		_outer_style.border_width_bottom = 3
		_outer_style.shadow_color = Color(0.2, 0.8, 0.4, 0.6)
		_outer_style.shadow_size = 6
		if _checkbox_icon != null:
			_checkbox_icon.text = "☑"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	else:
		_outer_style.border_color = base_col
		_outer_style.border_width_left = 2
		_outer_style.border_width_top = 2
		_outer_style.border_width_right = 2
		_outer_style.border_width_bottom = 2
		_outer_style.shadow_color = Color(0, 0, 0, 0.4)
		_outer_style.shadow_size = 4
		if _checkbox_icon != null:
			_checkbox_icon.text = "☐"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if selectable:
			self.is_selected = not is_selected
			selection_toggled.emit(item_data, is_selected)
		item_clicked.emit(item_data)

func _on_mouse_entered() -> void:
	if not is_dimmed:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.02, 1.02), 0.08)

func _on_mouse_exited() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

func _get_rarity_color(star: int) -> Color:
	if star >= 5: return Color(1.0, 0.82, 0.24, 0.95)
	elif star == 4: return Color(0.78, 0.48, 0.95, 0.95)
	elif star == 3: return Color(0.32, 0.72, 0.95, 0.90)
	return Color(0.68, 0.52, 0.36, 0.90)

func _get_item_slot_icon(slot: String) -> String:
	match slot:
		"WEAPON": return "⚔️"
		"HELMET", "HEAD": return "🪖"
		"ARMOR", "CHEST": return "🛡️"
		"BOOTS", "FEET": return "🥾"
		"RING": return "💍"
		"AMULET", "NECK": return "📿"
		"BOOK", "EXP_BOOK": return "📘"
		"POTION", "MEDICINE": return "🧪"
		"MATERIAL": return "🪨"
		_: return "📦"
