class_name HeroQuickInteractPopup
extends Control

## Quick Interaction Popup when tapping a 3D Hero in the Castle (P2-09)

signal feed_requested(hero_id: String, hero_name: String)
signal gift_fav_requested(hero_id: String, hero_name: String, fav_food: String)
signal rest_requested(hero_id: String, hero_name: String, is_resting: bool)
signal details_requested(hero_id: String)
signal closed

var _hero_data: Dictionary = {}
var _screen_pos: Vector2 = Vector2.ZERO
var _panel: PanelContainer

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func setup(hero_data: Dictionary, screen_pos: Vector2 = Vector2.ZERO) -> void:
	_hero_data = hero_data
	_screen_pos = screen_pos

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.20)
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close()
	)
	add_child(backdrop)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(286, 260)
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.09, 0.16, 0.96)
	ps.border_width_left = 2; ps.border_width_top = 2; ps.border_width_right = 2; ps.border_width_bottom = 2
	ps.border_color = Color(0.45, 0.82, 1.0, 0.92)
	ps.corner_radius_top_left = 10; ps.corner_radius_top_right = 10
	ps.corner_radius_bottom_left = 10; ps.corner_radius_bottom_right = 10
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	var vp := get_viewport_rect().size
	if vp.x <= 0:
		vp = Vector2(1280, 720)
	var target_pos := _screen_pos + Vector2(18, -110)
	if _screen_pos == Vector2.ZERO:
		target_pos = (vp - _panel.custom_minimum_size) * 0.5
	_panel.position = Vector2(
		clampf(target_pos.x, 12.0, maxf(12.0, vp.x - _panel.custom_minimum_size.x - 12.0)),
		clampf(target_pos.y, 12.0, maxf(12.0, vp.y - _panel.custom_minimum_size.y - 12.0)),
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12); margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10); margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var hid := str(_hero_data.get("id", ""))
	var hname := str(_hero_data.get("name", "Anh Hùng"))
	var stars := clampi(int(_hero_data.get("rarity", 1)), 1, 7)
	var hp := int(_hero_data.get("hp", 100))
	var mhp := maxi(1, int(_hero_data.get("maxHp", 100)))
	var hunger := int(_hero_data.get("hunger", 0))
	var fatigue := int(_hero_data.get("fatigue", 0))
	var mood := str(_hero_data.get("mood", "Bình thường"))
	var loyalty := int(_hero_data.get("loyalty", 50))
	var fav_food := str(_hero_data.get("favoriteFood", "Bánh Mì Nướng"))
	var is_resting := str(_hero_data.get("state", "")).to_upper() == "RESTING"

	var hdr := HBoxContainer.new()
	vbox.add_child(hdr)
	var title := Label.new()
	title.text = "%s %s" % ["★".repeat(stars), hname]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.45))
	hdr.add_child(title)

	var close_x := Button.new()
	close_x.text = "✖"
	close_x.custom_minimum_size = Vector2(26, 24)
	close_x.pressed.connect(_close)
	hdr.add_child(close_x)

	var stats := Label.new()
	stats.text = "❤️ HP: %d/%d  •  🍖 Đói: %d%%  •  💤 Mệt: %d%%\n😊 Tâm trạng: %s  •  🤝 Trung thành: %d" % [
		hp, mhp, hunger, fatigue, mood, loyalty
	]
	stats.add_theme_font_size_override("font_size", 11)
	stats.add_theme_color_override("font_color", Color(0.82, 0.90, 0.98))
	vbox.add_child(stats)

	var feed_btn := Button.new()
	feed_btn.text = "🍖 Cho ăn nhanh"
	feed_btn.pressed.connect(func():
		feed_requested.emit(hid, hname)
		_close()
	)
	vbox.add_child(feed_btn)

	var fav_btn := Button.new()
	fav_btn.text = "🍰 Tặng món yêu thích (%s)" % fav_food
	fav_btn.pressed.connect(func():
		gift_fav_requested.emit(hid, hname, fav_food)
		_close()
	)
	vbox.add_child(fav_btn)

	var rest_btn := Button.new()
	rest_btn.text = "🌅 Kết thúc nghỉ ngơi" if is_resting else "💤 Cho đi nghỉ"
	rest_btn.pressed.connect(func():
		rest_requested.emit(hid, hname, is_resting)
		_close()
	)
	vbox.add_child(rest_btn)

	var detail_btn := Button.new()
	detail_btn.text = "🛡️ Mở Hồ Sơ Chi Tiết"
	detail_btn.pressed.connect(func():
		details_requested.emit(hid)
		_close()
	)
	vbox.add_child(detail_btn)

func _close() -> void:
	closed.emit()
	queue_free()
