extends Control

const Ui := preload("res://scripts/ui/pve_ui.gd")
const MAX_PREVIEW_FLOORS := 100

var _highest_lbl: Label
var _food_lbl: Label
var _stone_lbl: Label
var _status_lbl: Label
var _floors_box: VBoxContainer
var _detail_title: Label
var _detail_badge: Label
var _detail_info: Label
var _detail_objectives: Label
var _enter_btn: Button
var _resume_btn: Button
var _selected_floor: int = 1
var _busy: bool = false

func _ready() -> void:
	_build_ui()
	PveState.snapshot_changed.connect(_render)
	PveState.command_changed.connect(_render_buttons)
	PveState.message_changed.connect(_set_message)
	if not GameState.is_logged_in():
		_render()
		_set_message("Hãy đăng nhập để đồng bộ tiến độ Tháp.", true)
		return
	_set_message("Đang tải trạng thái Tháp Thử Thách...", false)
	await GameState.refresh_heroes()
	await PveState.activate()
	var highest := _highest_floor()
	var active_floor := _active_map_floor()
	_selected_floor = active_floor if active_floor > 0 else highest
	_render()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Ui.INK
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	# Header
	var header_box := Ui.glass_panel(root, Ui.GOLD, 12, 16, 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header_box.add_child(header)

	var title := Ui.label(header, "🗼 THÁP THỬ THÁCH — BÊN NGOÀI THÁP", 22, Ui.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var high_pill := Ui.badge(header, "Tiến độ: Tầng 1", Color("232e47"), Ui.GOLD, Ui.GOLD, 13)
	_highest_lbl = high_pill.get_child(0) as Label
	var food_pill := Ui.badge(header, "🍖 0", Color("1c3330"), Ui.TEAL, Ui.TEAL, 13)
	_food_lbl = food_pill.get_child(0) as Label
	var stone_pill := Ui.badge(header, "💎 Đá: 0", Color("232e47"), Ui.BORDER, Ui.TEXT, 13)
	_stone_lbl = stone_pill.get_child(0) as Label

	Ui.button(header, "← Về căn cứ", _back_to_base, false, "ghost")

	# Body: Left Tower Floor Stack + Right Floor Detail & Enter Panel
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# Left: Tower Exterior Stack (1..100+)
	var left_col := Ui.glass_panel(body, Ui.BORDER, 12, 14, 14)
	left_col.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ui.label(left_col, "KIẾN TRÚC TẦNG THÁP (1–100 TẦNG · TẦNG 5, 10, 15... LÀ TẦNG ĐẶC BIỆT)", 13, Ui.GOLD)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(scroll)
	_floors_box = VBoxContainer.new()
	_floors_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_floors_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_floors_box)

	# Right: Selected Floor Inspector & Entry
	var right_col := Ui.glass_panel(body, Ui.GOLD, 12, 16, 16)
	right_col.get_parent().custom_minimum_size.x = 420
	right_col.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL

	_detail_title = Ui.label(right_col, "🗼 TẦNG 1", 22, Ui.GOLD)
	var badge_pill := Ui.badge(right_col, "ĐANG MỞ", Color("1c3330"), Ui.TEAL, Ui.TEAL, 12)
	_detail_badge = badge_pill.get_child(0) as Label

	var info_card := Ui.card(right_col, Ui.CARD, Ui.BORDER)
	Ui.label(info_card, "📋 THÔNG TIN TẦNG", 13, Ui.GOLD)
	_detail_info = Ui.label(info_card, "", 13, Ui.TEXT)
	_detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var obj_card := Ui.card(right_col, Ui.CARD, Ui.BORDER)
	obj_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Ui.label(obj_card, "⭐ MỤC TIÊU VƯỢT TẦNG (TỐI ĐA 5 SAO)", 13, Ui.GOLD)
	_detail_objectives = Ui.label(obj_card, "", 13, Ui.TEXT)
	_detail_objectives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_status_lbl = Ui.label(right_col, "", 13, Ui.MUTED)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_resume_btn = Ui.button(right_col, "▶ Tiếp tục tầng đang dở", _resume_active_floor, true, "accent")
	_resume_btn.custom_minimum_size.y = 44
	_resume_btn.visible = false

	_enter_btn = Ui.button(right_col, "⚔️ TIẾN VÀO TẦNG 1", _enter_selected_floor, true, "gold")
	_enter_btn.custom_minimum_size.y = 50

func _highest_floor() -> int:
	return maxi(1, int(PveState.snapshot.get("currentFloor", GameState.current_floor)))

func _active_map_floor() -> int:
	var map_value: Variant = PveState.snapshot.get("map")
	if map_value is Dictionary and str(map_value.get("status", "")) == "ACTIVE":
		return int(map_value.get("floor", 0))
	return 0

func _is_special_floor(floor_num: int) -> bool:
	return floor_num > 0 and floor_num % 5 == 0

func _render() -> void:
	if _floors_box == null:
		return
	var highest := _highest_floor()
	var active_floor := _active_map_floor()
	var top_display := maxi(MAX_PREVIEW_FLOORS, highest + 3)
	_selected_floor = clampi(_selected_floor, 1, top_display)

	_highest_lbl.text = "Tiến độ: Tầng %d" % highest
	_food_lbl.text = "🍖 %d" % int(PveState.snapshot.get("food", 0))
	_stone_lbl.text = "💎 Đá: %d" % int(PveState.snapshot.get("teleportStones", 0))

	Ui.clear(_floors_box)
	# Render from top floor down to Floor 1 (like an exterior tower)
	for f in range(top_display, 0, -1):
		var floor_num: int = f
		var is_cleared := floor_num < highest
		var is_current := floor_num == highest
		var is_locked := floor_num > highest
		var is_active := floor_num == active_floor
		var is_selected := floor_num == _selected_floor
		var is_special := _is_special_floor(floor_num)

		var status_tag := "🔒 CHƯA MỞ"
		if is_active:
			status_tag = "⚔️ ĐANG KHÁM PHÁ"
		elif is_cleared:
			status_tag = "✓ ĐÃ VƯỢT (Có thể vào lại)"
		elif is_current:
			status_tag = "🔥 TẦNG HIỆN TẠI"

		var prefix := "⚡ [ĐẶC BIỆT] Tầng %d" % floor_num if is_special else "🗼 Tầng %d" % floor_num
		var tone := "gold" if is_selected else ("danger" if is_special else ("accent" if is_cleared or is_active else "ghost"))
		var btn_text := "%s   —   %s" % [prefix, status_tag]
		var btn := Ui.button(_floors_box, btn_text, func():
			_selected_floor = floor_num
			_render()
		, is_selected, tone)
		btn.custom_minimum_size.y = 50 if is_special else 42
		if is_special and not is_selected:
			btn.add_theme_stylebox_override("normal", Ui.style(Color("3c1d28") if is_locked else Color("4a2530"), Ui.GOLD, 8, 12, 6))
		if is_locked:
			btn.modulate = Color(0.88, 0.78, 0.82, 0.82) if is_special else Color(0.68, 0.74, 0.84, 0.75)

	_render_detail(highest, active_floor)
	_render_buttons()

func _render_detail(highest: int, active_floor: int) -> void:
	var is_cleared := _selected_floor < highest
	var is_locked := _selected_floor > highest
	var is_active := _selected_floor == active_floor
	var is_special := _is_special_floor(_selected_floor)
	var scale_pct := 100 + (_selected_floor - 1) * 8
	var allow_retreat := "Không (Khóa rút lui tới khi hạ Boss)" if is_special else "Có (Tự do thu hồi & dùng Đá dịch chuyển)"

	_detail_title.text = ("⚡ TẦNG ĐẶC BIỆT %d" if is_special else "🗼 TẦNG %d") % _selected_floor
	if is_active:
		_detail_badge.text = "⚔️ ĐANG CÓ ĐỘI TRÊN TẦNG"
	elif is_cleared:
		_detail_badge.text = "✓ ĐÃ VƯỢT • CHƠI LẠI TỰ DO"
	elif is_locked:
		_detail_badge.text = "🔒 CHƯA MỞ KHÓA"
	else:
		_detail_badge.text = "🔥 TẦNG HIỆN TẠI"

	_detail_info.text = (
		"• Loại tầng: %s\n" % ("Tầng Đặc Biệt (Mốc 5 tầng)" if is_special else "Tầng Thường")
		+ "• Cho phép rút lui: %s\n" % allow_retreat
		+ "• Độ khó quái: %d%% sức mạnh cơ bản\n" % scale_pct
		+ "• Chi phí tham gia: Miễn phí vào cửa · 10 Lương thực / Hero khi triển khai đội"
	)

	_detail_objectives.text = (
		"⭐ +1 Sao: Hạ Boss chỉ định của tầng\n"
		+ "⭐ +1 Sao: Toàn đội còn sống khi vượt tầng\n"
		+ "⭐ +1 Sao: Không rút lui / không dùng Đá dịch chuyển\n"
		+ "⭐ +1 Sao: Khám phá tối thiểu 60% bản đồ tầng\n"
		+ "⭐ +1 Sao: Hoàn thành nhanh trong số lượt chuẩn"
	)

	if is_locked:
		_status_lbl.text = "Vượt Boss Tầng %d để mở khóa tầng này." % (_selected_floor - 1)
	elif active_floor > 0 and active_floor != _selected_floor:
		_status_lbl.text = "⚠️ Hiện đang có lượt khám phá dở ở Tầng %d. Hoàn thành hoặc thu hồi toàn bộ để chuyển sang tầng khác." % active_floor
	else:
		_status_lbl.text = "Sẵn sàng tiến vào Tầng %d." % _selected_floor

func _render_buttons() -> void:
	if _enter_btn == null:
		return
	var highest := _highest_floor()
	var active_floor := _active_map_floor()
	var is_locked := _selected_floor > highest
	var blocked_by_other := active_floor > 0 and active_floor != _selected_floor

	_resume_btn.visible = blocked_by_other
	_resume_btn.text = "▶ Tiếp tục Tầng %d đang dở" % active_floor
	_resume_btn.disabled = _busy

	if active_floor == _selected_floor:
		_enter_btn.text = "▶ TIẾP TỤC TẦNG %d" % _selected_floor
	elif _selected_floor < highest:
		_enter_btn.text = "⚔️ VÀO LẠI TẦNG %d" % _selected_floor
	else:
		_enter_btn.text = "⚔️ TIẾN VÀO TẦNG %d" % _selected_floor

	_enter_btn.disabled = _busy or is_locked or blocked_by_other

func _enter_selected_floor() -> void:
	if _busy:
		return
	var active_floor := _active_map_floor()
	if active_floor == _selected_floor:
		_go_to_map()
		return
	_busy = true
	_render_buttons()
	var result: Dictionary = await PveState.send_command("/api/pve/enter", {"floor": _selected_floor})
	if not is_inside_tree():
		return
	_busy = false
	if result.get("ok", false):
		_go_to_map()
	else:
		_set_message(PveState.error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), true)
		_render_buttons()

func _resume_active_floor() -> void:
	_go_to_map()

func _go_to_map() -> void:
	PveState.polling_enabled = false
	get_tree().change_scene_to_file("res://scenes/pve/pve_map.tscn")

func _back_to_base() -> void:
	PveState.polling_enabled = false
	get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")

func _set_message(message: String, is_error: bool) -> void:
	if _status_lbl != null:
		_status_lbl.text = message
		_status_lbl.modulate = Ui.DANGER if is_error else Ui.MUTED
