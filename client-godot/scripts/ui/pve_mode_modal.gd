class_name PveModeModal
extends Control

## PvE Tower Mode Selector Modal (SummonBannerModal card style)
## Two-step flow:
##   1. Horizontal scrollable list of PvE mode cards (Tower, Dungeon, Expedition, Conquest).
##   2. Detailed view of the selected mode with requirements, rewards, and Enter action.

signal mode_selected(mode_id: String)
signal closed

const CARD_WIDTH := 429
const CARD_GAP := 18
const CARD_STEP := CARD_WIDTH + CARD_GAP

var _modes: Array = []
var _selected_mode: Dictionary = {}

var _root_vbox: VBoxContainer
var _status_lbl: Label
var _content_slot: Control
var _mode_scroll: ScrollContainer
var _scroll_tween: Tween

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(modes: Array = []) -> void:
	_modes = modes.duplicate(true) if not modes.is_empty() else _build_default_modes()
	_selected_mode = {}
	_build_shell()
	_render_mode_list()

static func _build_default_modes() -> Array:
	var party_cnt := GameState.active_party_ids.size()
	var cur_floor := maxi(1, GameState.current_floor)
	var world_lvl := maxi(1, GameState.world_level)
	return [
		{
			"id": "TOWER",
			"badge": "🗼 CHẾ ĐỘ CHÍNH • ĐANG MỞ",
			"title": "Tháp Thử Thách (PvE Tower)",
			"subtitle": "Tầng hiện tại: %d  •  World Lv.%d" % [cur_floor, world_lvl],
			"requirement": "🛡️ Đội hình xuất kích: %d/5 Tướng" % party_cnt,
			"accent": Color(0.98, 0.72, 0.25),
			"bg": Color(0.14, 0.09, 0.20, 0.96),
			"available": true,
			"enter_label": "⚔️ Tiến Vào Tháp PvE",
			"highlights": [
				"• Khám phá bản đồ lưới theo tầng, mở sương mù chiến tranh",
				"• Chiến đấu với Quái & Boss tầng (Auto hoặc Điều khiển Thủ công)",
				"• Sử dụng vật phẩm Giả Kim & thu thập Rương tài nguyên, Trang bị",
				"• Rút lui an toàn qua Cổng Dịch Chuyển hoặc Điểm Hồi Thành"
			]
		},
		{
			"id": "DUNGEON",
			"badge": "🕳️ HẦM NGỤC • SẮP RA MẮT",
			"title": "Hầm Ngục Cổ Đại (Dungeon)",
			"subtitle": "Thám hiểm theo phiên • World Seed",
			"requirement": "🔑 Yêu cầu: Mở khóa sau Tầng 1 Tháp",
			"accent": Color(0.35, 0.78, 1.0),
			"bg": Color(0.08, 0.13, 0.22, 0.96),
			"available": false,
			"enter_label": "🚧 Đang hoàn thiện giao diện 3D",
			"highlights": [
				"• Bản đồ sinh ngẫu nhiên theo World Seed từng tầng",
				"• Đối mặt Quái tinh nhuệ & Bẫy hầm ngục với phần thưởng hiếm",
				"• Quản lý thể lực, khẩu phần và rút lui bảo toàn chiến lợi phẩm",
				"• Rơi Nguyên liệu rèn Trang bị & Đá cường hóa"
			]
		},
		{
			"id": "EXPEDITION",
			"badge": "🧭 VIỄN CHINH • SẮP RA MẮT",
			"title": "Viễn Chinh Thế Giới (Expedition)",
			"subtitle": "Cử đội thám hiểm dài ngày",
			"requirement": "👥 Yêu cầu: Tối thiểu 1 Đội Tướng rảnh",
			"accent": Color(0.42, 0.92, 0.68),
			"bg": Color(0.07, 0.16, 0.15, 0.96),
			"available": false,
			"enter_label": "🚧 Đang hoàn thiện giao diện 3D",
			"highlights": [
				"• Cử Tướng đi thu thập Lương thực, Gỗ, Đá và Bạc tự động",
				"• Thời gian thực theo khu vực tài nguyên ngoài Lâu Đài",
				"• Có thể triệu hồi đội về sớm khi cần nhân lực phòng thủ",
				"• Tối ưu hóa Tướng không nằm trong đội hình leo Tháp"
			]
		},
		{
			"id": "CONQUEST",
			"badge": "🏰 CHINH PHẠT • SẮP RA MẮT",
			"title": "Chinh Phạt Lãnh Thổ (Conquest)",
			"subtitle": "Chiến trường Liên Minh & Kỳ Quan",
			"requirement": "🏳️ Yêu cầu: Tham gia Liên Minh",
			"accent": Color(0.96, 0.46, 0.48),
			"bg": Color(0.18, 0.08, 0.12, 0.96),
			"available": false,
			"enter_label": "🚧 Đang hoàn thiện giao diện 3D",
			"highlights": [
				"• Chiếm đóng các Ô tài nguyên & Kỳ Quan trên Bản đồ Thế giới",
				"• Cạnh tranh Bảng Xếp Hạng Mùa Giải cùng Liên Minh",
				"• Nhận danh hiệu, Đá Quý và rương phần thưởng cuối mùa",
				"• Thiết lập đội hình phòng thủ lãnh thổ"
			]
		}
	]

