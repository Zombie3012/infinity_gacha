class_name KitchenMessHallModal
extends Control

## Kitchen & Mess Hall Dedicated Modal Dialog (Clash of Clans / Pick Me Up style)
## Tab 0: Cooking Station (Raw Food -> Rations, Batch Cooking, Special Feasts)
## Tab 1: Mess Hall (UniversalHeroCard Grid, Hunger/Fullness tracking, 1-Click Feed)

signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const BuildingInfoPopupScript = preload("res://scripts/ui/building_info_popup.gd")

var building_data: Dictionary = {}
var facility_level: int = 1
var max_level: int = 3

# UI References
var title_label: Label
var subtitle_label: Label
var food_stock_label: Label
var food_stock_bar: ProgressBar
var raw_food_label: Label
var upkeep_label: Label
var status_banner_label: Label
var content_container: VBoxContainer
var tabs_row: HBoxContainer
var tab_buttons: Array[Button] = []

var active_tab_index: int = 0
var cooking_qty: int = 5
var qty_display_label: Label
var cook_btn: Button

var browser: CardGridBrowser
var survival_heroes_data: Array = []
var food_stock: int = 0
var food_capacity: int = 200
var raw_food_stock: int = 0

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(b_data: Dictionary) -> void:
	building_data = b_data
	facility_level = int(b_data.get("level", 1))
	max_level = int(b_data.get("maxLevel", 3))
	_build_ui()
	refresh_kitchen_data()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.07, 0.88)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# 2. Main Centered Window
	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_wrap)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 680)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.065, 0.08, 0.12, 0.98)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.95, 0.78, 0.28, 0.9)
	pstyle.corner_radius_top_left = 12
	pstyle.corner_radius_top_right = 12
	pstyle.corner_radius_bottom_left = 12
	pstyle.corner_radius_bottom_right = 12
	pstyle.shadow_size = 14
	pstyle.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", pstyle)
	center_wrap.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(main_vbox)

	# --- Header Row ---
	var header := HBoxContainer.new()
	main_vbox.add_child(header)

	var icon_lbl := Label.new()
	icon_lbl.text = "🍖"
	icon_lbl.add_theme_font_size_override("font_size", 28)
	header.add_child(icon_lbl)

	var title_vb := VBoxContainer.new()
	title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_vb)

	title_label = Label.new()
	title_label.text = "BẾP & NHÀ ĂN QUÂN LƯƠNG (CẤP %d/3)" % facility_level
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	title_vb.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Hệ thống hậu cần sinh tồn • Nấu nướng quân lương & Tiếp tế bữa ăn"
	subtitle_label.add_theme_font_size_override("font_size", 11)
	subtitle_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
	title_vb.add_child(subtitle_label)

	var info_btn := Button.new()
	info_btn.text = " ℹ️ "
	info_btn.custom_minimum_size = Vector2(34, 34)
	info_btn.pressed.connect(func():
		var popup = BuildingInfoPopupScript.new()
		popup.setup(building_data)
		add_child(popup)
	)
	header.add_child(info_btn)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(34, 34)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# --- Top Logistics Dashboard (4 Indicator Cards) ---
	var dash_panel := PanelContainer.new()
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.04, 0.055, 0.085, 0.95)
	dstyle.corner_radius_top_left = 8
	dstyle.corner_radius_top_right = 8
	dstyle.corner_radius_bottom_left = 8
	dstyle.corner_radius_bottom_right = 8
	dash_panel.add_theme_stylebox_override("panel", dstyle)
	main_vbox.add_child(dash_panel)

	var dm := MarginContainer.new()
	dm.add_theme_constant_override("margin_left", 14)
	dm.add_theme_constant_override("margin_right", 14)
	dm.add_theme_constant_override("margin_top", 8)
	dm.add_theme_constant_override("margin_bottom", 8)
	dash_panel.add_child(dm)

	var dash_row := HBoxContainer.new()
	dash_row.add_theme_constant_override("separation", 16)
	dm.add_child(dash_row)

	# Card 1: FOOD Stock
	var c1 := _create_dash_card("📦 Kho Khẩu Phần (FOOD)", dash_row)
	food_stock_label = Label.new()
	food_stock_label.text = "0 / 200"
	food_stock_label.add_theme_font_size_override("font_size", 12)
	food_stock_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	c1.add_child(food_stock_label)
	food_stock_bar = ProgressBar.new()
	food_stock_bar.custom_minimum_size = Vector2(140, 6)
	food_stock_bar.show_percentage = false
	c1.add_child(food_stock_bar)

	# Card 2: RAW_FOOD Stock
	var c2 := _create_dash_card("🌾 Lương Thực Thô", dash_row)
	raw_food_label = Label.new()
	raw_food_label.text = "0"
	raw_food_label.add_theme_font_size_override("font_size", 13)
	raw_food_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	c2.add_child(raw_food_label)

	# Card 3: Base Upkeep (2 FOOD/day/hero)
	var c3 := _create_dash_card("⏳ Tiêu Hao Nội Bộ (24h)", dash_row)
	upkeep_label = Label.new()
	upkeep_label.text = "Đang tính..."
	upkeep_label.add_theme_font_size_override("font_size", 12)
	upkeep_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	c3.add_child(upkeep_label)

	# Card 4: Combat Dispatch Quota (50 FOOD for 5 heroes)
	var c4 := _create_dash_card("⚔️ Định Mức Xuất Trận", dash_row)
	var dispatch_lbl := Label.new()
	dispatch_lbl.text = "50 Khẩu phần / 5 Hero"
	dispatch_lbl.add_theme_font_size_override("font_size", 12)
	dispatch_lbl.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
	c4.add_child(dispatch_lbl)

	# Status message banner
	status_banner_label = Label.new()
	status_banner_label.text = "Chào mừng đến Bếp & Nhà Ăn Quân Lương!"
	status_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_banner_label.add_theme_font_size_override("font_size", 11)
	status_banner_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	main_vbox.add_child(status_banner_label)

	# --- Tabs Navigation Bar ---
	tabs_row = HBoxContainer.new()
	tabs_row.add_theme_constant_override("separation", 10)
	main_vbox.add_child(tabs_row)

	_add_tab_button("🍳 1. Chế Biến & Nấu Nướng", 0)
	_add_tab_button("🍱 2. Nhà Ăn Anh Hùng (Cho Ăn)", 1)

	var hsep := HSeparator.new()
	main_vbox.add_child(hsep)

	# --- Content Dynamic Container ---
	content_container = VBoxContainer.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_container)

	_switch_tab(0)

