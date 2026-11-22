extends Control
signal report_updated(report: Dictionary)
signal closed
const Ui = preload("res://scripts/ui/pve_ui.gd")
var battle_id := ""
var battle: Dictionary = {}
var _body: VBoxContainer
var _notice: Label
var _clock: Label
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
	var panel := Ui.panel(center, 1000)
	Ui.label(panel, "ĐIỀU KHIỂN GIAO CHIẾN", 22, Ui.GOLD)
	_clock = Ui.label(panel, "", 17)
	_body = VBoxContainer.new()
	panel.add_child(_body)
	_notice = Ui.label(panel, "", 14)
	var actions := HBoxContainer.new()
	panel.add_child(actions)
	Ui.button(actions, "Về map • Đội tiếp tục tự đánh", _leave)
	Ui.button(actions, "Thử lại lệnh chưa xác nhận", func():
		if _busy: return
		_busy = true
		var result: Dictionary = await PveState.retry_pending()
		_busy = false
		if result.get("ok", false): await _reload()
	)
	_render()
	await _send({"watching": true})

func _process(delta: float) -> void:
	if _clock != null:
		var remaining := maxf(0, float(battle.get("deadline", 0)) / 1000.0 - PveState.server_now())
		_clock.text = "Còn %.1f giây cho lượt này" % remaining if bool(battle.get("live", false)) else "Trận đã được lưu • Có thể quay về map"
	_elapsed += delta
	if _elapsed >= 1.0 and not _busy:
		_elapsed = 0
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
	_body.add_child(columns)
	for side in ["HERO", "ENEMY"]:
		var grid := GridContainer.new()
		grid.columns = 3
		columns.add_child(grid)
		for cell in range(9):
			var unit: Dictionary = {}
			for entry in units:
				if entry.get("side") == side and int(entry.get("slotIndex", -1)) == cell: unit = entry
			var id := str(unit.get("id", ""))
			var button := Ui.button(grid, "—" if unit.is_empty() else "%s%s\nHP %d/%d\nMP %d/%d" % ["▶ " if id == actor_id else "", unit.get("name", ""), int(unit.get("hp", 0)), int(unit.get("maxHp", 0)), int(unit.get("mp", 0)), int(unit.get("maxMp", 0))], func(): _target = id; _render())
			button.custom_minimum_size = Vector2(155, 74)
			button.disabled = unit.is_empty() or not bool(unit.get("alive", false))
			if unit.get("effects", []).has("STRENGTH_POTION"): button.text += "\nATK +20%"
			if id == _target: button.modulate = Ui.GOLD
	var entries: Array = report.get("log", [])
	for entry in entries.slice(maxi(0, entries.size() - 3)):
		Ui.label(_body, "%s → %s • %s • %d sát thương / %d hồi phục" % [entry.get("actorName", ""), entry.get("targetName", ""), entry.get("action", ""), int(entry.get("damage", 0)), int(entry.get("heal", 0))], 12, Ui.MUTED)
	if pending.is_empty():
		Ui.label(_body, "Kết quả: " + str(report.get("winner", "DRAW")), 18, Ui.GOLD)
		var settlement: Dictionary = battle.get("settlement", {})
		Ui.label(_body, "+%d bạc • +%d EXP/Hero" % [int(settlement.get("silverReward", 0)), int(settlement.get("heroExpReward", 0))], 15)
		return
	var hero := GameState.get_hero_by_id(actor_id)
	Ui.label(_body, "Lượt của %s • Chọn mục tiêu trên lưới rồi chọn hành động" % hero.get("name", actor_id), 15)
	var row := HBoxContainer.new()
	_body.add_child(row)
	Ui.button(row, "Đánh thường", func(): _send({"action": "BASIC", "targetId": _target}))
	for skill in hero.get("skills", []):
		if bool(skill.get("isUnlocked", false)):
			var code := str(skill.get("code", ""))
			var button := Ui.button(row, str(skill.get("name", code)), func(): _send({"action": "SKILL", "skillCode": code, "targetId": _target}))
			button.disabled = not pending.get("skills", []).any(func(ready_skill): return ready_skill.get("code") == code)
	var items: Dictionary = report.get("consumables", {}).get(actor_id, {})
	var items_row := HBoxContainer.new()
	_body.add_child(items_row)
	var shown: Array = []
	for slot in items.get("slots", []):
		if not slot is Dictionary: continue
		var code := str(slot.get("itemId", ""))
		if code == "MEDICINE" or shown.has(code): continue
		shown.append(code)
		var total := 0
		for other in items.get("slots", []):
			if other is Dictionary and other.get("itemId") == code: total += int(other.get("quantity", 0))
		Ui.button(items_row, ("Thuốc ma lực" if code == "MANA_POTION" else "Thuốc cường lực") + " ×%d" % total, func(): _send({"itemId": code}))
	Ui.label(_body, "Thuốc không tốn lượt • Tối đa 2 loại mỗi lượt, mỗi loại 1 viên", 13, Ui.MUTED)
	for button in _body.find_children("*", "Button", true, false):
		if _busy: button.disabled = true

func _send(body: Dictionary) -> void:
	if _busy: return
	_busy = true
	body = body.duplicate(true)
	if body.has("action") or body.has("itemId"):
		body["turnKey"] = battle.get("report", {}).get("pending", {}).get("key", "")
		if body.get("targetId", "") == "": body.erase("targetId")
	_render()
	var response: Dictionary = await PveState.send_command("/api/pve/battles/%s/action" % battle_id, body)
	if not is_inside_tree(): return
	_busy = false
	_notice.text = "" if response.get("ok", false) else PveState.error_message(str(response.get("error", "Không thể thực hiện")))
	await _reload()

func _leave() -> void:
	if _busy: return
	if bool(battle.get("live", false)): await _send({"watching": false})
	closed.emit()
	queue_free()
