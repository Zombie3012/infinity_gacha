extends RefCounted

const INK := Color("0a1220")
const PANEL := Color("142237")
const TEXT := Color("e5edf6")
const MUTED := Color("9fb2c8")
const GOLD := Color("e7bc72")
const TEAL := Color("56ccbb")

static func style(background: Color, border: Color = Color("2c405a"), radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box

static func panel(parent: Node, minimum_width: float = 0.0) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = minimum_width
	frame.add_theme_stylebox_override("panel", style(PANEL))
	parent.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	frame.add_child(column)
	return column

static func label(parent: Node, text: String, size: int = 14, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func button(parent: Node, text: String, callback: Callable, accent: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 36
	node.add_theme_stylebox_override("normal", style(Color("294a50") if accent else Color("21334b"), TEAL if accent else Color("38516b")))
	node.add_theme_stylebox_override("hover", style(Color("345673"), GOLD))
	node.add_theme_stylebox_override("pressed", style(Color("365b64"), GOLD))
	node.add_theme_color_override("font_color", TEXT)
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
