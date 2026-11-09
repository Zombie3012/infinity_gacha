class_name UniversalHeroCard
extends PanelContainer

## Universal Hero Card Component for Godot 4 Client
## Unified Tarot / Modern RPG Hero Card used across all facilities:
## Recovery Center, Dormitory, Training Center, Library, Barracks & Equipment.

signal card_clicked(hero_data: Dictionary)
signal selection_toggled(hero_data: Dictionary, is_selected: bool)

enum ContextMode {
	DEFAULT,       ## Standard profile: Stars, CP, Level, Class
	RECOVERY,      ## Recovery Center: HP Bar, Injury debuff, Bed / Queue status
	DORMITORY,     ## Dormitory / Mansion: Fatigue Bar, Morale, Rest Multiplier
	TRAINING,      ## Training Center: 4 Base Stats (STR/AGI/INT/STA) & Skill tag
	LIBRARY,       ## Library: EXP Bar, MAGE affinity badge, Study status
	RESEARCH,      ## Research Lab: Awakening Rank, Class change readiness
	EQUIPMENT      ## Equipment screen: Gear slots preview, equipped status
}

var hero_data: Dictionary = {}
var context_mode: ContextMode = ContextMode.DEFAULT
var is_selected: bool = false:
	set(value):
		is_selected = value
		_update_selection_visual()

var selectable: bool = false
var is_dimmed: bool = false

# Internal UI References
var _outer_style: StyleBoxFlat
var _inner_frame: PanelContainer
var _badge_container: HFlowContainer
var _status_bar_vbox: VBoxContainer
var _status_bar: ProgressBar
var _status_bar_label: Label
var _checkbox_icon: Label
var _name_label: Label
var _class_label: Label
var _level_label: Label
var _stars_label: Label
var _avatar_box: PanelContainer
var _avatar_canvas: Control
var _custom_badges: Array[Dictionary] = []

