class_name CodexModal
extends Control

## Encyclopedia & Castle Activity Log Modal (P2-14)
## 4 Tabs: Hero Codex (/api/hero-templates), Gear & Recipes (ItemGridBrowser 1★-7★),
## Alchemy & Items (/api/alchemy), Castle Activity Log (GameState.castle_activity_log)

signal closed

const UniversalHeroCardScript := preload("res://scripts/ui/universal_hero_card.gd")
const ItemGridBrowserScript := preload("res://scripts/ui/item_grid_browser.gd")

var _active_tab: int = 0
var _hero_templates: Array = []
var _crafting_recipes: Array = []
var _alchemy_recipes: Array = []

var _tab_buttons: Array[Button] = []
var _body_holder: Control
var _status_lbl: Label
var _embedded: bool = false

func set_embedded(embedded: bool) -> void:
	_embedded = embedded

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	await refresh_all()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.82)
	backdrop.visible = not _embedded
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	var parent_container: Control = self
	if not _embedded:
		var center := CenterContainer.new()
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		parent_container = center

	var vp := get_viewport_rect().size
	var pw := clampf(vp.x * 0.86, 700.0, 980.0) if vp.x > 0 else 940.0
	var ph := clampf(vp.y * 0.86, 480.0, 640.0) if vp.y > 0 else 600.0

	var panel := PanelContainer.new()
	if _embedded:
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		panel.custom_minimum_size = Vector2(pw, ph)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.92, 0.78, 0.35, 0.90)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	parent_container.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16); margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14); margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "📖 BÁCH KHOA TOÀN THƯ & NHẬT KÝ LÂU ĐÀI"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	hdr.add_child(title)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.visible = not _embedded
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var tab_names := ["🦸 Anh Hùng", "⚔️ Trang Bị & Rèn", "⚗️ Giả Kim & Thuốc", "📜 Nhật Ký Lâu Đài"]
	for i in range(tab_names.size()):
		var b := Button.new()
		b.text = tab_names[i]
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func(): switch_tab(idx))
		tabs.add_child(b)
		_tab_buttons.append(b)

	_body_holder = VBoxContainer.new()
	_body_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_body_holder)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải Bách Khoa..."
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func switch_tab(idx: int) -> void:
	_active_tab = idx
	_render_tab()

func refresh_all() -> void:
	var h_res := await ApiClient.get_req("/api/hero-templates")
	if not is_instance_valid(self): return
	if h_res.get("ok", false) and h_res.get("data") is Array:
		_hero_templates = h_res["data"]

	var c_res := await ApiClient.get_req("/api/crafting")
	if not is_instance_valid(self): return
	if c_res.get("ok", false) and c_res.get("data") is Dictionary:
		_crafting_recipes = c_res["data"].get("recipes", []) if c_res["data"].get("recipes") is Array else []

	var a_res := await ApiClient.get_req("/api/alchemy")
	if not is_instance_valid(self): return
	if a_res.get("ok", false) and a_res.get("data") is Dictionary:
		var ad: Dictionary = a_res["data"]
		_alchemy_recipes = ad.get("recipes", ad.get("formulas", [])) if (ad.get("recipes") is Array or ad.get("formulas") is Array) else []

	if _status_lbl != null:
		_status_lbl.text = "✅ Đã tải: %d Anh Hùng • %d Công thức Rèn • %d Giả Kim • %d Nhật ký" % [
			_hero_templates.size(), _crafting_recipes.size(), _alchemy_recipes.size(), GameState.castle_activity_log.size()
		]
	_render_tab()

func _render_tab() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].modulate = Color(1.0, 0.90, 0.42) if i == _active_tab else Color(0.76, 0.84, 0.92)
	if _body_holder == null:
		return
	for c in _body_holder.get_children():
		c.queue_free()

	match _active_tab:
		0: _render_heroes_codex()
		1: _render_equipment_codex()
		2: _render_alchemy_codex()
		3: _render_activity_log()

func _render_heroes_codex() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_holder.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	if _hero_templates.is_empty():
		var lbl := Label.new()
		lbl.text = "(Chưa có dữ liệu Anh Hùng mẫu.)"
		grid.add_child(lbl)
		return

	for t in _hero_templates:
		if not (t is Dictionary): continue
		var hcard: Control = UniversalHeroCardScript.new()
		grid.add_child(hcard)
		hcard.setup({
			"id": str(t.get("id", "")),
			"name": str(t.get("name", "Hero")),
			"rarity": int(t.get("defaultRarity", t.get("rarity", 1))),
			"level": 1,
			"maxLevel": 20,
			"classCode": str(t.get("classCode", "WARRIOR")),
		}, 0, false)

func _render_equipment_codex() -> void:
	var browser: Control = ItemGridBrowserScript.new()
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_holder.add_child(browser)
	browser.configure_header("Từ Điển Trang Bị & Công Thức Rèn (1★–7★)", ["Tất cả", "Vũ Khí", "Giáp", "Phụ Kiện"])

	var items: Array = []
	for r in _crafting_recipes:
		if not (r is Dictionary): continue
		items.append({
			"id": str(r.get("code", r.get("id", ""))),
			"itemId": str(r.get("code", "")),
			"name": str(r.get("name", r.get("code", "Trang bị"))),
			"starLevel": clampi(int(r.get("starLevel", r.get("rarity", 1))), 1, 7),
			"rarity": clampi(int(r.get("starLevel", r.get("rarity", 1))), 1, 7),
			"slot": str(r.get("slot", "WEAPON")),
			"quantity": 1,
			"source": "Lò Rèn",
		})
	if items.is_empty():
		for star in range(1, 8):
			items.append({
				"id": "codex-gear-%d" % star,
				"name": "Trang Bị Chuẩn %d★" % star,
				"starLevel": star,
				"rarity": star,
				"slot": "WEAPON",
				"quantity": 1,
				"source": "Lò Rèn / Tháp PvE",
			})
	browser.set_items(items)

func _render_alchemy_codex() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_holder.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	if _alchemy_recipes.is_empty():
		var lbl := Label.new()
		lbl.text = "⚗️ Xưởng Giả Kim điều chế Thuốc Hồi Máu, Thuốc Thể Lực, Thuốc Tăng Lực và Ngọc Hồi Sinh 7★."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(lbl)
		return

	for al in _alchemy_recipes:
		if not (al is Dictionary): continue
		var row := Label.new()
		row.text = "⚗️ %s — %s" % [str(al.get("name", al.get("code", "Công thức"))), str(al.get("description", "Điều chế tại Xưởng Giả Kim"))]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(row)

func _render_activity_log() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_holder.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	if GameState.castle_activity_log.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "📜 Chưa có hoạt động lâu đài nào được ghi nhận trong phiên này."
		vbox.add_child(empty_lbl)
		return

	for entry in GameState.castle_activity_log:
		var lbl := Label.new()
		lbl.text = "• " + entry
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 12)
		vbox.add_child(lbl)

func _close() -> void:
	closed.emit()
	queue_free()
