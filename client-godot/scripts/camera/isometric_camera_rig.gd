extends Node3D
class_name IsometricCameraRig

## Isometric 3D Camera Rig with Cinematic Multi-Floor Elevator Transition, Dynamic Action Zoom & Screen Shake
## Shared between Multi-Floor Base (Lobby) and PvE (Dungeon Exploration & Combat v2)

@export var default_iso_pitch_deg: float = -35.264
@export var default_iso_yaw_deg: float = 45.0
@export var default_ortho_size: float = 28.0
@export var action_ortho_size: float = 12.0
@export var pan_speed: float = 20.0
@export var pan_limits_min: Vector2 = Vector2(-38.0, -38.0)
@export var pan_limits_max: Vector2 = Vector2(38.0, 38.0)
@export var allow_manual_pan: bool = true
@export var use_castle_world_bounds: bool = false
@export var castle_world_min: Vector2 = Vector2(-115.0, -54.0)
@export var castle_world_max: Vector2 = Vector2(54.0, 54.0)
@export var castle_tier2_x_threshold: float = -50.0
@export var castle_tier2_height: float = 5.2

@onready var rotation_arm: Node3D = $RotationArm
@onready var camera: Camera3D = $RotationArm/Camera3D

var current_floor_y: float = 0.0
var current_terrace_center: Vector3 = Vector3.ZERO
var _overview_position: Vector3 = Vector3.ZERO
var _active_tween: Tween = null
var _shake_tween: Tween = null
var _rmb_panning: bool = false

