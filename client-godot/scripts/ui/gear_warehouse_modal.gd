class_name GearWarehouseModal
extends Control

## Universal Gear Warehouse Modal for Godot 4 Client
## Full-screen modal utilizing CardGridBrowser and UniversalItemCard
## for browsing warehouse equipment, equipping, and unequipping gear for Heroes.

signal item_equipped(item_id: String, item_name: String, hero_id: String, hero_name: String)
signal item_unequipped(item_id: String, item_name: String)
signal quick_unequip_requested(hero_id: String, hero_name: String)
signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalItemCardScript = preload("res://scripts/ui/universal_item_card.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")
const HeroPickerModalScript = preload("res://scripts/ui/hero_picker_modal.gd")

var target_hero_id: String = ""
var target_hero_name: String = "Hero"
var selected_item_data: Dictionary = {}

var browser
var title_label: Label
var hero_badge_label: Label
var item_detail_label: Label
var equip_action_btn: Button
var unequip_action_btn: Button

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	EventBus.heroes_updated.connect(func(_heroes: Array): setup(target_hero_id))
	_populate_browser()

func setup(hero_id: String = "") -> void:
	target_hero_id = hero_id
	var found := GameState.get_hero_by_id(target_hero_id)
	if not GameState.is_hero_available(found):
		var candidates: Array = GameState.heroes.filter(func(h): return h is Dictionary and GameState.is_hero_available(h))
		found = candidates[0] if not candidates.is_empty() else {}
	target_hero_id = str(found.get("id", ""))
	target_hero_name = str(found.get("name", "Chưa chọn Hero"))

	if is_inside_tree():
		_update_hero_header()
		_populate_browser()
		if not selected_item_data.is_empty():
			_on_item_clicked(selected_item_data)

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Backdrop
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.07, 0.86)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	# 2. Main Window
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 700)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.95, 0.85, 0.45, 0.85) # Gold / Bronze
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

	# 3. Header Row: Title & Close
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	title_label = Label.new()
	title_label.text = "📦 KHO TRANG BỊ & THÁNH DI VẬT (WAREHOUSE)"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	title_box.add_child(title_label)

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = "Quản lý kho đồ, so sánh chỉ số và Tháo / Mặc trang bị trực quan"
	subtitle_lbl.add_theme_font_size_override("font_size", 12)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	title_box.add_child(subtitle_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_modal)
	header_row.add_child(close_btn)

	# 4. Target Hero Banner & Quick Actions
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 8)
	root_vbox.add_child(hero_row)

	hero_badge_label = Label.new()
	hero_badge_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_badge_label.add_theme_font_size_override("font_size", 13)
	hero_row.add_child(hero_badge_label)

	var switch_hero_btn := Button.new()
	switch_hero_btn.text = "👥 Đổi Hero Khác"
	switch_hero_btn.custom_minimum_size = Vector2(0, 30)
	switch_hero_btn.pressed.connect(_on_switch_hero_pressed)
	hero_row.add_child(switch_hero_btn)

	var quick_unequip_btn := Button.new()
	quick_unequip_btn.text = "🔄 Tháo Toàn Bộ Về Kho"
	quick_unequip_btn.custom_minimum_size = Vector2(0, 30)
	quick_unequip_btn.modulate = Color(1.0, 0.75, 0.65)
	quick_unequip_btn.pressed.connect(func():
		if not target_hero_id.is_empty():
			quick_unequip_requested.emit(target_hero_id, target_hero_name)
	)
	hero_row.add_child(quick_unequip_btn)

	_update_hero_header()

	# 5. CardGridBrowser Component
	browser = CardGridBrowserScript.new()
	browser.browser_type = CardGridBrowserScript.BrowserType.ITEM
	browser.item_context_mode = UniversalItemCardScript.ContextMode.INVENTORY
	browser.grid_columns = 4
	browser.card_selectable = false
	browser.multi_select_enabled = false
	root_vbox.add_child(browser)

	var filter_pills: Array = ["Tất cả", "Chưa trang bị", "Vũ khí", "Giáp", "Trang sức", "Đang mặc"]
	browser.configure_header("Danh sách Trang bị trong Kho", filter_pills)
	browser.item_selected.connect(_on_item_clicked)

	# 6. Selected Item Inspection & Action Bar
	var action_panel := PanelContainer.new()
	var ap_style := StyleBoxFlat.new()
	ap_style.bg_color = Color(0.10, 0.13, 0.18, 0.95)
	ap_style.border_width_left = 1
	ap_style.border_width_top = 1
	ap_style.border_width_right = 1
	ap_style.border_width_bottom = 1
	ap_style.border_color = Color(0.25, 0.35, 0.45, 0.7)
	ap_style.corner_radius_top_left = 6
	ap_style.corner_radius_top_right = 6
	ap_style.corner_radius_bottom_left = 6
	ap_style.corner_radius_bottom_right = 6
	action_panel.add_theme_stylebox_override("panel", ap_style)
	root_vbox.add_child(action_panel)

	var ap_margin := MarginContainer.new()
	ap_margin.add_theme_constant_override("margin_left", 12)
	ap_margin.add_theme_constant_override("margin_top", 8)
	ap_margin.add_theme_constant_override("margin_right", 12)
	ap_margin.add_theme_constant_override("margin_bottom", 8)
	action_panel.add_child(ap_margin)

	var ap_row := HBoxContainer.new()
	ap_row.add_theme_constant_override("separation", 10)
	ap_margin.add_child(ap_row)

	item_detail_label = Label.new()
	item_detail_label.text = "👈 Bấm vào một món trang bị trong kho để xem chi tiết & thao tác Mặc / Tháo."
	item_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_detail_label.add_theme_font_size_override("font_size", 12)
	item_detail_label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96))
	ap_row.add_child(item_detail_label)

	equip_action_btn = Button.new()
	equip_action_btn.text = "🛡️ Mặc Cho Hero"
	equip_action_btn.custom_minimum_size = Vector2(160, 34)
	equip_action_btn.visible = false
	equip_action_btn.modulate = Color(0.45, 0.95, 0.65)
	equip_action_btn.pressed.connect(_on_equip_action_pressed)
	ap_row.add_child(equip_action_btn)

	unequip_action_btn = Button.new()
	unequip_action_btn.text = "➖ Tháo Về Kho"
	unequip_action_btn.custom_minimum_size = Vector2(160, 34)
	unequip_action_btn.visible = false
	unequip_action_btn.modulate = Color(1.0, 0.65, 0.65)
	unequip_action_btn.pressed.connect(_on_unequip_action_pressed)
	ap_row.add_child(unequip_action_btn)

