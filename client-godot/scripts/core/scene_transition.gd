extends CanvasLayer

## Global Scene Transition & Loading Overlay (P3-05)

var _overlay: ColorRect
var _label: Label
var _transitioning: bool = false

func _ready() -> void:
	layer = 120
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0.02, 0.03, 0.06, 1.0)
	_overlay.modulate.a = 0.0
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(center)

	_label = Label.new()
	_label.text = "⏳ Đang chuyển cảnh..."
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.75, 0.90, 1.0))
	center.add_child(_label)

func change_scene(scene_path: String, loading_text: String = "⏳ Đang chuyển cảnh...") -> void:
	if _transitioning or not is_inside_tree():
		return
	_transitioning = true
	_overlay.visible = true
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	if _label != null:
		_label.text = loading_text
	_overlay.modulate.a = 0.0
	var tw_in := create_tween()
	tw_in.tween_property(_overlay, "modulate:a", 1.0, 0.14)
	await tw_in.finished
	if is_inside_tree():
		get_tree().change_scene_to_file(scene_path)
		await get_tree().process_frame
	if is_inside_tree():
		var tw_out := create_tween()
		tw_out.tween_property(_overlay, "modulate:a", 0.0, 0.16)
		await tw_out.finished
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transitioning = false