func _create_dash_card(title: String, parent: Node) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	parent.add_child(vb)

	var tlbl := Label.new()
	tlbl.text = title
	tlbl.add_theme_font_size_override("font_size", 10)
	tlbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	vb.add_child(tlbl)
	return vb

func _add_tab_button(text: String, tab_idx: int) -> void:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(180, 36)
	btn.pressed.connect(func(): _switch_tab(tab_idx))
	tabs_row.add_child(btn)
	tab_buttons.append(btn)

func _switch_tab(idx: int) -> void:
	active_tab_index = idx
	for i in range(tab_buttons.size()):
		var b := tab_buttons[i]
		if i == idx:
			b.modulate = Color(0.4, 1.0, 0.65)
		else:
			b.modulate = Color(0.8, 0.8, 0.8)

	for c in content_container.get_children():
		c.queue_free()

	if idx == 0:
		_render_cooking_tab()
	elif idx == 1:
		_render_mess_hall_tab()

## -----------------------------------------------------------------------------
## TAB 0: COOKING STATION
## -----------------------------------------------------------------------------
func _render_cooking_tab() -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(vb)

	# Recipe conversion box
	var recipe_panel := PanelContainer.new()
	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0.045, 0.06, 0.09, 0.95)
	rstyle.border_width_left = 1
	rstyle.border_width_top = 1
	rstyle.border_width_right = 1
	rstyle.border_width_bottom = 1
	rstyle.border_color = Color(0.95, 0.78, 0.28, 0.35)
	rstyle.corner_radius_top_left = 8
	rstyle.corner_radius_top_right = 8
	rstyle.corner_radius_bottom_left = 8
	rstyle.corner_radius_bottom_right = 8
	recipe_panel.add_theme_stylebox_override("panel", rstyle)
	vb.add_child(recipe_panel)

	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 16)
	rm.add_theme_constant_override("margin_right", 16)
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_theme_constant_override("margin_bottom", 14)
	recipe_panel.add_child(rm)

	var rhbox := HBoxContainer.new()
	rhbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rhbox.add_theme_constant_override("separation", 20)
	rm.add_child(rhbox)

	var in_card := _create_mini_recipe_card("🌾 2x Lương Thực Thô", Color(1.0, 0.85, 0.4))
	rhbox.add_child(in_card)

	var arr_lbl := Label.new()
	arr_lbl.text = "➔ NẤU THÀNH ➔"
	arr_lbl.add_theme_font_size_override("font_size", 13)
	arr_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	rhbox.add_child(arr_lbl)

	var out_card := _create_mini_recipe_card("🍖 1x Khẩu Phần Quân Lương (+20 Độ No)", Color(0.4, 1.0, 0.6))
	rhbox.add_child(out_card)

	# Stepper / Quantity Row
	var qty_panel := PanelContainer.new()
	var qstyle := StyleBoxFlat.new()
	qstyle.bg_color = Color(0.05, 0.07, 0.10, 0.9)
	qstyle.corner_radius_top_left = 8
	qstyle.corner_radius_top_right = 8
	qstyle.corner_radius_bottom_left = 8
	qstyle.corner_radius_bottom_right = 8
	qty_panel.add_theme_stylebox_override("panel", qstyle)
	vb.add_child(qty_panel)

	var qm := MarginContainer.new()
	qm.add_theme_constant_override("margin_left", 16)
	qm.add_theme_constant_override("margin_right", 16)
	qm.add_theme_constant_override("margin_top", 12)
	qm.add_theme_constant_override("margin_bottom", 12)
	qty_panel.add_child(qm)

	var qvb := VBoxContainer.new()
	qvb.add_theme_constant_override("separation", 8)
	qm.add_child(qvb)

	var qtitle := Label.new()
	qtitle.text = "🔢 CHỌN SỐ LƯỢNG KHẨU PHẦN MUỐN NẤU:"
	qtitle.add_theme_font_size_override("font_size", 12)
	qtitle.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
	qvb.add_child(qtitle)

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 8)
	qvb.add_child(step_row)

	_add_qty_step_btn(step_row, "-10", -10)
	_add_qty_step_btn(step_row, "-5", -5)
	_add_qty_step_btn(step_row, "-1", -1)

	qty_display_label = Label.new()
	qty_display_label.text = "%d Khẩu phần (Cần %d Lương thực thô)" % [cooking_qty, cooking_qty * 2]
	qty_display_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qty_display_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qty_display_label.add_theme_font_size_override("font_size", 13)
	qty_display_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	step_row.add_child(qty_display_label)

	_add_qty_step_btn(step_row, "+1", 1)
	_add_qty_step_btn(step_row, "+5", 5)
	_add_qty_step_btn(step_row, "+10", 10)

	var max_btn := Button.new()
	max_btn.text = "Tối Đa (Max)"
	max_btn.custom_minimum_size = Vector2(90, 32)
	max_btn.modulate = Color(0.4, 0.9, 1.0)
	max_btn.pressed.connect(_set_max_cooking)
	step_row.add_child(max_btn)

	# Primary Cook Button
	cook_btn = Button.new()
	cook_btn.custom_minimum_size = Vector2(0, 44)
	cook_btn.text = "🍳 NẤU NGAY %d KHẨU PHẦN QUÂN LƯƠNG" % cooking_qty
	cook_btn.modulate = Color(0.4, 1.0, 0.6)
	cook_btn.pressed.connect(_on_cook_pressed)
	vb.add_child(cook_btn)

	# Special Feast Section (Tactical Feast)
	var feast_panel := PanelContainer.new()
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.12, 0.08, 0.05, 0.95)
	fstyle.border_width_left = 1
	fstyle.border_width_top = 1
	fstyle.border_width_right = 1
	fstyle.border_width_bottom = 1
	fstyle.border_color = Color(1.0, 0.65, 0.3, 0.5)
	fstyle.corner_radius_top_left = 8
	fstyle.corner_radius_top_right = 8
	fstyle.corner_radius_bottom_left = 8
	fstyle.corner_radius_bottom_right = 8
	feast_panel.add_theme_stylebox_override("panel", fstyle)
	vb.add_child(feast_panel)

	var fm := MarginContainer.new()
	fm.add_theme_constant_override("margin_left", 16)
	fm.add_theme_constant_override("margin_right", 16)
	fm.add_theme_constant_override("margin_top", 10)
	fm.add_theme_constant_override("margin_bottom", 10)
	feast_panel.add_child(fm)

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 14)
	fm.add_child(frow)

	var flbl := Label.new()
	flbl.text = "🍲 TIỆC BUFF CHIẾN ĐẤU ĐẶC BIỆT:\nNấu tiệc lớn 15 Khẩu Phần (Tiêu hao 30 Lương Thực Thô) giúp tăng cường sĩ khí và tốc độ phục hồi cho toàn căn cứ!"
	flbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flbl.add_theme_font_size_override("font_size", 11)
	flbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.7))
	frow.add_child(flbl)

	var feast_btn := Button.new()
	feast_btn.text = "🍲 Nấu Tiệc Lớn (15)"
	feast_btn.custom_minimum_size = Vector2(150, 36)
	feast_btn.modulate = Color(1.0, 0.75, 0.35)
	feast_btn.pressed.connect(func(): _cook_specific_amount(15))
	frow.add_child(feast_btn)

	_update_cooking_display()

