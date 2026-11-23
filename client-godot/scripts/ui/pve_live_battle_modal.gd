extends Control
signal report_updated(report: Dictionary)
signal closed

const Ui = preload("res://scripts/ui/pve_ui.gd")
var battle_id := ""
var battle: Dictionary = {}
var _body: VBoxContainer
var _notice: Label
var _clock: Label
var _clock_bar: ProgressBar
var _busy := false
var _elapsed := 0.0
var _target := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.04, 0.94)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := Ui.glass_panel(center, Ui.GOLD, 14, 18, 16)
	panel.get_parent().custom_minimum_size.x = 1020

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	panel.add_child(header)
	var title := Ui.label(header, "⚔️ ĐIỀU KHIỂN GIAO CHIẾN", 21, Ui.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock = Ui.label(header, "", 15, Ui.TEAL)
	_clock_bar = Ui.progress_bar(panel, 10.0, 10.0, Ui.GOLD, 6)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	panel.add_child(_body)

	_notice = Ui.label(panel, "", 13, Ui.DANGER)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	panel.add_child(actions)
	Ui.button(actions, "← Về map • Đội tiếp tục tự đánh", _leave, false, "ghost")
	Ui.button(actions, "Thử lại lệnh chưa xác nhận", func():
		if _busy: return
		_busy = true
		var result: Dictionary = await PveState.retry_pending()
		_busy = false
		if result.get("ok", false): await _reload()
	, false, "danger")
	_render()
	await _send({"watching": true})

func _process(delta: float) -> void:
	if _clock != null:
		var is_live := bool(battle.get("live", false))
		var remaining := maxf(0.0, float(battle.get("deadline", 0)) / 1000.0 - PveState.server_now())
		_clock.text = "⏱ Còn %.1f giây" % remaining if is_live else "✓ Trận đã lưu • Có thể quay về map"
		if _clock_bar != null:
			_clock_bar.visible = is_live
			_clock_bar.value = clampf(remaining, 0.0, 10.0)
	_elapsed += delta
	if _elapsed >= 1.0 and not _busy:
		_elapsed = 0.0
		_reload()

func _reload() -> void:
	if _busy: return
	_busy = true
	var response: Dictionary = await ApiClient.get_req("/api/pve/battles/" + battle_id.uri_encode())
	if not is_inside_tree(): return
	_busy = false
	if response.get("ok", false):
		battle = response.get("data", {})
		_render()
	else: _notice.text = "Không tải được trận. Hãy kiểm tra kết nối."

func _render() -> void:
	if _body == null: return
	Ui.clear(_body)
	var report: Dictionary = battle.get("report", {})
	report_updated.emit(report)
	var pending: Dictionary = report.get("pending", {})
	var actor_id := str(pending.get("actorId", ""))
	var units: Array = report.get("units", [])

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	_body.add_child(columns)
	for side in ["HERO", "ENEMY"]:
		var side_card := Ui.card(columns, Ui.CARD, Ui.TEAL if side == "HERO" else Ui.DANGER)
		side_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Ui.label(side_card, "🛡️ ĐỘI HÌNH CỦA BẠN" if side == "HERO" else "⚔️ ĐỘI HÌNH ĐỊCH", 13, Ui.TEAL if side == "HERO" else Ui.DANGER)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		side_card.add_child(grid)
		for cell in range(9):
			var unit: Dictionary = {}
			for entry in units:
				if entry.get("side") == side and int(entry.get("slotIndex", -1)) == cell: unit = entry
			var id := str(unit.get("id", ""))
			var hp := int(unit.get("hp", 0))
			var max_hp := maxi(1, int(unit.get("maxHp", 1)))
			var mp := int(unit.get("mp", 0))
			var max_mp := maxi(1, int(unit.get("maxMp", 1)))
			var is_actor := (id == actor_id and not id.is_empty())
			var is_target := (id == _target and not id.is_empty())
			var tone := "gold" if is_target else ("accent" if is_actor else ("default" if not unit.is_empty() else "ghost"))
			var cell_txt := "—" if unit.is_empty() else "%s%s\nHP %d/%d\nMP %d/%d" % ["▶ " if is_actor else "", unit.get("name", ""), hp, max_hp, mp, max_mp]
			if not unit.is_empty() and unit.get("effects", []).has("STRENGTH_POTION"):
				cell_txt += " · ATK+20%"
			var slot_col := VBoxContainer.new()
			slot_col.add_theme_constant_override("separation", 2)
			grid.add_child(slot_col)
			var button := Ui.button(slot_col, cell_txt, func(): _target = id; _render(), is_actor or is_target, tone)
			button.custom_minimum_size = Vector2(154, 68)
			button.clip_text = true
			button.disabled = unit.is_empty() or not bool(unit.get("alive", false))
			if not unit.is_empty():
				Ui.progress_bar(slot_col, float(hp), float(max_hp), Ui.SUCCESS if side == "HERO" else Ui.DANGER, 4)

	var log_card := Ui.card(_body, Color(0.06, 0.10, 0.17, 0.92), Ui.BORDER_SOFT)
	var entries: Array = report.get("log", [])
	if entries.is_empty():
		Ui.label(log_card, "Chưa có diễn biến lượt đánh.", 12, Ui.MUTED)
	else:
		for entry in entries.slice(maxi(0, entries.size() - 3)):
			Ui.label(log_card, "%s → %s • %s • %d sát thương / %d hồi phục" % [entry.get("actorName", ""), entry.get("targetName", ""), entry.get("action", ""), int(entry.get("damage", 0)), int(entry.get("heal", 0))], 12, Ui.TEXT)

	if pending.is_empty():
		var res_card := Ui.card(_body, Color(0.11, 0.17, 0.25, 0.95), Ui.GOLD)
		Ui.label(res_card, "Kết quả: " + str(report.get("winner", "DRAW")), 18, Ui.GOLD)
		var settlement: Dictionary = battle.get("settlement", {})
		Ui.label(res_card, "+%d Bạc • +%d EXP/Hero" % [int(settlement.get("silverReward", 0)), int(settlement.get("heroExpReward", 0))], 14, Ui.TEAL)
		return

	var hero := GameState.get_hero_by_id(actor_id)
	var cmd_card := Ui.card(_body, Ui.CARD, Ui.GOLD)
	Ui.label(cmd_card, "▶ Lượt của %s • Chọn mục tiêu trên lưới địch rồi chọn hành động" % hero.get("name", actor_id), 14, Ui.GOLD)
	var cmd_split := HBoxContainer.new()
	cmd_split.add_theme_constant_override("separation", 16)
	cmd_card.add_child(cmd_split)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_split.add_child(row)
	Ui.button(row, "⚔️ Đánh thường", func(): _send({"action": "BASIC", "targetId": _target}), true, "gold")
	for skill in hero.get("skills", []):
		if bool(skill.get("isUnlocked", false)):
			var code := str(skill.get("code", ""))
			var button := Ui.button(row, str(skill.get("name", code)), func(): _send({"action": "SKILL", "skillCode": code, "targetId": _target}), true, "accent")
			button.disabled = not pending.get("skills", []).any(func(ready_skill): return ready_skill.get("code") == code)

	var items: Dictionary = report.get("consumables", {}).get(actor_id, {})
	var items_row := HBoxContainer.new()
	items_row.add_theme_constant_override("separation", 8)
	cmd_split.add_child(items_row)
	var shown: Array = []
	for slot in items.get("slots", []):
		if not slot is Dictionary: continue
		var code := str(slot.get("itemId", ""))
		if code == "MEDICINE" or shown.has(code): continue
		shown.append(code)
		var total := 0
		for other in items.get("slots", []):
			if other is Dictionary and other.get("itemId") == code: total += int(other.get("quantity", 0))
		Ui.button(items_row, ("🔷 Thuốc ma lực" if code == "MANA_POTION" else "💪 Thuốc cường lực") + " ×%d" % total, func(): _send({"itemId": code}))
	Ui.label(cmd_card, "Thuốc không tốn lượt • Tối đa 2 loại mỗi lượt, mỗi loại 1 viên", 12, Ui.MUTED)
	for button in _body.find_children("*", "Button", true, false):
		if _busy: button.disabled = true

func _send(payload: Dictionary) -> void:
	if _busy: return
	_busy = true
	_notice.text = ""
	_render()
	var result: Dictionary = await PveState.send_command("/api/pve/battles/%s/action" % battle_id.uri_encode(), payload)
	if not is_inside_tree(): return
	_busy = false
	if result.get("ok", false):
		await _reload()
	else:
		_notice.text = PveState.error_message(str(result.get("error", "Không thể thực hiện lệnh")))
		_render()

func _leave() -> void:
	await ApiClient.post_req("/api/pve/battles/%s/action" % battle_id.uri_encode(), {"watching": false})
	closed.emit()
	queue_free()