func _init() -> void:
	custom_minimum_size = Vector2(190, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS

func _ready() -> void:
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func setup(data: Dictionary, mode: ContextMode = ContextMode.DEFAULT, can_select: bool = false) -> void:
	hero_data = data
	context_mode = mode
	selectable = can_select
	_custom_badges.clear()
	_rebuild_ui()

func set_selected(selected: bool) -> void:
	self.is_selected = selected

func add_badge(text: String, bg_color: Color, text_color: Color = Color.WHITE) -> void:
	_custom_badges.append({
		"text": text,
		"bg": bg_color,
		"fg": text_color
	})
	_refresh_badges()

func clear_badges() -> void:
	_custom_badges.clear()
	_refresh_badges()

func set_dimmed(dimmed: bool) -> void:
	is_dimmed = dimmed
	modulate = Color(0.6, 0.6, 0.6, 0.75) if dimmed else Color.WHITE

func set_status_bar(current_val: float, max_val: float, label_text: String, bar_color: Color) -> void:
	if _status_bar == null or _status_bar_label == null:
		return
	_status_bar_vbox.visible = true
	_status_bar.max_value = maxf(1.0, max_val)
	_status_bar.value = clampf(current_val, 0.0, max_val)
	_status_bar_label.text = label_text

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = bar_color
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_status_bar.add_theme_stylebox_override("fill", fill_style)

# ==============================================================================
# UI CONSTRUCTION & RENDERING
# ==============================================================================

func _rebuild_ui() -> void:
	for c in get_children():
		c.queue_free()

	var star: int = int(hero_data.get("rarity", 1))
	var rarity_col := _get_rarity_color(star)

	# 1. Outer Container Style
	_outer_style = StyleBoxFlat.new()
	_outer_style.bg_color = Color(0.065, 0.08, 0.12, 0.98)
	_outer_style.border_width_left = 2
	_outer_style.border_width_top = 2
	_outer_style.border_width_right = 2
	_outer_style.border_width_bottom = 2
	_outer_style.border_color = rarity_col
	_outer_style.corner_radius_top_left = 10
	_outer_style.corner_radius_top_right = 10
	_outer_style.corner_radius_bottom_left = 10
	_outer_style.corner_radius_bottom_right = 10
	_outer_style.shadow_size = 5
	_outer_style.shadow_color = Color(0, 0, 0, 0.45)
	add_theme_stylebox_override("panel", _outer_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(main_vbox)

	# Header: Stars + Class Icon + Selection Checkbox
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header_row)

	_stars_label = Label.new()
	_stars_label.text = "★".repeat(clampi(star, 1, 7))
	_stars_label.add_theme_font_size_override("font_size", 11)
	_stars_label.add_theme_color_override("font_color", rarity_col)
	header_row.add_child(_stars_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	var hid: String = str(hero_data.get("id", ""))
	var in_party: bool = GameState.active_party_ids.has(hid)
	if in_party:
		var party_badge := _create_mini_badge("⚔️ PVE", Color(0.85, 0.22, 0.22, 0.9))
		header_row.add_child(party_badge)

	var is_locked: bool = bool(hero_data.get("isLocked", false))
	if is_locked:
		var lock_badge := _create_mini_badge("🔒", Color(0.18, 0.22, 0.28, 0.9))
		header_row.add_child(lock_badge)

	if selectable:
		_checkbox_icon = Label.new()
		_checkbox_icon.text = "☑" if is_selected else "☐"
		_checkbox_icon.add_theme_font_size_override("font_size", 13)
		_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55) if is_selected else Color(0.6, 0.68, 0.78))
		header_row.add_child(_checkbox_icon)

	# Avatar Box with Occult Aura
	_avatar_box = PanelContainer.new()
	_avatar_box.custom_minimum_size = Vector2(0, 115)
	_avatar_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ab_style := StyleBoxFlat.new()
	ab_style.bg_color = Color(0.04, 0.05, 0.08, 0.95)
	ab_style.border_width_left = 1
	ab_style.border_width_top = 1
	ab_style.border_width_right = 1
	ab_style.border_width_bottom = 1
	ab_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.3)
	ab_style.corner_radius_top_left = 6
	ab_style.corner_radius_top_right = 6
	ab_style.corner_radius_bottom_left = 6
	ab_style.corner_radius_bottom_right = 6
	_avatar_box.add_theme_stylebox_override("panel", ab_style)
	main_vbox.add_child(_avatar_box)

	_avatar_canvas = Control.new()
	_avatar_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_canvas.draw.connect(_on_avatar_canvas_draw)
	_avatar_box.add_child(_avatar_canvas)

	# Center Hero Silhouette / Icon
	var cls: String = str(hero_data.get("classCode", hero_data.get("heroClass", "WARRIOR")))
	var center_icon := Label.new()
	center_icon.text = _get_class_icon(cls)
	center_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_icon.add_theme_font_size_override("font_size", 38)
	center_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_avatar_box.add_child(center_icon)

	# Awakening Rank Badge (Top-left of avatar)
	var awaken_rank: int = int(hero_data.get("awakeningRank", 0))
	if awaken_rank > 0:
		var awk_lbl := Label.new()
		awk_lbl.text = "⚡ +%d" % awaken_rank
		awk_lbl.add_theme_font_size_override("font_size", 9)
		awk_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 1.0))
		awk_lbl.position = Vector2(6, 4)
		_avatar_box.add_child(awk_lbl)

	# Dead / Disabled status overlay
	var hero_state_str: String = str(hero_data.get("state", "HEALTHY")).to_upper()
	if hero_state_str == "DEAD" or hero_state_str == "DISABLED":
		var dead_panel := PanelContainer.new()
		dead_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		var dp_style := StyleBoxFlat.new()
		dp_style.bg_color = Color(0.4, 0.05, 0.05, 0.75)
		dead_panel.add_theme_stylebox_override("panel", dp_style)
		var dead_lbl := Label.new()
		dead_lbl.text = "TỬ TRẬN" if hero_state_str == "DEAD" else "THƯƠNG NẶNG"
		dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dead_lbl.add_theme_font_size_override("font_size", 13)
		dead_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		dead_panel.add_child(dead_lbl)
		_avatar_box.add_child(dead_panel)

	# Class Title Pill on bottom of Avatar Box
	var elem: String = str(hero_data.get("element", "NEUTRAL")).to_upper()
	var class_pill := Label.new()
	class_pill.text = cls
	class_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_pill.add_theme_font_size_override("font_size", 9)
	class_pill.add_theme_color_override("font_color", _get_element_color(elem) if elem != "NEUTRAL" else Color(0.85, 0.92, 1.0))
	class_pill.position = Vector2(0, 92)
	class_pill.size = Vector2(_avatar_box.custom_minimum_size.x, 20)
	class_pill.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_avatar_box.add_child(class_pill)

	# Name & Level Row
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 1)
	main_vbox.add_child(info_vbox)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	info_vbox.add_child(name_row)

	_name_label = Label.new()
	_name_label.text = str(hero_data.get("name", "Hero"))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.add_theme_font_size_override("font_size", 12)
	_name_label.add_theme_color_override("font_color", Color.WHITE)
	name_row.add_child(_name_label)

	var lvl: int = int(hero_data.get("level", 1))
	var promo_rank: int = int(hero_data.get("promotionRank", 0))
	var star_ceiling: int = int(hero_data.get("starCeiling", star * 10))
	var max_lvl: int = int(hero_data.get("maxLevel", mini(star_ceiling, (promo_rank + 1) * 10)))
	_level_label = Label.new()
	_level_label.text = "Lv.%d/%d" % [lvl, max_lvl]
	_level_label.add_theme_font_size_override("font_size", 11)
	_level_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	name_row.add_child(_level_label)

	# Dynamic Context Section (Status Progress Bar & Context Data)
	_status_bar_vbox = VBoxContainer.new()
	_status_bar_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(_status_bar_vbox)

	var sb_header_row := HBoxContainer.new()
	_status_bar_vbox.add_child(sb_header_row)

	_status_bar_label = Label.new()
	_status_bar_label.add_theme_font_size_override("font_size", 10)
	_status_bar_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb_header_row.add_child(_status_bar_label)

	_status_bar = ProgressBar.new()
	_status_bar.custom_minimum_size = Vector2(0, 7)
	_status_bar.show_percentage = false
	var bg_bar := StyleBoxFlat.new()
	bg_bar.bg_color = Color(0.12, 0.15, 0.22, 0.95)
	bg_bar.corner_radius_top_left = 3
	bg_bar.corner_radius_top_right = 3
	bg_bar.corner_radius_bottom_left = 3
	bg_bar.corner_radius_bottom_right = 3
	_status_bar.add_theme_stylebox_override("background", bg_bar)
	_status_bar_vbox.add_child(_status_bar)

	# Specific Context Setup
	_apply_context_rules()

	# Badges Row
	_badge_container = HFlowContainer.new()
	_badge_container.add_theme_constant_override("h_separation", 4)
	_badge_container.add_theme_constant_override("v_separation", 4)
	main_vbox.add_child(_badge_container)
	_refresh_badges()

	_update_selection_visual()

