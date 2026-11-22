extends Control

const Ui := preload("res://scripts/ui/pve_ui.gd")
const PartyEditor := preload("res://scripts/ui/pve_party_editor.gd")
const UnitActor := preload("res://scenes/common/unit_actor_3d.tscn")
const SYMBOLS := {"CAMP": "⌂", "EMPTY": "·", "RESOURCE": "◆", "ENEMY": "⚔", "BOSS": "♛", "UNKNOWN": "?", "WALL": "▦", "ROCK": "▲"}
const TILE_NAMES := {"CAMP": "Điểm xuất phát", "EMPTY": "Đường đi", "RESOURCE": "Tài nguyên", "ENEMY": "Đội địch", "BOSS": "Boss tầng", "UNKNOWN": "Chưa khám phá", "WALL": "Tường", "ROCK": "Đá"}
var _title: Label
var _status: Label
var _connection: Label
var _food: Label
var _enter: Button
var _retry: Button
var _party_picker: OptionButton
var _deploy: Button
var _edit: Button
var _create: Button
var _recall: Button
var _stone: Button
var _reset_tower: Button
var _auto: Button
var _squads: VBoxContainer
var _reports: VBoxContainer
var _more_reports: Button
var _history_cursor: String = ""
var _history_busy: bool = false
var _grid: GridContainer
var _breadcrumbs: HBoxContainer
var _portal_actions: HBoxContainer
var _objective: Label
var _view_area_id: String = "floor"
var _follow_key: String = ""
var _map_width: int = 12
var _map_hint: Label
var _tiles: Array[Button] = []
var _party_ids: Array = []
var _report_rows: Array = []
var _editor: Control
var _eta_elapsed: float = 0.0
var _portrait_views: Dictionary = {}

func _ready() -> void:
	_build_ui()
	_render_controls()
	PveState.snapshot_changed.connect(_render_state)
	PveState.command_changed.connect(_render_controls)
	PveState.message_changed.connect(_set_message)
	if not GameState.is_logged_in():
		_set_message("Hãy đăng nhập trước khi vào map chinh phạt.", true)
		return
	_set_message("Đang tải đội và bản đồ...", false)
	await GameState.refresh_heroes()
	await PveState.activate()
	_render_state()
	await _load_reports()
	if not PveState.pending_command.is_empty():
		_set_message("Có lệnh chưa được xác nhận. Bấm Thử lại lệnh để kiểm tra an toàn.", true)

func _process(delta: float) -> void:
	_eta_elapsed += delta
	if _eta_elapsed >= 1.0:
		_eta_elapsed = 0.0
		_render_eta()