func _create_mini_recipe_card(text: String, col: Color) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(240, 50)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	ps.border_width_left = 1
	ps.border_width_top = 1
	ps.border_width_right = 1
	ps.border_width_bottom = 1
	ps.border_color = col
	ps.corner_radius_top_left = 6
	ps.corner_radius_top_right = 6
	ps.corner_radius_bottom_left = 6
	ps.corner_radius_bottom_right = 6
	pc.add_theme_stylebox_override("panel", ps)

	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	pc.add_child(l)
	return pc

func _add_qty_step_btn(parent: Node, label: String, delta: int) -> void:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(40, 32)
	btn.pressed.connect(func():
		cooking_qty = clampi(cooking_qty + delta, 1, 50)
		_update_cooking_display()
	)
	parent.add_child(btn)

func _set_max_cooking() -> void:
	var max_by_raw := int(floor(float(raw_food_stock) / 2.0))
	var room_in_stock := maxi(0, food_capacity - food_stock)
	cooking_qty = clampi(mini(max_by_raw, room_in_stock), 1, 50)
	_update_cooking_display()

func _update_cooking_display() -> void:
	if qty_display_label != null:
		var raw_needed := cooking_qty * 2
		qty_display_label.text = "%d Khẩu phần (Cần %d Lương thực thô)" % [cooking_qty, raw_needed]
	if cook_btn != null:
		var raw_needed := cooking_qty * 2
		var can_cook := (raw_food_stock >= raw_needed) and (food_stock < food_capacity)
		cook_btn.disabled = not can_cook
		cook_btn.text = "🍳 NẤU NGAY %d KHẨU PHẦN QUÂN LƯƠNG" % cooking_qty if can_cook else "❌ THIẾU NGUYÊN LIỆU HOẶC KHO ĐẦY"
		cook_btn.modulate = Color(0.4, 1.0, 0.6) if can_cook else Color(0.7, 0.7, 0.7)

