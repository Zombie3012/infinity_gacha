class_name FriendsModal
extends Control

## Friends Modal (P2-03)
## 3 tabs: Bạn Bè (/api/friends), Lời Mời (/api/friends/requests), Tìm Kiếm & Chặn (/api/friends/search)

signal closed
signal private_chat_requested(peer_name: String, peer_master_id: String)

var _active_tab: int = 0
var _busy: bool = false
var _friends: Array = []
var _blocked: Array = []
var _unclaimed_gift_count: int = 0
var _incoming_requests: Array = []
var _outgoing_requests: Array = []
var _search_results: Array = []

var _panel: PanelContainer
var _tab_buttons: Array[Button] = []
var _body_vbox: VBoxContainer
var _status_lbl: Label
var _search_input: LineEdit
var _profile_overlay: PanelContainer

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

	var vp := get_viewport_rect().size
	var pw := clampf(vp.x * 0.82, 660.0, 900.0) if vp.x > 0 else 820.0
	var ph := clampf(vp.y * 0.84, 460.0, 620.0) if vp.y > 0 else 560.0

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(pw, ph)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.42, 0.82, 0.65, 0.88)
	ps.corner_radius_top_left = 12; ps.corner_radius_top_right = 12
	ps.corner_radius_bottom_left = 12; ps.corner_radius_bottom_right = 12
	_panel.add_theme_stylebox_override("panel", ps)
	center.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16); margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14); margin.add_theme_constant_override("margin_bottom", 14)
	_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var hdr := HBoxContainer.new()
	root.add_child(hdr)
	var title := Label.new()
	title.text = "👥 HỆ THỐNG BẠN BÈ & TÌNH BẠN"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.55, 0.95, 0.78))
	hdr.add_child(title)

	var ref_btn := Button.new()
	ref_btn.text = "🔄 Làm mới"
	ref_btn.pressed.connect(func(): await refresh_all())
	hdr.add_child(ref_btn)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.pressed.connect(_close)
	hdr.add_child(close_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	root.add_child(tabs)
	var tab_names := ["👥 Bạn Bè", "📨 Lời Mời", "🔍 Tìm Kiếm & Chặn"]
	for i in range(tab_names.size()):
		var b := Button.new()
		b.text = tab_names[i]
		b.custom_minimum_size = Vector2(0, 34)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var idx := i
		b.pressed.connect(func(): switch_tab(idx))
		tabs.add_child(b)
		_tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body_vbox = VBoxContainer.new()
	_body_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_body_vbox)

	_status_lbl = Label.new()
	_status_lbl.text = "Đang tải danh sách bạn bè..."
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	root.add_child(_status_lbl)

func switch_tab(idx: int) -> void:
	_active_tab = idx
	_render_body()

func refresh_all() -> void:
	var f_res := await ApiClient.get_req("/api/friends")
	if not is_instance_valid(self): return
	if f_res.get("ok", false) and f_res.get("data") is Dictionary:
		var fd: Dictionary = f_res["data"]
		_friends = fd.get("friends", []) if fd.get("friends") is Array else []
		_blocked = fd.get("blocked", []) if fd.get("blocked") is Array else []
		_unclaimed_gift_count = int(fd.get("unclaimedGiftCount", 0))

	var r_res := await ApiClient.get_req("/api/friends/requests")
	if not is_instance_valid(self): return
	if r_res.get("ok", false) and r_res.get("data") is Dictionary:
		var rd: Dictionary = r_res["data"]
		_incoming_requests = rd.get("incoming", []) if rd.get("incoming") is Array else []
		_outgoing_requests = rd.get("outgoing", []) if rd.get("outgoing") is Array else []

	GameState.set_badge_count("friends", _unclaimed_gift_count + _incoming_requests.size())
	_update_tab_labels()
	if _status_lbl != null:
		_status_lbl.text = "✅ Bạn bè: %d • Lời mời đến: %d • Quà chưa nhận: %d" % [_friends.size(), _incoming_requests.size(), _unclaimed_gift_count]
	_render_body()