func _format_num(n: int) -> String:
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0 and s[i - 1] != "-":
			out = "," + out
	return out

func _format_status_text() -> String:
	var ration := int(GameState.materials.get("RATION", 0))
	return "🛡️ Đội hình: %d/5 Tướng   |   🗼 Tầng Tháp: %d   |   🍖 Khẩu phần: %s" % [
		GameState.active_party_ids.size(),
		maxi(1, GameState.current_floor),
		_format_num(ration)
	]

func _build_shell() -> void:
	for c in get_children():
		c.queue_free()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.03, 0.07, 0.85)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.07, 0.09, 0.15, 0.98)
	pstyle.border_width_left = 2
	pstyle.border_width_top = 2
	pstyle.border_width_right = 2
	pstyle.border_width_bottom = 2
	pstyle.border_color = Color(0.95, 0.78, 0.28, 0.9)
	pstyle.corner_radius_top_left = 14
	pstyle.corner_radius_top_right = 14
	pstyle.corner_radius_bottom_left = 14
	pstyle.corner_radius_bottom_right = 14
	pstyle.shadow_size = 16
	pstyle.shadow_color = Color(0, 0, 0, 0.7)
	panel.add_theme_stylebox_override("panel", pstyle)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(_root_vbox)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	_root_vbox.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text = "⚔️ CỔNG THÁP PvE & CHINH PHẠT"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)

	_status_lbl = Label.new()
	_status_lbl.text = _format_status_text()
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	top_bar.add_child(_status_lbl)

	var close_btn := Button.new()
	close_btn.text = " ✕ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(_close)
	top_bar.add_child(close_btn)

	_root_vbox.add_child(HSeparator.new())

	_content_slot = VBoxContainer.new()
	_content_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root_vbox.add_child(_content_slot)

func _clear_content() -> void:
	if _content_slot == null:
		return
	for c in _content_slot.get_children():
		c.queue_free()

func _render_mode_list() -> void:
	_selected_mode = {}
	_clear_content()

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)
	_content_slot.add_child(header_row)

	var subtitle := Label.new()
	subtitle.text = "Hiển thị 2 chế độ mỗi khung • Kéo thanh trượt ngang hoặc bấm ◀ / ▶ để chuyển sang chế độ tiếp theo:"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.76, 0.85, 0.96))
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(subtitle)

	if _modes.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Hiện chưa có chế độ PvE nào khả dụng."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_content_slot.add_child(empty_lbl)
		return

	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.custom_minimum_size = Vector2(36, 28)
	prev_btn.tooltip_text = "Cuộn về thẻ trước"
	header_row.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.custom_minimum_size = Vector2(36, 28)
	next_btn.tooltip_text = "Cuộn sang thẻ tiếp theo"
	header_row.add_child(next_btn)

	var h_scroll := ScrollContainer.new()
	h_scroll.name = "ModeCarouselScroll"
	h_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS if _modes.size() > 2 else ScrollContainer.SCROLL_MODE_DISABLED
	h_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h_scroll.custom_minimum_size = Vector2(CARD_WIDTH * 2 + CARD_GAP, 404)
	h_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_scroll.clip_contents = true
	_content_slot.add_child(h_scroll)
	_mode_scroll = h_scroll

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", CARD_GAP)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_scroll.add_child(hbox)

	for m in _modes:
		if not (m is Dictionary):
			continue
		hbox.add_child(_create_mode_card(m))

	var max_scroll := maxi(0, (_modes.size() - 2) * CARD_STEP)
	prev_btn.visible = _modes.size() > 2
	next_btn.visible = _modes.size() > 2
	prev_btn.pressed.connect(func(): _scroll_modes_by(-CARD_STEP, max_scroll))
	next_btn.pressed.connect(func(): _scroll_modes_by(CARD_STEP, max_scroll))

