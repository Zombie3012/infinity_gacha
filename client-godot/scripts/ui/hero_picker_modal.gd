class_name HeroPickerModal
extends Control

## Universal Hero Picker Modal for Godot 4 Client
## Provides a reusable modal dialog using CardGridBrowser and UniversalHeroCard
## to pick one or more Heroes across all facilities and base workflows.

signal hero_picked(hero_data: Dictionary)
signal heroes_picked(heroes_data: Array)
signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")

var multi_select: bool = false
var max_selection: int = 1
var context_mode: int = 0
var allowed_classes: Array = []
var excluded_hero_ids: Array = []
var filter_pills: Array = ["Tất cả", "Trong Đội PvE", "Đang phân công", "Chưa xếp"]
var modal_title: String = "Chọn Anh Hùng"
var modal_subtitle: String = "Bấm vào thẻ Hero để chọn thao tác"
var action_btn_text: String = "Xác nhận chọn Hero"

var browser
var title_label: Label
var subtitle_label: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	_populate_browser()

## Setup configuration before adding to scene tree
func configure(
	title: String,
	can_multi: bool = false,
	max_sel: int = 1,
	ctx_mode: int = 0,
	classes_filter: Array = [],
	exclude_ids: Array = [],
	pills: Array = [],
	subtitle: String = ""
) -> void:
	modal_title = title
	if subtitle != "":
		modal_subtitle = subtitle
	multi_select = can_multi
	max_selection = max_sel
	context_mode = ctx_mode
	allowed_classes = classes_filter
	excluded_hero_ids = exclude_ids
	if not pills.is_empty():
		filter_pills = pills

	if is_inside_tree():
		if title_label != null:
			title_label.text = modal_title
		if subtitle_label != null:
			subtitle_label.text = modal_subtitle
		if browser != null:
			browser.configure_header("Danh sách Hero phù hợp", filter_pills)
		_populate_browser()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.07, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# 2. Main Centered Window
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(880, 680)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.35, 0.85, 0.65, 0.85) # Emerald / Cyan
	p_style.corner_radius_top_left = 12
	p_style.corner_radius_top_right = 12
	p_style.corner_radius_bottom_left = 12
	p_style.corner_radius_bottom_right = 12
	p_style.shadow_size = 14
	p_style.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# 3. Header Row: Title & Close Button
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	title_label = Label.new()
	title_label.text = modal_title
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	title_box.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = modal_subtitle
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	title_box.add_child(subtitle_label)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_modal)
	header_row.add_child(close_btn)

	# 4. CardGridBrowser Component
	browser = CardGridBrowserScript.new()
	browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	browser.hero_context_mode = context_mode
	browser.grid_columns = 3
	browser.card_selectable = multi_select
	browser.multi_select_enabled = multi_select
	browser.max_selection = max_selection
	root_vbox.add_child(browser)

	browser.configure_header("Danh sách Hero phù hợp", filter_pills)
	browser.set_action_button(action_btn_text, "Chọn")

	browser.item_selected.connect(func(item: Dictionary):
		if not multi_select:
			hero_picked.emit(item)
			close_modal()
	)

	browser.action_confirmed.connect(func(selected_items: Array):
		if multi_select:
			heroes_picked.emit(selected_items)
			close_modal()
		elif not selected_items.is_empty():
			hero_picked.emit(selected_items[0])
			close_modal()
	)

func _populate_browser() -> void:
	if browser == null:
		return

	var candidates: Array = []
	for h in GameState.heroes:
		if not (h is Dictionary):
			continue
		var hid := str(h.get("id", ""))
		if excluded_hero_ids.has(hid):
			continue

		if not allowed_classes.is_empty():
			var hcls := str(h.get("classCode", h.get("heroClass", ""))).to_upper()
			var match_cls := false
			for req_c in allowed_classes:
				if str(req_c).to_upper() == hcls:
					match_cls = true
					break
			if not match_cls:
				continue

		candidates.append(h)

	browser.hero_context_mode = context_mode
	browser.card_selectable = multi_select
	browser.multi_select_enabled = multi_select
	browser.max_selection = max_selection
	browser.set_items(candidates, false)

func close_modal() -> void:
	closed.emit()
	queue_free()
