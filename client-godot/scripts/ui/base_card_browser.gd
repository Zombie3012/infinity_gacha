class_name BaseCardBrowser
extends VBoxContainer

## Base Reusable Card Grid Browser Component for Godot 4 Client
## Provides Header, Search Bar, Filter Pills, Sort Options, Multi-select,
## Responsive Grid, and Optional Bottom Action Bar.

signal item_selected(item: Dictionary)
signal item_deselected(item: Dictionary)
signal selection_changed(selected_items: Array)
signal action_confirmed(selected_items: Array)
signal quick_action_requested(action_code: String, selected_items: Array)
signal item_action_requested(action_code: String, item_data: Dictionary, quantity: int)

@export var grid_columns: int = 3
@export var card_selectable: bool = true
@export var multi_select_enabled: bool = true
@export var max_selection: int = 6
@export var show_header: bool = true
@export var show_action_bar: bool = true

var all_items: Array = []
var filtered_items: Array = []
var selected_item_ids: Array = []

# Filter & Sort states
var current_search_query: String = ""
var current_filter_pill_idx: int = 0
var current_sort_mode: int = 0
var sort_ascending: bool = false
var filter_pills: Array = []
var filter_predicates: Array = []

# UI Node References
var header_row: HBoxContainer
var header_title_label: Label
var header_count_label: Label
var search_input: LineEdit
var filter_btn: Button
var pills_row: HBoxContainer
var grid_container: GridContainer
var empty_label: Label
var bottom_action_container: VBoxContainer
var selection_count_label: Label
var action_badge_label: Label
var confirm_action_btn: Button
var extra_action_box: HBoxContainer
var _pill_buttons: Array[Button] = []
var _card_nodes: Dictionary = {}

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)

func _ready() -> void:
	_ensure_component_layout()

func _ensure_component_layout() -> void:
	if header_title_label == null:
		_build_component_layout()

# ==============================================================================
# VIRTUAL HOOKS (Override in subclasses)
# ==============================================================================

func _get_default_placeholder() -> String:
	return "🔍 Tìm kiếm..."

func _get_count_unit() -> String:
	return "Mục"

func _get_sort_labels() -> PackedStringArray:
	return PackedStringArray(["Mặc định", "Tên A-Z"])

func _matches_search(it: Dictionary, query: String) -> bool:
	var iname := str(it.get("name", it.get("targetName", ""))).to_lower()
	return query in iname

func _passes_pill_filter_text(_it: Dictionary, _pill_text: String) -> bool:
	return true

func _compare_items(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("id", "")) < str(b.get("id", ""))

func _create_card_node(_it: Dictionary, _is_sel: bool) -> Control:
	return Control.new()

func _update_responsive_columns(_scroll_node: ScrollContainer) -> void:
	if grid_container != null:
		grid_container.columns = grid_columns

# ==============================================================================
# CONFIGURATION & INITIALIZATION API
# ==============================================================================

func configure_header(title: String, pills: Array = []) -> void:
	_ensure_component_layout()
	if header_title_label != null:
		header_title_label.text = title
	filter_pills.clear()
	filter_predicates.clear()
	for p in pills:
		filter_pills.append(str(p))
		filter_predicates.append(Callable())
	current_filter_pill_idx = 0
	_rebuild_filter_pills()

func configure_filters(title: String, filter_defs: Array) -> void:
	_ensure_component_layout()
	if header_title_label != null:
		header_title_label.text = title
	filter_pills.clear()
	filter_predicates.clear()
	for fdef in filter_defs:
		if fdef is Dictionary:
			filter_pills.append(str(fdef.get("label", "")))
			var pred = fdef.get("predicate", Callable())
			filter_predicates.append(pred if pred is Callable else Callable())
		else:
			filter_pills.append(str(fdef))
			filter_predicates.append(Callable())
	current_filter_pill_idx = 0
	_rebuild_filter_pills()