func _apply_context_rules() -> void:
	match context_mode:
		ContextMode.RECOVERY:
			var cur_hp: float = float(hero_data.get("hp", 100))
			var max_hp: float = maxf(1.0, float(hero_data.get("maxHp", 100)))
			var hp_pct: float = (cur_hp / max_hp) * 100.0

			var bar_col := Color(0.28, 0.92, 0.45) # Green
			if hp_pct < 20.0:
				bar_col = Color(0.95, 0.25, 0.28) # Red/Critical
			elif hp_pct < 50.0:
				bar_col = Color(0.98, 0.58, 0.22) # Orange/Injured
			elif hp_pct < 80.0:
				bar_col = Color(0.95, 0.85, 0.32) # Yellow/Minor

			set_status_bar(cur_hp, max_hp, "HP: %d%% (%d/%d)" % [int(round(hp_pct)), int(cur_hp), int(max_hp)], bar_col)

			var state_str := str(hero_data.get("state", "HEALTHY")).to_upper()
			var is_treating := bool(hero_data.get("isTreating", false))
			var is_queued := bool(hero_data.get("isQueued", false))

			if is_treating:
				add_badge("🛏️ Đang hồi phục", Color(0.25, 0.65, 0.95, 0.9))
			elif is_queued:
				add_badge("⏳ Hàng chờ", Color(0.95, 0.70, 0.20, 0.9))
			elif state_str == "INJURED" or hp_pct < 99.9:
				add_badge("🩸 Bị thương", Color(0.85, 0.35, 0.15, 0.9))
			else:
				add_badge("❤️ Đã khỏe", Color(0.20, 0.65, 0.35, 0.9))

		ContextMode.DORMITORY:
			var fat: float = float(hero_data.get("fatigue", 0))
			var bar_col := Color(0.35, 0.85, 0.45)
			if fat > 75.0:
				bar_col = Color(0.92, 0.28, 0.28)
			elif fat > 40.0:
				bar_col = Color(0.95, 0.65, 0.25)
			set_status_bar(fat, 100.0, "Mệt mỏi: %d%%" % int(fat), bar_col)

			var is_resting := str(hero_data.get("state", "")) == "RESTING"
			if is_resting:
				add_badge("💤 Đang nghỉ ngơi", Color(0.25, 0.55, 0.95, 0.9))

		ContextMode.LIBRARY:
			var hexp: float = float(hero_data.get("exp", 0))
			var req_exp: float = maxf(1.0, float(hero_data.get("nextLevelExp", 1000)))
			set_status_bar(hexp, req_exp, "EXP: %d/%d" % [int(hexp), int(req_exp)], Color(0.35, 0.75, 1.0))
			var cls: String = str(hero_data.get("classCode", hero_data.get("heroClass", ""))).to_upper()
			if cls == "MAGE":
				add_badge("🔮 MAGE (Hợp lệ)", Color(0.55, 0.32, 0.92, 0.9))
			else:
				add_badge("🔒 Không thể phân công", Color(0.4, 0.45, 0.52, 0.8))

		ContextMode.TRAINING:
			_status_bar_vbox.visible = false
			var str_v := int(hero_data.get("str", 10))
			var agi_v := int(hero_data.get("agi", 10))
			var int_v := int(hero_data.get("int", 10))
			var sta_v := int(hero_data.get("sta", 10))
			add_badge("💪 STR %d" % str_v, Color(0.85, 0.35, 0.35, 0.85))
			add_badge("⚡ AGI %d" % agi_v, Color(0.35, 0.75, 0.92, 0.85))
			add_badge("🔮 INT %d" % int_v, Color(0.68, 0.42, 0.95, 0.85))
			add_badge("🛡️ STA %d" % sta_v, Color(0.42, 0.85, 0.55, 0.85))

		ContextMode.DEFAULT, _:
			var mhp: int = int(hero_data.get("maxHp", 100))
			var atk: int = int(hero_data.get("attack", 10))
			var def_v: int = int(hero_data.get("defense", 10))
			var spd: int = int(hero_data.get("speed", 10))
			var cp: int = int(hero_data.get("combatPower", mhp + atk * 4 + def_v * 3 + spd * 2))
			_status_bar_label.text = "🔥 LC: %s" % _format_number(cp)
			_status_bar_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
			_status_bar.visible = false

