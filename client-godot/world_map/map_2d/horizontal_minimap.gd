class_name HorizontalMinimap
extends Control
## Independent 2:1 Horizontal Equirectangular World Minimap (Solar-Scale & Fog-Synchronized).
## Never rotates with the 3D globe; displays the full Fantasy Planet texture,
## subtle unexplored mist overlay, Solar-Scale Bastion marker, pulsing Player Position Dot,
## discovered Dungeons, active Fleets, Imperial Wonder, and live Camera viewport indicator.

signal navigate_lat_lon_requested(lat_deg: float, lon_deg: float)

const PlanetCoordinatesScript := preload("res://world_map/core/planet_coordinates.gd")

var _albedo_tex: Texture2D
var _fog_tex: Texture2D
var _sector_bounds: Dictionary = PlanetCoordinatesScript.DEFAULT_SECTOR_BOUNDS.duplicate()
var _base_lat_lon := Vector2(19.0, -11.0)
var _focus_lat_lon := Vector2(19.0, -11.0)
var _zoom_level := 0.85
var _morph_factor := 0.0
var _dungeons_ll: Array = []
var _fleets_ll: Array = []
var _pulse_time := 0.0
var _dragging := false

func _ready() -> void:
	custom_minimum_size = Vector2(228.0, 114.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func configure(albedo_tex: Texture2D, sector_bounds: Dictionary, fog_tex: Texture2D = null) -> void:
	_albedo_tex = albedo_tex
	_sector_bounds = sector_bounds
	_fog_tex = fog_tex
	queue_redraw()

func set_fog_texture(fog_tex: Texture2D) -> void:
	_fog_tex = fog_tex
	queue_redraw()

func sync_state(
	base_ll: Vector2,
	focus_ll: Vector2,
	zoom_level: float,
	morph_factor: float,
	dungeons_ll: Array,
	fleets_ll: Array,
	pulse_time: float
) -> void:
	_base_lat_lon = base_ll
	_focus_lat_lon = focus_ll
	_zoom_level = zoom_level
	_morph_factor = morph_factor
	_dungeons_ll = dungeons_ll
	_fleets_ll = fleets_ll
	_pulse_time = pulse_time
	queue_redraw()

func _ll_to_mini(lat_deg: float, lon_deg: float) -> Vector2:
	var uv: Vector2 = PlanetCoordinatesScript.lat_lon_to_uv(lat_deg, lon_deg)
	return Vector2(uv.x * size.x, uv.y * size.y)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_emit_nav_for_pos(mb.position)
	elif event is InputEventMouseMotion and _dragging:
		_emit_nav_for_pos((event as InputEventMouseMotion).position)

func _emit_nav_for_pos(local_pos: Vector2) -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var uv := Vector2(clampf(local_pos.x / size.x, 0.0, 1.0), clampf(local_pos.y / size.y, 0.0, 1.0))
	var ll: Vector2 = PlanetCoordinatesScript.uv_to_lat_lon(uv)
	navigate_lat_lon_requested.emit(ll.x, ll.y)

func _draw() -> void:
	var full_rect := Rect2(Vector2.ZERO, size)
	if _albedo_tex != null:
		draw_texture_rect(_albedo_tex, full_rect, false)
	else:
		draw_rect(full_rect, Color(0.05, 0.12, 0.24, 1.0), true)

	# Subtle unexplored mist tint across world (keeps continents recognizable while highlighting explored bastion)
	draw_rect(full_rect, Color(0.03, 0.05, 0.12, 0.28), true)

	# Subtle latitude/longitude cartographic grid lines
	for i in range(1, 4):
		var y := size.y * float(i) / 4.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(0.75, 0.88, 1.0, 0.10), 1.0)
	for j in range(1, 6):
		var x := size.x * float(j) / 6.0
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(0.75, 0.88, 1.0, 0.10), 1.0)

	# Highlight active Bastion / Expedition Sector around Player Base (or legacy 12x12 sector)
	if int(_sector_bounds.get("world_grid_width", 0)) > 0:
		var base_c := _ll_to_mini(_base_lat_lon.x, _base_lat_lon.y)
		var sec_rect := Rect2(base_c - Vector2(5.0, 5.0), Vector2(10.0, 10.0))
		draw_rect(sec_rect, Color(0.35, 0.92, 0.68, 0.20), true)
		draw_rect(sec_rect, Color(0.95, 0.82, 0.36, 0.78), false, 1.1)
	else:
		var tl := _ll_to_mini(float(_sector_bounds.get("lat_max", 19.33)), float(_sector_bounds.get("lon_min", -11.33)))
		var br := _ll_to_mini(float(_sector_bounds.get("lat_min", 18.67)), float(_sector_bounds.get("lon_max", -10.67)))
		var sec_center := (tl + br) * 0.5
		var sec_sz := Vector2(maxf(8.0, absf(br.x - tl.x)), maxf(8.0, absf(br.y - tl.y)))
		var sec_rect := Rect2(sec_center - sec_sz * 0.5, sec_sz)
		draw_rect(sec_rect, Color(0.35, 0.92, 0.68, 0.22), true)
		draw_rect(sec_rect, Color(0.95, 0.82, 0.36, 0.80), false, 1.1)

	# Imperial Wonder landmark diamond
	var w_pt := _ll_to_mini(float(_sector_bounds.get("wonder_lat", 6.0)), float(_sector_bounds.get("wonder_lon", 32.0)))
	draw_circle(w_pt, 2.8, Color(1.0, 0.84, 0.24, 0.95))

	# Discovered Dungeons
	for d_ll in _dungeons_ll:
		if d_ll is Vector2:
			draw_circle(_ll_to_mini(d_ll.x, d_ll.y), 1.8, Color(1.0, 0.52, 0.20, 0.92))

	# Active Fleets
	for f_item in _fleets_ll:
		if f_item is Dictionary:
			var f_pt := _ll_to_mini(float(f_item.get("lat", 0.0)), float(f_item.get("lon", 0.0)))
			var f_col: Color = f_item.get("color", Color(1.0, 0.94, 0.42))
			draw_circle(f_pt, 2.2, f_col)

	# Pulsing Player Position Dot
	var pulse := 0.5 + 0.5 * sin(_pulse_time)
	var base_pt := _ll_to_mini(_base_lat_lon.x, _base_lat_lon.y)
	draw_circle(base_pt, 4.0 + pulse * 2.4, Color(0.28, 0.92, 1.0, 0.32))
	draw_circle(base_pt, 2.6, Color(0.32, 0.94, 1.0, 1.0))
	draw_circle(base_pt, 1.2, Color(1.0, 1.0, 1.0, 1.0))

	# Live Camera Focus / Viewport Indicator (scaled logarithmically to reflect Solar-Scale zoom!)
	var cam_pt := _ll_to_mini(_focus_lat_lon.x, _focus_lat_lon.y)
	if _morph_factor >= 0.55:
		draw_arc(cam_pt, 12.0, 0.0, TAU, 24, Color(1.0, 1.0, 1.0, 0.85), 1.4)
		draw_circle(cam_pt, 1.8, Color(1.0, 1.0, 1.0, 0.95))
	else:
		var z_norm := clampf((_zoom_level - 0.24) / 0.76, 0.0, 1.0)
		var span_ratio := exp(lerpf(log(0.58), log(0.035), z_norm))
		var bw := clampf(size.x * span_ratio, 8.0, size.x * 0.85)
		var bh := clampf(size.y * span_ratio * 1.15, 6.0, size.y * 0.85)
		draw_rect(Rect2(cam_pt - Vector2(bw * 0.5, bh * 0.5), Vector2(bw, bh)), Color(1.0, 1.0, 1.0, 0.84), false, 1.2)
		draw_circle(cam_pt, 1.6, Color(1.0, 1.0, 1.0, 0.95))

	# Crisp outer frame
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2(1.0, 1.0)), Color(0.84, 0.68, 0.32, 0.58), false, 1.0)
