extends Control

signal closed

const HeroCard = preload("res://scripts/ui/universal_hero_card.gd")
const HeroPicker = preload("res://scripts/ui/hero_picker_modal.gd")
const CLASSES := {"WARRIOR": "Chiến binh", "THIEF": "Đạo tặc", "SPEARMAN": "Thương thủ", "ARCHER": "Cung thủ", "MAGE": "Pháp sư"}
const BOOKS := {"SAMPLE_HERO_EXP_100": "Sách EXP sơ cấp", "SAMPLE_HERO_EXP_1000": "Sách EXP trung cấp", "SAMPLE_HERO_EXP_10000": "Sách EXP cao cấp"}
var _hall: Dictionary = {}
var _selected: Dictionary = {}
var _preview: Dictionary = {}
var _tab := 0
var _busy := false
var _data_ready := false
var _panel: PanelContainer
var _body: VBoxContainer
var _hero_body: VBoxContainer
var _notice: Label
var _summary: Label
var _close_button: Button
var _refresh_button: Button
var _tabs: Array[Button] = []
var _action_buttons: Array[Button] = []
var _hours := 1
var _alchemy: Dictionary = {}
var _airship_port: Dictionary = {}
var _craft_quantity := 1

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(hall: Dictionary) -> void:
	_hall = hall.duplicate(true)
	_tab = clampi(int(hall.get("initialTab", 0)), 0, 2)

func _ready() -> void:
	_build_ui()
	EventBus.heroes_updated.connect(_on_heroes_updated)
	await _refresh()

