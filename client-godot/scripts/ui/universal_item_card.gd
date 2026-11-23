class_name UniversalItemCard
extends PanelContainer

## Universal Item & Equipment Slot Card (Compact Trove-style Square Slot)
## Displays:
##   - 1★–7★ Rarity Border (Silver, Green, Blue, Purple, Gold, Red, Animated Rainbow)
##   - Center Item Icon
##   - Top-left compact Star tag & Top-right Enhance (+N) / Equipped / Selection checkbox
##   - Bottom-right crisp Quantity badge
## Hovering (PC) or Tapping (Mobile) opens ItemDetailPopover with full info & actions.

signal item_clicked(item_data: Dictionary)
signal selection_toggled(item_data: Dictionary, is_selected: bool)
signal item_action_requested(action_code: String, item_data: Dictionary, quantity: int)

const RarityStyleScript = preload("res://scripts/ui/rarity_style.gd")
const ItemDetailPopoverScript = preload("res://scripts/ui/item_detail_popover.gd")

enum ContextMode {
	INVENTORY,     ## Warehouse / Inventory: Show stats & owner tag in popover
	FORGE_ENHANCE, ## Forge: Show enhance level (+15)
	FORGE_FUSE,    ## Forge: Show fuse readiness (2/2)
	EQUIP_SLOT,    ## Equipment selector
	ALCHEMY,       ## Alchemy Workshop
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
var enable_hover_popover: bool = true

var _outer_style: StyleBoxFlat
var _checkbox_icon: Label
var _icon_label: Label
var _star_label: Label
var _qty_label: Label
var _badge_container: HFlowContainer
var _custom_badges: Array[Dictionary] = []
var _active_popover: Control = null

func _init() -> void:
	custom_minimum_size = Vector2(92, 92)
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

func _exit_tree() -> void:
	_dismiss_popover()

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

func clear_badges() -> void:
	_custom_badges.clear()

func set_dimmed(dimmed: bool) -> void:
	is_dimmed = dimmed
	modulate = Color(0.6, 0.6, 0.6, 0.75) if dimmed else Color.WHITE

func _rebuild_ui() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	var star: int = clampi(int(item_data.get("starLevel", item_data.get("rarity", 1))), 1, 7)
	var rarity_col := RarityStyleScript.color_for_star(star)

	_outer_style = StyleBoxFlat.new()
	_outer_style.bg_color = Color(0.06, 0.08, 0.12, 0.96)
	_outer_style.set_border_width_all(2)
	_outer_style.border_color = rarity_col
	_outer_style.set_corner_radius_all(8)
	_outer_style.shadow_size = 4
	_outer_style.shadow_color = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", _outer_style)

	# Root overlay inside the 92x92 slot
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center large icon
	var slot_str := str(item_data.get("slotType", item_data.get("slot", item_data.get("itemType", item_data.get("category", "MATERIAL"))))).to_upper()
	_icon_label = Label.new()
	_icon_label.text = _get_item_slot_icon(slot_str)
	_icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_icon_label.add_theme_font_size_override("font_size", 34)
	_icon_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(_icon_label)

	# Top bar: Star tag (left) + Enhance / Equipped / Checkbox (right)
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_left", 5)
	top_margin.add_theme_constant_override("margin_right", 5)
	top_margin.add_theme_constant_override("margin_top", 3)
	overlay.add_child(top_margin)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 2)
	top_margin.add_child(top_row)

	_star_label = Label.new()
	_star_label.text = "%d★" % star
	_star_label.add_theme_font_size_override("font_size", 10)
	_star_label.add_theme_color_override("font_color", rarity_col)
	top_row.add_child(_star_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)

	var enh: int = int(item_data.get("enhanceLevel", 0))
	if enh > 0:
		var enh_lbl := Label.new()
		enh_lbl.text = "+%d" % enh
		enh_lbl.add_theme_font_size_override("font_size", 10)
		enh_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
		top_row.add_child(enh_lbl)
	elif str(item_data.get("equippedHeroName", "")) != "" or not str(item_data.get("equippedHeroId", "")).is_empty():
		var eq_lbl := Label.new()
		eq_lbl.text = "🛡️"
		eq_lbl.add_theme_font_size_override("font_size", 10)
		top_row.add_child(eq_lbl)

	if selectable:
		_checkbox_icon = Label.new()
		_checkbox_icon.text = "☑" if is_selected else "☐"
		_checkbox_icon.add_theme_font_size_override("font_size", 11)
		_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55) if is_selected else Color(0.7, 0.78, 0.88))
		top_row.add_child(_checkbox_icon)

	# Bottom-right quantity pill (like Trove slot count)
	var qty := int(item_data.get("quantity", item_data.get("count", 1)))
	var bot_margin := MarginContainer.new()
	bot_margin.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_margin.add_theme_constant_override("margin_left", 4)
	bot_margin.add_theme_constant_override("margin_right", 5)
	bot_margin.add_theme_constant_override("margin_bottom", 3)
	overlay.add_child(bot_margin)

	var bot_row := HBoxContainer.new()
	bot_row.alignment = BoxContainer.ALIGNMENT_END
	bot_margin.add_child(bot_row)

	_qty_label = Label.new()
	_qty_label.text = _format_qty(qty) if qty > 1 or context_mode == ContextMode.MATERIAL else ""
	_qty_label.add_theme_font_size_override("font_size", 11)
	_qty_label.add_theme_color_override("font_color", Color.WHITE)
	_qty_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	_qty_label.add_theme_constant_override("outline_size", 3)
	bot_row.add_child(_qty_label)

	_update_selection_visual()
	if star >= 7 and not is_selected:
		RarityStyleScript.attach_rainbow_border(self, 8.0, 3.0)
	_set_children_mouse_filter_ignore(self)

