class_name SummonBannerModal
extends Control

## Summon Banner Modal
## Two-step summon flow:
##   1. Horizontal scrollable list of available banners (Normal vs Special).
##   2. Detailed view of the selected banner with pure flat rates (no pity),
##      currency requirements (Normal Scrolls vs 100 Gems/roll), and x1 / x10 summon buttons.

signal summon_requested(banner_id: String, banner_type: String, roll_count: int)
signal exchange_scrolls_requested(amount: int)
signal closed

var _banners: Array = []
var _selected_banner: Dictionary = {}

var _root_vbox: VBoxContainer
var _resource_lbl: Label
var _content_slot: Control

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(banners: Array) -> void:
	_banners = banners.duplicate(true)
	_selected_banner = {}
	_build_shell()
	_render_banner_list()

func refresh_resources() -> void:
	if _resource_lbl != null and is_instance_valid(_resource_lbl):
		_resource_lbl.text = _format_resources_text()
	if not _selected_banner.is_empty():
		_render_banner_detail(_selected_banner)
	else:
		_render_banner_list()

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

func _format_resources_text() -> String:
	return "📜 Thiên Thư: %s   |   💎 Đá Quý: %s   |   🪙 Bạc: %s" % [
		_format_num(GameState.normal_scrolls),
		_format_num(GameState.gem_stones),
		_format_num(GameState.silver_coins),
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

	# Top resource bar + Close
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	_root_vbox.add_child(top_bar)

	var title_lbl := Label.new()
	title_lbl.text = "✨ ĐẠI TRIỆU HỒI ANH HÙNG"
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title_lbl)

	_resource_lbl = Label.new()
	_resource_lbl.text = _format_resources_text()
	_resource_lbl.add_theme_font_size_override("font_size", 13)
	_resource_lbl.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	top_bar.add_child(_resource_lbl)

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

func _render_banner_list() -> void:
	_selected_banner = {}
	_clear_content()

	var subtitle := Label.new()
	subtitle.text = "Chọn một Banner bên dưới (cuộn ngang nếu có nhiều Banner) để xem tỉ lệ thuần và tiến hành Triệu Hồi:"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.76, 0.85, 0.96))
	_content_slot.add_child(subtitle)

	if _banners.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Hiện chưa có Banner triệu hồi nào đang mở."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_content_slot.add_child(empty_lbl)
		return

	var h_scroll := ScrollContainer.new()
	h_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	h_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	h_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_slot.add_child(h_scroll)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h_scroll.add_child(hbox)

	for b in _banners:
		if not (b is Dictionary):
			continue
		hbox.add_child(_create_banner_card(b))

func _create_banner_card(b: Dictionary) -> Control:
	var btype := str(b.get("bannerType", "NORMAL")).to_upper()
	var is_special := (btype == "SPECIAL" or btype == "LIMITED")
	var bname := str(b.get("name", "Banner Triệu Hồi"))
	var cost_type := str(b.get("costType", "GEMS" if is_special else "SCROLL"))
	var cost_per := int(b.get("costPerRoll", 100 if is_special else 1))
	var min_star := int(b.get("minHeroRarity", 2 if is_special else 1))
	var max_star := int(b.get("maxHeroRarity", 5 if is_special else 3))

	var accent := Color(0.98, 0.72, 0.25) if is_special else Color(0.35, 0.78, 1.0)
	var bg := Color(0.14, 0.09, 0.20, 0.96) if is_special else Color(0.08, 0.13, 0.22, 0.96)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(410, 390)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = accent
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Mở banner " + bname
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
					_render_banner_detail.call_deferred(b)
					card.accept_event()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			_render_banner_detail.call_deferred(b)
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
	badge.text = "🌟 BANNER ĐẶC BIỆT • TỈ LỆ THUẦN" if is_special else "📜 BANNER THƯỜNG • TỈ LỆ THUẦN"
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", accent)
	vb.add_child(badge)

	var title := Label.new()
	title.text = bname
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85))
	vb.add_child(title)

	var range_lbl := Label.new()
	range_lbl.text = "⚔️ Giới hạn Hero: %d★ – %d★  +  📦 Vật liệu" % [min_star, max_star]
	range_lbl.add_theme_font_size_override("font_size", 13)
	range_lbl.add_theme_color_override("font_color", Color(0.55, 0.96, 0.72))
	vb.add_child(range_lbl)

	var cost_lbl := Label.new()
	cost_lbl.text = (
		"💎 Chi phí: %d Đá Quý / 1 lần  (%s Gem / 10 lần)" % [cost_per, _format_num(cost_per * 10)]
		if cost_type == "GEMS"
		else "📜 Chi phí: %d Thiên Thư Thường / 1 lần  (10 Cuộn / 10 lần)" % cost_per
	)
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	vb.add_child(cost_lbl)

	vb.add_child(HSeparator.new())

	var rates: Dictionary = b.get("rates", {})
	var rate_lines: PackedStringArray = []
	var rate_keys := ["", "oneStarHeroPercent", "twoStarHeroPercent", "threeStarHeroPercent", "fourStarHeroPercent", "fiveStarHeroPercent", "sixStarHeroPercent", "sevenStarHeroPercent"]
	for star in range(7, 0, -1):
		var rate := float(rates.get(rate_keys[star], 0.0))
		if rate > 0.0: rate_lines.append("Hero %d\u2605: %.2f%%" % [star, rate])
	rate_lines.append("• Vật liệu & Sách EXP: %.2f%%" % float(rates.get("materialPercent", 50.0)))
	rate_lines.append("• Cơ chế: Random tên, nghề & chỉ số gốc (Không Pity)")

	var rate_lbl := Label.new()
	rate_lbl.text = "\n".join(rate_lines)
	rate_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rate_lbl.add_theme_font_size_override("font_size", 12)
	rate_lbl.add_theme_color_override("font_color", Color(0.84, 0.90, 0.98))
	rate_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(rate_lbl)

	_ignore_card_children_mouse(card)
	return card