func _build_ui() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Ui.INK
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_title = Ui.label(header, "CHINH PHẠT · BẢN ĐỒ PvE", 23, Ui.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_food = Ui.label(header, "", 14, Ui.TEAL)
	Ui.button(header, "Về căn cứ", _back_to_base)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_connection = Ui.label(toolbar, "Đang kết nối...", 13, Ui.MUTED)
	_connection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enter = Ui.button(toolbar, "Bắt đầu khám phá", _enter_map, true)
	_reset_tower = Ui.button(toolbar, "DEV · Reset tháp", _confirm_reset_tower)
	_reset_tower.visible = false
	Ui.button(toolbar, "Tải lại", func(): await PveState.refresh())
	_retry = Ui.button(toolbar, "Thử lại lệnh", func(): await PveState.retry_pending(), true)
	_retry.visible = false
	_status = Ui.label(column, "Chọn một đội và ra lệnh trên bản đồ.", 14, Ui.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var left := Ui.panel(body, 258)
	Ui.label(left, "ĐỘI CHINH PHẠT", 16, Ui.GOLD)
	_party_picker = OptionButton.new()
	_party_picker.custom_minimum_size.x = 230
	_party_picker.item_selected.connect(func(index: int):
		if index >= 0 and index < _party_ids.size():
			PveState.selected_party_id = str(_party_ids[index])
			_render_controls()
	)
	left.add_child(_party_picker)
	_deploy = Ui.button(left, "Triển khai đội", _deploy_party, true)
	_edit = Ui.button(left, "Đội hình & chiến thuật", _edit_party)
	_create = Ui.button(left, "Tạo đội mới", func(): _open_editor({}))
	Ui.label(left, "ĐỘI TRÊN MAP · TỐI ĐA 3", 13, Ui.MUTED)
	var squad_scroll := ScrollContainer.new()
	squad_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	squad_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(squad_scroll)
	_squads = VBoxContainer.new()
	_squads.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	squad_scroll.add_child(_squads)
	_recall = Ui.button(left, "Thu hồi đội đã chọn", _recall_squad)
	_stone = Ui.button(left, "Dùng Đá dịch chuyển", _place_recall_point)
	_auto = Ui.button(left, "Bật tự khám phá", _toggle_auto, true)
	Ui.button(left, "Vật phẩm đội đã chọn", func():
		if PveState.selected_squad_id.is_empty(): return
		var modal = preload("res://scripts/ui/pve_field_items_modal.gd").new()
		modal.squad_id = PveState.selected_squad_id
		add_child(modal)
	)
	var center := Ui.panel(body)
	center.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breadcrumbs = HBoxContainer.new()
	center.add_child(_breadcrumbs)
	_objective = Ui.label(center, "Mục tiêu: Hạ boss được chỉ định", 14, Ui.GOLD)
	_portal_actions = HBoxContainer.new()
	center.add_child(_portal_actions)
	_map_hint = Ui.label(center, "Khám phá đường đi để tìm tài nguyên và boss.", 13, Ui.MUTED)
	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_child(map_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	map_scroll.add_child(_grid)
	_ensure_grid(12, 12)
	var legend := Ui.label(center, "⌂ Căn cứ   ◆ Tài nguyên   ⚔ Địch   ♛ Boss\nAvatar đội trưởng · 1 giây/ô · 4 hướng", 12, Ui.MUTED)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var right := Ui.panel(body, 234)
	Ui.label(right, "CHIẾN BÁO", 16, Ui.GOLD)
	var hint := Ui.label(right, "Mở trận thủ công để điều khiển.\nCác đội khác vẫn hoạt động.", 12, Ui.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var report_scroll := ScrollContainer.new()
	report_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(report_scroll)
	_reports = VBoxContainer.new()
	_reports.custom_minimum_size.x = 208
	_reports.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report_scroll.add_child(_reports)
	_more_reports = Ui.button(right, "Chiến báo cũ hơn", func(): await _load_reports(true))
	_more_reports.visible = false

func _render_state() -> void:
	var data: Dictionary = PveState.snapshot
	var map_value: Variant = data.get("map")
	var map_data: Dictionary = map_value if map_value is Dictionary else {}
	_title.text = "CHINH PHẠT · TẦNG %d" % int(map_data.get("floor", data.get("currentFloor", GameState.current_floor)))
	_food.text = "Lương thực: %d" % int(data.get("food", 0))
	_enter.text = "Tiến vào tầng tiếp theo" if str(map_data.get("status", "")) == "CLEARED" else "Bắt đầu khám phá"
	Ui.clear(_squads)
	var active: Array = PveState.active_squads()
	if active.is_empty():
		Ui.label(_squads, "Chưa triển khai đội nào.\nMỗi Hero cần 10 FOOD khi xuất phát.", 12, Ui.MUTED)
		PveState.selected_squad_id = ""
	elif not active.any(func(squad): return str(squad.get("id", "")) == PveState.selected_squad_id):
		PveState.selected_squad_id = str(active[0].get("id", ""))
	for index in range(active.size()):
		var squad: Dictionary = active[index]
		var squad_id := str(squad.get("id", ""))
		var row := Ui.button(_squads, "", func():
			PveState.selected_squad_id = squad_id
			_follow_key = ""
			_render_state()
		, squad_id == PveState.selected_squad_id)
		row.custom_minimum_size = Vector2(226, 69)
		row.clip_text = true
		row.set_meta("squad_id", squad_id)
		row.set_meta("ordinal", index + 1)
	_render_eta()
	_party_ids.clear()
	_party_picker.clear()
	for party in data.get("parties", []):
		_party_ids.append(str(party.get("id", "")))
		_party_picker.add_item("%s · %d Hero" % [str(party.get("name", "Đội")), party.get("members", []).size()])
	if not _party_ids.has(PveState.selected_party_id) and not _party_ids.is_empty():
		PveState.selected_party_id = str(_party_ids[0])
	var selected_index: int = _party_ids.find(PveState.selected_party_id)
	if selected_index >= 0:
		_party_picker.select(selected_index)
	var selected_squad: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	var follow_key := "%s:%s" % [PveState.selected_squad_id, selected_squad.get("areaId", "floor")]
	if follow_key != _follow_key:
		_view_area_id = str(selected_squad.get("areaId", "floor"))
		_follow_key = follow_key
	var area_data: Dictionary = map_data
	for candidate in data.get("areas", []):
		if str(candidate.get("id", "")) == _view_area_id:
			area_data = candidate.duplicate(true)
			area_data["status"] = map_data.get("status", "")
	_ensure_grid(int(area_data.get("width", 12)), int(area_data.get("height", 12)))
	_render_navigation(area_data, selected_squad)
	var objective: Dictionary = data.get("objective", {})
	_objective.text = "Mục tiêu: Hạ boss được chỉ định · %d/%d%s" % [int(objective.get("progress", 0)), int(objective.get("required", 1)), " · Hoàn tất" if str(objective.get("status", "")) == "COMPLETED" else ""]
	if str(map_data.get("recallPolicy", "FREE")) == "UNTIL_COMPLETE" and str(map_data.get("status", "")) == "ACTIVE":
		_objective.text += " · Cấm thu hồi và dùng Đá dịch chuyển tới khi hoàn thành"
	_render_tiles(area_data, active)
	var existing_ids: Array = _report_rows.map(func(row): return str(row.get("battleId", "")))
	for event_value in data.get("events", []):
		if str(event_value.get("kind", "")) == "SQUAD_DETECTED":
			_set_message("Một đội đã bị quái phát hiện! Tìm vật cản để cắt tầm nhìn.", true)
		elif str(event_value.get("kind", "")) == "SQUAD_LOST":
			_set_message("Quái mất dấu, đang tìm tại vị trí cuối nhìn thấy.", false)
		if str(event_value.get("kind", "")) == "BATTLE_COMPLETED":
			var details: Dictionary = event_value.get("data", {})
			if bool(details.get("ambush", false)):
				_set_message("Đội bị phục kích! Quái có pha đánh mở màn.", true)
			if not existing_ids.has(str(details.get("battleId", ""))):
				_report_rows.push_front(details)
			else:
				for row in _report_rows:
					if row.get("battleId") == details.get("battleId"): row.merge(details, true)
	for squad in data.get("squads", []):
		var battle_id: String = PveState.optional_id(squad.get("lastBattleId"))
		if not battle_id.is_empty() and not _report_rows.any(func(row): return str(row.get("battleId", "")) == battle_id):
			_report_rows.append({"battleId": battle_id, "squadId": squad.get("id", ""), "name": squad.get("name", "Đội")})
	Ui.clear(_reports)
	for result in _report_rows:
		var label := "Thắng" if str(result.get("winner", "")) == "HERO" else "Thất bại" if str(result.get("winner", "")) == "ENEMY" else "Hòa" if str(result.get("winner", "")) == "DRAW" else "Chiến báo"
		var report_id := str(result.get("battleId", ""))
		var report_button := Ui.button(_reports, "Tầng %d · %s · Xem lại" % [int(result.get("floor", 1)), label], func(): _watch_report(report_id))
		for squad in data.get("squads", []):
			if squad.get("lastBattleId") == report_id and squad.get("status") == "FIGHTING":
				report_button.text = "Điều khiển trận • " + str(squad.get("name", "Đội"))
		report_button.tooltip_text = "Báo cáo trận đấu và phần thưởng đã lưu"
		if result.has("silverReward"):
			Ui.label(_reports, "+%d Silver · +%d EXP/Hero" % [int(result.get("silverReward", 0)), int(result.get("heroExpReward", 0))], 11, Ui.MUTED)
	if _report_rows.is_empty():
		Ui.label(_reports, "Chưa có trận đấu.\nDi chuyển đội đến ô có địch.", 12, Ui.MUTED)
	_render_controls()

func _load_reports(more: bool = false) -> void:
	if _history_busy or not GameState.is_logged_in():
		return
	_history_busy = true
	_more_reports.disabled = true
	var endpoint := "/api/pve/battles?limit=30"
	if more and not _history_cursor.is_empty():
		endpoint += "&before=" + _history_cursor.uri_encode()
	var response: Dictionary = await ApiClient.get_req(endpoint)
	_history_busy = false
	if not is_inside_tree():
		return
	if response.get("ok", false) and response.get("data") is Dictionary:
		var data: Dictionary = response["data"]
		for entry in data.get("battles", []):
			var report_id := str(entry.get("id", ""))
			var detail: Dictionary = entry.get("settlement", {}).duplicate(true)
			detail["battleId"] = report_id
			detail["winner"] = str(entry.get("winner", ""))
			detail["name"] = str(entry.get("name", "Đội"))
			var matched := false
			for index in range(_report_rows.size()):
				if str(_report_rows[index].get("battleId", "")) == report_id:
					_report_rows[index] = detail
					matched = true
					break
			if not matched:
				_report_rows.append(detail)
		_history_cursor = PveState.optional_id(data.get("nextCursor"))
		_more_reports.visible = not _history_cursor.is_empty()
		_render_state()
	_more_reports.disabled = false

func _ensure_grid(width: int, height: int) -> void:
	if _tiles.size() == width * height and _map_width == width:
		return
	for button in _tiles:
		_grid.remove_child(button)
		button.queue_free()
	_tiles.clear()
	_map_width = width
	_grid.columns = width
	for index in range(width * height):
		var button := Button.new()
		button.custom_minimum_size = Vector2(43, 40)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(func(): _move_selected(index % width, index / width))
		_grid.add_child(button)
		_tiles.append(button)

func _render_navigation(area: Dictionary, selected: Dictionary) -> void:
	Ui.clear(_breadcrumbs)
	Ui.clear(_portal_actions)
	var chain: Array = [area]
	var parent_id: String = PveState.optional_id(area.get("parentAreaId"))
	while not parent_id.is_empty():
		var found := false
		for candidate in PveState.snapshot.get("areas", []):
			if str(candidate.get("id", "")) == parent_id:
				chain.push_front(candidate)
				parent_id = PveState.optional_id(candidate.get("parentAreaId"))
				found = true
				break
		if not found:
			break
	for entry in chain:
		var area_id := str(entry.get("id", "floor"))
		Ui.button(_breadcrumbs, str(entry.get("name", "Tầng")), func():
			_view_area_id = area_id
			_render_state()
		)
	for portal in area.get("portals", []):
		if str(selected.get("areaId", "floor")) != _view_area_id or int(portal.get("x", -1)) != int(selected.get("x", -2)) or int(portal.get("y", -1)) != int(selected.get("y", -2)):
			continue
		var portal_id := str(portal.get("id", ""))
		var action := Ui.button(_portal_actions, str(portal.get("label", "Qua cửa")), func():
			await PveState.send_command("/api/pve/squads/%s/portal" % PveState.selected_squad_id, {"areaId": _view_area_id, "portalId": portal_id})
		)
		action.disabled = not _can_command() or str(selected.get("status", "")) == "FIGHTING"

func _render_tiles(map_data: Dictionary, active: Array) -> void:
	var known_count := 0
	var nodes: Array = map_data.get("tiles", [])
	var selected: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	for index in range(_tiles.size()):
		var button: Button = _tiles[index]
		var node: Dictionary = nodes[index] if index < nodes.size() else {}
		var kind := str(node.get("kind", "UNKNOWN"))
		var consumed := bool(node.get("collected", false)) or bool(node.get("cleared", false))
		var caption := str(SYMBOLS.get(kind, "?"))
		var is_recall_point := false
		var floor_map: Dictionary = PveState.snapshot.get("map", {}) if PveState.snapshot.get("map") is Dictionary else {}
		for point in floor_map.get("recallPoints", []):
			if str(point.get("areaId", "floor")) == _view_area_id and int(point.get("x", -1)) == index % _map_width and int(point.get("y", -1)) == index / _map_width:
				is_recall_point = true
		for portal in map_data.get("portals", []):
			if int(portal.get("x", -1)) == index % _map_width and int(portal.get("y", -1)) == index / _map_width:
				if str(map_data.get("level", "")) != "FLOOR":
					caption = "↪"
		for building in map_data.get("buildings", []):
			if str(map_data.get("level", "")) == "FLOOR" and int(building.get("parentTileId", -1)) == index:
				caption = "⌂+"
		for enemy in map_data.get("enemies", []):
			if int(enemy.get("x", -1)) == index % _map_width and int(enemy.get("y", -1)) == index / _map_width:
				caption = "♛" if bool(enemy.get("boss", false)) else "⚔"
		var background := Color("182b32") if kind != "UNKNOWN" else Color("101a29")
		if is_recall_point:
			caption = "⟲"
		var radar := false
		for enemy in map_data.get("enemies", []):
			if enemy.get("radarTileIds", []).has(index) and kind != "UNKNOWN":
				radar = true
		if radar:
			background = background.lerp(Color("70383d"), 0.4)
		var border := Color("29454d") if kind != "UNKNOWN" else Color("1d2a3d")
		if kind != "UNKNOWN":
			known_count += 1
		if consumed:
			caption = "✓"
		elif kind in ["ENEMY", "BOSS"]:
			background = Color("56313a") if kind == "ENEMY" else Color("60402f")
		elif kind == "RESOURCE":
			background = Color("254b3d")
		elif kind == "CAMP":
			background = Color("34506a")
		for drop in map_data.get("drops", []):
			if int(drop.get("x", -1)) == index % _map_width and int(drop.get("y", -1)) == index / _map_width:
				caption = "🎒"
		for step in selected.get("route", []) if str(selected.get("areaId", "floor")) == _view_area_id else []:
			if int(step.get("x", -1)) == index % _map_width and int(step.get("y", -1)) == index / _map_width:
				border = Ui.GOLD
		for child in button.get_children():
			if child.has_meta("pve_portrait"):
				button.remove_child(child)
				child.queue_free()
		var occupants: Array = []
		for ordinal in range(active.size()):
			var squad: Dictionary = active[ordinal]
			if str(squad.get("areaId", "floor")) != _view_area_id:
				continue
			if int(squad.get("x", -1)) == index % _map_width and int(squad.get("y", -1)) == index / _map_width:
				occupants.append({"squad": squad, "ordinal": ordinal + 1})
				if str(squad.get("id", "")) == PveState.selected_squad_id:
					background = Color("38677a")
					border = Ui.TEAL
		button.text = "" if not occupants.is_empty() else caption
		for position in range(occupants.size()):
			var occupant: Dictionary = occupants[position]
			var squad: Dictionary = occupant["squad"]
			var hero_id := PveState.optional_id(squad.get("leaderHeroId"))
			var hero: Dictionary = GameState.get_hero_by_id(hero_id)
			var portrait := TextureRect.new()
			portrait.set_meta("pve_portrait", true)
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.position = Vector2(float(position) * 40.0 / occupants.size(), 1)
			portrait.size = Vector2(40.0 / occupants.size(), 37)
			portrait.texture = _leader_portrait(hero_id, hero)
			portrait.tooltip_text = str(hero.get("name", "Đội trưởng"))
			button.add_child(portrait)
		button.add_theme_stylebox_override("normal", Ui.style(background, border, 4))
		button.add_theme_stylebox_override("hover", Ui.style(background.lightened(0.15), Ui.GOLD, 4))
		button.tooltip_text = "(%d, %d) · %s" % [index % _map_width, index / _map_width, str(TILE_NAMES.get(kind, kind))]
		if is_recall_point:
			button.tooltip_text += "\nĐiểm dịch chuyển · Các đội đứng tại đây có thể thu hồi"
		for building in map_data.get("buildings", []):
			if str(map_data.get("level", "")) == "FLOOR" and int(building.get("parentTileId", -1)) == index:
				button.tooltip_text += "\n" + str(building.get("name", "Công trình"))
		for occupant in occupants:
			var leader: Dictionary = GameState.get_hero_by_id(PveState.optional_id(occupant["squad"].get("leaderHeroId")))
			button.tooltip_text += "\nĐội %d · %s · Đội trưởng: %s" % [occupant["ordinal"], occupant["squad"].get("name", "Đội"), leader.get("name", "Hero")]
		if node.get("resource") is Dictionary and not consumed:
			button.tooltip_text += "\n%s ×%d" % [str(node["resource"].get("itemId", "")), int(node["resource"].get("quantity", 0))]
		button.disabled = not _can_command() or selected.is_empty() or str(map_data.get("status", "")) != "ACTIVE"
	_map_hint.text = "Đã khám phá %d/%d ô · %dm/ô · %s" % [known_count, _tiles.size(), int(map_data.get("metersPerTile", 1000)), "Hoàn thành mục tiêu để mở tầng mới" if str(map_data.get("status", "")) != "CLEARED" else "Tầng đã hoàn thành"]

func _leader_portrait(hero_id: String, hero: Dictionary) -> Texture2D:
	if hero_id.is_empty() or hero.is_empty():
		return null
	if _portrait_views.has(hero_id) and is_instance_valid(_portrait_views[hero_id]):
		return _portrait_views[hero_id].get_texture()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var actor: UnitActor3D = UnitActor.instantiate()
	viewport.add_child(actor)
	actor.setup_combat_unit(hero)
	actor.name_label.visible = false
	actor.hp_label.visible = false
	actor.speech_label.visible = false
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.4
	viewport.add_child(camera)
	camera.position = Vector3(2, 2.2, 3)
	camera.look_at(Vector3(0, 0.8, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	viewport.add_child(light)
	light.rotation_degrees = Vector3(-45, -35, 0)
	_portrait_views[hero_id] = viewport
	return viewport.get_texture()

func _render_eta() -> void:
	var statuses := {"IDLE": "Sẵn sàng", "MOVING": "Đang hành quân", "FIGHTING": "Đang tự giao chiến"}
	for child in _squads.get_children():
		if not (child is Button):
			continue
		var squad: Dictionary = PveState.squad_by_id(str(child.get_meta("squad_id", "")))
		var eta: int = maxi(0, int(ceil(PveState.parse_time(str(squad.get("nextStepAt", ""))) - PveState.server_now())))
		var state_value := str(squad.get("status", ""))
		child.text = "%d · %s\n(%d, %d) · %s%s" % [int(child.get_meta("ordinal", 0)), str(squad.get("name", "Đội")),
			int(squad.get("x", 0)), int(squad.get("y", 0)), str(statuses.get(state_value, state_value)), " · %ds" % eta if state_value == "MOVING" else ""]

func _can_command() -> bool:
	return PveState.connected and not PveState.command_busy and PveState.pending_command.is_empty()

func _render_controls() -> void:
	if _enter == null:
		return
	var map_value: Variant = PveState.snapshot.get("map")
	var active_map := map_value is Dictionary and str(map_value.get("status", "")) == "ACTIVE"
	_connection.text = "Đã kết nối · Đội %d/3" % PveState.active_squads().size() if PveState.connected else "Mất kết nối · Đang thử đồng bộ"
	if bool(PveState.snapshot.get("catchupPending", false)):
		_connection.text = "Đang xử lý tiến độ khi vắng mặt…"
	_connection.modulate = Ui.TEAL if PveState.connected else Color("ffad82")
	_enter.disabled = not _can_command() or active_map
	_retry.visible = not PveState.pending_command.is_empty()
	_retry.disabled = PveState.command_busy
	var party_deployed: bool = PveState.active_squads().any(func(squad): return str(squad.get("partyId", "")) == PveState.selected_party_id)
	_deploy.disabled = not _can_command() or not active_map or party_deployed or PveState.active_squads().size() >= 3 or PveState.selected_party_id.is_empty()
	_edit.disabled = not _can_command() or party_deployed or PveState.selected_party_id.is_empty()
	_create.disabled = not _can_command()
	if is_instance_valid(_editor):
		_editor.set_busy(PveState.command_busy or not PveState.pending_command.is_empty())
	var selected: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	_recall.disabled = not _can_command() or selected.is_empty() or str(selected.get("status", "")) not in ["IDLE", "MOVING"]
	_auto.disabled = _recall.disabled
	_recall.disabled = _recall.disabled or bool(selected.get("pursued", false))
	if selected.has("canRecall"):
		_recall.disabled = not _can_command() or not bool(selected.get("canRecall", false))
	_recall.text = "Thu hồi tại điểm dịch chuyển" if bool(selected.get("atRecallPoint", false)) else "Thu hồi đội đã chọn"
	var recall_reason: String = PveState.optional_id(selected.get("recallBlockReason"))
	_recall.tooltip_text = PveState.error_message(recall_reason) if not recall_reason.is_empty() else "Đưa đội về căn cứ"
	_stone.text = "Đá dịch chuyển ×%d · Tạo điểm thu hồi" % int(PveState.snapshot.get("teleportStones", 0))
	var recall_locked := active_map and str(map_value.get("recallPolicy", "FREE")) == "UNTIL_COMPLETE"
	_stone.disabled = not _can_command() or not active_map or recall_locked or selected.is_empty() or str(selected.get("status", "")) != "IDLE" or bool(selected.get("atRecallPoint", false)) or int(PveState.snapshot.get("teleportStones", 0)) < 1
	_stone.tooltip_text = "Tầng này cấm dùng Đá dịch chuyển." if recall_locked else "Tiêu hao 1 đá để tạo điểm thu hồi dùng chung tới hết tầng; cho phép thoát truy đuổi, không dùng giữa trận."
	_reset_tower.visible = OS.is_debug_build() and bool(PveState.snapshot.get("devToolsEnabled", false))
	_reset_tower.disabled = not _can_command()
	_auto.text = "Dừng tự khám phá" if bool(selected.get("autoExplore", false)) else "Bật tự khám phá"
	for button in _tiles:
		button.disabled = not _can_command() or not active_map or selected.is_empty() or str(selected.get("status", "")) == "FIGHTING" or str(selected.get("areaId", "floor")) != _view_area_id

func _enter_map() -> void:
	await PveState.send_command("/api/pve/enter")

func _deploy_party() -> void:
	var result: Dictionary = await PveState.send_command("/api/pve/parties/%s/deploy" % PveState.selected_party_id)
	if result.get("ok", false):
		PveState.selected_squad_id = str(result.get("data", {}).get("squadId", ""))
		_render_state()

func _recall_squad() -> void:
	await PveState.send_command("/api/pve/squads/%s/recall" % PveState.selected_squad_id)

func _place_recall_point() -> void:
	var squad: Dictionary = PveState.squad_by_id(PveState.selected_squad_id)
	if not squad.is_empty():
		await PveState.send_command("/api/pve/squads/%s/recall-point" % PveState.selected_squad_id, {"areaId": squad.get("areaId", "floor"), "x": squad.get("x", 0), "y": squad.get("y", 0)})

func _confirm_reset_tower() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "DEV · Reset tháp về tầng 1"
	dialog.dialog_text = "Dừng lượt tháp hiện tại, thu hồi mọi đội và quay về tầng 1.\nGiữ Hero, vật phẩm và chiến báo cũ."
	dialog.confirmed.connect(func():
		var result: Dictionary = await PveState.send_command("/api/pve/dev/reset-tower", {"confirm": true})
		if result.get("ok", false):
			PveState.selected_squad_id = ""
			_view_area_id = "floor"
			_follow_key = ""
			GameState.current_floor = 1
			_render_state()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _toggle_auto() -> void:
	var squad := PveState.squad_by_id(PveState.selected_squad_id)
	if not squad.is_empty():
		await PveState.send_command("/api/pve/squads/%s/auto" % PveState.selected_squad_id, {"enabled": not bool(squad.get("autoExplore", false))})

func _move_selected(x: int, y: int) -> void:
	if _can_command() and not PveState.selected_squad_id.is_empty():
		await PveState.send_command("/api/pve/squads/%s/move" % PveState.selected_squad_id, {"x": x, "y": y, "areaId": _view_area_id})

func _edit_party() -> void:
	for party in PveState.snapshot.get("parties", []):
		if str(party.get("id", "")) == PveState.selected_party_id:
			_open_editor(party)
			return

func _open_editor(party: Dictionary) -> void:
	if is_instance_valid(_editor):
		return
	_editor = PartyEditor.new()
	_editor.configure(party)
	_editor.saved.connect(_save_party)
	_editor.retry_requested.connect(_retry_party_save)
	add_child(_editor)

func _save_party(party_id: String, payload: Dictionary) -> void:
	var endpoint := "/api/pve/parties" if party_id.is_empty() else "/api/pve/parties/" + party_id
	var method := HTTPClient.METHOD_POST if party_id.is_empty() else HTTPClient.METHOD_PUT
	var result: Dictionary = await PveState.send_command(endpoint, payload, method)
	_finish_party_save(result)

func _retry_party_save() -> void:
	var result: Dictionary = await PveState.retry_pending()
	_finish_party_save(result)

func _finish_party_save(result: Dictionary) -> void:
	if result.get("ok", false):
		PveState.selected_party_id = str(result.get("data", {}).get("partyId", ""))
		if is_instance_valid(_editor):
			_editor.queue_free()
		_render_state()
	else:
		if is_instance_valid(_editor):
			_editor.show_error(PveState.error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), not PveState.pending_command.is_empty())
		_set_message(PveState.error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), true)

func _watch_report(battle_id: String) -> void:
	PveState.selected_battle_id = battle_id
	get_tree().change_scene_to_file("res://scenes/pve/isometric_pve_arena_3d.tscn")

func _set_message(message: String, is_error: bool) -> void:
	_status.text = message
	_status.modulate = Color("ffb49a") if is_error else Ui.MUTED

func _back_to_base() -> void:
	PveState.polling_enabled = false
	get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")
