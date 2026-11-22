extends Node

class BaseFixture extends "res://scenes/base/isometric_base_3d.gd":
	signal response_ready
	var requests := 0
	var renders := 0
	var pause_last := false
	func _ready() -> void: set_process(false)
	func _backend_refresh_steps() -> Array[Callable]:
		return [_immediate, _pending] if pause_last else [_pending, _immediate]
	func _pending() -> bool:
		requests += 1
		await response_ready
		return true
	func _immediate() -> bool:
		requests += 1
		return true
	func _refresh_hud() -> void: renders += 1
	func _refresh_3d_plots() -> void: renders += 1
	func _spawn_resident_heroes() -> void: renders += 1
	func _re_render_inspector_if_open() -> void: renders += 1
	func exercise_detached_refresh() -> void:
		super._refresh_3d_plots()
		super._apply_all_grid_transforms()

var checks := 0
var failures := 0
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("BASE LIFECYCLE: " + message)

func make_base() -> Node3D:
	var base = load("res://scenes/base/isometric_base_3d.tscn").instantiate()
	base.set_script(BaseFixture)
	add_child(base)
	return base

func _ready() -> void:
	var base = make_base()
	base._sync_all_from_backend()
	expect(base.requests == 1, "First refresh is waiting for a response")
	remove_child(base)
	base.response_ready.emit()
	await get_tree().process_frame
	expect(base.requests == 1 and base.renders == 0, "Exit during HTTP stops remaining requests and rendering")
	base.exercise_detached_refresh()
	base.free()

	base = make_base()
	base._sync_all_from_backend()
	base.queue_free()
	base.response_ready.emit()
	expect(base.requests == 1 and base.renders == 0, "Queued deletion blocks a response before the node actually exits")
	await get_tree().process_frame

	base = make_base()
	base.pause_last = true
	base._sync_all_from_backend()
	expect(base.requests == 2, "Last refresh is waiting, matching the party-response stack")
	remove_child(base)
	base.response_ready.emit()
	await get_tree().process_frame
	expect(base.renders == 0, "A late final response cannot update detached base nodes")
	base.free()

	base = make_base()
	base._sync_all_from_backend()
	remove_child(base)
	add_child(base)
	base.response_ready.emit()
	await get_tree().process_frame
	expect(base.requests == 1 and base.renders == 0, "Re-entering the tree cannot revive an old sync")
	base._sync_all_from_backend()
	base.response_ready.emit()
	await get_tree().process_frame
	expect(base.requests == 3 and base.renders == 4, "A fresh sync renders normally after re-entry")
	base.queue_free()
	await get_tree().process_frame

	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 12, 16)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var plot = load("res://scenes/base/base_plot_3d.tscn").instantiate()
	plot.setup_plot(1, true, {"buildingType": "HOUSE", "level": 1, "status": "READY"})
	add_child(plot)
	await get_tree().process_frame
	remove_child(plot)
	plot.setup_plot(1, true, {"buildingType": "HOUSE", "level": 2, "status": "READY"})
	plot._fit_caption_to_camera()
	expect(plot.sub_label.text.contains("2"), "Detached setup keeps local caption data without accessing a viewport")
	var style = load("res://scripts/base/building_label_style.gd")
	expect(style.fit(plot.title_label, camera, 18.0) == 1.0, "Detached labels skip global transform calculations")
	add_child(plot)
	remove_child(camera)
	plot._fit_caption_to_camera()
	expect(style.fit(plot.title_label, camera, 18.0) == 1.0, "Detached cameras are safe")
	add_child(camera)
	plot._fit_caption_to_camera()
	expect(plot.title_label.pixel_size > 0, "Caption fitting resumes after valid tree entry")
	plot.queue_free()
	plot._fit_caption_to_camera()
	camera.queue_free()
	await get_tree().process_frame
	print("BASE_LIFECYCLE_TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)
