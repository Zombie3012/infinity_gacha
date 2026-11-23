class_name MailboxModal
extends Control

## Mailbox & Economy Ledger Modal (M07)
## 2 tabs: Hòm Thư (/api/mailbox) & Sổ Giao Dịch Ví (/api/economy/balances, /api/economy/transactions)

signal closed

var _active_tab: int = 0
var _busy: bool = false
var _messages: Array = []
var _balances: Dictionary = {}
var _transactions: Array = []

var _tab_buttons: Array[Button] = []
var _body_vbox: VBoxContainer
var _status_lbl: Label
var _claim_all_btn: Button

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
	backdrop.color = Color(0.02, 0.03, 0.06, 0.85)
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
	panel.custom_minimum_size = Vector2(900, 600)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.09, 0.14, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.95, 0.82, 0.35, 0.88)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "✉️ HÒM THƯ & SỔ GIAO DỊCH"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.38))
	hdr.add_child(title)

	_claim_all_btn = Button.new()
	_claim_all_btn.text = "🎁 Nhận Tất Cả Thư"
	_claim_all_btn.custom_minimum_size = Vector2(150, 32)
	_claim_all_btn.pressed.connect(claim_all_messages)
	hdr.add_child(_claim_all_btn)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	for i in range(2):
		var names := ["✉️ Hòm Thư Lãnh Địa", "🪙 Sổ Giao Dịch Ví"]
		var btn := Button.new()
		btn.text = names[i]
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		btn.pressed.connect(func(): _switch_tab(idx))
		tabs.add_child(btn)
		_tab_buttons.append(btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_body_vbox)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải hòm thư..."
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	root.add_child(_status_lbl)

func refresh_all() -> void:
	if _status_lbl != null:
		_status_lbl.text = "⏳ Đang đồng bộ..."
	var m_res := await ApiClient.get_req("/api/mailbox")
	if not is_instance_valid(self): return
	if m_res.get("ok", false):
		var d = m_res.get("data")
		if d is Array:
			_messages = d
		elif d is Dictionary:
			_messages = []
			for u in d.get("unclaimed", []): _messages.append(u)
			for cl in d.get("claimed", []): _messages.append(cl)
			if _messages.is_empty():
				_messages = d.get("messages", [])

	var b_res := await ApiClient.get_req("/api/economy/balances")
	if not is_instance_valid(self): return
	if b_res.get("ok", false) and b_res.get("data") is Dictionary:
		_balances = b_res["data"]

	var t_res := await ApiClient.get_req("/api/economy/transactions?limit=50")
	if not is_instance_valid(self): return
	if t_res.get("ok", false):
		var td = t_res.get("data")
		_transactions = td if td is Array else (td.get("transactions", []) if td is Dictionary else [])

	if _status_lbl != null:
		_status_lbl.text = "✅ Đã tải %d thư và %d giao dịch." % [_messages.size(), _transactions.size()]
	_render_tab()

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	_render_tab()

func _render_tab() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].modulate = Color(1.0, 0.90, 0.42) if i == _active_tab else Color(0.76, 0.84, 0.92)
	if _claim_all_btn != null:
		_claim_all_btn.visible = (_active_tab == 0)
	if _body_vbox == null:
		return
	for c in _body_vbox.get_children():
		c.queue_free()

	if _active_tab == 0:
		_render_mailbox()
	else:
		_render_ledger()