func _on_cook_pressed() -> void:
	_cook_specific_amount(cooking_qty)

func _cook_specific_amount(qty: int) -> void:
	status_banner_label.text = "🍳 Đang nấu %d khẩu phần quân lương..." % qty
	var res := await ApiClient.post_req("/api/survival/kitchen/cook", { "quantity": qty })
	if res["ok"]:
		status_banner_label.text = "✅ Đã nấu thành công %d Khẩu Phần Quân Lương!" % qty
		await refresh_kitchen_data()
	else:
		status_banner_label.text = "❌ Nấu thất bại: %s" % str(res["error"])

## -----------------------------------------------------------------------------
## TAB 1: MESS HALL (HERO FEEDING)
## -----------------------------------------------------------------------------
func _render_mess_hall_tab() -> void:
	browser = CardGridBrowserScript.new()
	browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	browser.hero_context_mode = UniversalHeroCardScript.ContextMode.KITCHEN
	browser.grid_columns = 3
	browser.card_selectable = true
	browser.multi_select_enabled = true
	browser.max_selection = 10
	content_container.add_child(browser)

	browser.configure_header("DANH SÁCH ANH HÙNG DÙNG BỮA", [
		"Tất Cả", "Đang Đói", "Đói Lả", "Tổ Đội PVE", "No Nê"
	])
	browser.set_action_button("🍖 Cho Ăn Hero Đã Chọn (+20% No)", "Cho ăn")

	var quick_feed_pve_btn := browser.add_extra_action_button(
		"🍱 Cho Ăn Toàn Đội PVE",
		"FEED_PVE_PARTY",
		Color(0.35, 0.85, 1.0)
	)

	browser.action_confirmed.connect(_on_feed_selected_heroes)
	browser.quick_action_requested.connect(_on_quick_action_requested)

	_populate_browser_items()