func _ignore_card_children_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control: child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_card_children_mouse(child)

func _render_banner_detail(b: Dictionary) -> void:
	_selected_banner = b
	_clear_content()

	var bid := str(b.get("id", ""))
	var btype := str(b.get("bannerType", "NORMAL")).to_upper()
	var is_special := (btype == "SPECIAL" or btype == "LIMITED")
	var bname := str(b.get("name", "Banner Triệu Hồi"))
	var cost_type := str(b.get("costType", "GEMS" if is_special else "SCROLL"))
	var cost_per := int(b.get("costPerRoll", 100 if is_special else 1))
	var accent := Color(0.98, 0.72, 0.25) if is_special else Color(0.35, 0.78, 1.0)

	# Sub-header with Back button
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	_content_slot.add_child(nav)

	var back_btn := Button.new()
	back_btn.text = "⬅️ Danh Sách Banner"
	back_btn.custom_minimum_size = Vector2(160, 34)
	back_btn.pressed.connect(_render_banner_list)
	nav.add_child(back_btn)

	var b_title := Label.new()
	b_title.text = bname
	b_title.add_theme_font_size_override("font_size", 18)
	b_title.add_theme_color_override("font_color", accent)
	b_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(b_title)

	# Body detail panel
	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.05, 0.07, 0.12, 0.90)
	dstyle.border_width_left = 1
	dstyle.border_width_top = 1
	dstyle.border_width_right = 1
	dstyle.border_width_bottom = 1
	dstyle.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	dstyle.corner_radius_top_left = 10
	dstyle.corner_radius_top_right = 10
	dstyle.corner_radius_bottom_left = 10
	dstyle.corner_radius_bottom_right = 10
	detail_panel.add_theme_stylebox_override("panel", dstyle)
	_content_slot.add_child(detail_panel)

	var dmargin := MarginContainer.new()
	dmargin.add_theme_constant_override("margin_left", 20)
	dmargin.add_theme_constant_override("margin_right", 20)
	dmargin.add_theme_constant_override("margin_top", 16)
	dmargin.add_theme_constant_override("margin_bottom", 16)
	detail_panel.add_child(dmargin)

	var dvbox := VBoxContainer.new()
	dvbox.add_theme_constant_override("separation", 10)
	dmargin.add_child(dvbox)

	var mech_lbl := Label.new()
	mech_lbl.text = (
		"🎲 CƠ CHẾ PROCEDURAL RANDOM HERO (KHÔNG PITY — TỈ LỆ THUẦN)\n"
		+ "• Hero procedural sinh ngẫu nhiên tên, nghề và 4 chỉ số gốc (STR / INT / STA / AGI) theo ngân sách sao; template cố định giữ tên riêng.\n"
		+ "• 1★–2★: 100% Vô nghề (chuyển chức ở Lv.20)  |  3★: 40% có nghề  |  4★: 70% có nghề  |  5★–7★: 100% có nghề.\n"
		+ "• Mỗi lần nhận Hero tạo một cá thể riêng. Mọi Hero đều có thể tử trận; hồ sơ được giữ tại Sử Điện Anh Hùng."
	)
	mech_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mech_lbl.add_theme_font_size_override("font_size", 13)
	mech_lbl.add_theme_color_override("font_color", Color(0.86, 0.93, 1.0))
	dvbox.add_child(mech_lbl)

	dvbox.add_child(HSeparator.new())

	var rates: Dictionary = b.get("rates", {})
	var rate_header := Label.new()
	rate_header.text = "📊 BẢNG XÁC SUẤT TRIỆU HỒI THUẦN (%):"
	rate_header.add_theme_font_size_override("font_size", 14)
	rate_header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	dvbox.add_child(rate_header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 6)
	dvbox.add_child(grid)

	var rate_keys := ["", "oneStarHeroPercent", "twoStarHeroPercent", "threeStarHeroPercent", "fourStarHeroPercent", "fiveStarHeroPercent", "sixStarHeroPercent", "sevenStarHeroPercent"]
	for star in range(7, 0, -1):
		var rate := float(rates.get(rate_keys[star], 0.0))
		if rate > 0.0:
			_add_rate_row(grid, "Hero %d\u2605:" % star, "%.2f%%" % rate, Color(1.0, 0.85, 0.35))

	_add_rate_row(grid, "📦 Vật Liệu, Ấn & Sách EXP:", "%.2f%%" % float(rates.get("materialPercent", 50.0)), Color(0.95, 0.78, 0.55))

	# Action buttons row
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	_content_slot.add_child(actions)

	if cost_type == "GEMS":
		var btn1 := Button.new()
		btn1.text = "💎 Triệu Hồi ×1 (%d Gem)" % cost_per
		btn1.custom_minimum_size = Vector2(230, 48)
		btn1.modulate = Color(0.55, 0.90, 1.0)
		btn1.disabled = GameState.gem_stones < cost_per
		btn1.pressed.connect(func():
			summon_requested.emit(bid, btype, 1)
			_close()
		)
		actions.add_child(btn1)

		var btn10 := Button.new()
		btn10.text = "🌟 Đại Triệu Hồi ×10 (%s Gem)" % _format_num(cost_per * 10)
		btn10.custom_minimum_size = Vector2(260, 48)
		btn10.modulate = Color(1.0, 0.85, 0.35)
		btn10.disabled = GameState.gem_stones < (cost_per * 10)
		btn10.pressed.connect(func():
			summon_requested.emit(bid, btype, 10)
			_close()
		)
		actions.add_child(btn10)
	else:
		var ex_btn := Button.new()
		ex_btn.text = "🪙 Đổi 10 Thiên Thư (100,000 Bạc)"
		ex_btn.custom_minimum_size = Vector2(230, 48)
		ex_btn.modulate = Color(0.90, 0.75, 0.45)
		ex_btn.disabled = GameState.silver_coins < 100000
		ex_btn.pressed.connect(func():
			exchange_scrolls_requested.emit(10)
		)
		actions.add_child(ex_btn)

		var can_1 := GameState.normal_scrolls >= 1 or GameState.silver_coins >= 10000
		var btn1 := Button.new()
		btn1.text = "📜 Triệu Hồi ×1 (1 Thiên Thư)"
		btn1.custom_minimum_size = Vector2(215, 48)
		btn1.modulate = Color(0.45, 0.88, 1.0)
		btn1.disabled = not can_1
		btn1.pressed.connect(func():
			summon_requested.emit(bid, btype, 1)
			_close()
		)
		actions.add_child(btn1)

		var needed_for_10 := maxi(0, 10 - GameState.normal_scrolls)
		var can_10 := GameState.normal_scrolls >= 10 or GameState.silver_coins >= needed_for_10 * 10000
		var btn10 := Button.new()
		btn10.text = "🌟 Đại Triệu Hồi ×10 (10 Thiên Thư)"
		btn10.custom_minimum_size = Vector2(235, 48)
		btn10.modulate = Color(1.0, 0.85, 0.35)
		btn10.disabled = not can_10
		btn10.pressed.connect(func():
			summon_requested.emit(bid, btype, 10)
			_close()
		)
		actions.add_child(btn10)

func _add_rate_row(grid: GridContainer, label_txt: String, val_txt: String, color: Color) -> void:
	var l := Label.new()
	l.text = label_txt
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)

	var v := Label.new()
	v.text = val_txt
	v.add_theme_font_size_override("font_size", 13)
	v.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	grid.add_child(v)

func _close() -> void:
	closed.emit()
	queue_free()