func _update_tab_labels() -> void:
	if _tab_buttons.size() >= 3:
		_tab_buttons[0].text = "👥 Bạn Bè (%d)" % _friends.size()
		_tab_buttons[1].text = "📨 Lời Mời (%d)" % _incoming_requests.size()
		_tab_buttons[2].text = "🔍 Tìm Kiếm & Chặn (%d)" % _blocked.size()

func _render_body() -> void:
	for i in range(_tab_buttons.size()):
		_tab_buttons[i].modulate = Color(1.0, 0.90, 0.42) if i == _active_tab else Color(0.76, 0.84, 0.92)
	if _body_vbox == null:
		return
	for c in _body_vbox.get_children():
		c.queue_free()

	match _active_tab:
		0: _render_friends_tab()
		1: _render_requests_tab()
		2: _render_search_and_block_tab()

func _make_card() -> HBoxContainer:
	var card := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.10, 0.13, 0.20, 0.95)
	cs.border_width_left = 1; cs.border_width_top = 1; cs.border_width_right = 1; cs.border_width_bottom = 1
	cs.border_color = Color(0.28, 0.42, 0.58, 0.72)
	cs.corner_radius_top_left = 8; cs.corner_radius_top_right = 8
	cs.corner_radius_bottom_left = 8; cs.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", cs)
	_body_vbox.add_child(card)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12); m.add_theme_constant_override("margin_right", 12)
	m.add_theme_constant_override("margin_top", 8); m.add_theme_constant_override("margin_bottom", 8)
	card.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	m.add_child(row)
	return row

func _render_friends_tab() -> void:
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(top_bar)

	var claim_all_btn := Button.new()
	claim_all_btn.text = "🎁 Nhận Tất Cả Quà (%d)" % _unclaimed_gift_count
	claim_all_btn.disabled = _busy or _unclaimed_gift_count <= 0
	claim_all_btn.pressed.connect(func(): await claim_all_gifts())
	top_bar.add_child(claim_all_btn)

	var send_all_btn := Button.new()
	send_all_btn.text = "💝 Tặng Quà Tất Cả"
	send_all_btn.disabled = _busy or _friends.is_empty()
	send_all_btn.pressed.connect(func(): await send_gift_all())
	top_bar.add_child(send_all_btn)

	if _friends.is_empty():
		var lbl := Label.new()
		lbl.text = "Chưa có bạn bè nào. Hãy sang tab Tìm Kiếm hoặc Liên Minh để kết bạn!"
		lbl.add_theme_color_override("font_color", Color(0.75, 0.84, 0.94))
		_body_vbox.add_child(lbl)
		return

	for f in _friends:
		if not (f is Dictionary): continue
		var fid := str(f.get("friendMasterId", ""))
		var fname := str(f.get("masterName", "Master"))
		var lvl := int(f.get("level", 1))
		var sent := bool(f.get("giftSentToday", false))
		var has_gift := bool(f.get("giftReceivedUnclaimed", false))

		var row := _make_card()
		var info := Label.new()
		info.text = "👤 %s (Lv.%d)%s" % [fname, lvl, "  • 🎁 Có quà chưa nhận!" if has_gift else ""]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var gift_btn := Button.new()
		gift_btn.text = "✓ Đã tặng" if sent else "🎁 Tặng Quà"
		gift_btn.disabled = _busy or sent
		gift_btn.pressed.connect(func(): await send_gift(fid))
		row.add_child(gift_btn)

		var chat_btn := Button.new()
		chat_btn.text = "💬 Nhắn Riêng"
		chat_btn.pressed.connect(func():
			private_chat_requested.emit(fname, fid)
			_close()
		)
		row.add_child(chat_btn)

		var prof_btn := Button.new()
		prof_btn.text = "🪪 Hồ Sơ"
		prof_btn.pressed.connect(func(): await view_profile(fid))
		row.add_child(prof_btn)

		var visit_btn := Button.new()
		visit_btn.text = "🏰 Thăm Lâu Đài"
		visit_btn.pressed.connect(func(): await visit_friend_base(fid, fname))
		row.add_child(visit_btn)

		var block_btn := Button.new()
		block_btn.text = "🚫 Chặn"
		block_btn.pressed.connect(func(): await block_master(fid))
		row.add_child(block_btn)

		var del_btn := Button.new()
		del_btn.text = "🗑️ Xóa"
		del_btn.pressed.connect(func(): await remove_friend(fid))
		row.add_child(del_btn)

