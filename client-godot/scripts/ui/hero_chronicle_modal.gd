extends Control

signal closed

const STATUS_NAMES := {"ALIVE": "Đang sống", "DEAD": "Tử trận", "SACRIFICED": "Đã tiêu hao"}
const EVENT_NAMES := {"SUMMONED": "Được triệu hồi", "DIED": "Tử trận", "RESURRECTED": "Được hồi sinh", "STAR_PROMOTED": "Thăng sao", "SACRIFICED": "Được dùng làm nguyên liệu", "ARCHIVED": "Lưu hồ sơ"}
var _list: VBoxContainer
var _detail: RichTextLabel
var _notice: Label
var _stock: Label
var _revive: Button
var _page_label: Label
var _previous: Button
var _next: Button
var _records: Array = []
var _selected: Dictionary = {}
var _status := ""
var _page := 1
var _gems := 0
var _busy := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.04, 0.9)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28
	panel.offset_right = -28
	panel.offset_top = 28
	panel.offset_bottom = -28
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "📖 SỬ ĐIỆN ANH HÙNG"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	header.add_child(title)
	var close := Button.new()
	close.text = "Đóng"
	close.pressed.connect(func(): closed.emit(); queue_free())
	header.add_child(close)
	_stock = Label.new()
	body.add_child(_stock)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	for code in ["", "ALIVE", "DEAD", "SACRIFICED"]:
		var button := Button.new()
		button.text = "Tất cả" if code == "" else str(STATUS_NAMES[code])
		button.pressed.connect(func():
			if _busy: return
			_status = code
			_page = 1
			_selected = {}
			_load_records()
		)
		filters.add_child(button)
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.split_offset = 290
	body.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 230
	columns.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_detail = RichTextLabel.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.selection_enabled = true
	columns.add_child(_detail)
	var pages := HBoxContainer.new()
	body.add_child(pages)
	_previous = Button.new()
	_previous.text = "← Trang trước"
	_previous.pressed.connect(func():
		if not _busy and _page > 1:
			_page -= 1
			_load_records()
	)
	pages.add_child(_previous)
	_page_label = Label.new()
	pages.add_child(_page_label)
	_next = Button.new()
	_next.text = "Trang sau →"
	_next.pressed.connect(func():
		if not _busy:
			_page += 1
			_load_records()
	)
	pages.add_child(_next)
	_revive = Button.new()
	_revive.text = "Hồi sinh — 1 Ngọc hồi sinh 7★ • 100% HP • Không phí thêm"
	_revive.disabled = true
	_revive.pressed.connect(_resurrect)
	body.add_child(_revive)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_notice)
	_load_records()

func _load_records() -> void:
	if _busy: return
	_busy = true
	_revive.disabled = true
	_notice.text = "Đang đọc sử điện..."
	var response: Dictionary = await ApiClient.get_req("/api/chronicles/heroes?status=%s&page=%d" % [_status, _page])
	if not is_inside_tree(): return
	_busy = false
	if not bool(response.get("ok", false)):
		_notice.text = str(response.get("error", "Không thể tải sử điện."))
		return
	var data: Dictionary = response.get("data", {})
	_records = data.get("records", [])
	_gems = int(data.get("resurrectionGem", {}).get("quantity", 0))
	_stock.text = "Ngọc hồi sinh 7★: %d • Mỗi lần dùng 1 viên. Trang bị đã rơi không được tạo lại." % _gems
	_page_label.text = "Trang %d • %d hồ sơ" % [_page, int(data.get("total", 0))]
	_previous.disabled = _page <= 1
	_next.disabled = _page * 50 >= int(data.get("total", 0))
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var selection: Dictionary = {}
	for record in _records:
		var button := Button.new()
		button.text = "%s %s\n%s" % ["★".repeat(clampi(int(record.get("rarity", 1)), 1, 7)), record.get("name", "Hero"), STATUS_NAMES.get(str(record.get("status", "")), "")]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(func():
			if not _busy: _select_record(record)
		)
		_list.add_child(button)
		if str(record.get("id", "")) == str(_selected.get("id", "")): selection = record
	if selection.is_empty() and not _records.is_empty(): selection = _records[0]
	_select_record(selection)
	_notice.text = "Chưa có hồ sơ phù hợp." if _records.is_empty() else "Tiểu sử thuộc thế giới hư cấu; lịch sử ghi nhận các mốc thực tế của Hero."

func _select_record(record: Dictionary) -> void:
	_selected = record
	_revive.disabled = _busy or _gems < 1 or str(record.get("status", "")) != "DEAD" or record.get("heroId") == null
	if record.is_empty():
		_detail.text = "Chọn một hồ sơ để xem tiểu sử và hành trình."
		return
	var lines := PackedStringArray()
	lines.append("%s — %d★\n%s • %s\n" % [record.get("name", "Hero"), int(record.get("rarity", 1)), record.get("classCode", ""), STATUS_NAMES.get(str(record.get("status", "")), "")])
	lines.append(str(record.get("biography", "")))
	lines.append("\nHÀNH TRÌNH")
	for event in record.get("events", []):
		var at := str(event.get("at", "")).replace("T", " ").left(19)
		lines.append("%s UTC • %s %s" % [at, EVENT_NAMES.get(str(event.get("type", "")), str(event.get("type", ""))), str(event.get("detail", ""))])
	_detail.text = "\n".join(lines)

func _resurrect() -> void:
	if _busy or _revive.disabled: return
	_busy = true
	_revive.disabled = true
	_notice.text = "Đang hồi sinh..."
	var response: Dictionary = await ApiClient.post_req("/api/chronicles/heroes/%s/resurrect" % str(_selected.get("id", "")), {})
	if not is_inside_tree(): return
	var message := "Đã hồi sinh Hero về 100% HP." if bool(response.get("ok", false)) else str(response.get("error", "Không thể hồi sinh."))
	await GameState.refresh_heroes()
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	if not is_inside_tree(): return
	_busy = false
	await _load_records()
	_notice.text = message