func _format_qty(qty: int) -> String:
	if qty >= 1_000_000:
		return "%.1fM" % (float(qty) / 1_000_000.0)
	if qty >= 10_000:
		return "%.1fK" % (float(qty) / 1_000.0)
	return str(qty)

func _set_children_mouse_filter_ignore(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_set_children_mouse_filter_ignore(child)

func _update_selection_visual() -> void:
	if _outer_style == null:
		return
	var star: int = clampi(int(item_data.get("starLevel", item_data.get("rarity", 1))), 1, 7)
	var base_col := RarityStyleScript.color_for_star(star)

	if is_selected:
		_outer_style.border_color = Color(0.35, 1.0, 0.55, 1.0)
		_outer_style.set_border_width_all(3)
		_outer_style.shadow_color = Color(0.2, 0.8, 0.4, 0.6)
		_outer_style.shadow_size = 6
		if _checkbox_icon != null:
			_checkbox_icon.text = "☑"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	else:
		_outer_style.border_color = base_col
		_outer_style.set_border_width_all(2)
		_outer_style.shadow_color = Color(0, 0, 0, 0.45)
		_outer_style.shadow_size = 4
		if _checkbox_icon != null:
			_checkbox_icon.text = "☐"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))

func _open_popover(pinned: bool) -> void:
	if not enable_hover_popover or not is_inside_tree():
		return
	if is_instance_valid(_active_popover):
		_active_popover.queue_free()
	var host := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	if host == null:
		return
	var pop := ItemDetailPopoverScript.new()
	host.add_child(pop)
	pop.setup(item_data, get_global_rect(), context_mode, pinned)
	pop.action_requested.connect(func(code: String, data: Dictionary, qty: int):
		item_action_requested.emit(code, data, qty)
	)
	_active_popover = pop

func _dismiss_popover() -> void:
	if is_instance_valid(_active_popover):
		_active_popover.queue_free()
		_active_popover = null

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if selectable:
			self.is_selected = not is_selected
			selection_toggled.emit(item_data, is_selected)
		elif enable_hover_popover:
			_open_popover(true)
		item_clicked.emit(item_data)

func _on_mouse_entered() -> void:
	if not is_dimmed:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.05, 1.05), 0.08)
	if enable_hover_popover:
		if is_instance_valid(_active_popover) and _active_popover.has_method("set_card_hovered"):
			_active_popover.set_card_hovered(true)
		else:
			_open_popover(false)

func _on_mouse_exited() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)
	if is_instance_valid(_active_popover) and _active_popover.has_method("set_card_hovered"):
		_active_popover.set_card_hovered(false)

func _get_rarity_color(star: int) -> Color:
	return RarityStyleScript.color_for_star(star)

func _get_item_slot_icon(slot: String) -> String:
	match slot:
		"WEAPON", "MAIN_HAND": return "⚔️"
		"OFF_HAND", "SHIELD": return "🛡️"
		"HELMET", "HEAD": return "🪖"
		"ARMOR", "CHEST": return "🦺"
		"BOOTS", "FEET": return "🥾"
		"RING": return "💍"
		"AMULET", "NECK": return "📿"
		"BOOK", "EXP_BOOK", "DEVELOPMENT": return "📘"
		"POTION", "MEDICINE", "CONSUMABLE": return "🧪"
		"SCROLL": return "📜"
		"FOOD": return "🍖"
		"EQUIPMENT": return "⚔️"
		"MATERIAL": return "🪨"
		_: return "📦"