func _populate_browser_items() -> void:
	if browser == null:
		return
	var items: Array = []
	for h in GameState.heroes:
		if not (h is Dictionary) or GameState.is_hero_pve_deployed(h):
			continue
		var d: Dictionary = h.duplicate(true)
		var hid := str(d.get("id", ""))
		# Find hunger from survival_heroes_data if available
		for s in survival_heroes_data:
			if str(s.get("heroId", "")) == hid:
				d["hunger"] = float(s.get("hungerScore", 0.0))
				d["hungerScore"] = float(s.get("hungerScore", 0.0))
				d["fatigue"] = float(s.get("fatigueScore", 0.0))
				break
		items.append(d)
	browser.set_items(items, true)

func _on_feed_selected_heroes(selected: Array) -> void:
	if selected.is_empty():
		return
	status_banner_label.text = "🍖 Đang tiếp tế thức ăn cho %d Hero..." % selected.size()
	var fed_count: int = 0
	for h in selected:
		var hid := str(h.get("id", ""))
		var res := await ApiClient.post_req("/api/survival/heroes/%s/feed" % hid, { "quantity": 1 })
		if res["ok"]:
			fed_count += 1

	status_banner_label.text = "✅ Đã cho %d Hero dùng bữa (+20%% Độ no mỗi phần)!" % fed_count
	await refresh_kitchen_data()

func _on_quick_action_requested(action_code: String, _sel: Array) -> void:
	if action_code == "FEED_PVE_PARTY":
		var party_ids: Array = GameState.active_party_ids
		if party_ids.is_empty():
			status_banner_label.text = "ℹ️ Đội hình PVE hiện đang trống."
			return
		status_banner_label.text = "🍱 Đang cho toàn bộ Tổ đội PVE (%d Hero) dùng bữa..." % party_ids.size()
		var count: int = 0
		for hid in party_ids:
			if GameState.is_hero_pve_deployed(GameState.get_hero_by_id(str(hid))):
				continue
			var res := await ApiClient.post_req("/api/survival/heroes/%s/feed" % str(hid), { "quantity": 1 })
			if res["ok"]:
				count += 1
		status_banner_label.text = "✅ Đã tiếp tế quân lương thành công cho %d thành viên Tổ đội PVE!" % count
		await refresh_kitchen_data()

## -----------------------------------------------------------------------------
## DATA REFRESH
## -----------------------------------------------------------------------------
func refresh_kitchen_data() -> void:
	var res := await ApiClient.get_req("/api/survival")
	if res["ok"] and res["data"] is Dictionary:
		var d: Dictionary = res["data"]
		var food_info: Dictionary = d.get("food", {})
		food_stock = int(food_info.get("stock", 0))
		food_capacity = int(food_info.get("capacity", 200))
		survival_heroes_data = d.get("heroes", [])

	raw_food_stock = int(GameState.materials.get("FOOD_RAW", GameState.materials.get("RAW_FOOD", 0)))

	# Update Top Dashboard
	if food_stock_label != null:
		food_stock_label.text = "%d / %d" % [food_stock, food_capacity]
	if food_stock_bar != null:
		food_stock_bar.max_value = maxf(1.0, float(food_capacity))
		food_stock_bar.value = float(food_stock)
		var fill_style := StyleBoxFlat.new()
		var pct := float(food_stock) / maxf(1.0, float(food_capacity))
		fill_style.bg_color = Color(0.3, 0.9, 0.5) if pct > 0.35 else (Color(0.95, 0.7, 0.2) if pct > 0.15 else Color(0.95, 0.3, 0.3))
		food_stock_bar.add_theme_stylebox_override("fill", fill_style)

	if raw_food_label != null:
		raw_food_label.text = "%d" % raw_food_stock

	# Upkeep quote
	var up_res := await ApiClient.get_req("/api/survival/upkeep?hours=24")
	if up_res["ok"] and up_res["data"] is Dictionary:
		var req_amt := int(up_res["data"].get("required", 0))
		var days_left: float = float(food_stock) / maxf(1.0, float(req_amt))
		if upkeep_label != null:
			upkeep_label.text = "%d/ngày (Đủ dùng ~%.1f ngày)" % [req_amt, days_left]

	if active_tab_index == 0:
		_update_cooking_display()
	elif active_tab_index == 1:
		_populate_browser_items()

func _close() -> void:
	closed.emit()
	queue_free()