func _render_requests_tab() -> void:
	var in_hdr := Label.new()
	in_hdr.text = "📥 Lời mời kết bạn đến (%d)" % _incoming_requests.size()
	in_hdr.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	_body_vbox.add_child(in_hdr)

	if _incoming_requests.is_empty():
		var e1 := Label.new()
		e1.text = "(Không có lời mời đến.)"
		_body_vbox.add_child(e1)
	else:
		for req in _incoming_requests:
			if not (req is Dictionary): continue
			var rid := str(req.get("requestId", ""))
			var rname := str(req.get("masterName", "Master"))
			var lvl := int(req.get("level", 1))
			var row := _make_card()
			var lbl := Label.new()
			lbl.text = "👤 %s (Lv.%d)" % [rname, lvl]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)

			var acc_btn := Button.new()
			acc_btn.text = "✅ Chấp Nhận"
			acc_btn.disabled = _busy
			acc_btn.pressed.connect(func(): await accept_request(rid))
			row.add_child(acc_btn)

			var dec_btn := Button.new()
			dec_btn.text = "❌ Từ Chối"
			dec_btn.disabled = _busy
			dec_btn.pressed.connect(func(): await decline_request(rid))
			row.add_child(dec_btn)

	var out_hdr := Label.new()
	out_hdr.text = "📤 Lời mời đã gửi (%d)" % _outgoing_requests.size()
	out_hdr.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))
	_body_vbox.add_child(out_hdr)

	if _outgoing_requests.is_empty():
		var e2 := Label.new()
		e2.text = "(Chưa gửi lời mời nào.)"
		_body_vbox.add_child(e2)
	else:
		for req in _outgoing_requests:
			if not (req is Dictionary): continue
			var rid := str(req.get("requestId", ""))
			var rname := str(req.get("masterName", "Master"))
			var lvl := int(req.get("level", 1))
			var row := _make_card()
			var lbl := Label.new()
			lbl.text = "⏳ %s (Lv.%d)" % [rname, lvl]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)

			var cancel_btn := Button.new()
			cancel_btn.text = "↩️ Hủy"
			cancel_btn.disabled = _busy
			cancel_btn.pressed.connect(func(): await decline_request(rid))
			row.add_child(cancel_btn)

func _render_search_and_block_tab() -> void:
	var s_row := HBoxContainer.new()
	s_row.add_theme_constant_override("separation", 8)
	_body_vbox.add_child(s_row)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Nhập tên Master hoặc ID để tìm..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.text_submitted.connect(func(txt: String): await search_masters(txt))
	s_row.add_child(_search_input)

	var s_btn := Button.new()
	s_btn.text = "🔍 Tìm Kiếm"
	s_btn.pressed.connect(func(): await search_masters(_search_input.text if _search_input != null else ""))
	s_row.add_child(s_btn)

	for r in _search_results:
		if not (r is Dictionary): continue
		var mid := str(r.get("masterId", ""))
		var mname := str(r.get("masterName", "Master"))
		var lvl := int(r.get("level", 1))
		var rel := str(r.get("relationStatus", "NONE"))
		var row := _make_card()
		var lbl := Label.new()
		lbl.text = "👤 %s (Lv.%d)" % [mname, lvl]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		if rel == "NONE":
			var add_btn := Button.new()
			add_btn.text = "➕ Kết Bạn"
			add_btn.disabled = _busy
			add_btn.pressed.connect(func(): await send_request(mid))
			row.add_child(add_btn)
		else:
			var st_lbl := Label.new()
			st_lbl.text = "[%s]" % rel
			row.add_child(st_lbl)

		if rel != "BLOCKED":
			var blk_btn := Button.new()
			blk_btn.text = "🚫 Chặn"
			blk_btn.disabled = _busy
			blk_btn.pressed.connect(func(): await block_master(mid))
			row.add_child(blk_btn)

	var b_hdr := Label.new()
	b_hdr.text = "🚫 Danh sách đã chặn (%d)" % _blocked.size()
	b_hdr.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	_body_vbox.add_child(b_hdr)

	for b in _blocked:
		if not (b is Dictionary): continue
		var bid := str(b.get("friendMasterId", ""))
		var bname := str(b.get("masterName", "Master"))
		var row := _make_card()
		var lbl := Label.new()
		lbl.text = "🚫 %s" % bname
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var unb_btn := Button.new()
		unb_btn.text = "🔓 Bỏ Chặn"
		unb_btn.disabled = _busy
		unb_btn.pressed.connect(func(): await unblock_master(bid))
		row.add_child(unb_btn)

