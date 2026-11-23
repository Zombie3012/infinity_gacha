class_name HeroPickerModal
extends Control

## Universal Hero Picker Modal for Godot 4 Client
## Provides a reusable modal dialog using CardGridBrowser and UniversalHeroCard
## to pick one or more Heroes across all facilities and base workflows.

signal hero_picked(hero_data: Dictionary)
signal heroes_picked(heroes_data: Array)
signal heroes_released(heroes_data: Array)
signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")

var multi_select: bool = false
var max_selection: int = 1
var context_mode: int = 0
var allowed_classes: Array = []
var excluded_hero_ids: Array = []
var exclude_deployed: bool = false
var prioritized_hero_ids: Array = []
var allow_worker_release: bool = false
var max_building_workers: int = 0
var filter_pills: Array = ["Tất cả", "Trong Đội PvE", "Đang phân công", "Chưa xếp"]
var modal_title: String = "Chọn Anh Hùng"
var modal_subtitle: String = "Bấm vào thẻ Hero để chọn thao tác"
var action_btn_text: String = "Xác nhận chọn Hero"

var browser
var title_label: Label
var subtitle_label: Label
var feedback_label: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	EventBus.heroes_updated.connect(func(_heroes: Array): _populate_browser())
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

	feedback_label = Label.new()
	feedback_label.text = ""
	feedback_label.visible = false
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback_label.add_theme_font_size_override("font_size", 12)
	root_vbox.add_child(feedback_label)

	browser.configure_header("Danh sách Hero phù hợp", filter_pills)
	browser.set_action_button(action_btn_text, "Chọn")

	browser.item_selected.connect(func(item: Dictionary):
		if not multi_select:
			hero_picked.emit(item)
			close_modal()
	)

	browser.selection_changed.connect(func(selected_items: Array):
		if not allow_worker_release or browser.confirm_action_btn == null:
			return
		var rel_cnt := 0
		var new_cnt := 0
		for it in selected_items:
			if it is Dictionary:
				if prioritized_hero_ids.has(str(it.get("id", ""))):
					rel_cnt += 1
				else:
					new_cnt += 1
		if rel_cnt > 0 and new_cnt == 0:
			browser.confirm_action_btn.text = "🚪 Giải phóng Hero đang làm (%d)" % rel_cnt
		elif rel_cnt > 0 and new_cnt > 0:
			browser.confirm_action_btn.text = "🔄 Giải phóng (%d) & Phân công (%d)" % [rel_cnt, new_cnt]
		elif new_cnt > 0:
			browser.confirm_action_btn.text = "✅ Xác nhận chọn Hero (%d)" % new_cnt
		else:
			browser.confirm_action_btn.text = action_btn_text
	)

	browser.action_confirmed.connect(func(selected_items: Array):
		if multi_select:
			if allow_worker_release and max_building_workers > 0:
				var to_release: Array = []
				var new_picks: Array = []
				for it in selected_items:
					if not (it is Dictionary):
						continue
					if prioritized_hero_ids.has(str(it.get("id", ""))):
						to_release.append(it)
					else:
						new_picks.append(it)
				if not to_release.is_empty() and new_picks.is_empty():
					browser.clear_selection()
					heroes_released.emit(to_release)
					return
				var remaining := max_building_workers - (prioritized_hero_ids.size() - to_release.size())
				if remaining <= 0:
					show_notice_box("⚠️ Công trình đã đủ nhân công (%d/%d)!\nCần giải phóng Hero đang làm ở đầu danh sách trước khi phân công thêm." % [prioritized_hero_ids.size(), max_building_workers], true)
					return
				if new_picks.size() > remaining:
					show_notice_box("⚠️ Chỉ còn %d chỗ trống (%d/%d).\nHãy chọn bớt hoặc chọn thêm Hero đang làm để giải phóng!" % [remaining, prioritized_hero_ids.size(), max_building_workers], true)
					return
				if not to_release.is_empty():
					heroes_released.emit(to_release)
				if not new_picks.is_empty():
					heroes_picked.emit(new_picks)
					close_modal()
				return
			heroes_picked.emit(selected_items)
			close_modal()
		elif not selected_items.is_empty():
			hero_picked.emit(selected_items[0])
			close_modal()
	)

func _populate_browser() -> void:
	if browser == null:
		return

	var prioritized: Array = []
	var candidates: Array = []
	for h in GameState.heroes:
		if not (h is Dictionary) or not GameState.is_hero_alive(h):
			continue
		var hid := str(h.get("id", ""))
		var is_prioritized := prioritized_hero_ids.has(hid)
		if excluded_hero_ids.has(hid) and not is_prioritized:
			continue
		if exclude_deployed and not is_prioritized and GameState.is_hero_pve_deployed(h):
			continue

		if not allowed_classes.is_empty() and not is_prioritized:
			var hcls := str(h.get("classCode", h.get("heroClass", ""))).to_upper()
			var match_cls := false
			for req_c in allowed_classes:
				if str(req_c).to_upper() == hcls:
					match_cls = true
					break
			if not match_cls:
				continue

		if is_prioritized:
			var h_copy: Dictionary = h.duplicate(true)
			h_copy["_worker_priority"] = true
			prioritized.append(h_copy)
		else:
			candidates.append(h)

	var combined: Array = prioritized + candidates
	browser.hero_context_mode = context_mode
	browser.card_selectable = multi_select
	browser.multi_select_enabled = multi_select
	browser.max_selection = max_selection
	browser.set_items(combined, false)

func set_feedback(message: String, is_error: bool = false) -> void:
	if feedback_label != null and is_instance_valid(feedback_label):
		feedback_label.text = message
		feedback_label.visible = not message.is_empty()
		feedback_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if is_error else Color(0.48, 0.96, 0.68))

func show_notice_box(message: String, is_error: bool = true) -> void:
	var old_box := get_node_or_null("NoticeBoxOverlay")
	if old_box != null:
		old_box.queue_free()

	var overlay := ColorRect.new()
	overlay.name = "NoticeBoxOverlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.01, 0.02, 0.04, 0.62)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			overlay.queue_free()
	)
	add_child(overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(440, 150)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.08, 0.11, 0.17, 0.98)
	bstyle.set_border_width_all(2)
	bstyle.border_color = Color(1.0, 0.48, 0.42, 0.95) if is_error else Color(0.42, 0.95, 0.68, 0.95)
	bstyle.set_corner_radius_all(12)
	bstyle.shadow_size = 16
	bstyle.shadow_color = Color(0, 0, 0, 0.75)
	box.add_theme_stylebox_override("panel", bstyle)
	center.add_child(box)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 20)
	m.add_theme_constant_override("margin_right", 20)
	m.add_theme_constant_override("margin_top", 18)
	m.add_theme_constant_override("margin_bottom", 16)
	box.add_child(m)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	m.add_child(vb)

	var title_lbl := Label.new()
	title_lbl.text = "⚠️ THÔNG BÁO" if is_error else "✅ THÔNG BÁO"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.50) if is_error else Color(0.48, 0.96, 0.68))
	vb.add_child(title_lbl)

	var msg_lbl := Label.new()
	msg_lbl.text = message
	msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_lbl.add_theme_font_size_override("font_size", 13)
	msg_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	vb.add_child(msg_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = "(Nhấn ra ngoài khung để đóng)"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.65, 0.74, 0.85))
	vb.add_child(hint_lbl)

func close_modal() -> void:
	closed.emit()
	queue_free()
