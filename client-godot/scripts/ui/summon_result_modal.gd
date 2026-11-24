class_name SummonResultModal
extends Control

## Gacha Summon Result Modal (P2-06)
## Displays x1 / x10 summon results with UniversalHeroCard / UniversalItemCard (capped at 5★ Gold),
## sequential reveal animation, Skip button, and Summon Again button.

signal summon_again_requested(roll_count: int, banner_id: String, banner_type: String)
signal closed

const MAX_GACHA_STAR := 5
const UniversalHeroCardScript := preload("res://scripts/ui/universal_hero_card.gd")
const UniversalItemCardScript := preload("res://scripts/ui/universal_item_card.gd")

var _roll_count: int = 1
var _results: Array = []
var _highest_rarity: int = 1
var _banner_id: String = ""
var _banner_type: String = "NORMAL"

var _card_wrappers: Array[Control] = []
var _reveal_index: int = 0
var _reveal_timer: Timer
var _skip_btn: Button
var _again_btn: Button
var _close_btn: Button
var _revealed_all: bool = false

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(roll_count: int, results: Array, highest_rarity: int, banner_id: String = "", banner_type: String = "NORMAL") -> void:
	_roll_count = roll_count
	_results = results
	_highest_rarity = clampi(highest_rarity, 1, MAX_GACHA_STAR)
	_banner_id = banner_id
	_banner_type = banner_type

func _ready() -> void:
	_build_ui()
	_start_sequential_reveal()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()
	_card_wrappers.clear()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.03, 0.04, 0.08, 0.85)
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vp := get_viewport_rect().size
	var is_single := (_results.size() <= 1)
	var pw := clampf(vp.x * 0.82, 460.0, 960.0) if not is_single else 480.0
	var ph := clampf(vp.y * 0.80, 420.0, 580.0) if not is_single else 500.0

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(pw, ph)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.10, 0.16, 0.98)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(1.0, 0.84, 0.25, 0.95) if _highest_rarity >= 5 else (Color(0.75, 0.42, 1.0, 0.92) if _highest_rarity == 4 else Color(0.32, 0.78, 1.0, 0.88))
	ps.corner_radius_top_left = 14; ps.corner_radius_top_right = 14
	ps.corner_radius_bottom_left = 14; ps.corner_radius_bottom_right = 14
	panel.add_theme_stylebox_override("panel", ps)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20); margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16); margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var hdr := Label.new()
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_font_size_override("font_size", 20)
	hdr.add_theme_color_override("font_color", Color(1.0, 0.90, 0.42) if _highest_rarity >= 4 else Color(0.55, 0.90, 1.0))
	hdr.text = "🌟 KẾT QUẢ TRIỆU HỒI ×%d (TỐI ĐA 5★ VÀNG)" % _roll_count
	root.add_child(hdr)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)

	var grid := GridContainer.new()
	grid.columns = 1 if is_single else 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	grid_center.add_child(grid)

	for r in _results:
		if not (r is Dictionary):
			continue
		var rar := clampi(int(r.get("rarity", 1)), 1, MAX_GACHA_STAR)
		var rtype := str(r.get("rewardType", r.get("itemType", "MATERIAL"))).to_upper()
		var rname := str(r.get("rewardName", "Phần Thưởng"))

		var slot_box := VBoxContainer.new()
		slot_box.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_box.add_theme_constant_override("separation", 4)
		slot_box.modulate.a = 0.0
		slot_box.scale = Vector2(0.82, 0.82)
		grid.add_child(slot_box)

		if rtype == "HERO":
			var hcard: Control = UniversalHeroCardScript.new()
			slot_box.add_child(hcard)
			hcard.setup({
				"id": str(r.get("heroInstanceId", r.get("rewardId", ""))),
				"name": rname,
				"rarity": rar,
				"level": 1,
				"maxLevel": 20,
				"classCode": str(r.get("classCode", "WARRIOR")),
			}, 0, false)
			if bool(r.get("isDuplicate", false)):
				hcard.add_badge("🔄 +1 Mảnh", Color(0.85, 0.45, 0.15, 0.95))
			else:
				hcard.add_badge("✨ MỚI", Color(0.18, 0.65, 0.35, 0.95))
		else:
			var icard: Control = UniversalItemCardScript.new()
			slot_box.add_child(icard)
			icard.setup({
				"id": str(r.get("rewardId", "")),
				"itemId": str(r.get("rewardId", "")),
				"name": rname,
				"starLevel": rar,
				"rarity": rar,
				"slot": "MATERIAL",
				"quantity": int(r.get("quantity", 1)),
				"source": "Triệu Hồi",
			}, 0, false)

		var name_lbl := Label.new()
		name_lbl.text = "%s (%d★)" % [rname, rar]
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.custom_minimum_size = Vector2(110, 0)
		name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		slot_box.add_child(name_lbl)

		_card_wrappers.append(slot_box)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	root.add_child(btn_row)

	_skip_btn = Button.new()
	_skip_btn.text = "⏭️ Bỏ qua"
	_skip_btn.custom_minimum_size = Vector2(120, 38)
	_skip_btn.pressed.connect(skip_reveal)
	btn_row.add_child(_skip_btn)

	_again_btn = Button.new()
	_again_btn.text = "🎲 Triệu hồi tiếp (×%d)" % _roll_count
	_again_btn.custom_minimum_size = Vector2(180, 38)
	_again_btn.visible = false
	_again_btn.pressed.connect(func():
		var rc := _roll_count
		var bid := _banner_id
		var btype := _banner_type
		_close()
		summon_again_requested.emit(rc, bid, btype)
	)
	btn_row.add_child(_again_btn)

	_close_btn = Button.new()
	_close_btn.text = "✅ Xác nhận"
	_close_btn.custom_minimum_size = Vector2(140, 38)
	_close_btn.visible = false
	_close_btn.pressed.connect(_close)
	btn_row.add_child(_close_btn)

func _start_sequential_reveal() -> void:
	if _card_wrappers.is_empty():
		skip_reveal()
		return
	_reveal_index = 0
	_reveal_timer = Timer.new()
	_reveal_timer.wait_time = 0.12
	_reveal_timer.one_shot = false
	_reveal_timer.timeout.connect(_reveal_next_card)
	add_child(_reveal_timer)
	_reveal_timer.start()
	_reveal_next_card()

func _reveal_next_card() -> void:
	if _reveal_index >= _card_wrappers.size():
		_finish_reveal()
		return
	var card := _card_wrappers[_reveal_index]
	_reveal_index += 1
	if is_instance_valid(card):
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(card, "modulate:a", 1.0, 0.16)
		tw.tween_property(card, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _reveal_index >= _card_wrappers.size():
		_finish_reveal()

func skip_reveal() -> void:
	if _reveal_timer != null and is_instance_valid(_reveal_timer):
		_reveal_timer.stop()
	for card in _card_wrappers:
		if is_instance_valid(card):
			card.modulate.a = 1.0
			card.scale = Vector2.ONE
	_reveal_index = _card_wrappers.size()
	_finish_reveal()

func _finish_reveal() -> void:
	_revealed_all = true
	if _reveal_timer != null and is_instance_valid(_reveal_timer):
		_reveal_timer.stop()
	if _skip_btn != null:
		_skip_btn.visible = false
	if _again_btn != null:
		_again_btn.visible = not _banner_id.is_empty()
	if _close_btn != null:
		_close_btn.visible = true

func _close() -> void:
	closed.emit()
	queue_free()