func _render_mailbox() -> void:
	if _messages.is_empty():
		var lbl := Label.new()
		lbl.text = "📭 Hòm thư hiện đang trống."
		lbl.add_theme_color_override("font_color", Color(0.72, 0.82, 0.94))
		_body_vbox.add_child(lbl)
		return

	for msg in _messages:
		if not (msg is Dictionary): continue
		var mid := str(msg.get("id", ""))
		var claimed := bool(msg.get("claimedAt", "") != "" and msg.get("claimedAt") != null) or bool(msg.get("isClaimed", false))
		var title_txt := str(msg.get("title", msg.get("subject", "Thư Hệ Thống")))
		var body_txt := str(msg.get("body", msg.get("content", "")))
		var attach: Dictionary = msg.get("attachments", {}) if msg.get("attachments") is Dictionary else {}
		var silver := int(attach.get("silver", msg.get("silverCoins", 0)))
		var gems := int(attach.get("gems", msg.get("gems", 0)))
		var items_arr: Array = attach.get("items", []) if attach.get("items") is Array else []
		var reward_str := ""
		if silver > 0: reward_str += "🪙 +%d Bạc  " % silver
		if gems > 0: reward_str += "💎 +%d Gem  " % gems
		if not items_arr.is_empty(): reward_str += "📦 %d loại vật phẩm" % items_arr.size()

		var card := PanelContainer.new()
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(0.10, 0.13, 0.20, 0.95)
		cs.border_width_left = 1; cs.border_width_top = 1; cs.border_width_right = 1; cs.border_width_bottom = 1
		cs.border_color = Color(0.32, 0.45, 0.65, 0.7)
		cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
		cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
		card.add_theme_stylebox_override("panel", cs)
		_body_vbox.add_child(card)

		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 12); m.add_theme_constant_override("margin_right", 12)
		m.add_theme_constant_override("margin_top", 8); m.add_theme_constant_override("margin_bottom", 8)
		card.add_child(m)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		m.add_child(row)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var t := Label.new()
		t.text = "✉️ " + title_txt
		t.add_theme_font_size_override("font_size", 14)
		t.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		info.add_child(t)

		var b := Label.new()
		b.text = body_txt + ("\n🎁 Đính kèm: " + reward_str if not reward_str.is_empty() else "")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98))
		info.add_child(b)

		var btn := Button.new()
		btn.text = "Đã nhận" if claimed else "Nhận Quà"
		btn.custom_minimum_size = Vector2(120, 34)
		btn.disabled = _busy or claimed
		btn.pressed.connect(func(): await claim_message(mid))
		row.add_child(btn)

func _render_ledger() -> void:
	var bal_lbl := Label.new()
	bal_lbl.text = "💰 Số dư hiện tại — 🪙 Bạc: %d   |   💎 Đá Quý: %d" % [
		int(_balances.get("silverCoins", GameState.silver_coins)),
		int(_balances.get("gems", GameState.gem_stones)),
	]
	bal_lbl.add_theme_font_size_override("font_size", 14)
	bal_lbl.add_theme_color_override("font_color", Color(0.55, 0.96, 0.72))
	_body_vbox.add_child(bal_lbl)

	if _transactions.is_empty():
		var empty := Label.new()
		empty.text = "Chưa có giao dịch thu/chi nào được ghi nhận."
		empty.add_theme_color_override("font_color", Color(0.72, 0.82, 0.94))
		_body_vbox.add_child(empty)
		return

	for tx in _transactions:
		if not (tx is Dictionary): continue
		var ctype := str(tx.get("currencyType", "SILVER"))
		var delta := int(tx.get("amount", tx.get("delta", 0)))
		var reason := str(tx.get("reason", tx.get("source", "Giao dịch")))
		var line := Label.new()
		line.text = "• [%s] %+d  —  %s" % [ctype, delta, reason]
		line.add_theme_font_size_override("font_size", 12)
		line.add_theme_color_override("font_color", Color(0.55, 0.95, 0.65) if delta >= 0 else Color(1.0, 0.68, 0.58))
		_body_vbox.add_child(line)

func claim_message(mid: String) -> void:
	if _busy or mid.is_empty(): return
	_busy = true
	var res := await ApiClient.post_req("/api/mailbox/%s/claim" % mid, {})
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🎁 Đã nhận quà thư!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	await refresh_all()

func claim_all_messages() -> void:
	if _busy: return
	_busy = true
	var claimed_cnt := 0
	for msg in _messages:
		if not (msg is Dictionary): continue
		var claimed := bool(msg.get("claimedAt", "") != "" and msg.get("claimedAt") != null) or bool(msg.get("isClaimed", false))
		if not claimed:
			var res := await ApiClient.post_req("/api/mailbox/%s/claim" % str(msg.get("id", "")), {})
			if res.get("ok", false):
				claimed_cnt += 1
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "🎁 Đã nhận %d thư chưa nhận!" % claimed_cnt
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	await refresh_all()

func _close() -> void:
	closed.emit()
	queue_free()