func _update_hero_header() -> void:
	if hero_badge_label == null:
		return
	if target_hero_id.is_empty():
		hero_badge_label.text = "🎯 Đang thao tác: Chưa chọn Hero"
	else:
		hero_badge_label.text = "🎯 Hero đang chọn mặc đồ: 【%s】" % target_hero_name
		hero_badge_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.75))

func _populate_browser() -> void:
	if browser == null:
		return
	var items: Array = []
	if not GameState.equipment_list.is_empty():
		items = GameState.equipment_list
	else:
		items = GameState.crafting_overview.get("equipment", [])

	browser.set_items(items, false)

func _on_item_clicked(item: Dictionary) -> void:
	selected_item_data = item
	var iname := str(item.get("name", item.get("targetName", "Trang bị")))
	var estar := int(item.get("starLevel", item.get("rarity", 1)))
	var eenh := int(item.get("enhanceLevel", 0))
	var eslot := str(item.get("slot", item.get("itemType", "EQ"))).to_upper()
	var eq_hid := str(item.get("equippedHeroId", ""))
	var eq_hname := str(item.get("equippedHeroName", ""))

	var atk := int(item.get("atkBonus", item.get("attack", 0)))
	var def_b := int(item.get("defBonus", item.get("defense", 0)))
	var hp_b := int(item.get("hpBonus", item.get("maxHp", 0)))

	var stat_desc: PackedStringArray = []
	if atk > 0: stat_desc.append("+ATK %d" % atk)
	if def_b > 0: stat_desc.append("+DEF %d" % def_b)
	if hp_b > 0: stat_desc.append("+HP %d" % hp_b)

	var stat_str: String = ", ".join(stat_desc) if not stat_desc.is_empty() else "Không có chỉ số cộng thêm"
	var enh_str: String = " (+%d)" % eenh if eenh > 0 else ""

	var status_text := ""
	if eq_hid != "":
		status_text = " • 👤 Đang mặc bởi: %s" % eq_hname
	else:
		status_text = " • 📦 Trạng thái: Trong Kho đồ"

	item_detail_label.text = "[%s] %s %d★%s — %s%s" % [eslot, iname, estar, enh_str, stat_str, status_text]

	if eq_hid != "":
		equip_action_btn.visible = false
		unequip_action_btn.visible = true
		unequip_action_btn.text = "➖ Tháo Khỏi %s" % eq_hname
	else:
		unequip_action_btn.visible = false
		if not target_hero_id.is_empty():
			equip_action_btn.visible = true
			equip_action_btn.text = "🛡️ Mặc Cho %s" % target_hero_name
		else:
			equip_action_btn.visible = false

func _on_equip_action_pressed() -> void:
	if selected_item_data.is_empty() or target_hero_id.is_empty():
		return
	var item_id := str(selected_item_data.get("id", ""))
	var item_name := str(selected_item_data.get("name", "Trang bị"))
	item_equipped.emit(item_id, item_name, target_hero_id, target_hero_name)

func _on_unequip_action_pressed() -> void:
	if selected_item_data.is_empty():
		return
	var item_id := str(selected_item_data.get("id", ""))
	var item_name := str(selected_item_data.get("name", "Trang bị"))
	item_unequipped.emit(item_id, item_name)

func _on_switch_hero_pressed() -> void:
	var existing = get_tree().root.get_node_or_null("HeroPickerModal")
	if existing != null:
		existing.queue_free()

	var modal = HeroPickerModalScript.new()
	modal.exclude_deployed = true
	modal.name = "HeroPickerModal"
	modal.configure(
		"Chọn Hero Mặc / Tháo Trang Bị",
		false,
		1,
		UniversalHeroCardScript.ContextMode.EQUIPMENT,
		[],
		[],
		["Tất cả", "Trong Đội PvE", "Chưa xếp"],
		"Chọn Hero để duyệt kho và trang bị vật phẩm phù hợp"
	)
	modal.hero_picked.connect(func(picked_hero: Dictionary):
		setup(str(picked_hero.get("id", "")))
	)
	get_parent().add_child(modal)

func refresh_items() -> void:
	_populate_browser()
	if not selected_item_data.is_empty():
		var found_item: Dictionary = {}
		var iid := str(selected_item_data.get("id", ""))
		var cur_list: Array = GameState.equipment_list if not GameState.equipment_list.is_empty() else GameState.crafting_overview.get("equipment", [])
		for it in cur_list:
			if str(it.get("id", "")) == iid:
				found_item = it
				break
		if not found_item.is_empty():
			_on_item_clicked(found_item)
		else:
			equip_action_btn.visible = false
			unequip_action_btn.visible = false
			item_detail_label.text = "👈 Bấm vào một món trang bị trong kho để xem chi tiết & thao tác Mặc / Tháo."

func close_modal() -> void:
	closed.emit()
	queue_free()