func set_items(items: Array, preserve_selection: bool = false) -> void:
	_ensure_component_layout()
	all_items = items
	if not preserve_selection:
		selected_item_ids.clear()
	else:
		var valid_ids: Array = items.filter(func(it): return it is Dictionary).map(func(it): return str(it.get("id", "")))
		selected_item_ids = selected_item_ids.filter(func(id): return valid_ids.has(id))
	apply_filter_and_sort()

func set_action_button(label_text: String, _badge_prefix: String = "Hành động") -> void:
	_ensure_component_layout()
	if confirm_action_btn != null:
		confirm_action_btn.text = label_text
	_update_action_bar()

func add_extra_action_button(title: String, action_code: String, btn_color: Color = Color.WHITE) -> Button:
	_ensure_component_layout()
	var btn := Button.new()
	btn.text = title
	btn.custom_minimum_size = Vector2(0, 36)
	btn.modulate = btn_color
	btn.pressed.connect(func():
		var sel_items := get_selected_items()
		quick_action_requested.emit(action_code, sel_items)
	)
	if extra_action_box != null:
		extra_action_box.add_child(btn)
	_update_action_bar()
	return btn

func get_selected_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for it in all_items:
		if it is Dictionary:
			var iid := str(it.get("id", ""))
			if selected_item_ids.has(iid):
				result.append(it)
	return result

func clear_selection() -> void:
	selected_item_ids.clear()
	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

func select_item_by_id(item_id: String) -> void:
	if not selected_item_ids.has(item_id):
		if not multi_select_enabled:
			selected_item_ids.clear()
		selected_item_ids.append(item_id)
		_update_card_selection_visuals()
		_update_action_bar()
		selection_changed.emit(get_selected_items())

func select_items_by_ids(ids: Array) -> void:
	selected_item_ids.clear()
	var valid_ids: Array = all_items.filter(func(it): return it is Dictionary).map(func(it): return str(it.get("id", "")))
	for id in ids:
		var sid := str(id)
		if valid_ids.has(sid) and selected_item_ids.size() < max_selection and not selected_item_ids.has(sid):
			selected_item_ids.append(sid)
	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

# ==============================================================================
# COMPONENT LAYOUT BUILDER
# ==============================================================================