func _refresh_badges() -> void:
	if _badge_container == null:
		return
	for c in _badge_container.get_children():
		c.queue_free()

	for b_def in _custom_badges:
		var badge := _create_mini_badge(str(b_def.get("text", "")), b_def.get("bg", Color(0.2, 0.4, 0.7, 0.9)), b_def.get("fg", Color.WHITE))
		_badge_container.add_child(badge)

func _create_mini_badge(text: String, bg_col: Color, fg_col: Color = Color.WHITE) -> PanelContainer:
	var pill := PanelContainer.new()
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = bg_col
	pstyle.corner_radius_top_left = 3
	pstyle.corner_radius_top_right = 3
	pstyle.corner_radius_bottom_left = 3
	pstyle.corner_radius_bottom_right = 3
	pill.add_theme_stylebox_override("panel", pstyle)

	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 4)
	pm.add_theme_constant_override("margin_right", 4)
	pm.add_theme_constant_override("margin_top", 1)
	pm.add_theme_constant_override("margin_bottom", 1)
	pill.add_child(pm)

	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", fg_col)
	pm.add_child(lbl)
	return pill

func _update_selection_visual() -> void:
	if _outer_style == null:
		return
	var star: int = int(hero_data.get("rarity", 1))
	var base_col := _get_rarity_color(star)

	if is_selected:
		_outer_style.border_color = Color(0.35, 1.0, 0.55, 1.0)
		_outer_style.border_width_left = 3
		_outer_style.border_width_top = 3
		_outer_style.border_width_right = 3
		_outer_style.border_width_bottom = 3
		_outer_style.shadow_color = Color(0.2, 0.8, 0.4, 0.6)
		_outer_style.shadow_size = 8
		if _checkbox_icon != null:
			_checkbox_icon.text = "☑"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	else:
		_outer_style.border_color = base_col
		_outer_style.border_width_left = 2
		_outer_style.border_width_top = 2
		_outer_style.border_width_right = 2
		_outer_style.border_width_bottom = 2
		_outer_style.shadow_color = Color(0, 0, 0, 0.45)
		_outer_style.shadow_size = 5
		if _checkbox_icon != null:
			_checkbox_icon.text = "☐"
			_checkbox_icon.add_theme_color_override("font_color", Color(0.6, 0.68, 0.78))