func _scroll_modes_by(delta_px: int, max_scroll: int) -> void:
	if _mode_scroll == null or not is_instance_valid(_mode_scroll):
		return
	var current := _mode_scroll.scroll_horizontal
	var snapped := int(round(float(current) / float(CARD_STEP))) * CARD_STEP
	var target := clampi(snapped + delta_px, 0, max_scroll)
	if _scroll_tween != null and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_scroll_tween.tween_property(_mode_scroll, "scroll_horizontal", target, 0.22)

func _create_mode_card(m: Dictionary) -> Control:
	var m_title := str(m.get("title", "Chế độ PvE"))
	var badge_txt := str(m.get("badge", "⚔️ PvE"))
	var sub_txt := str(m.get("subtitle", ""))
	var req_txt := str(m.get("requirement", ""))
	var is_avail := bool(m.get("available", false))
	var accent: Color = m.get("accent", Color(0.35, 0.78, 1.0))
	var bg: Color = m.get("bg", Color(0.08, 0.13, 0.22, 0.96))

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 386)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent if is_avail else accent.darkened(0.35)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Xem chế độ " + m_title
	card.focus_mode = Control.FOCUS_ALL

	var hover_style: StyleBoxFlat = style.duplicate()
	hover_style.bg_color = bg.lightened(0.12)
	hover_style.border_color = accent.lightened(0.2)
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_style))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", style))
	card.focus_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_style))
	card.focus_exited.connect(func(): card.add_theme_stylebox_override("panel", style))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				card.set_meta("press_origin", event.global_position)
			elif card.has_meta("press_origin"):
				var origin: Vector2 = card.get_meta("press_origin")
				card.remove_meta("press_origin")
				if origin.distance_to(event.global_position) < 8.0 and card.get_global_rect().has_point(event.global_position):
					_render_mode_detail.call_deferred(m)
					card.accept_event()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_render_mode_detail.call_deferred(m)
			card.accept_event()
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	card.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var badge := Label.new()
	badge.text = badge_txt
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", accent)
	vb.add_child(badge)

	var title := Label.new()
	title.text = m_title
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	vb.add_child(title)

	if sub_txt != "":
		var sub_lbl := Label.new()
		sub_lbl.text = sub_txt
		sub_lbl.add_theme_font_size_override("font_size", 13)
		sub_lbl.add_theme_color_override("font_color", Color(0.55, 0.96, 0.72) if is_avail else Color(0.70, 0.78, 0.88))
		vb.add_child(sub_lbl)

	if req_txt != "":
		var req_lbl := Label.new()
		req_lbl.text = req_txt
		req_lbl.add_theme_font_size_override("font_size", 13)
		req_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		vb.add_child(req_lbl)

	vb.add_child(HSeparator.new())

	var highlights: Array = m.get("highlights", [])
	var hl_lines: PackedStringArray = []
	for line in highlights:
		hl_lines.append(str(line))

	var hl_lbl := Label.new()
	hl_lbl.text = "\n".join(hl_lines)
	hl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl_lbl.add_theme_font_size_override("font_size", 12)
	hl_lbl.add_theme_color_override("font_color", Color(0.84, 0.90, 0.98))
	hl_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(hl_lbl)

	var hint_lbl := Label.new()
	hint_lbl.text = "👉 Nhấn thẻ để xem chi tiết & Xuất kích" if is_avail else "👉 Nhấn thẻ để xem thông tin chế độ"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", accent)
	vb.add_child(hint_lbl)

	_ignore_card_children_mouse(card)
	return card

func _ignore_card_children_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_card_children_mouse(child)

