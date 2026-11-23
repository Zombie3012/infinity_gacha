class_name ChatPanelModal
extends Control

## 3-Channel Chat Modal (M11)
## Channels: WORLD (/api/chat/world), ALLIANCE (/api/alliance/chat), PRIVATE (/api/chat/private)

signal closed

enum Channel { WORLD = 0, ALLIANCE = 1, PRIVATE = 2 }

var _active_channel: int = Channel.WORLD
var _busy: bool = false
var _messages: Array = []

var _tab_buttons: Array[Button] = []
var _private_row: HBoxContainer
var _recipient_input: LineEdit
var _messages_label: RichTextLabel
var _msg_input: LineEdit
var _status_lbl: Label

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	await refresh_messages()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.06, 0.80)
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 540)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.42, 0.78, 1.0, 0.88)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16); margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14); margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "💬 KÊNH TRÒ CHUYỆN (CHAT 3 KÊNH)"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.88, 1.0))
	hdr.add_child(title)

	var ref_btn := Button.new()
	ref_btn.text = "🔄 Làm mới"
	ref_btn.pressed.connect(func(): await refresh_messages())
	hdr.add_child(ref_btn)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	for i in range(3):
		var names := ["🌍 Thế Giới", "🏳️ Liên Minh", "🔒 Riêng Tư"]
		var b := Button.new()
		b.text = names[i]
		b.custom_minimum_size = Vector2(0, 32)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func(): await switch_channel(idx))
		tabs.add_child(b)
		_tab_buttons.append(b)

	_private_row = HBoxContainer.new()
	_private_row.add_theme_constant_override("separation", 8)
	_private_row.visible = false
	root.add_child(_private_row)

	var r_lbl := Label.new()
	r_lbl.text = "Người nhận:"
	_private_row.add_child(r_lbl)

	_recipient_input = LineEdit.new()
	_recipient_input.placeholder_text = "Nhập tên Master hoặc ID người nhận..."
	_recipient_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_private_row.add_child(_recipient_input)

	var msg_panel := PanelContainer.new()
	msg_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mps := StyleBoxFlat.new()
	mps.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	mps.border_width_left = 1; mps.border_width_top = 1; mps.border_width_right = 1; mps.border_width_bottom = 1
	mps.border_color = Color(0.24, 0.34, 0.48, 0.7)
	mps.corner_radius_top_left = 8; mps.corner_radius_top_right = 8
	mps.corner_radius_bottom_left = 8; mps.corner_radius_bottom_right = 8
	msg_panel.add_theme_stylebox_override("panel", mps)
	root.add_child(msg_panel)

	var mm := MarginContainer.new()
	mm.add_theme_constant_override("margin_left", 10); mm.add_theme_constant_override("margin_right", 10)
	mm.add_theme_constant_override("margin_top", 8); mm.add_theme_constant_override("margin_bottom", 8)
	msg_panel.add_child(mm)

	_messages_label = RichTextLabel.new()
	_messages_label.bbcode_enabled = false
	_messages_label.scroll_following = true
	mm.add_child(_messages_label)

	var send_row := HBoxContainer.new()
	send_row.add_theme_constant_override("separation", 8)
	root.add_child(send_row)

	_msg_input = LineEdit.new()
	_msg_input.placeholder_text = "Nhập tin nhắn..."
	_msg_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_input.text_submitted.connect(func(_t: String): await send_current_message())
	send_row.add_child(_msg_input)

	var send_btn := Button.new()
	send_btn.text = "📨 Gửi"
	send_btn.custom_minimum_size = Vector2(100, 34)
	send_btn.pressed.connect(func(): await send_current_message())
	send_row.add_child(send_btn)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang kết nối kênh chat..."
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func switch_channel(ch: int) -> void:
	_active_channel = ch
	await refresh_messages()

func refresh_messages() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].modulate = Color(1.0, 0.90, 0.42) if i == _active_channel else Color(0.76, 0.84, 0.92)
	if _private_row != null:
		_private_row.visible = (_active_channel == Channel.PRIVATE)

	var res: Dictionary
	match _active_channel:
		Channel.WORLD:
			res = await ApiClient.get_req("/api/chat/world")
		Channel.ALLIANCE:
			res = await ApiClient.get_req("/api/alliance/chat")
		Channel.PRIVATE:
			var peer := _recipient_input.text.strip_edges() if _recipient_input != null else ""
			var path := "/api/chat/private" + ("?peer=%s" % peer.uri_encode() if not peer.is_empty() else "")
			res = await ApiClient.get_req(path)

	if not is_instance_valid(self): return
	if res.get("ok", false):
		var d = res.get("data")
		if d is Array:
			_messages = d
		elif d is Dictionary:
			_messages = d.get("messages", d.get("items", []))
		else:
			_messages = []
		_render_messages()
		_status_lbl.text = "✅ Đã tải %d tin nhắn." % _messages.size()
	else:
		_messages = []
		_messages_label.text = "⚠️ " + str(res.get("error", "Không có tin nhắn hoặc chưa gia nhập Liên Minh."))
		_status_lbl.text = str(res.get("error", ""))

func _render_messages() -> void:
	if _messages.is_empty():
		_messages_label.text = "(Chưa có tin nhắn nào trong kênh này.)"
		return
	var lines: PackedStringArray = []
	for m in _messages:
		if not (m is Dictionary): continue
		var sname := str(m.get("senderName", m.get("masterName", "Master")))
		var rname := str(m.get("recipientName", ""))
		var body := str(m.get("body", ""))
		if _active_channel == Channel.PRIVATE and not rname.is_empty():
			lines.append("[%s → %s]: %s" % [sname, rname, body])
		else:
			lines.append("[%s]: %s" % [sname, body])
	_messages_label.text = "\n".join(lines)

func send_current_message() -> Dictionary:
	if _busy: return {}
	var text := _msg_input.text.strip_edges() if _msg_input != null else ""
	if text.is_empty():
		return {}
	_busy = true
	var res: Dictionary
	match _active_channel:
		Channel.WORLD:
			res = await ApiClient.post_req("/api/chat/world", {"body": text})
		Channel.ALLIANCE:
			res = await ApiClient.post_req("/api/alliance/chat", {"body": text})
		Channel.PRIVATE:
			var peer := _recipient_input.text.strip_edges() if _recipient_input != null else ""
			res = await ApiClient.post_req("/api/chat/private", {"recipientName": peer, "body": text})
	_busy = false
	if not is_instance_valid(self): return res
	if res.get("ok", false):
		_msg_input.text = ""
		await refresh_messages()
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Gửi thất bại"))
	return res

func _close() -> void:
	closed.emit()
	queue_free()