func _build_component_layout() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Top Header Row
	header_row = HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	header_row.visible = show_header
	add_child(header_row)

	header_title_label = Label.new()
	header_title_label.text = ""
	header_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_title_label.add_theme_font_size_override("font_size", 16)
	header_title_label.add_theme_color_override("font_color", Color.WHITE)
	header_row.add_child(header_title_label)

	header_count_label = Label.new()
	header_count_label.text = "0 / 0 %s" % _get_count_unit()
	header_count_label.add_theme_font_size_override("font_size", 13)
	header_count_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	header_row.add_child(header_count_label)

	# 2. Search & Sort Bar
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	add_child(search_row)

	search_input = LineEdit.new()
	search_input.placeholder_text = _get_default_placeholder()
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_input.custom_minimum_size = Vector2(0, 38)
	search_input.clear_button_enabled = true
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.10, 0.12, 0.17, 0.95)
	s_style.border_width_left = 1
	s_style.border_width_top = 1
	s_style.border_width_right = 1
	s_style.border_width_bottom = 1
	s_style.border_color = Color(0.24, 0.32, 0.45)
	s_style.corner_radius_top_left = 6
	s_style.corner_radius_top_right = 6
	s_style.corner_radius_bottom_left = 6
	s_style.corner_radius_bottom_right = 6
	search_input.add_theme_stylebox_override("normal", s_style)
	search_input.text_changed.connect(_on_search_text_changed)
	search_row.add_child(search_input)

	filter_btn = Button.new()
	var sort_labels := _get_sort_labels()
	filter_btn.text = "%s 🎚️" % (sort_labels[0] if sort_labels.size() > 0 else "Sắp xếp")
	filter_btn.custom_minimum_size = Vector2(115, 38)
	filter_btn.pressed.connect(_on_sort_toggle_pressed)
	search_row.add_child(filter_btn)

	# 3. Filter Pills Row
	pills_row = HBoxContainer.new()
	pills_row.add_theme_constant_override("separation", 6)
	add_child(pills_row)
	_rebuild_filter_pills()

	# 4. Scroll Container with Cards Grid
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 2)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(margin)

	grid_container = GridContainer.new()
	grid_container.columns = grid_columns
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_container.add_theme_constant_override("h_separation", 10)
	grid_container.add_theme_constant_override("v_separation", 10)
	margin.add_child(grid_container)
	scroll.resized.connect(func(): _update_responsive_columns(scroll))

	empty_label = Label.new()
	empty_label.text = "Không tìm thấy kết quả nào phù hợp."
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.add_theme_font_size_override("font_size", 14)
	empty_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.visible = false
	margin.add_child(empty_label)

	# 5. Optional Bottom Action Bar
	bottom_action_container = VBoxContainer.new()
	bottom_action_container.add_theme_constant_override("separation", 8)
	add_child(bottom_action_container)

	var sep := HSeparator.new()
	bottom_action_container.add_child(sep)

	var bottom_info_row := HBoxContainer.new()
	bottom_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_action_container.add_child(bottom_info_row)

	selection_count_label = Label.new()
	selection_count_label.text = "Đã chọn 0 %s" % _get_count_unit()
	selection_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_count_label.add_theme_font_size_override("font_size", 13)
	selection_count_label.add_theme_color_override("font_color", Color.WHITE)
	bottom_info_row.add_child(selection_count_label)

	action_badge_label = Label.new()
	action_badge_label.text = ""
	action_badge_label.add_theme_font_size_override("font_size", 13)
	action_badge_label.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
	bottom_info_row.add_child(action_badge_label)

	extra_action_box = HBoxContainer.new()
	extra_action_box.add_theme_constant_override("separation", 6)
	bottom_action_container.add_child(extra_action_box)

	confirm_action_btn = Button.new()
	confirm_action_btn.text = "Xác nhận hành động"
	confirm_action_btn.custom_minimum_size = Vector2(0, 42)
	confirm_action_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_action_btn.disabled = true
	var c_style := StyleBoxFlat.new()
	c_style.bg_color = Color(0.12, 0.38, 0.22, 0.95)
	c_style.corner_radius_top_left = 6
	c_style.corner_radius_top_right = 6
	c_style.corner_radius_bottom_left = 6
	c_style.corner_radius_bottom_right = 6
	confirm_action_btn.add_theme_stylebox_override("normal", c_style)
	confirm_action_btn.pressed.connect(func():
		action_confirmed.emit(get_selected_items())
	)
	bottom_action_container.add_child(confirm_action_btn)
	_update_action_bar()

func _rebuild_filter_pills() -> void:
	if pills_row == null:
		return
	for c in pills_row.get_children():
		c.queue_free()
	_pill_buttons.clear()

	if filter_pills.is_empty():
		pills_row.visible = false
		return
	pills_row.visible = true

	if current_filter_pill_idx < 0 or current_filter_pill_idx >= filter_pills.size():
		current_filter_pill_idx = 0

	for i in range(filter_pills.size()):
		var pill_text: String = str(filter_pills[i])
		var pbtn := Button.new()
		pbtn.text = pill_text
		pbtn.custom_minimum_size = Vector2(0, 30)
		var target_idx := i
		pbtn.pressed.connect(func():
			current_filter_pill_idx = target_idx
			_update_pill_styles()
			apply_filter_and_sort()
		)
		pills_row.add_child(pbtn)
		_pill_buttons.append(pbtn)

	_update_pill_styles()

func _update_pill_styles() -> void:
	for i in range(_pill_buttons.size()):
		var btn: Button = _pill_buttons[i]
		if i == current_filter_pill_idx:
			btn.modulate = Color(0.4, 1.0, 0.6)
		else:
			btn.modulate = Color(0.8, 0.85, 0.92)

# ==============================================================================
# FILTERING & SORTING LOGIC
# ==============================================================================