func _ready() -> void:
	_overview_position = global_position
	current_terrace_center = global_position
	rotation_arm.rotation_degrees = Vector3(default_iso_pitch_deg, default_iso_yaw_deg, 0.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = default_ortho_size

func get_camera_3d() -> Camera3D:
	return camera

func _unhandled_input(event: InputEvent) -> void:
	if not allow_manual_pan:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera.size = clampf(camera.size - 2.2, 8.0, 135.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera.size = clampf(camera.size + 2.2, 8.0, 135.0)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_rmb_panning = mb.pressed
	elif event is InputEventMouseMotion and _rmb_panning:
		var mm := event as InputEventMouseMotion
		var forward := Vector3(-1.0, 0.0, -1.0).normalized()
		var right := Vector3(1.0, 0.0, -1.0).normalized()
		var scale_factor := camera.size * 0.0022
		global_position += (-right * mm.relative.x + forward * mm.relative.y) * scale_factor
		_clamp_and_settle_pan_position(0.25)

func _process(delta: float) -> void:
	if not allow_manual_pan:
		return
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1.0

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		var forward := Vector3(-1.0, 0.0, -1.0).normalized()
		var right := Vector3(1.0, 0.0, -1.0).normalized()
		var speed_mult := clampf(camera.size / 28.0, 0.85, 2.6)
		var move := (right * input_dir.x + (-forward) * input_dir.y) * pan_speed * speed_mult * delta
		global_position += move
		_clamp_and_settle_pan_position(delta * 10.0)

func _clamp_and_settle_pan_position(y_lerp_weight: float = 0.25) -> void:
	if use_castle_world_bounds:
		global_position.x = clampf(global_position.x, castle_world_min.x, castle_world_max.x)
		global_position.z = clampf(global_position.z, castle_world_min.y, castle_world_max.y)
		var target_y := castle_tier2_height if global_position.x < castle_tier2_x_threshold else 0.0
		current_floor_y = target_y
		global_position.y = lerpf(global_position.y, target_y, clampf(y_lerp_weight, 0.15, 1.0))
	else:
		global_position.x = clampf(global_position.x, current_terrace_center.x + pan_limits_min.x, current_terrace_center.x + pan_limits_max.x)
		global_position.z = clampf(global_position.z, current_terrace_center.z + pan_limits_min.y, current_terrace_center.z + pan_limits_max.y)
		global_position.y = current_floor_y
	_overview_position = global_position

## Cinematic Terrace Glide Transition between Lobby Floors (10h <-> 4h Stepped Terrace Model):
## - Smoothly glides diagonally across (X, Y, Z) to the target terrace center with QUINT easing
## - Performs a mid-flight ortho zoom-out & pitch tilt that settles cleanly on arrival
func focus_lobby_floor(terrace_target: Variant, duration: float = 0.55) -> void:
	var target_pos := Vector3.ZERO
	if terrace_target is Vector3:
		target_pos = terrace_target
	else:
		target_pos = Vector3(0.0, float(terrace_target), 0.0)

	var delta_y := target_pos.y - current_floor_y
	var dist_3d := global_position.distance_to(target_pos)
	current_floor_y = target_pos.y
	current_terrace_center = target_pos
	_overview_position = target_pos

	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()

	var dir_sign := signf(delta_y)
	var mid_pitch := default_iso_pitch_deg + (dir_sign * 3.6)
	var mid_zoom := default_ortho_size + clampf(dist_3d * 0.14, 1.5, 4.2)

	_active_tween = create_tween()
	# Position glides smoothly along the 10h <-> 4h terrace diagonal
	_active_tween.parallel().tween_property(self, "global_position", target_pos, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)

	# Zoom & Pitch perform a two-phase terrace swoop (widen + tilt -> lock in)
	var zoom_seq := create_tween()
	zoom_seq.tween_property(camera, "size", mid_zoom, duration * 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	zoom_seq.tween_property(camera, "size", default_ortho_size, duration * 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var pitch_seq := create_tween()
	pitch_seq.tween_property(
		rotation_arm,
		"rotation_degrees",
		Vector3(mid_pitch, default_iso_yaw_deg, 0.0),
		duration * 0.35
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	pitch_seq.tween_property(
		rotation_arm,
		"rotation_degrees",
		Vector3(default_iso_pitch_deg, default_iso_yaw_deg, 0.0),
		duration * 0.65
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Smoothly transitions camera to a wide panoramic overview across all 6 lobby floors
func focus_base_overview(center_pos: Vector3, zoom_size: float = 36.0, duration: float = 0.55) -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	current_floor_y = center_pos.y
	current_terrace_center = center_pos
	_overview_position = center_pos
	_active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "global_position", center_pos, duration)
	_active_tween.tween_property(camera, "size", zoom_size, duration)
	_active_tween.tween_property(
		rotation_arm,
		"rotation_degrees",
		Vector3(default_iso_pitch_deg, default_iso_yaw_deg, 0.0),
		duration
	)

## Smoothly returns camera to the full tactical isometric overview on the current floor
func focus_overview(center_pos: Vector3 = _overview_position, duration: float = 0.45) -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	var target := Vector3(center_pos.x, current_floor_y, center_pos.z)
	_active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "global_position", target, duration)
	_active_tween.tween_property(camera, "size", default_ortho_size, duration)
	_active_tween.tween_property(
		rotation_arm,
		"rotation_degrees",
		Vector3(default_iso_pitch_deg, default_iso_yaw_deg, 0.0),
		duration
	)

## Dynamic Action Camera: zooms in and tilts slightly on a target 3D unit or building (preserving its Y floor height)
func focus_action_unit(unit_world_pos: Vector3, zoom_size: float = action_ortho_size, duration: float = 0.3) -> void:
	if _active_tween and _active_tween.is_valid():
		_active_tween.kill()
	var target_pivot := Vector3(unit_world_pos.x, unit_world_pos.y, unit_world_pos.z)
	_active_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(self, "global_position", target_pivot, duration)
	_active_tween.tween_property(camera, "size", zoom_size, duration)
	_active_tween.tween_property(
		rotation_arm,
		"rotation_degrees",
		Vector3(default_iso_pitch_deg + 6.0, default_iso_yaw_deg, 0.0),
		duration
	)

## Camera impact shake for Critical Hits, Boss Slams, or Phoenix Revive
func shake(intensity: float = 0.28, duration: float = 0.25) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var steps := 6
	var step_time := duration / float(steps)
	for i in range(steps):
		var offset := Vector2(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity)
		)
		_shake_tween.tween_property(camera, "h_offset", offset.x, step_time * 0.5)
		_shake_tween.parallel().tween_property(camera, "v_offset", offset.y, step_time * 0.5)
	_shake_tween.tween_property(camera, "h_offset", 0.0, step_time * 0.5)
	_shake_tween.parallel().tween_property(camera, "v_offset", 0.0, step_time * 0.5)
