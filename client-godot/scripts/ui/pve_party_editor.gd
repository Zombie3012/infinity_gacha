extends Control

signal saved(party_id: String, payload: Dictionary)
signal closed
signal retry_requested

const Ui := preload("res://scripts/ui/pve_ui.gd")
var party_data: Dictionary = {}
var _hero_ids: Array = []
var _slots: Dictionary = {}
var _skill_orders: Dictionary = {}
var _focused_hero: String = ""
var _name_input: LineEdit
var _priority: OptionButton
var _grid: GridContainer
var _skill_box: VBoxContainer
var _count_label: Label
var _save_button: Button
var _roster_box: VBoxContainer
var _hero_checks: Dictionary = {}
var _feedback: Label
var _retry_button: Button
var _close_button: Button

func configure(party: Dictionary) -> void:
	party_data = party.duplicate(true)
	for member in party_data.get("members", []):
		_hero_ids.append(str(member.get("heroId", "")))
	var plan_value: Variant = party_data.get("plan")
	if plan_value is Dictionary:
		for member in plan_value.get("members", []):
			_slots[int(member.get("slotIndex", 0))] = str(member.get("heroId", ""))
			_skill_orders[str(member.get("heroId", ""))] = member.get("skillOrder", []).duplicate()
	else:
		for index in range(_hero_ids.size()):
			_slots[[0, 2, 4, 6, 8][index]] = _hero_ids[index]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.04, 0.9)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.panel(center, 990)
	Ui.label(panel, "CHUẨN BỊ ĐỘI CHINH PHẠT", 22, Ui.GOLD)
	Ui.label(panel, "Chọn tối đa 5 Hero, xếp vị trí và đặt chiến thuật trước khi triển khai.", 14, Ui.MUTED)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Tên đội"
	_name_input.max_length = 60
	_name_input.text = str(party_data.get("name", ""))
	panel.add_child(_name_input)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	panel.add_child(body)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 285
	body.add_child(left)
	_count_label = Ui.label(left, "", 14, Ui.TEAL)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(285, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_roster_box = VBoxContainer.new()
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_box)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 325
	body.add_child(middle)
	Ui.label(middle, "HÀNG TRƯỚC — ĐỐI DIỆN KẺ ĐỊCH", 13, Ui.GOLD)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	middle.add_child(_grid)
	Ui.label(middle, "Hàng giữa / Hàng sau", 13, Ui.MUTED)
	var hint := Ui.label(middle, "Bấm vào một ô để chọn hoặc đổi vị trí Hero.\nÔ trống không cộng chỉ số.", 13, Ui.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 290
	body.add_child(right)
	Ui.label(right, "ƯU TIÊN MỤC TIÊU", 14, Ui.GOLD)
	_priority = OptionButton.new()
	_priority.add_item("Đánh hàng trước")
	_priority.add_item("Đánh mục tiêu ít máu nhất")
	_priority.add_item("Đánh mục tiêu mạnh nhất")
	var selected_priority := str(party_data.get("plan", {}).get("targetPriority", "FRONTLINE")) if party_data.get("plan") is Dictionary else "FRONTLINE"
	_priority.select(maxi(0, ["FRONTLINE", "LOWEST_HP", "HIGHEST_ATK"].find(selected_priority)))
	right.add_child(_priority)
	var skill_scroll := ScrollContainer.new()
	skill_scroll.custom_minimum_size = Vector2(290, 270)
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(skill_scroll)
	_skill_box = VBoxContainer.new()
	_skill_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(_skill_box)
	var info := Ui.label(right, "Khi giao chiến, Hero tự hành động.\nKhông thể đổi chiến thuật giữa trận.", 13, Ui.MUTED)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	_feedback = Ui.label(panel, "", 13, Color("ffb49a"))
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(actions)
	_save_button = Ui.button(actions, "Lưu đội hình & chiến thuật", _on_save, true)
	_save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_retry_button = Ui.button(actions, "Thử lại lệnh", func(): retry_requested.emit(), true)
	_retry_button.visible = false
	_close_button = Ui.button(actions, "Đóng", func(): closed.emit(); queue_free())
	_build_roster()
	if not _hero_ids.is_empty():
		_focused_hero = str(_hero_ids[0])
	_render_formation()
	_render_skills()

func _build_roster() -> void:
	var reserved: Array = PveState.reserved_hero_ids()
	for hero in GameState.heroes:
		if not (hero is Dictionary):
			continue
		var hero_id := str(hero.get("id", ""))
		var state_value := str(hero.get("state", ""))
		var check := CheckBox.new()
		check.text = "%s · %d★ Lv.%d" % [str(hero.get("name", "Hero")), int(hero.get("rarity", 1)), int(hero.get("level", 1))]
		check.clip_text = true
		check.custom_minimum_size.x = 275
		check.tooltip_text = "%s · %s" % [str(hero.get("name", "")), state_value]
		check.button_pressed = _hero_ids.has(hero_id)
		check.disabled = (state_value in ["DEAD", "DISABLED"] or reserved.has(hero_id)) and not check.button_pressed
		if reserved.has(hero_id):
			check.tooltip_text += " — Đang được triển khai"
		check.toggled.connect(func(selected: bool): _toggle_hero(hero_id, selected))
		_roster_box.add_child(check)
		_hero_checks[hero_id] = check

func _toggle_hero(hero_id: String, selected: bool) -> void:
	if selected:
		if _hero_ids.size() >= 5:
			_hero_checks[hero_id].set_pressed_no_signal(false)
			return
		_hero_ids.append(hero_id)
		for cell in [0, 2, 4, 6, 8, 1, 3, 5, 7]:
			if not _slots.has(cell):
				_slots[cell] = hero_id
				break
		_focused_hero = hero_id
	else:
		_hero_ids.erase(hero_id)
		for cell in _slots.keys():
			if _slots[cell] == hero_id:
				_slots.erase(cell)
		if _focused_hero == hero_id:
			_focused_hero = str(_hero_ids[0]) if not _hero_ids.is_empty() else ""
	_render_formation()
	_render_skills()

func _render_formation() -> void:
	Ui.clear(_grid)
	_count_label.text = "%d / 5 Hero đã chọn" % _hero_ids.size()
	_save_button.disabled = _hero_ids.is_empty()
	for cell in range(9):
		var hero_id := str(_slots.get(cell, ""))
		var hero: Dictionary = GameState.get_hero_by_id(hero_id)
		var caption := str(hero.get("name", "Ô trống")) if not hero_id.is_empty() else "Ô trống"
		var button := Ui.button(_grid, caption, func(): _choose_cell(cell), hero_id == _focused_hero and not hero_id.is_empty())
		button.custom_minimum_size = Vector2(104, 75)
		button.clip_text = true
		button.tooltip_text = "Hàng %d · Cột %d\n%s" % [cell / 3 + 1, cell % 3 + 1, caption]

func _choose_cell(cell: int) -> void:
	var menu := PopupMenu.new()
	add_child(menu)
	menu.add_item("Để trống ô này", 0)
	for index in range(_hero_ids.size()):
		var hero: Dictionary = GameState.get_hero_by_id(str(_hero_ids[index]))
		menu.add_item(str(hero.get("name", "Hero")), index + 1)
	menu.id_pressed.connect(func(choice: int):
		var previous := str(_slots.get(cell, ""))
		if choice == 0:
			_slots.erase(cell)
		else:
			var next_id := str(_hero_ids[choice - 1])
			var old_cell: int = -1
			for occupied in _slots:
				if str(_slots[occupied]) == next_id:
					old_cell = int(occupied)
			if old_cell >= 0:
				if previous.is_empty():
					_slots.erase(old_cell)
				else:
					_slots[old_cell] = previous
			_slots[cell] = next_id
			_focused_hero = next_id
		_render_formation()
		_save_button.disabled = _slots.size() != _hero_ids.size() or _hero_ids.is_empty()
		_render_skills()
	)
	menu.popup_hide.connect(func(): menu.queue_free())
	menu.position = Vector2i(get_global_mouse_position())
	menu.popup()

func _render_skills() -> void:
	Ui.clear(_skill_box)
	var hero: Dictionary = GameState.get_hero_by_id(_focused_hero)
	var heading := Ui.label(_skill_box, "KỸ NĂNG — " + str(hero.get("name", "Chọn một Hero")), 13, Ui.GOLD)
	heading.clip_text = true
	heading.tooltip_text = str(hero.get("name", ""))
	var skills: Array = hero.get("skills", []).filter(func(skill): return bool(skill.get("isUnlocked", false)))
	var available: Array = skills.map(func(skill): return str(skill.get("code", "")))
	var ordered: Array = []
	for code in _skill_orders.get(_focused_hero, []):
		if available.has(code):
			ordered.append(code)
	for code in available:
		if not ordered.has(code):
			ordered.append(code)
	_skill_orders[_focused_hero] = ordered
	if ordered.is_empty():
		Ui.label(_skill_box, "Chưa mở khóa kỹ năng riêng.\nHero tự dùng đòn đánh cơ bản.", 13, Ui.MUTED)
		return
	for index in range(ordered.size()):
		var row := HBoxContainer.new()
		_skill_box.add_child(row)
		var skill_name := str(ordered[index])
		for skill in skills:
			if str(skill.get("code", "")) == skill_name:
				skill_name = str(skill.get("name", skill_name))
		var label := Ui.label(row, "%d. %s" % [index + 1, skill_name], 12)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		var up := Ui.button(row, "↑", func(): _move_skill(index, -1))
		up.disabled = index == 0
		var down := Ui.button(row, "↓", func(): _move_skill(index, 1))
		down.disabled = index == ordered.size() - 1
	Ui.label(_skill_box, "Kỹ năng chưa sẵn sàng sẽ được bỏ qua.\nHero hồi máu tự chọn đồng đội yếu nhất.", 12, Ui.MUTED)

func _move_skill(index: int, direction: int) -> void:
	var order: Array = _skill_orders.get(_focused_hero, [])
	var other := index + direction
	if other < 0 or other >= order.size():
		return
	var original: Variant = order[index]
	order[index] = order[other]
	order[other] = original
	_render_skills()

func _on_save() -> void:
	if _name_input.text.strip_edges().is_empty():
		_name_input.grab_focus()
		show_error("Hãy đặt tên cho đội trước khi lưu.", false)
		return
	var members: Array = []
	for cell in range(9):
		if _slots.has(cell):
			var hero_id := str(_slots[cell])
			members.append({"heroId": hero_id, "slotIndex": cell, "skillOrder": _skill_orders.get(hero_id, [])})
	var priorities := ["FRONTLINE", "LOWEST_HP", "HIGHEST_ATK"]
	saved.emit(str(party_data.get("id", "")), {"name": _name_input.text.strip_edges(), "heroIds": _hero_ids.duplicate(),
		"plan": {"targetPriority": priorities[_priority.selected], "members": members}})

func show_error(message: String, retry_available: bool) -> void:
	_feedback.text = message
	_retry_button.visible = retry_available
	set_busy(retry_available)

func set_busy(busy: bool) -> void:
	if not is_node_ready():
		return
	_name_input.editable = not busy
	for control in find_children("*", "BaseButton", true, false):
		if control == _close_button or control == _retry_button:
			continue
		if busy:
			if not control.has_meta("pve_previous_disabled"):
				control.set_meta("pve_previous_disabled", control.disabled)
			control.disabled = true
		elif control.has_meta("pve_previous_disabled"):
			control.disabled = bool(control.get_meta("pve_previous_disabled"))
			control.remove_meta("pve_previous_disabled")
	_retry_button.disabled = PveState.command_busy