func apply_filter_and_sort() -> void:
	filtered_items.clear()
	var q := current_search_query.strip_edges().to_lower()

	for it in all_items:
		if not (it is Dictionary):
			continue
		if q != "" and not _matches_search(it, q):
			continue
		if not _passes_pill_filter(it):
			continue
		filtered_items.append(it)

	_sort_filtered_items()
	_render_cards()
	_update_action_bar()

func _passes_pill_filter(it: Dictionary) -> bool:
	if filter_pills.is_empty() or current_filter_pill_idx <= 0 or current_filter_pill_idx >= filter_pills.size():
		return true
	if current_filter_pill_idx < filter_predicates.size():
		var pred = filter_predicates[current_filter_pill_idx]
		if pred is Callable and (pred as Callable).is_valid():
			return bool((pred as Callable).call(it))
	var pill_text: String = str(filter_pills[current_filter_pill_idx]).to_lower()
	return _passes_pill_filter_text(it, pill_text)

func _sort_filtered_items() -> void:
	filtered_items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_items(a, b)
	)

func _render_cards() -> void:
	if grid_container == null:
		return
	if grid_container.get_parent() != null and grid_container.get_parent().get_parent() is ScrollContainer:
		_update_responsive_columns(grid_container.get_parent().get_parent() as ScrollContainer)
	for c in grid_container.get_children():
		c.queue_free()
	_card_nodes.clear()

	if header_count_label != null:
		header_count_label.text = "%d / %d %s" % [
			filtered_items.size(),
			all_items.size(),
			_get_count_unit()
		]

	if filtered_items.is_empty():
		empty_label.visible = true
		return
	empty_label.visible = false

	for it in filtered_items:
		var iid := str(it.get("id", ""))
		var is_sel := selected_item_ids.has(iid)
		var card := _create_card_node(it, is_sel)
		grid_container.add_child(card)
		_card_nodes[iid] = card

func _update_card_selection_visuals() -> void:
	for iid in _card_nodes.keys():
		var node = _card_nodes[iid]
		if is_instance_valid(node) and node.has_method("set_selected"):
			node.set_selected(selected_item_ids.has(iid))

func _update_action_bar() -> void:
	if bottom_action_container != null:
		var has_extra := extra_action_box != null and extra_action_box.get_child_count() > 0
		bottom_action_container.visible = show_action_bar and (card_selectable or has_extra)

	var count := selected_item_ids.size()
	if selection_count_label != null:
		selection_count_label.text = "Đã chọn %d %s" % [count, _get_count_unit()]

	if confirm_action_btn != null:
		confirm_action_btn.visible = card_selectable
		confirm_action_btn.disabled = count == 0
		confirm_action_btn.modulate = Color(0.4, 1.0, 0.6) if count > 0 else Color(0.8, 0.8, 0.8)

	if action_badge_label != null:
		if count > 0:
			action_badge_label.text = "Thực hiện x%d" % count
			action_badge_label.visible = true
		else:
			action_badge_label.visible = false

func _on_card_selection_toggled(data: Dictionary, is_sel: bool) -> void:
	var iid := str(data.get("id", ""))
	if is_sel:
		if not multi_select_enabled:
			selected_item_ids.clear()
		if selected_item_ids.size() < max_selection:
			if not selected_item_ids.has(iid):
				selected_item_ids.append(iid)
		else:
			if _card_nodes.has(iid):
				_card_nodes[iid].set_selected(false)
			return
	else:
		selected_item_ids.erase(iid)

	_update_card_selection_visuals()
	_update_action_bar()
	selection_changed.emit(get_selected_items())

func _on_search_text_changed(new_text: String) -> void:
	current_search_query = new_text
	apply_filter_and_sort()

func _on_sort_toggle_pressed() -> void:
	var sort_labels := _get_sort_labels()
	if sort_labels.is_empty():
		return
	current_sort_mode = (current_sort_mode + 1) % sort_labels.size()
	filter_btn.text = "%s 🎚️" % sort_labels[current_sort_mode]
	apply_filter_and_sort()
