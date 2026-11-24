extends Node3D
## Interactive Milestone 3 & 4 Showcase Scene (press F6 in Godot Editor to inspect).
## Supports:
## - Mouse Wheel: Seamless continuous zoom from 2D Flat Map -> 3D Planet Globe
## - Left-Drag: Pan 2D infinitely across +/-180 deg OR Orbit 360 deg in 3D Globe mode
## - WASD / Arrows: Smooth directional navigation
## - Click: Analytic raycast picking showing Lat/Lon & nearest Fantasy Region
## - Quick-jump Continent buttons + 2D/3D Toggle + Live LOD readout

const WorldMap3DScene := preload("res://world_map/scenes/world_map_3d.tscn")

var _world_3d: Node3D
var _status_lbl: Label
var _pick_lbl: Label
var _dragging := false
var _drag_moved := false
var _drag_start := Vector2.ZERO
var _last_mouse := Vector2.ZERO

func _ready() -> void:
	_world_3d = WorldMap3DScene.instantiate()
	_world_3d.name = "WorldMap3D"
	add_child(_world_3d)
	_build_hud()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.offset_left = 14.0
	panel.offset_top = 14.0
	panel.offset_right = 410.0
	panel.offset_bottom = 176.0
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)

	_status_lbl = Label.new()
	_status_lbl.text = "Milestone 3 & 4 — Zoom: 0.78 | Morph: 0.00 | LOD: Địa phương"
	vb.add_child(_status_lbl)

	_pick_lbl = Label.new()
	_pick_lbl.text = "Cuộn chuột: Zoom 2D ↔ 3D | Kéo chuột: Pan / Xoay 360° | Click: Chọn vùng"
	vb.add_child(_pick_lbl)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vb.add_child(btn_row)

	var toggle_btn := Button.new()
	toggle_btn.text = "🌐 2D ↔ 3D"
	toggle_btn.pressed.connect(func(): _world_3d.camera_controller.toggle_3d_planet_view())
	btn_row.add_child(toggle_btn)

	for item in [
		["Lục Bảo", 19.0, -11.0, 0.76],
		["Kỳ Quan", 6.0, 32.0, 0.65],
		["Pha Lê", -14.0, 62.0, 0.55],
		["Băng Phong", 58.0, 102.0, 0.55],
		["Nguyền Rủa", -28.0, -80.0, 0.55],
	]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(func():
			_world_3d.camera_controller.fly_to_lat_lon(item[1], item[2], item[3])
		)
		btn_row.add_child(b)

func _unhandled_input(event: InputEvent) -> void:
	if _world_3d == null or _world_3d.camera_controller == null:
		return
	var ctrl = _world_3d.camera_controller
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			ctrl.zoom_by_step(0.08)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			ctrl.zoom_by_step(-0.08)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if mb.pressed:
				_dragging = true
				_drag_moved = false
				_drag_start = mb.position
				_last_mouse = mb.position
			else:
				var was_click := (mb.button_index == MOUSE_BUTTON_LEFT and not _drag_moved)
				_dragging = false
				_drag_moved = false
				if was_click:
					var hit: Dictionary = ctrl.pick_lat_lon_at_screen(mb.position)
					if bool(hit.get("hit", false)):
						var lat := float(hit["lat"])
						var lon := float(hit["lon"])
						var reg: Dictionary = _world_3d.planet_data.find_nearest_region(lat, lon)
						_pick_lbl.text = "📍 Pick: LAT %.1f°, LON %.1f° — Gần nhất: %s" % [lat, lon, str(reg.get("name", "Đại dương"))]
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if not _drag_moved and mm.position.distance_to(_drag_start) >= 6.0:
			_drag_moved = true
		if _drag_moved:
			ctrl.apply_screen_drag(mm.position - _last_mouse, get_viewport().get_visible_rect().size)
		_last_mouse = mm.position

func _process(delta: float) -> void:
	if _world_3d == null or _world_3d.camera_controller == null:
		return
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1.0
	if move != Vector2.ZERO:
		_world_3d.camera_controller.apply_directional_move(move.normalized(), delta)

	var ctrl = _world_3d.camera_controller
	var lod = _world_3d.lod_controller
	if _status_lbl != null:
		_status_lbl.text = "Zoom: %.2f | Morph: %.2f | LOD %d (%s) | LAT %.1f° LON %.1f°" % [
			ctrl.zoom_level, ctrl.morph_factor, lod.current_tier, lod.get_tier_label(), ctrl.focus_lat, ctrl.focus_lon
		]