func search_masters(query: String) -> Dictionary:
	var res := await ApiClient.get_req("/api/friends/search?q=%s" % query.strip_edges().uri_encode())
	if not is_instance_valid(self): return res
	if res.get("ok", false) and res.get("data") is Dictionary:
		_search_results = res["data"].get("results", [])
		_status_lbl.text = "🔍 Tìm thấy %d Master." % _search_results.size()
		_render_body()
	return res

func send_request(target_master_id: String) -> Dictionary:
	if _busy or target_master_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/requests", {"targetMasterId": target_master_id})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "📨 Đã gửi lời mời kết bạn!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func accept_request(request_id: String) -> Dictionary:
	if _busy or request_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/requests/%s/accept" % request_id, {})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "✅ Đã trở thành bạn bè!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func decline_request(request_id: String) -> Dictionary:
	if _busy or request_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/requests/%s/decline" % request_id, {})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🗑️ Đã hủy / từ chối lời mời." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func remove_friend(friend_master_id: String) -> Dictionary:
	if _busy or friend_master_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.delete_req("/api/friends/%s" % friend_master_id)
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🗑️ Đã xóa bạn bè." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func block_master(target_master_id: String) -> Dictionary:
	if _busy or target_master_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/%s/block" % target_master_id, {})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🚫 Đã chặn người chơi này." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func unblock_master(target_master_id: String) -> Dictionary:
	if _busy or target_master_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.delete_req("/api/friends/%s/block" % target_master_id)
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🔓 Đã bỏ chặn." if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func send_gift(friend_master_id: String) -> Dictionary:
	if _busy or friend_master_id.is_empty(): return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/%s/gift" % friend_master_id, {})
	_busy = false
	if not is_instance_valid(self): return res
	_status_lbl.text = "🎁 Đã gửi quà tình bạn!" if res.get("ok", false) else ("❌ " + str(res.get("error", "Lỗi")))
	await refresh_all()
	return res

func send_gift_all() -> void:
	if _busy: return
	_busy = true
	var sent_cnt := 0
	for f in _friends:
		if f is Dictionary and not bool(f.get("giftSentToday", false)):
			var res := await ApiClient.post_req("/api/friends/%s/gift" % str(f.get("friendMasterId", "")), {})
			if res.get("ok", false):
				sent_cnt += 1
	_busy = false
	if not is_instance_valid(self): return
	_status_lbl.text = "💝 Đã tặng quà cho %d bạn bè!" % sent_cnt
	await refresh_all()

func claim_all_gifts() -> Dictionary:
	if _busy: return {}
	_busy = true
	var res := await ApiClient.post_req("/api/friends/gifts/claim-all", {})
	_busy = false
	if not is_instance_valid(self): return res
	if res.get("ok", false) and res.get("data") is Dictionary:
		var cnt := int(res["data"].get("claimedCount", 0))
		var silver := int(res["data"].get("totalSilver", 0))
		_status_lbl.text = "🎁 Đã nhận %d quà (+%d Bạc)!" % [cnt, silver]
		await GameState.refresh_profile()
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Lỗi nhận quà"))
	await refresh_all()
	return res