func _build_ui() -> void:
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.02, 0.045, 0.9)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.12)
	style.border_color = Color(0.61, 0.48, 0.84)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	_panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := _label(header, "🔮 ĐẠI SẢNH MA THUẬT", 23, Color(0.88, 0.78, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_refresh_button = Button.new()
	_refresh_button.text = "Tải lại"
	_refresh_button.pressed.connect(func(): if not _busy: _refresh())
	header.add_child(_refresh_button)
	_close_button = Button.new()
	_close_button.text = "Đóng"
	_close_button.pressed.connect(func(): closed.emit(); queue_free())
	header.add_child(_close_button)
	_summary = _label(layout, "Đang tải đại sảnh...", 14)
	var tabs := HBoxContainer.new()
	layout.add_child(tabs)
	var names := ["📚 Thư viện", "⚗ Giả kim", "✨ Nghiên cứu"]
	for i in range(names.size()):
		var button := Button.new()
		button.text = names[i]
		button.custom_minimum_size.y = 42
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _select_tab(i))
		tabs.add_child(button)
		_tabs.append(button)
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(columns)
	var hero_scroll := ScrollContainer.new()
	hero_scroll.custom_minimum_size.x = 230
	hero_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(hero_scroll)
	_hero_body = VBoxContainer.new()
	_hero_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hero_body.add_theme_constant_override("separation", 8)
	hero_scroll.add_child(_hero_body)
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(content_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	content_scroll.add_child(_body)
	_notice = _label(layout, "", 14, Color(1.0, 0.86, 0.52))
	_notice.custom_minimum_size.y = 24
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	_render()

func _fit_panel() -> void:
	var available := get_viewport_rect().size - Vector2(48, 48)
	_panel.custom_minimum_size = Vector2(minf(1120, available.x), minf(700, available.y))

func _label(parent: Node, text: String, font_size := 15, color := Color(0.85, 0.89, 0.96)) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _section(title: String, description := "") -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.105, 0.17)
	style.set_corner_radius_all(8)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	_body.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	_label(box, title, 19, Color(0.88, 0.79, 1.0))
	if not description.is_empty(): _label(box, description, 14)
	return box

func _button(parent: Node, text: String, callback: Callable, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = disabled or _busy or not _data_ready
	button.pressed.connect(callback)
	parent.add_child(button)
	_action_buttons.append(button)
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _stock(code: String) -> int:
	return int(GameState.materials.get(code, 0))

func _can_develop() -> bool:
	return _data_ready and not _busy and GameState.is_hero_available(_selected) and not bool(_selected.get("isLocked", false)) and _hall.get("status") == "READY"

func _render() -> void:
	if _body == null: return
	_clear(_body)
	_clear(_hero_body)
	_action_buttons.clear()
	_close_button.disabled = _busy
	_refresh_button.disabled = _busy
	_summary.text = "Cấp %d • Nhân sự %d/6 • Bạc: %d" % [int(_hall.get("level", 1)), _hall.get("workers", []).size(), GameState.silver_coins]
	for i in range(_tabs.size()):
		_tabs[i].disabled = _busy
		_tabs[i].modulate = Color(0.91, 0.77, 1.0) if i == _tab else Color(0.65, 0.72, 0.83)
	_render_hero()
	if _tab == 0: _render_library()
	elif _tab == 1: _render_alchemy()
	else: _render_research()

func _render_hero() -> void:
	_label(_hero_body, "Hero đang chọn", 17)
	if not _selected.is_empty():
		var card = HeroCard.new()
		_hero_body.add_child(card)
		var modes := [HeroCard.ContextMode.LIBRARY, HeroCard.ContextMode.RECOVERY, HeroCard.ContextMode.RESEARCH]
		card.setup(_selected, modes[_tab])
	else: _label(_hero_body, "Chọn một Hero còn sống để sử dụng chức năng.")
	_button(_hero_body, "Chọn Hero", _pick_hero)
	var assignments := GameState.get_worker_assignment_map()
	var id := str(_selected.get("id", ""))
	var job: Dictionary = assignments.get(id, {})
	var here := str(job.get("building", {}).get("id", "")) == str(_hall.get("id", ""))
	var elsewhere := not job.is_empty() and not here
	var manage_disabled: bool = _selected.is_empty() or not GameState.is_hero_available(_selected) or elsewhere or (not here and _hall.get("workers", []).size() >= 6)
	_button(_hero_body, "Cho Hero rời đại sảnh" if here else "Phân công vào đại sảnh", _toggle_worker, manage_disabled)
	_label(_hero_body, "Đang làm việc ở công trình khác." if elsewhere else "Ưu tiên tối đa 2 MAGE sản xuất sách; 2 Hero tiếp theo hỗ trợ giả kim.", 13)
	for worker in _hall.get("workers", []):
		_label(_hero_body, "• " + str(worker.get("heroName", "Hero")), 13)

func _production(wing: String, title: String) -> void:
	var box := _section(title)
	for output in _hall.get("magicProduction", []):
		if str(output.get("wing", "")) != wing: continue
		_label(box, "Đang có %.1f / %d • Sản lượng %.1f/giờ" % [float(output.get("stored", 0)), int(output.get("capacity", 0)), float(output.get("ratePerHour", 0))])
		if wing == "LIBRARY" and output.get("workerIds", []).is_empty(): _label(box, "Cần phân công MAGE để sản xuất sách.", 14, Color(1.0, 0.77, 0.35))
	_button(box, "Thu hoạch sách và đá của đại sảnh", func(): _act("/api/base/buildings/%s/collect" % _hall.get("id", ""), {}, "Đã thu hoạch sản phẩm vào kho."))

func _render_library() -> void:
	_production("LIBRARY", "📚 Sản xuất sách EXP")
	var usable := _can_develop()
	var maxed := int(_selected.get("level", 1)) >= int(_selected.get("maxLevel", 10))
	var study := _section("Tu luyện MAGE", "Chọn MAGE để nhận EXP theo cấp đại sảnh. Trần cấp của Hero vẫn được áp dụng.")
	var hours := SpinBox.new()
	hours.min_value = 1
	hours.max_value = 12
	hours.value = _hours
	hours.suffix = " giờ"
	hours.editable = not _busy
	hours.value_changed.connect(func(value): _hours = int(value))
	study.add_child(hours)
	_button(study, "Tu luyện ma pháp", _study, not usable or str(_selected.get("classCode", "")) != "MAGE" or maxed)
	var books := _section("Đọc sách EXP", "Dùng một cuốn cho Hero đang chọn.")
	for code in BOOKS:
		_button(books, "%s • Còn %d" % [BOOKS[code], _stock(code)], func(): _use_book(code), not usable or maxed or _stock(code) < 1)
	var skills := _section("Lĩnh hội kỹ năng", "Nâng cấp tiêu hao 1 Sách Kỹ Năng mỗi lần. Đang có: %d." % _stock("SAMPLE_HERO_SKILL_BOOK"))
	if _selected.get("skills", []).is_empty(): _label(skills, "Hero này chưa có kỹ năng được cấu hình.")
	for skill in _selected.get("skills", []):
		var unlocked := bool(skill.get("isUnlocked", false))
		var level := int(skill.get("skillLevel", 1))
		var code := str(skill.get("code", ""))
		var name := str(skill.get("name", "Kỹ năng"))
		_button(skills, ("Nâng %s • Lv.%d/%d" % [name, level, int(skill.get("maxLevel", 5))]) if unlocked else "Mở khóa " + name,
			func(): _skill(code, unlocked), not usable or (level >= int(skill.get("maxLevel", 5)) or _stock("SAMPLE_HERO_SKILL_BOOK") < 1 if unlocked else not bool(skill.get("canUnlock", false))))

func _render_alchemy() -> void:
	_production("ALCHEMY_WORKSHOP", "⚗ Sản xuất Đá Cường Hóa")
	var stock := _section("Kho giả kim")
	_label(stock, "Đá Cường Hóa: %d\nThuốc điều trị: %d" % [_stock("ENHANCEMENT_STONE"), _stock("MEDICINE")])
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 8)
	stock.add_child(card_row)
	var item_card_script = load("res://scripts/ui/universal_item_card.gd")
	for mat_def in [
		{"id": "ENHANCEMENT_STONE", "name": "Đá Cường Hóa", "star": 2, "slot": "MATERIAL"},
		{"id": "MEDICINE", "name": "Thuốc điều trị", "star": 2, "slot": "POTION"},
		{"id": "MANA_POTION", "name": "Thuốc ma lực", "star": 2, "slot": "POTION"},
		{"id": "STRENGTH_POTION", "name": "Thuốc cường lực", "star": 3, "slot": "POTION"},
		{"id": "ALCHEMY_HERB_1", "name": "Dược liệu 1★", "star": 1, "slot": "MATERIAL"},
	]:
		var ic: Control = item_card_script.new()
		ic.setup({
			"id": mat_def["id"],
			"itemId": mat_def["id"],
			"name": mat_def["name"],
			"starLevel": mat_def["star"],
			"slot": mat_def["slot"],
			"quantity": _stock(str(mat_def["id"])),
			"source": "Đại Sảnh Ma Thuật",
		}, 0, false)
		card_row.add_child(ic)
	var care := _section("Dùng thuốc điều trị", "Dùng 1 thuốc để chữa khẩn cấp cho Hero đang chọn. Thuốc không hồi sinh Hero tử trận.")
	_button(care, "Chữa trị bằng 1 thuốc", _heal, not _can_develop() or _stock("MEDICINE") < 1 or int(_selected.get("hp", 0)) >= int(_selected.get("maxHp", 1)))
	var recipes := _section("Chế thuốc", "Mỗi viên: 3 Dược liệu 1★ và 100 bạc. Nghiên cứu công thức tại tab Nghiên cứu.")
	_label(recipes, "Dược liệu 1★: %d" % _stock("ALCHEMY_HERB_1"))
	var amount := SpinBox.new()
	amount.min_value = 1
	amount.max_value = 99
	amount.value = _craft_quantity
	amount.suffix = " viên"
	amount.editable = not _busy
	amount.value_changed.connect(func(value): _craft_quantity = int(value))
	recipes.add_child(amount)
	for recipe in _alchemy.get("recipes", []):
		var code := str(recipe.get("code", ""))
		_button(recipes, "Chế %s • %s" % [recipe.get("name", code), "Đã mở" if bool(recipe.get("unlocked", false)) else "Chưa nghiên cứu"],
			func(): _act("/api/alchemy/craft", {"code": code, "quantity": _craft_quantity}, "Đã chế thuốc."), not bool(recipe.get("unlocked", false)))
	var use := _section("Dùng thuốc ngoài trận", "Thuốc ma lực hồi 50% MP; cường lực tăng 20% ATK trong trận PvE kế tiếp.")
	for code in ["MANA_POTION", "STRENGTH_POTION"]:
		_button(use, "%s • Còn %d" % ["Thuốc ma lực" if code == "MANA_POTION" else "Thuốc cường lực", _stock(code)],
			func(): _act("/api/alchemy/use", {"heroId": _selected.get("id", ""), "itemId": code}, "Đã sử dụng thuốc."), not _can_develop() or _stock(code) < 1)

func _render_research() -> void:
	var working := GameState.get_worker_assignment_map().has(str(_selected.get("id", "")))
	var change := _section("✨ Chuyển chức", "Cần Lv.20, 50.000 bạc và 1 Ấn Chuyển Nghề. Chỉ hiển thị nghề đạt điều kiện chỉ số của Hero.")
	_label(change, "Ấn Chuyển Nghề: %d" % _stock("CLASS_CHANGE_TOKEN"))
	if working: _label(change, "Cho Hero rời công trình trước khi chuyển chức hoặc thức tỉnh.", 14, Color(1.0, 0.78, 0.35))
	var options: Array = _selected.get("classChangeOptions", [])
	if options.is_empty(): _label(change, "Hero chưa đủ cấp/chỉ số để chuyển chức.")
	for code in options:
		var current := str(_selected.get("classCode", "")) == str(code)
		_button(change, str(CLASSES.get(code, code)) + (" • Hiện tại" if current else " • Chuyển nghề"), func(): _change_class(str(code)),
			current or working or not _can_develop() or int(_selected.get("level", 1)) < 20 or _stock("CLASS_CHANGE_TOKEN") < 1 or GameState.silver_coins < 50000)
	var awaken := _section("Thức tỉnh huyết mạch")
	if _preview.is_empty():
		_label(awaken, "Chọn Hero để xem điều kiện và chi phí thức tỉnh.")
	else:
		var hero: Dictionary = _preview.get("hero", {})
		var req: Dictionary = _preview.get("requirements", {})
		_label(awaken, "Bậc +%d → +%d\nLõi cần %d / đang có %d • Phí %d bạc\nYêu cầu Lv.%d • Bậc đột phá %d" % [int(hero.get("currentRank", 0)), int(hero.get("nextRank", 1)), int(req.get("materialQuantity", 0)), int(req.get("currentMaterialCount", 0)), int(req.get("silverCost", 0)), int(req.get("requiredHeroLevel", 1)), int(req.get("requiredPromotionRank", 0))])
		_button(awaken, "Đã thức tỉnh tối đa" if bool(hero.get("isMax", false)) else "Thức tỉnh Hero", _awaken,
			working or not _can_develop() or not bool(_preview.get("canAwaken", false)))
	var tree := _section("Cây công nghệ • Giả kim", "Nền tảng → ba nhánh độc lập. Nghiên cứu hoàn tất ngay và được lưu theo Master.")
	_label(tree, "Dược liệu 1★: %d" % _stock("ALCHEMY_HERB_1"))
	var learned: Array = []
	for tech in _alchemy.get("technologies", []):
		if bool(tech.get("researched", false)): learned.append(tech.get("code"))
	for tech in _alchemy.get("technologies", []):
		var code := str(tech.get("code", ""))
		var done := bool(tech.get("researched", false))
		var prerequisite: Variant = tech.get("prerequisite")
		_label(tree, "%s • %d bạc + %d dược liệu" % [tech.get("name", code), int(tech.get("silver", 0)), int(tech.get("herbs", 0))])
		_button(tree, "Đã nghiên cứu" if done else "Nghiên cứu " + str(tech.get("name", code)),
			func(): _act("/api/alchemy/research", {"code": code}, "Nghiên cứu đã hoàn tất."), done or (prerequisite != null and not learned.has(prerequisite)))
	var airship_sec := _section("⚓ Cây công nghệ • Bến Thiên Hành", "Mở khóa bản thiết kế tàu bay (Trinh Sát 2×2, Cứu Hộ 2×3, Tấn Công 3×3, Vận Tải 4×5), mở rộng sàn bãi đậu và hỗ trợ viễn chinh RTS.")
	if _airship_port.is_empty():
		_label(airship_sec, "Đang tải dữ liệu công nghệ Bến Thiên Hành...")
	elif not bool(_airship_port.get("unlockedByFloor", false)):
		_label(airship_sec, "🔒 Yêu cầu vượt Tháp tầng %d để mở khóa nghiên cứu Bến Thiên Hành (hiện tại: Tầng %d)." % [
			int(_airship_port.get("requiredFloor", 25)), int(_airship_port.get("clearedFloor", 1))
		], 14, Color(1.0, 0.72, 0.35))
	elif not bool(_airship_port.get("portBuilt", false)):
		_label(airship_sec, "🏗️ Bạn đã vượt Tháp tầng 25! Hãy xây công trình [Bến Thiên Hành – Cảng Tàu Bay] ngoài Căn cứ 3D để bắt đầu nghiên cứu.", 14, Color(0.55, 0.88, 1.0))
	else:
		var dock_info: Dictionary = _airship_port.get("dock", {})
		_label(airship_sec, "Cảng Tàu Bay Lv.%d • Sàn bãi đậu hiện tại: %d×%d ô • Thời lượng tầm nhìn Scout: %d phút" % [
			int(_airship_port.get("portLevel", 1)),
			int(dock_info.get("width", 4)),
			int(dock_info.get("height", 4)),
			int(int(_airship_port.get("visionDurationSeconds", 3600)) / 60),
		], 13, Color(0.65, 0.9, 1.0))
		var branch_labels := {
			"SHIPYARD": "🛸 Nhánh Chế Tạo Tàu Bay",
			"DOCK": "📐 Nhánh Mở Rộng Sàn Bãi Đậu",
			"LOGISTICS": "📡 Nhánh Hỗ Trợ Viễn Chinh & Radar",
		}
		var tech_nodes: Array = _airship_port.get("techTree", [])
		for branch_key in ["SHIPYARD", "DOCK", "LOGISTICS"]:
			_label(airship_sec, str(branch_labels[branch_key]), 15, Color(0.95, 0.84, 0.45))
			for node in tech_nodes:
				if str(node.get("branch", "")) != branch_key:
					continue
				var tcode := str(node.get("code", ""))
				var unlocked_t := bool(node.get("unlocked", false))
				var can_unlock := bool(node.get("canUnlock", false))
				var cost_silver := int(node.get("costSilver", 0))
				var req_port := int(node.get("requiredPortLevel", 1))
				_label(airship_sec, "• %s (Cảng Lv.%d+ • %d bạc)\n  %s" % [
					str(node.get("name", tcode)), req_port, cost_silver, str(node.get("description", ""))
				], 13, Color(0.55, 0.96, 0.68) if unlocked_t else Color(0.84, 0.88, 0.95))
				var btn_txt := "✅ Đã nghiên cứu" if unlocked_t else ("🔬 Nghiên cứu %s (%d bạc)" % [str(node.get("name", tcode)), cost_silver])
				_button(
					airship_sec,
					btn_txt,
					func(): _act("/api/base/airships/tech/%s/unlock" % tcode, {}, "Đã mở khóa công nghệ Bến Thiên Hành!"),
					unlocked_t or not can_unlock or GameState.silver_coins < cost_silver
				)

func _pick_hero() -> void:
	if _busy: return
	var picker = HeroPicker.new()
	picker.exclude_deployed = true
	picker.configure("Chọn Hero cho Đại Sảnh Ma Thuật")
	picker.hero_picked.connect(func(hero): _select_hero(hero))
	add_child(picker)

func _select_hero(hero: Dictionary) -> void:
	if _busy: return
	_selected = hero
	_preview = {}
	_render()
	if _tab == 2: await _load_preview()

func _select_tab(index: int) -> void:
	if _busy: return
	_tab = index
	_preview = {}
	_render()
	if _tab == 2: await _load_preview()

func _on_heroes_updated(_heroes: Array) -> void:
	if _busy: return
	_selected = GameState.get_hero_by_id(str(_selected.get("id", "")))
	if not GameState.is_hero_available(_selected): _selected = {}
	_preview = {}
	_render()
	if _tab == 2: _load_preview()

func _refresh() -> void:
	_busy = true
	_preview = {}
	_render()
	var ok := await GameState.refresh_profile()
	if not is_inside_tree(): return
	if ok: ok = await GameState.refresh_base_overview()
	if not is_inside_tree(): return
	if ok: ok = await GameState.refresh_inventory()
	if not is_inside_tree(): return
	if ok: ok = await GameState.refresh_heroes()
	if not is_inside_tree(): return
	if ok:
		var alchemy_result: Dictionary = await ApiClient.get_req("/api/alchemy")
		if not is_inside_tree(): return
		ok = bool(alchemy_result.get("ok", false))
		_alchemy = alchemy_result.get("data", {}) if ok else {}
		var airship_result: Dictionary = await ApiClient.get_req("/api/base/airships")
		if not is_inside_tree(): return
		_airship_port = airship_result.get("data", {}) if bool(airship_result.get("ok", false)) and airship_result.get("data", null) is Dictionary else {}
	_data_ready = ok
	if ok:
		var found := false
		for hall in GameState.base_overview.get("buildings", []):
			if str(hall.get("id", "")) == str(_hall.get("id", "")) and hall.get("buildingType") == "HALL_OF_MAGIC":
				_hall = hall
				found = true
		_data_ready = found and _hall.get("status") == "READY"
		_selected = GameState.get_hero_by_id(str(_selected.get("id", "")))
		if not GameState.is_hero_available(_selected):
			_selected = {}
			for hero in GameState.heroes:
				if GameState.is_hero_available(hero):
					_selected = hero
					break
	_busy = false
	_render()
	_notice.text = "" if _data_ready else "Không tải được đại sảnh sẵn sàng. Hãy bấm Tải lại."
	if _tab == 2 and _data_ready: await _load_preview()

func _load_preview() -> void:
	if _busy or not _data_ready or _selected.is_empty(): return
	var id := str(_selected.get("id", ""))
	_busy = true
	_render()
	var response: Dictionary = await ApiClient.get_req("/api/heroes/%s/awaken/preview" % id)
	if not is_inside_tree(): return
	_busy = false
	var fresh := GameState.get_hero_by_id(id)
	if GameState.is_hero_available(fresh):
		_selected = fresh
		_preview = response.get("data", {}) if bool(response.get("ok", false)) else {}
	else:
		_selected = {}
		_preview = {}
	_render()
	if not bool(response.get("ok", false)): _notice.text = "Không tải được điều kiện thức tỉnh."

func _act(path: String, body: Dictionary, success: String, method := HTTPClient.METHOD_POST) -> void:
	if _busy or not _data_ready: return
	_busy = true
	_render()
	_notice.text = "Đang thực hiện..."
	var headers: Dictionary = {}
	if path.begins_with("/api/alchemy/"): headers["Idempotency-Key"] = "alchemy-%d-%d" % [Time.get_unix_time_from_system() * 1000, randi()]
	var response: Dictionary = await ApiClient.api_request(path, method, body, headers)
	if not is_inside_tree(): return
	var message := success if bool(response.get("ok", false)) else _error_message(str(response.get("error", "Không thể thực hiện.")))
	if int(response.get("status", 0)) == 0: message = "Chưa nhận được kết quả. Đã yêu cầu tải lại dữ liệu; hãy kiểm tra trước khi thao tác tiếp."
	await _refresh()
	if is_inside_tree(): _notice.text = message + ("" if _data_ready else " Chưa tải lại được dữ liệu.")

func _study() -> void:
	await _act("/api/base/buildings/%s/mage-study" % _hall.get("id", ""), {"heroId": _selected.get("id", ""), "hours": _hours}, "Hero đã nhận EXP tu luyện.")

func _use_book(code: String) -> void:
	await _act("/api/inventory/items/%s/use" % code, {"targetHeroId": _selected.get("id", ""), "quantity": 1}, "Đã sử dụng sách EXP.")

func _skill(code: String, unlocked: bool) -> void:
	await _act("/api/heroes/%s/skills/%s/%s" % [_selected.get("id", ""), code, "upgrade" if unlocked else "unlock"], {}, "Đã cập nhật kỹ năng.")

func _heal() -> void:
	await _act("/api/alchemy/use", {"heroId": _selected.get("id", ""), "itemId": "MEDICINE"}, "Đã dùng thuốc điều trị cho Hero.")

func _change_class(code: String) -> void:
	await _act("/api/heroes/%s/class-change" % _selected.get("id", ""), {"targetClass": code}, "Đã chuyển chức Hero.")

func _awaken() -> void:
	await _act("/api/heroes/%s/awaken" % _selected.get("id", ""), {}, "Đã thức tỉnh Hero.")

func _toggle_worker() -> void:
	var id := str(_selected.get("id", ""))
	var here := false
	for worker in _hall.get("workers", []):
		if str(worker.get("heroInstanceId", "")) == id: here = true
	if here: await _act("/api/base/buildings/%s/workers/%s" % [_hall.get("id", ""), id], {}, "Hero đã rời vị trí làm việc.", HTTPClient.METHOD_DELETE)
	else: await _act("/api/base/buildings/%s/workers" % _hall.get("id", ""), {"heroId": id}, "Đã phân công Hero vào đại sảnh.")

func _error_message(code: String) -> String:
	match code:
		"ERR_ALCHEMY_MISSING_RESOURCES": return "Không đủ bạc hoặc Dược liệu 1★."
		"ERR_ALCHEMY_PREREQUISITE": return "Cần nghiên cứu công nghệ trước đó."
		"ERR_ALCHEMY_RECIPE_LOCKED": return "Công thức chưa được nghiên cứu."
		"ERR_ALCHEMY_ALREADY_RESEARCHED": return "Công nghệ này đã được nghiên cứu."
		"ERR_CONSUMABLE_STOCK": return "Không đủ vật phẩm trong kho."
		"ERR_COMBAT_BUFF_ACTIVE": return "Hero đã có hiệu ứng thuốc cường lực cho trận kế tiếp."
		"ERR_COMBAT_MP_FULL": return "Hero đã đầy MP hoặc không có MP."
		"ERR_COMBAT_HP_FULL": return "Hero đã đầy HP và không có thương tích."
		"ERR_CLASS_NOT_ELIGIBLE": return "Hero chưa đủ điều kiện chỉ số để chuyển sang nghề này."
		"ERR_CLASS_LEVEL_REQUIRED": return "Hero cần đạt cấp 20 để chuyển chức."
		"ERR_CLASS_ITEM_REQUIRED": return "Cần 1 Ấn Chuyển Nghề."
		"ERR_CLASS_INSUFFICIENT_SILVER": return "Không đủ bạc để chuyển chức."
		"ERR_HERO_PERMANENTLY_DEAD": return "Hero đã tử trận, cần hồi sinh tại Sử Điện."
	return code