func _on_avatar_canvas_draw() -> void:
	if _avatar_canvas == null:
		return
	var c: Vector2 = _avatar_canvas.size / 2.0
	var star: int = int(hero_data.get("rarity", 1))
	var col: Color = _get_rarity_color(star)
	var ring_col := Color(col.r, col.g, col.b, 0.22)
	var thin_col := Color(col.r, col.g, col.b, 0.12)

	_avatar_canvas.draw_arc(c, 42.0, 0.0, TAU, 36, ring_col, 1.2, true)
	_avatar_canvas.draw_arc(c, 30.0, 0.0, TAU, 28, thin_col, 1.0, true)
	_avatar_canvas.draw_line(c - Vector2(48.0, 0.0), c - Vector2(36.0, 0.0), thin_col, 1.0, true)
	_avatar_canvas.draw_line(c + Vector2(36.0, 0.0), c + Vector2(48.0, 0.0), thin_col, 1.0, true)
	_avatar_canvas.draw_line(c - Vector2(0.0, 48.0), c - Vector2(0.0, 36.0), thin_col, 1.0, true)
	_avatar_canvas.draw_line(c + Vector2(0.0, 36.0), c + Vector2(0.0, 48.0), thin_col, 1.0, true)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if selectable:
			self.is_selected = not is_selected
			selection_toggled.emit(hero_data, is_selected)
		card_clicked.emit(hero_data)

func _on_mouse_entered() -> void:
	if not is_dimmed:
		var tw := create_tween()
		tw.tween_property(self, "scale", Vector2(1.02, 1.02), 0.08)

func _on_mouse_exited() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.0, 1.0), 0.08)

# ==============================================================================
# HELPERS
# ==============================================================================

func _get_rarity_color(star: int) -> Color:
	if star >= 7:
		return Color(1.0, 0.45, 0.95, 1.0) # 7★ Prismatic Rainbow
	elif star == 6:
		return Color(0.95, 0.22, 0.28, 1.0) # 6★ Crimson / Mythic Red
	elif star == 5:
		return Color(1.0, 0.82, 0.24, 0.95) # 5★ Gold
	elif star == 4:
		return Color(0.78, 0.48, 0.95, 0.95) # 4★ Purple
	elif star == 3:
		return Color(0.32, 0.72, 0.95, 0.90) # 3★ Blue
	elif star == 2:
		return Color(0.35, 0.85, 0.50, 0.90) # 2★ Green
	return Color(0.68, 0.72, 0.78, 0.85)     # 1★ Gray/Bronze

func _get_element_color(elem: String) -> Color:
	match elem.to_upper():
		"FIRE": return Color(1.0, 0.40, 0.25)
		"WATER": return Color(0.35, 0.75, 1.0)
		"WIND", "AIR": return Color(0.40, 0.95, 0.65)
		"EARTH": return Color(0.85, 0.68, 0.35)
		"LIGHT": return Color(1.0, 0.95, 0.55)
		"DARK": return Color(0.75, 0.45, 0.95)
		_: return Color(0.85, 0.88, 0.95)

func _get_class_icon(hero_class: String) -> String:
	match hero_class.to_upper():
		"WARRIOR": return "⚔️"
		"TANK", "KNIGHT", "PALADIN": return "🛡️"
		"MAGE": return "🔮"
		"ARCHER", "RANGER": return "🏹"
		"ASSASSIN": return "🗡️"
		"SUPPORT", "PRIEST", "HEALER": return "🌿"
		_: return "👤"

func _format_number(val: int) -> String:
	if val >= 1_000_000:
		return "%.1fM" % (float(val) / 1_000_000.0)
	elif val >= 10_000:
		return "%.1fK" % (float(val) / 1000.0)
	return str(val)
