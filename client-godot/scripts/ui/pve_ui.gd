extends RefCounted

const INK := Color("0a1220")
const PANEL := Color("142237")
const CARD := Color("16263d")
const GLASS := Color(0.04, 0.07, 0.13, 0.90)
const TEXT := Color("e5edf6")
const MUTED := Color("9fb2c8")
const GOLD := Color("e7bc72")
const TEAL := Color("56ccbb")
const SUCCESS := Color("52d198")
const DANGER := Color("ef6f6c")
const WARNING := Color("f4b956")
const BORDER := Color("2c405a")
const BORDER_SOFT := Color(0.22, 0.34, 0.48, 0.72)

static func style(background: Color, border: Color = BORDER, radius: int = 8, margin_h: int = 12, margin_v: int = 10) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
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

static func glass_panel(parent: Node, border: Color = BORDER, radius: int = 12, margin_h: int = 12, margin_v: int = 10) -> VBoxContainer:
	var frame := PanelContainer.new()
	var box := style(GLASS, border, radius, margin_h, margin_v)
	box.shadow_size = 8
	box.shadow_color = Color(0, 0, 0, 0.45)
	frame.add_theme_stylebox_override("panel", box)
	parent.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	frame.add_child(column)
	return column

static func card(parent: Node, background: Color = CARD, border: Color = BORDER, radius: int = 10) -> VBoxContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", style(background, border, radius, 10, 8))
	parent.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	frame.add_child(column)
	return column

static func label(parent: Node, text: String, size: int = 14, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func badge(parent: Node, text: String, fill: Color = Color("1f344d"), border: Color = BORDER, text_color: Color = TEXT, font_size: int = 12) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", style(fill, border, 999, 10, 4))
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", text_color)
	pill.add_child(lbl)
	parent.add_child(pill)
	return pill

static func progress_bar(parent: Node, value: float, max_value: float, fill_color: Color = TEAL, height: int = 8) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.max_value = maxf(1.0, max_value)
	bar.value = clampf(value, 0.0, bar.max_value)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.08, 0.14, 0.95)
	bg.set_corner_radius_all(999)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(999)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	return bar

static func button(parent: Node, text: String, callback: Callable, accent: bool = false, tone: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.custom_minimum_size.y = 34
	var resolved_tone := tone if not tone.is_empty() else ("accent" if accent else "default")
	var normal_bg := Color("21334b")
	var normal_border := Color("38516b")
	var hover_bg := Color("2e4766")
	var hover_border := GOLD
	match resolved_tone:
		"accent":
			normal_bg = Color("234b52")
			normal_border = TEAL
			hover_bg = Color("2e626a")
		"gold":
			normal_bg = Color("4b391a")
			normal_border = GOLD
			hover_bg = Color("644b22")
		"danger":
			normal_bg = Color("4c2429")
			normal_border = DANGER
			hover_bg = Color("673038")
		"ghost":
			normal_bg = Color(0.08, 0.13, 0.21, 0.72)
			normal_border = BORDER_SOFT
			hover_bg = Color(0.14, 0.22, 0.34, 0.92)
	node.add_theme_stylebox_override("normal", style(normal_bg, normal_border, 8, 12, 6))
	node.add_theme_stylebox_override("hover", style(hover_bg, hover_border, 8, 12, 6))
	node.add_theme_stylebox_override("pressed", style(hover_bg.darkened(0.12), GOLD, 8, 12, 6))
	node.add_theme_stylebox_override("disabled", style(Color(0.09, 0.13, 0.20, 0.65), Color(0.18, 0.24, 0.34, 0.55), 8, 12, 6))
	node.add_theme_color_override("font_color", TEXT)
	node.add_theme_color_override("font_disabled_color", Color(0.55, 0.63, 0.72, 0.75))
	node.pressed.connect(callback)
	parent.add_child(node)
	return node

static func clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