func view_profile(friend_master_id: String) -> Dictionary:
	var res := await ApiClient.get_req("/api/friends/%s/profile" % friend_master_id)
	if not is_instance_valid(self): return res
	if res.get("ok", false) and res.get("data") is Dictionary:
		var prof: Dictionary = res["data"].get("profile", {})
		var mname := str(prof.get("masterName", "Master"))
		var lvl := int(prof.get("level", 1))
		var al := str(prof.get("allianceName", ""))
		var hcnt := int(prof.get("heroCount", 0))
		var top_heroes: Array = prof.get("topHeroes", []) if prof.get("topHeroes") is Array else []
		var h_names: PackedStringArray = []
		for h in top_heroes:
			if h is Dictionary:
				h_names.append("%s (%d★ Lv.%d)" % [str(h.get("name", "Hero")), int(h.get("rarity", 1)), int(h.get("level", 1))])
		_status_lbl.text = "🪪 %s (Lv.%d) • LM: %s • %d Tướng • Top: %s" % [
			mname, lvl, al if not al.is_empty() else "Chưa gia nhập", hcnt, ", ".join(h_names) if not h_names.is_empty() else "Không có"
		]
	else:
		_status_lbl.text = "❌ " + str(res.get("error", "Không thể xem hồ sơ"))
	return res

func _close() -> void:
	closed.emit()
	queue_free()

func visit_friend_base(friend_master_id: String, friend_name: String = "Bạn bè") -> Dictionary:
	var res := await ApiClient.get_req("/api/friends/%s/base" % friend_master_id)
	if not is_instance_valid(self): return res
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		_status_lbl.text = "❌ " + str(res.get("error", "Không thể thăm Lâu Đài"))
		return res

	var data: Dictionary = res["data"]
	var m_info: Dictionary = data.get("master", {}) if data.get("master") is Dictionary else {}
	var buildings: Array = data.get("buildings", []) if data.get("buildings") is Array else []
	var m_name := str(m_info.get("masterName", friend_name))
	var m_lvl := int(m_info.get("level", 1))

	if _profile_overlay != null and is_instance_valid(_profile_overlay):
		_profile_overlay.queue_free()

	_profile_overlay = PanelContainer.new()
	_profile_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_profile_overlay.custom_minimum_size = Vector2(520, 380)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.11, 0.18, 0.99)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(1.0, 0.85, 0.35, 0.95)
	ps.corner_radius_top_left = 10; ps.corner_radius_top_right = 10
	ps.corner_radius_bottom_left = 10; ps.corner_radius_bottom_right = 10
	_profile_overlay.add_theme_stylebox_override("panel", ps)
	add_child(_profile_overlay)

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 16); m.add_theme_constant_override("margin_right", 16)
	m.add_theme_constant_override("margin_top", 14); m.add_theme_constant_override("margin_bottom", 14)
	_profile_overlay.add_child(m)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)

	var hdr := HBoxContainer.new()
	v.add_child(hdr)
	var t := Label.new()
	t.text = "🏰 LÂU ĐÀI CỦA %s (Lv.%d)" % [m_name.to_upper(), m_lvl]
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	hdr.add_child(t)
	var x_btn := Button.new()
	x_btn.text = "✖"
	x_btn.pressed.connect(func(): _profile_overlay.queue_free())
	hdr.add_child(x_btn)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)

	if buildings.is_empty():
		var elbl := Label.new()
		elbl.text = "Chưa có công trình nào được xây dựng."
		grid.add_child(elbl)
	else:
		for b in buildings:
			if not (b is Dictionary): continue
			var blbl := Label.new()
			blbl.text = "🏛️ %s • Ô #%d (Lv.%d)" % [str(b.get("buildingType", "")), int(b.get("plotIndex", 0)), int(b.get("level", 1))]
			grid.add_child(blbl)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 10)
	v.add_child(act_row)

	var gift_b := Button.new()
	gift_b.text = "🎁 Tặng Quà Tình Bạn"
	gift_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gift_b.pressed.connect(func(): await send_gift(friend_master_id))
	act_row.add_child(gift_b)

	var praise_b := Button.new()
	praise_b.text = "👏 Gửi Lời Khen"
	praise_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	praise_b.pressed.connect(func():
		var pm := await ApiClient.post_req("/api/chat/private", {"recipientMasterId": friend_master_id, "body": "👏 Lâu Đài của bạn thật ấn tượng!"})
		_status_lbl.text = "👏 Đã gửi lời khen tới %s!" % m_name if pm.get("ok", false) else ("❌ " + str(pm.get("error", "")))
	)
	act_row.add_child(praise_b)
	return res