func _render_mode_detail(m: Dictionary) -> void:
	_selected_mode = m
	_clear_content()

	var m_id := str(m.get("id", ""))
	var m_title := str(m.get("title", "Chế độ PvE"))
	var badge_txt := str(m.get("badge", ""))
	var sub_txt := str(m.get("subtitle", ""))
	var req_txt := str(m.get("requirement", ""))
	var is_avail := bool(m.get("available", false))
	var enter_txt := str(m.get("enter_label", "⚔️ Xuất Kích"))
	var accent: Color = m.get("accent", Color(0.35, 0.78, 1.0))

	var nav_bar := HBoxContainer.new()
	nav_bar.add_theme_constant_override("separation", 12)
	_content_slot.add_child(nav_bar)

	var back_btn := Button.new()
	back_btn.text = "← Quay lại danh sách"
	back_btn.custom_minimum_size = Vector2(180, 34)
	back_btn.pressed.connect(_render_mode_list)
	nav_bar.add_child(back_btn)

	var d_title := Label.new()
	d_title.text = "%s  —  %s" % [m_title, badge_txt]
	d_title.add_theme_font_size_override("font_size", 16)
	d_title.add_theme_color_override("font_color", accent)
	d_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav_bar.add_child(d_title)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_slot.add_child(body)

	# Left panel: Mode mechanics & highlights
	var left_panel := PanelContainer.new()
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lstyle := StyleBoxFlat.new()
	lstyle.bg_color = Color(0.05, 0.08, 0.14, 0.9)
	lstyle.border_width_left = 1
	lstyle.border_width_top = 1
	lstyle.border_width_right = 1
	lstyle.border_width_bottom = 1
	lstyle.border_color = Color(0.28, 0.36, 0.52, 0.7)
	lstyle.corner_radius_top_left = 10
	lstyle.corner_radius_top_right = 10
	lstyle.corner_radius_bottom_left = 10
	lstyle.corner_radius_bottom_right = 10
	left_panel.add_theme_stylebox_override("panel", lstyle)
	body.add_child(left_panel)

	var lm := MarginContainer.new()
	lm.add_theme_constant_override("margin_left", 16)
	lm.add_theme_constant_override("margin_right", 16)
	lm.add_theme_constant_override("margin_top", 14)
	lm.add_theme_constant_override("margin_bottom", 14)
	left_panel.add_child(lm)

	var lvb := VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 10)
	lm.add_child(lvb)

	var sec_hdr := Label.new()
	sec_hdr.text = "📜 CHI TIẾT CHẾ ĐỘ & CƠ CHẾ"
	sec_hdr.add_theme_font_size_override("font_size", 14)
	sec_hdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	lvb.add_child(sec_hdr)

	var highlights: Array = m.get("highlights", [])
	var hl_lines: PackedStringArray = []
	for line in highlights:
		hl_lines.append(str(line))

	var hl_lbl := Label.new()
	hl_lbl.text = "\n\n".join(hl_lines)
	hl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl_lbl.add_theme_font_size_override("font_size", 13)
	hl_lbl.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	hl_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lvb.add_child(hl_lbl)

	# Right panel: Status, requirements & Enter button
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(360, 0)
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rstyle := lstyle.duplicate()
	rstyle.border_color = accent
	right_panel.add_theme_stylebox_override("panel", rstyle)
	body.add_child(right_panel)

	var rm := MarginContainer.new()
	rm.add_theme_constant_override("margin_left", 16)
	rm.add_theme_constant_override("margin_right", 16)
	rm.add_theme_constant_override("margin_top", 14)
	rm.add_theme_constant_override("margin_bottom", 14)
	right_panel.add_child(rm)

	var rvb := VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 12)
	rm.add_child(rvb)

	var r_hdr := Label.new()
	r_hdr.text = "⚔️ CHUẨN BỊ XUẤT KÍCH"
	r_hdr.add_theme_font_size_override("font_size", 14)
	r_hdr.add_theme_color_override("font_color", Color(0.55, 0.96, 0.72))
	rvb.add_child(r_hdr)

	var info_lbl := Label.new()
	info_lbl.text = "%s\n%s\n\n%s" % [sub_txt, req_txt, _format_status_text()]
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_lbl.add_theme_font_size_override("font_size", 13)
	info_lbl.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	info_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rvb.add_child(info_lbl)

	var enter_btn := Button.new()
	enter_btn.text = enter_txt
	enter_btn.custom_minimum_size = Vector2(0, 52)
	enter_btn.disabled = not is_avail
	enter_btn.modulate = Color(1.0, 0.85, 0.35) if is_avail else Color(0.65, 0.70, 0.78)
	enter_btn.pressed.connect(func():
		mode_selected.emit(m_id)
		_close()
	)
	rvb.add_child(enter_btn)

func _close() -> void:
	closed.emit()
	queue_free()
