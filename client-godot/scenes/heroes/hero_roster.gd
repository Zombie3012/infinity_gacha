extends Control

## Upgraded Hero Barracks, 3D Hero Pedestal, 4-Tab Deep Profile (Stats / Skills / Imprints / Equipment)
## & Pick Me Up Star Promotion Ritual for Godot 4 Client

const UnitActorScene: PackedScene = preload("res://scenes/common/unit_actor_3d.tscn")

@onready var hero_item_list: ItemList = %HeroItemList
@onready var hero_name_label: Label = %HeroNameLabel
@onready var hero_class_label: Label = %HeroClassLabel
@onready var hero_star_label: Label = %HeroStarLabel
@onready var hero_level_label: Label = %HeroLevelLabel
@onready var hero_cp_label: Label = %HeroCpLabel
@onready var base_stats_label: Label = %BaseStatsLabel
@onready var combat_stats_label: Label = %CombatStatsLabel
@onready var equipment_list_label: Label = %EquipmentListLabel

@onready var promote_panel: PanelContainer = %PromotePanel
@onready var promote_info_label: Label = %PromoteInfoLabel
@onready var fodder_item_list: ItemList = %FodderItemList
@onready var confirm_promote_btn: Button = %ConfirmPromoteBtn
@onready var open_promote_btn: Button = %OpenPromoteBtn
@onready var close_promote_btn: Button = %ClosePromoteBtn
@onready var back_btn: Button = %BackBtn
@onready var status_label: Label = %StatusLabel

var _filtered_heroes: Array = []
var _selected_hero: Dictionary = {}
var _selected_fodder_ids: Array[String] = []
var _preview_data: Dictionary = {}
var _hero_imprints: Array = []
var _active_profile_tab: int = 0 # 0: Stats, 1: Skills, 2: Imprints, 3: Equipment
var _roster_filter_mode: int = 0 # 0: All, 1: Party, 2: 4-5★, 3: 1-3★
var _selected_exp_book_id: String = "SAMPLE_HERO_EXP_100"
var _equipment_filter_slot: String = "ALL"
var _equipment_selected_slot: String = "HELMET"
var _equipment_inspected_item_id: String = ""
var _equipment_rarity_filter: int = 0 # 0: All, 5: 5★, 4: 4★, 3: 1-3★

# Dynamic UI & 3D Pedestal references
var _tab_content_scroll: ScrollContainer = null
var _tab_content_vbox: VBoxContainer = null
var _tab_buttons: Array[Button] = []
var _filter_buttons: Array[Button] = []
var _sort_buttons: Array[Button] = []
var _party_toggle_btn: Button = null
var _lock_toggle_btn: Button = null
var _quick_level_for_promote_btn: Button = null
var _auto_pick_fodder_btn: Button = null
var _promote_modal_backdrop: ColorRect = null
var _pedestal_equipment_overlay: MarginContainer = null
var _pedestal_left_slots_vbox: VBoxContainer = null
var _pedestal_right_slots_vbox: VBoxContainer = null

# Grid View & Detail View Navigation references
var _in_detail_view: bool = false
var _grid_sort_mode: int = 0 # 0: CP, 1: Level, 2: Stars, 3: Name
var _grid_sort_ascending: bool = false
var _grid_view_container: VBoxContainer = null
var _hero_grid_container: GridContainer = null
var _grid_total_label: Label = null
var _main_layout: Control = null
var _detail_back_btn: Button = null
var _detail_close_btn: Button = null
var _prev_hero_btn: Button = null
var _next_hero_btn: Button = null
var _breadcrumb_class_label: Label = null

# Stats Details Modal references (Bảng Toàn Bộ Chỉ Số)
var _stats_detail_modal_backdrop: ColorRect = null
var _stats_detail_panel: PanelContainer = null
var _stats_detail_vbox: VBoxContainer = null

# Equipment Set Bonus Modal references (Chi Tiết Bộ Chữ Ký & Lấp Lánh)
var _set_bonus_modal_backdrop: ColorRect = null
var _set_bonus_vbox: VBoxContainer = null

# Awakening Ritual Modal references (Khung Nghi Thức Thức Tỉnh Huyết Mạch)
var _awaken_modal_backdrop: ColorRect = null
var _awaken_panel: PanelContainer = null
var _awaken_header_label: Label = null
var _awaken_info_label: Label = null
var _awaken_req_box: VBoxContainer = null
var _confirm_awaken_btn: Button = null
var _close_awaken_btn: Button = null
var _awaken_preview_data: Dictionary = {}

# Breakthrough Modal references (Khung Nghi Thức Đột Phá Cấp Độ)
var _breakthrough_modal_backdrop: ColorRect = null
var _breakthrough_panel: PanelContainer = null
var _breakthrough_header_label: Label = null
var _breakthrough_info_label: Label = null
var _breakthrough_req_box: VBoxContainer = null
var _confirm_breakthrough_btn: Button = null
var _close_breakthrough_btn: Button = null
var _breakthrough_preview_data: Dictionary = {}

# 3D Hero Pedestal Viewport
var _pedestal_pivot: Node3D = null
var _pedestal_actor: UnitActor3D = null
var _pedestal_ring: MeshInstance3D = null
var _pedestal_light: OmniLight3D = null
var _auto_rotate_3d: bool = true

func _get_hero_max_imprint_slots(star: int) -> int:
	if star >= 5:
		return 4
	elif star == 4:
		return 3
	elif star == 3:
		return 2
	return 1

func _get_hero_class_icon(hero_class: String) -> String:
	match hero_class.to_upper():
		"WARRIOR": return "⚔️"
		"TANK": return "🛡️"
		"MAGE": return "🔮"
		"ARCHER": return "🏹"
		"ASSASSIN": return "🗡️"
		"SUPPORT": return "🌿"
		"HEALER": return "⚕️"
		_: return "👤"

func _get_hero_element_color(element: String) -> Color:
	match element.to_upper():
		"FIRE": return Color(1.0, 0.45, 0.2)
		"WATER": return Color(0.25, 0.7, 1.0)
		"WIND": return Color(0.3, 0.85, 0.45)
		"EARTH": return Color(0.85, 0.7, 0.3)
		"LIGHT": return Color(1.0, 0.9, 0.4)
		"DARK": return Color(0.75, 0.4, 0.95)
		"LIGHTNING": return Color(0.95, 0.85, 0.25)
		_: return Color(0.65, 0.75, 0.85)

func _get_rarity_border_color(star: int) -> Color:
	if star >= 5:
		return Color(1.0, 0.82, 0.24, 0.95)
	elif star == 4:
		return Color(0.78, 0.48, 0.95, 0.95)
	elif star == 3:
		return Color(0.32, 0.72, 0.95, 0.90)
	return Color(0.68, 0.52, 0.36, 0.90)

func _get_rarity_rank_name(star: int) -> String:
	if star >= 5:
		return "S"
	elif star == 4:
		return "A"
	elif star == 3:
		return "B"
	return "C"

func _ready() -> void:
	hero_item_list.item_selected.connect(_on_hero_selected)
	open_promote_btn.pressed.connect(_on_open_promote_pressed)
	close_promote_btn.pressed.connect(_on_close_promote_pressed)
	confirm_promote_btn.pressed.connect(_on_confirm_promote_pressed)
	fodder_item_list.multi_selected.connect(_on_fodder_selected)
	back_btn.pressed.connect(_on_back_pressed)

	promote_panel.visible = false
	_setup_enhanced_layout()
	await _sync_all_roster_data()

func _process(delta: float) -> void:
	if _pedestal_pivot != null and is_instance_valid(_pedestal_pivot) and _auto_rotate_3d:
		_pedestal_pivot.rotate_y(delta * 0.85)
	if _pedestal_ring != null and is_instance_valid(_pedestal_ring):
		_pedestal_ring.rotate_y(-delta * 1.4)

func _sync_all_roster_data(preserve_hero_id: String = "") -> void:
	status_label.text = "🔄 Đang đồng bộ dữ liệu Doanh Trại & Hồ Sơ Tướng..."
	await GameState.ensure_demo_session()
	await GameState.refresh_profile()
	await GameState.refresh_heroes()
	await GameState.refresh_party()
	await GameState.refresh_crafting()
	await GameState.refresh_equipment()
	await GameState.refresh_inventory()
	_refresh_hero_list(preserve_hero_id)
	status_label.text = "🛡️ Doanh Trại sẵn sàng — Chọn Tướng để xem Mô hình 3D, Chỉ số, Kỹ năng, Ấn ký Imprint, Trang bị & Thăng Sao."

# ==============================================================================
# ENHANCED UI & 3D PEDESTAL CONSTRUCTION
# ==============================================================================

func _setup_enhanced_layout() -> void:
	# 1. MainLayout & LeftListPanel: Hide LeftListPanel and default to Grid View
	_main_layout = find_child("MainLayout", true, false) as Control
	var left_panel := find_child("LeftListPanel", true, false) as Control
	if left_panel != null:
		left_panel.visible = false
	if _main_layout != null:
		_main_layout.visible = false

	# Construct Grid View Container
	var root_vbox: VBoxContainer = _main_layout.get_parent() as VBoxContainer if _main_layout != null else null
	if root_vbox != null:
		_grid_view_container = VBoxContainer.new()
		_grid_view_container.name = "HeroGridViewContainer"
		_grid_view_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid_view_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_grid_view_container.add_theme_constant_override("separation", 10)
		root_vbox.add_child(_grid_view_container)
		root_vbox.move_child(_grid_view_container, _main_layout.get_index())

		# Row 1: Index Banner, Counter Badge & Quick Summon
		var grid_banner_row := HBoxContainer.new()
		grid_banner_row.add_theme_constant_override("separation", 10)
		_grid_view_container.add_child(grid_banner_row)

		var index_title := Label.new()
		index_title.text = "🏛️ DANH BẠ ANH HÙNG (HERO ROSTER)"
		index_title.add_theme_font_size_override("font_size", 16)
		index_title.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
		grid_banner_row.add_child(index_title)

		var index_sub := Label.new()
		index_sub.text = "• Nhấn vào thẻ Tướng để xem Hồ Sơ Chi Tiết"
		index_sub.add_theme_font_size_override("font_size", 12)
		index_sub.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		grid_banner_row.add_child(index_sub)

		var banner_spacer := Control.new()
		banner_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_banner_row.add_child(banner_spacer)

		var total_badge := PanelContainer.new()
		var tb_style := StyleBoxFlat.new()
		tb_style.bg_color = Color(0.08, 0.12, 0.18, 0.9)
		tb_style.border_width_left = 1
		tb_style.border_width_top = 1
		tb_style.border_width_right = 1
		tb_style.border_width_bottom = 1
		tb_style.border_color = Color(0.25, 0.65, 0.95, 0.8)
		tb_style.corner_radius_top_left = 4
		tb_style.corner_radius_top_right = 4
		tb_style.corner_radius_bottom_left = 4
		tb_style.corner_radius_bottom_right = 4
		total_badge.add_theme_stylebox_override("panel", tb_style)
		var tb_margin := MarginContainer.new()
		tb_margin.add_theme_constant_override("margin_left", 10)
		tb_margin.add_theme_constant_override("margin_right", 10)
		tb_margin.add_theme_constant_override("margin_top", 4)
		tb_margin.add_theme_constant_override("margin_bottom", 4)
		total_badge.add_child(tb_margin)
		_grid_total_label = Label.new()
		_grid_total_label.text = "TỔNG SỐ #0"
		_grid_total_label.add_theme_font_size_override("font_size", 12)
		_grid_total_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
		tb_margin.add_child(_grid_total_label)
		grid_banner_row.add_child(total_badge)

		var quick_summon_btn := Button.new()
		quick_summon_btn.text = "✨ Triệu Hồi Nhanh ×10"
		quick_summon_btn.custom_minimum_size = Vector2(170, 32)
		quick_summon_btn.pressed.connect(_on_quick_summon_in_barracks)
		grid_banner_row.add_child(quick_summon_btn)

		# Row 2: Filters & Sort Controls
		var grid_ctrl_row := HBoxContainer.new()
		grid_ctrl_row.add_theme_constant_override("separation", 8)
		_grid_view_container.add_child(grid_ctrl_row)

		var filter_names := ["Tất cả", "⚔️ Đội PvE", "🌟 4-5★", "⭐ 1-3★"]
		_filter_buttons.clear()
		for i in range(filter_names.size()):
			var fbtn := Button.new()
			fbtn.text = filter_names[i]
			fbtn.custom_minimum_size = Vector2(90, 30)
			fbtn.add_theme_font_size_override("font_size", 12)
			var f_idx := i
			fbtn.pressed.connect(func():
				_roster_filter_mode = f_idx
				_refresh_hero_list(str(_selected_hero.get("id", "")))
			)
			grid_ctrl_row.add_child(fbtn)
			_filter_buttons.append(fbtn)

		var ctrl_spacer := Control.new()
		ctrl_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_ctrl_row.add_child(ctrl_spacer)

		var sort_lbl := Label.new()
		sort_lbl.text = "Sắp xếp theo:"
		sort_lbl.add_theme_font_size_override("font_size", 12)
		sort_lbl.add_theme_color_override("font_color", Color(0.7, 0.78, 0.88))
		grid_ctrl_row.add_child(sort_lbl)

		var sort_names := ["🔥 Lực Chiến ▼", "📈 Cấp Độ ▼", "⭐ Sao ▼", "🔤 Tên A-Z ▲"]
		_sort_buttons.clear()
		for s_idx in range(sort_names.size()):
			var sbtn := Button.new()
			sbtn.text = sort_names[s_idx]
			sbtn.custom_minimum_size = Vector2(0, 30)
			sbtn.add_theme_font_size_override("font_size", 12)
			var cur_s := s_idx
			sbtn.pressed.connect(func():
				if _grid_sort_mode == cur_s:
					_grid_sort_ascending = not _grid_sort_ascending
				else:
					_grid_sort_mode = cur_s
					_grid_sort_ascending = false
				_update_sort_button_labels()
				_refresh_hero_list(str(_selected_hero.get("id", "")))
			)
			grid_ctrl_row.add_child(sbtn)
			_sort_buttons.append(sbtn)

		# Row 3: Grid Scroll Container
		var grid_scroll := ScrollContainer.new()
		grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_grid_view_container.add_child(grid_scroll)

		var grid_margin := MarginContainer.new()
		grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_margin.add_theme_constant_override("margin_left", 2)
		grid_margin.add_theme_constant_override("margin_right", 6)
		grid_margin.add_theme_constant_override("margin_top", 4)
		grid_margin.add_theme_constant_override("margin_bottom", 12)
		grid_scroll.add_child(grid_margin)

		_hero_grid_container = GridContainer.new()
		_hero_grid_container.columns = 5
		_hero_grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_hero_grid_container.add_theme_constant_override("h_separation", 12)
		_hero_grid_container.add_theme_constant_override("v_separation", 12)
		grid_margin.add_child(_hero_grid_container)

	# 2. Detail View in CenterDetailPanel (Honkai: Star Rail Layout)
	var center_vbox: VBoxContainer = hero_name_label.get_parent()
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var center_panel := center_vbox.get_parent().get_parent()
	if center_panel is Control:
		center_panel.clip_contents = true
		center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		center_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for legacy_node_name in ["HSeparator1", "BaseStatsHeader", "BaseStatsLabel", "HSeparator2", "CombatStatsHeader", "CombatStatsLabel", "HSeparator3", "EquipmentListLabel", "Spacer"]:
		var n := center_vbox.get_node_or_null(legacy_node_name)
		if n != null and n is CanvasItem:
			n.visible = false

	var header_stats_row: Control = center_vbox.get_node_or_null("HeaderStatsRow") as Control
	if hero_name_label.get_parent() != null:
		hero_name_label.get_parent().remove_child(hero_name_label)
	if header_stats_row != null and header_stats_row.get_parent() != null:
		header_stats_row.get_parent().remove_child(header_stats_row)
	if open_promote_btn.get_parent() != null:
		open_promote_btn.get_parent().remove_child(open_promote_btn)

	var hsr_layout := HBoxContainer.new()
	hsr_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsr_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsr_layout.add_theme_constant_override("separation", 14)
	center_vbox.add_child(hsr_layout)

	# ==============================================================================
	# COLUMN 1: LEFT NAVIGATION & TABS (Honkai Star Rail Style)
	# ==============================================================================
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(185, 0)
	left_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_theme_constant_override("separation", 8)
	hsr_layout.add_child(left_col)

	_detail_back_btn = Button.new()
	_detail_back_btn.text = "⬅ Quay lại Danh Sách"
	_detail_back_btn.custom_minimum_size = Vector2(0, 32)
	_detail_back_btn.add_theme_font_size_override("font_size", 12)
	var db_style := StyleBoxFlat.new()
	db_style.bg_color = Color(0.12, 0.18, 0.28, 0.9)
	db_style.border_width_left = 1
	db_style.border_width_top = 1
	db_style.border_width_right = 1
	db_style.border_width_bottom = 1
	db_style.border_color = Color(0.35, 0.65, 0.95, 0.75)
	db_style.corner_radius_top_left = 6
	db_style.corner_radius_top_right = 6
	db_style.corner_radius_bottom_left = 6
	db_style.corner_radius_bottom_right = 6
	_detail_back_btn.add_theme_stylebox_override("normal", db_style)
	_detail_back_btn.pressed.connect(_close_hero_detail)
	left_col.add_child(_detail_back_btn)

	var breadcrumb_vbox := VBoxContainer.new()
	breadcrumb_vbox.add_theme_constant_override("separation", 2)
	left_col.add_child(breadcrumb_vbox)

	var bc_title := Label.new()
	bc_title.text = "HỒ SƠ TƯỚNG"
	bc_title.add_theme_font_size_override("font_size", 11)
	bc_title.add_theme_color_override("font_color", Color(0.68, 0.78, 0.9))
	breadcrumb_vbox.add_child(bc_title)

	_breadcrumb_class_label = Label.new()
	_breadcrumb_class_label.text = "MAGE / DARK"
	_breadcrumb_class_label.add_theme_font_size_override("font_size", 11)
	_breadcrumb_class_label.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	breadcrumb_vbox.add_child(_breadcrumb_class_label)

	left_col.add_child(HSeparator.new())

	# Vertical Tab Buttons
	var tab_icons := ["✨", "🔮", "💠", "🛡️"]
	var tab_titles := ["Chỉ Số", "Kỹ Năng", "Ấn Ký", "Trang Bị"]
	_tab_buttons.clear()
	for t_idx in range(tab_titles.size()):
		var tbtn := Button.new()
		tbtn.text = " %s  %s" % [tab_icons[t_idx], tab_titles[t_idx]]
		tbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tbtn.custom_minimum_size = Vector2(0, 42)
		tbtn.add_theme_font_size_override("font_size", 13)
		var target_tab := t_idx
		tbtn.pressed.connect(func():
			_active_profile_tab = target_tab
			_render_active_profile_tab()
		)
		left_col.add_child(tbtn)
		_tab_buttons.append(tbtn)

	var left_spacer := Control.new()
	left_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(left_spacer)

	# Quick Nav Switcher & Action buttons at bottom left
	var switcher_row := HBoxContainer.new()
	switcher_row.add_theme_constant_override("separation", 6)
	left_col.add_child(switcher_row)

	_prev_hero_btn = Button.new()
	_prev_hero_btn.text = "◀ Trước"
	_prev_hero_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_hero_btn.custom_minimum_size = Vector2(0, 32)
	_prev_hero_btn.add_theme_font_size_override("font_size", 11)
	_prev_hero_btn.pressed.connect(_on_nav_prev_hero_pressed)
	switcher_row.add_child(_prev_hero_btn)

	_next_hero_btn = Button.new()
	_next_hero_btn.text = "Sau ▶"
	_next_hero_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_hero_btn.custom_minimum_size = Vector2(0, 32)
	_next_hero_btn.add_theme_font_size_override("font_size", 11)
	_next_hero_btn.pressed.connect(_on_nav_next_hero_pressed)
	switcher_row.add_child(_next_hero_btn)

	_party_toggle_btn = Button.new()
	_party_toggle_btn.text = "⚔️ Đội PvE"
	_party_toggle_btn.custom_minimum_size = Vector2(0, 32)
	_party_toggle_btn.add_theme_font_size_override("font_size", 11)
	_party_toggle_btn.pressed.connect(_on_toggle_party_pressed)
	left_col.add_child(_party_toggle_btn)

	_lock_toggle_btn = Button.new()
	_lock_toggle_btn.text = "🔓 Khóa"
	_lock_toggle_btn.custom_minimum_size = Vector2(0, 32)
	_lock_toggle_btn.add_theme_font_size_override("font_size", 11)
	_lock_toggle_btn.pressed.connect(_on_toggle_lock_pressed)
	left_col.add_child(_lock_toggle_btn)

	# ==============================================================================
	# COLUMN 2: CENTER STAGE 3D PEDESTAL
	# ==============================================================================
	var pedestal_card := PanelContainer.new()
	pedestal_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pedestal_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.06, 0.10, 0.94)
	pstyle.border_width_left = 1
	pstyle.border_width_top = 1
	pstyle.border_width_right = 1
	pstyle.border_width_bottom = 1
	pstyle.border_color = Color(0.20, 0.35, 0.58, 0.45)
	pstyle.corner_radius_top_left = 10
	pstyle.corner_radius_top_right = 10
	pstyle.corner_radius_bottom_left = 10
	pstyle.corner_radius_bottom_right = 10
	pedestal_card.add_theme_stylebox_override("panel", pstyle)
	hsr_layout.add_child(pedestal_card)

	var ped_vbox := VBoxContainer.new()
	ped_vbox.add_theme_constant_override("separation", 6)
	ped_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ped_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pedestal_card.add_child(ped_vbox)

	var stage_stack := Control.new()
	stage_stack.custom_minimum_size = Vector2(420, 480)
	stage_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ped_vbox.add_child(stage_stack)

	var sub_vp_container := SubViewportContainer.new()
	sub_vp_container.stretch = true
	sub_vp_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage_stack.add_child(sub_vp_container)

	var sub_vp := SubViewport.new()
	sub_vp.own_world_3d = true
	sub_vp.transparent_bg = false
	sub_vp.msaa_3d = Viewport.MSAA_4X
	sub_vp_container.add_child(sub_vp)

	_build_3d_pedestal_scene(sub_vp)

	# Equipment Slots Symmetrical Overlay around 3D Unit
	_pedestal_equipment_overlay = MarginContainer.new()
	_pedestal_equipment_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pedestal_equipment_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pedestal_equipment_overlay.add_theme_constant_override("margin_left", 4)
	_pedestal_equipment_overlay.add_theme_constant_override("margin_top", 10)
	_pedestal_equipment_overlay.add_theme_constant_override("margin_right", 4)
	_pedestal_equipment_overlay.add_theme_constant_override("margin_bottom", 10)
	_pedestal_equipment_overlay.visible = false
	stage_stack.add_child(_pedestal_equipment_overlay)

	var overlay_hbox := HBoxContainer.new()
	overlay_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pedestal_equipment_overlay.add_child(overlay_hbox)

	_pedestal_left_slots_vbox = VBoxContainer.new()
	_pedestal_left_slots_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pedestal_left_slots_vbox.add_theme_constant_override("separation", 6)
	_pedestal_left_slots_vbox.custom_minimum_size = Vector2(88, 0)
	overlay_hbox.add_child(_pedestal_left_slots_vbox)

	var overlay_center_spacer := Control.new()
	overlay_center_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_center_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_hbox.add_child(overlay_center_spacer)

	_pedestal_right_slots_vbox = VBoxContainer.new()
	_pedestal_right_slots_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pedestal_right_slots_vbox.add_theme_constant_override("separation", 6)
	_pedestal_right_slots_vbox.custom_minimum_size = Vector2(88, 0)
	overlay_hbox.add_child(_pedestal_right_slots_vbox)

	var ped_btn_row := HBoxContainer.new()
	ped_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ped_btn_row.add_theme_constant_override("separation", 8)
	ped_vbox.add_child(ped_btn_row)

	var rot_btn := Button.new()
	rot_btn.text = "🔄 Xoay 3D"
	rot_btn.custom_minimum_size = Vector2(95, 28)
	rot_btn.add_theme_font_size_override("font_size", 10)
	rot_btn.pressed.connect(func(): _auto_rotate_3d = not _auto_rotate_3d)
	ped_btn_row.add_child(rot_btn)

	var set_btn := Button.new()
	set_btn.text = "✨ Chi Tiết Bộ Set"
	set_btn.custom_minimum_size = Vector2(125, 28)
	set_btn.add_theme_font_size_override("font_size", 10)
	set_btn.modulate = Color(1.0, 0.88, 0.40)
	set_btn.pressed.connect(_open_set_bonus_modal)
	ped_btn_row.add_child(set_btn)

	var atk_btn := Button.new()
	atk_btn.text = "⚔️ Đòn Đánh"
	atk_btn.custom_minimum_size = Vector2(95, 28)
	atk_btn.add_theme_font_size_override("font_size", 10)
	atk_btn.pressed.connect(_on_preview_attack_3d)
	ped_btn_row.add_child(atk_btn)

	# ==============================================================================
	# COLUMN 3: RIGHT PANEL (Header, Active Tab Scroll, and Ascend Button)
	# ==============================================================================
	var right_card := PanelContainer.new()
	right_card.custom_minimum_size = Vector2(480, 0)
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rstyle := StyleBoxFlat.new()
	rstyle.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	rstyle.border_width_left = 1
	rstyle.border_width_top = 1
	rstyle.border_width_right = 1
	rstyle.border_width_bottom = 1
	rstyle.border_color = Color(0.25, 0.38, 0.55, 0.6)
	rstyle.corner_radius_top_left = 10
	rstyle.corner_radius_top_right = 10
	rstyle.corner_radius_bottom_left = 10
	rstyle.corner_radius_bottom_right = 10
	right_card.add_theme_stylebox_override("panel", rstyle)
	hsr_layout.add_child(right_card)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 14)
	right_margin.add_theme_constant_override("margin_top", 10)
	right_margin.add_theme_constant_override("margin_right", 14)
	right_margin.add_theme_constant_override("margin_bottom", 10)
	right_card.add_child(right_margin)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_margin.add_child(right_vbox)

	var r_head_row := HBoxContainer.new()
	r_head_row.add_theme_constant_override("separation", 6)
	right_vbox.add_child(r_head_row)

	hero_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero_name_label.add_theme_font_size_override("font_size", 22)
	r_head_row.add_child(hero_name_label)

	_detail_close_btn = Button.new()
	_detail_close_btn.text = "✕"
	_detail_close_btn.custom_minimum_size = Vector2(34, 30)
	_detail_close_btn.add_theme_font_size_override("font_size", 14)
	_detail_close_btn.pressed.connect(_close_hero_detail)
	r_head_row.add_child(_detail_close_btn)

	if header_stats_row != null:
		right_vbox.add_child(header_stats_row)

	right_vbox.add_child(HSeparator.new())

	_tab_content_scroll = ScrollContainer.new()
	_tab_content_scroll.clip_contents = true
	_tab_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tab_content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_tab_content_scroll)

	_tab_content_vbox = VBoxContainer.new()
	_tab_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_content_vbox.add_theme_constant_override("separation", 8)
	_tab_content_scroll.add_child(_tab_content_vbox)

	right_vbox.add_child(HSeparator.new())

	open_promote_btn.custom_minimum_size = Vector2(0, 44)
	open_promote_btn.add_theme_font_size_override("font_size", 15)
	right_vbox.add_child(open_promote_btn)

	_build_stats_detail_modal()
	_build_set_bonus_modal()

	# 3. Convert PromotePanel into a Centered Modal Overlay so it never pushes MainLayout off-screen
	if promote_panel != null:
		_promote_modal_backdrop = ColorRect.new()
		_promote_modal_backdrop.name = "PromoteModalBackdrop"
		_promote_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_promote_modal_backdrop.color = Color(0.03, 0.05, 0.09, 0.84)
		_promote_modal_backdrop.visible = false
		add_child(_promote_modal_backdrop)

		var modal_center := CenterContainer.new()
		modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
		_promote_modal_backdrop.add_child(modal_center)

		var old_parent := promote_panel.get_parent()
		if old_parent != null:
			old_parent.remove_child(promote_panel)
		modal_center.add_child(promote_panel)

		promote_panel.visible = true
		promote_panel.clip_contents = true
		promote_panel.custom_minimum_size = Vector2(560, 470)
		var mstyle := StyleBoxFlat.new()
		mstyle.bg_color = Color(0.08, 0.11, 0.17, 0.98)
		mstyle.border_width_left = 2
		mstyle.border_width_top = 2
		mstyle.border_width_right = 2
		mstyle.border_width_bottom = 2
		mstyle.border_color = Color(1.0, 0.85, 0.28, 0.92)
		mstyle.corner_radius_top_left = 10
		mstyle.corner_radius_top_right = 10
		mstyle.corner_radius_bottom_left = 10
		mstyle.corner_radius_bottom_right = 10
		promote_panel.add_theme_stylebox_override("panel", mstyle)

	var promote_vbox: VBoxContainer = fodder_item_list.get_parent()
	promote_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promote_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promote_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fodder_item_list.custom_minimum_size = Vector2(0, 110)

	_auto_pick_fodder_btn = Button.new()
	_auto_pick_fodder_btn.text = "⚡ Tự Động Chọn Đủ Phôi Hiến Tế"
	_auto_pick_fodder_btn.custom_minimum_size = Vector2(0, 34)
	_auto_pick_fodder_btn.clip_text = true
	_auto_pick_fodder_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_auto_pick_fodder_btn.pressed.connect(_on_auto_pick_fodders_pressed)
	promote_vbox.add_child(_auto_pick_fodder_btn)
	promote_vbox.move_child(_auto_pick_fodder_btn, fodder_item_list.get_index() + 1)

	_quick_level_for_promote_btn = Button.new()
	_quick_level_for_promote_btn.text = "📘 Đọc Sách EXP Để Đạt Cấp Tối Đa Ngay"
	_quick_level_for_promote_btn.custom_minimum_size = Vector2(0, 34)
	_quick_level_for_promote_btn.clip_text = true
	_quick_level_for_promote_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_quick_level_for_promote_btn.visible = false
	_quick_level_for_promote_btn.pressed.connect(_on_quick_level_up_hero)
	promote_vbox.add_child(_quick_level_for_promote_btn)
	promote_vbox.move_child(_quick_level_for_promote_btn, 3)

	confirm_promote_btn.clip_text = true
	confirm_promote_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	close_promote_btn.text = "✖ Đóng Cửa Sổ Thăng Sao"

	# 4. Construct Awaken Bloodline Modal (Khung Nghi Thức Thức Tỉnh Huyết Mạch)
	_build_awaken_modal()

	# 5. Construct Breakthrough Modal (Khung Nghi Thức Đột Phá Cấp Độ)
	_build_breakthrough_modal()

func _build_stats_detail_modal() -> void:
	_stats_detail_modal_backdrop = ColorRect.new()
	_stats_detail_modal_backdrop.name = "StatsDetailModalBackdrop"
	_stats_detail_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_detail_modal_backdrop.color = Color(0.03, 0.05, 0.09, 0.88)
	_stats_detail_modal_backdrop.visible = false
	add_child(_stats_detail_modal_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_detail_modal_backdrop.add_child(center)

	_stats_detail_panel = PanelContainer.new()
	_stats_detail_panel.custom_minimum_size = Vector2(620, 560)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.07, 0.10, 0.16, 0.98)
	mstyle.border_width_left = 2
	mstyle.border_width_top = 2
	mstyle.border_width_right = 2
	mstyle.border_width_bottom = 2
	mstyle.border_color = Color(0.35, 0.75, 1.0, 0.92)
	mstyle.corner_radius_top_left = 10
	mstyle.corner_radius_top_right = 10
	mstyle.corner_radius_bottom_left = 10
	mstyle.corner_radius_bottom_right = 10
	_stats_detail_panel.add_theme_stylebox_override("panel", mstyle)
	center.add_child(_stats_detail_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	_stats_detail_panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	var header_row := HBoxContainer.new()
	root_vbox.add_child(header_row)

	var title_lbl := Label.new()
	title_lbl.text = "📊 BẢNG TOÀN BỘ CHỈ SỐ ANH HÙNG"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_lbl)

	var close_x := Button.new()
	close_x.text = "✖"
	close_x.custom_minimum_size = Vector2(34, 30)
	close_x.pressed.connect(func(): _stats_detail_modal_backdrop.visible = false)
	header_row.add_child(close_x)

	root_vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	_stats_detail_vbox = VBoxContainer.new()
	_stats_detail_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_detail_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_stats_detail_vbox)

	var bottom_close_btn := Button.new()
	bottom_close_btn.text = "✖ Đóng Cửa Sổ Chi Tiết"
	bottom_close_btn.custom_minimum_size = Vector2(0, 36)
	bottom_close_btn.pressed.connect(func(): _stats_detail_modal_backdrop.visible = false)
	root_vbox.add_child(bottom_close_btn)

func _open_stats_detail_modal() -> void:
	if _stats_detail_modal_backdrop == null:
		return
	_stats_detail_modal_backdrop.visible = true
	_populate_stats_detail_modal()

func _populate_stats_detail_modal() -> void:
	if _stats_detail_vbox == null or _selected_hero.is_empty():
		return
	for c in _stats_detail_vbox.get_children():
		c.queue_free()

	var h := _selected_hero
	var hid := str(h.get("id", ""))
	var hname := str(h.get("name", "Hero"))

	var eff_base: Dictionary = h.get("effectiveBaseStats", {}) if h.get("effectiveBaseStats") is Dictionary else {}
	var b_str := int(eff_base.get("str", h.get("baseStr", 10)))
	var b_int := int(eff_base.get("int", h.get("baseInt", 10)))
	var b_sta := int(eff_base.get("sta", h.get("baseSta", 10)))
	var b_agi := int(eff_base.get("agi", h.get("baseAgi", 10)))

	var train_stats: Dictionary = h.get("trainingStats", {}) if h.get("trainingStats") is Dictionary else {}
	var t_str := int(train_stats.get("str", 0))
	var t_int := int(train_stats.get("int", 0))
	var t_sta := int(train_stats.get("sta", 0))
	var t_agi := int(train_stats.get("agi", 0))

	# Section 1: 4 Chỉ Số Gốc & Huấn Luyện
	var sec1_lbl := Label.new()
	sec1_lbl.text = "💪 4 CHỈ SỐ GỐC COMBAT V2 (GỐC + HUẤN LUYỆN + ẤN KÝ + TRANG BỊ)"
	sec1_lbl.add_theme_font_size_override("font_size", 14)
	sec1_lbl.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
	_stats_detail_vbox.add_child(sec1_lbl)

	var base_stats_lbl := Label.new()
	base_stats_lbl.text = "• STR (Sức mạnh): %d (+%d HL)   |   • INT (Trí tuệ): %d (+%d HL)\n• STA (Thể chất): %d (+%d HL)   |   • AGI (Nhanh nhẹn): %d (+%d HL)" % [
		b_str, t_str, b_int, t_int, b_sta, t_sta, b_agi, t_agi
	]
	base_stats_lbl.add_theme_font_size_override("font_size", 13)
	base_stats_lbl.add_theme_color_override("font_color", Color(0.92, 0.96, 0.88))
	_stats_detail_vbox.add_child(base_stats_lbl)

	var train_grid := GridContainer.new()
	train_grid.columns = 4
	train_grid.add_theme_constant_override("h_separation", 6)
	train_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for st in [
		{"code": "str", "label": "💪 +1 STR"},
		{"code": "int", "label": "🔮 +1 INT"},
		{"code": "sta", "label": "🛡️ +1 STA"},
		{"code": "agi", "label": "⚡ +1 AGI"}
	]:
		var scode := str(st["code"])
		var btn := Button.new()
		btn.text = str(st["label"])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func():
			await _on_train_stat_pressed(hid, hname, scode)
			_populate_stats_detail_modal()
		)
		train_grid.add_child(btn)
	_stats_detail_vbox.add_child(train_grid)

	_stats_detail_vbox.add_child(HSeparator.new())

	# Section 2: Combat & Survival Stats
	var sec2_lbl := Label.new()
	sec2_lbl.text = "⚔️ TOÀN BỘ CHỈ SỐ CHIẾN ĐẤU THỰC CHIẾN & SINH TỒN"
	sec2_lbl.add_theme_font_size_override("font_size", 14)
	sec2_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42))
	_stats_detail_vbox.add_child(sec2_lbl)

	var d_stats: Dictionary = h.get("derivedStats", {}) if h.get("derivedStats") is Dictionary else {}
	var v2_stats: Dictionary = h.get("v2Stats", {}) if h.get("v2Stats") is Dictionary else {}
	var hp := int(d_stats.get("hp", h.get("hp", 100)))
	var max_hp := int(d_stats.get("maxHp", h.get("maxHp", 100)))
	var mp := int(h.get("mp", 100))
	var max_mp := int(h.get("maxMp", 100))
	var atk := int(d_stats.get("attack", h.get("attack", 10)))
	var def_val := int(d_stats.get("defense", h.get("defense", 10)))
	var spd := int(d_stats.get("speed", h.get("speed", 10)))
	var matk := int(v2_stats.get("matk", 0))
	var mdef := int(v2_stats.get("mdef", 0))

	var crit_raw := float(v2_stats.get("critRate", 5.0))
	var crit_pct := crit_raw * 100.0 if (crit_raw <= 1.0 and crit_raw > 0.0) else crit_raw
	var crit_dmg_raw := float(v2_stats.get("critDamage", 150.0))
	var crit_dmg := crit_dmg_raw * 100.0 if (crit_dmg_raw <= 3.0 and crit_dmg_raw > 0.0) else crit_dmg_raw
	var eva_raw := float(v2_stats.get("evasion", 0.0))
	var eva_pct := eva_raw * 100.0 if (eva_raw <= 1.0 and eva_raw > 0.0) else eva_raw

	var combat_info := Label.new()
	combat_info.text = (
		"• Sinh lực (HP): %s / %s   |   • Năng lượng (MP): %s / %s\n" % [_format_num(hp), _format_num(max_hp), _format_num(mp), _format_num(max_mp)] +
		"• Tấn công vật lý (ATK): %s   |   • Phòng thủ vật lý (DEF): %s\n" % [_format_num(atk), _format_num(def_val)] +
		"• Tốc độ xuất chiêu (SPD): %s\n" % _format_num(spd) +
		("• Công phép (MATK): %s   |   • Kháng phép (MDEF): %s\n" % [_format_num(matk), _format_num(mdef)] if (matk > 0 or mdef > 0) else "") +
		"• Tỷ lệ Bạo kích: %.1f%%   |   • Sát thương Bạo kích: %.0f%%\n" % [crit_pct, crit_dmg] +
		"• Khả năng Né tránh: %.1f%%" % eva_pct
	)
	combat_info.add_theme_font_size_override("font_size", 13)
	combat_info.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
	_stats_detail_vbox.add_child(combat_info)

	# Section 3: 7-Element Affinity Matrix
	_stats_detail_vbox.add_child(HSeparator.new())
	var sec3_lbl := Label.new()
	sec3_lbl.text = "🔮 BẢNG CHỈ SỐ TƯƠNG THÍCH 7 NGUYÊN TỐ (ELEMENTAL AFFINITY)"
	sec3_lbl.add_theme_font_size_override("font_size", 14)
	sec3_lbl.add_theme_color_override("font_color", Color(0.82, 0.65, 1.0))
	_stats_detail_vbox.add_child(sec3_lbl)

	var aff_dict: Dictionary = h.get("elementAffinities", {}) if h.get("elementAffinities") is Dictionary else {}
	var elem_defs := [
		{"key": "FIRE", "label": "🔥 Hỏa (Fire)", "col": Color(1.0, 0.45, 0.28), "def_val": 60},
		{"key": "WATER", "label": "💧 Thủy (Water)", "col": Color(0.32, 0.78, 1.0), "def_val": 45},
		{"key": "WIND", "label": "🌪️ Phong (Wind)", "col": Color(0.45, 0.96, 0.68), "def_val": 40},
		{"key": "EARTH", "label": "🪨 Địa (Earth)", "col": Color(0.88, 0.72, 0.42), "def_val": 35},
		{"key": "LIGHT", "label": "☀️ Quang (Light)", "col": Color(1.0, 0.92, 0.38), "def_val": 50},
		{"key": "DARK", "label": "🌑 Ám (Dark)", "col": Color(0.78, 0.52, 1.0), "def_val": 30},
		{"key": "LIGHTNING", "label": "⚡ Lôi (Lightning)", "col": Color(0.55, 0.88, 1.0), "def_val": 55}
	]
	var elem_grid := GridContainer.new()
	elem_grid.columns = 2
	elem_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elem_grid.add_theme_constant_override("h_separation", 6)
	elem_grid.add_theme_constant_override("v_separation", 4)
	for ed in elem_defs:
		var ekey := str(ed["key"])
		var eval := int(aff_dict.get(ekey, ed["def_val"]))
		var tier_str := "S" if eval >= 80 else ("A" if eval >= 60 else ("B" if eval >= 40 else "C"))

		var ecard := PanelContainer.new()
		ecard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var estyle := StyleBoxFlat.new()
		estyle.bg_color = Color(0.09, 0.12, 0.19, 0.92)
		estyle.border_width_left = 3
		estyle.border_color = ed["col"]
		estyle.corner_radius_top_left = 4
		estyle.corner_radius_bottom_left = 4
		ecard.add_theme_stylebox_override("panel", estyle)

		var em := MarginContainer.new()
		em.add_theme_constant_override("margin_left", 8)
		em.add_theme_constant_override("margin_right", 8)
		em.add_theme_constant_override("margin_top", 4)
		em.add_theme_constant_override("margin_bottom", 4)
		ecard.add_child(em)

		var eh := HBoxContainer.new()
		eh.add_theme_constant_override("separation", 6)
		em.add_child(eh)

		var elbl := Label.new()
		elbl.text = ed["label"]
		elbl.add_theme_font_size_override("font_size", 12)
		elbl.add_theme_color_override("font_color", ed["col"])
		elbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eh.add_child(elbl)

		var vlbl := Label.new()
		vlbl.text = "%d điểm [Hạng %s]" % [eval, tier_str]
		vlbl.add_theme_font_size_override("font_size", 12)
		vlbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		eh.add_child(vlbl)

		elem_grid.add_child(ecard)
	_stats_detail_vbox.add_child(elem_grid)

func _build_set_bonus_modal() -> void:
	_set_bonus_modal_backdrop = ColorRect.new()
	_set_bonus_modal_backdrop.name = "SetBonusModalBackdrop"
	_set_bonus_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_bonus_modal_backdrop.color = Color(0.03, 0.05, 0.09, 0.88)
	_set_bonus_modal_backdrop.visible = false
	add_child(_set_bonus_modal_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_bonus_modal_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(660, 480)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.07, 0.10, 0.16, 0.98)
	mstyle.border_width_left = 2
	mstyle.border_width_top = 2
	mstyle.border_width_right = 2
	mstyle.border_width_bottom = 2
	mstyle.border_color = Color(1.0, 0.82, 0.35, 0.95)
	mstyle.corner_radius_top_left = 10
	mstyle.corner_radius_top_right = 10
	mstyle.corner_radius_bottom_left = 10
	mstyle.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", mstyle)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root_vbox)

	var header_row := HBoxContainer.new()
	root_vbox.add_child(header_row)

	var title_lbl := Label.new()
	title_lbl.text = "✨ CHI TIẾT THUỘC TÍNH BỘ SET TRANG BỊ"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_lbl)

	var close_x := Button.new()
	close_x.text = "✖"
	close_x.custom_minimum_size = Vector2(34, 30)
	close_x.pressed.connect(func(): _set_bonus_modal_backdrop.visible = false)
	header_row.add_child(close_x)

	root_vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	_set_bonus_vbox = VBoxContainer.new()
	_set_bonus_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_bonus_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(_set_bonus_vbox)

	var bottom_close_btn := Button.new()
	bottom_close_btn.text = "✖ Đóng Cửa Sổ Bộ Set"
	bottom_close_btn.custom_minimum_size = Vector2(0, 36)
	bottom_close_btn.pressed.connect(func(): _set_bonus_modal_backdrop.visible = false)
	root_vbox.add_child(bottom_close_btn)

func _open_set_bonus_modal() -> void:
	if _set_bonus_modal_backdrop == null:
		return
	_set_bonus_modal_backdrop.visible = true
	_populate_set_bonus_modal()

func _populate_set_bonus_modal() -> void:
	if _set_bonus_vbox == null or _selected_hero.is_empty():
		return
	for c in _set_bonus_vbox.get_children():
		c.queue_free()

	var hid: String = str(_selected_hero.get("id", ""))
	var hname: String = str(_selected_hero.get("name", "Hero"))
	var equips: Dictionary = _get_hero_equipped_items_map(hid)

	var hero_subhead := Label.new()
	hero_subhead.text = "🛡️ Tướng: %s • Phẩm chất: %d★" % [hname, int(_selected_hero.get("rarity", 1))]
	hero_subhead.add_theme_font_size_override("font_size", 12)
	hero_subhead.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	_set_bonus_vbox.add_child(hero_subhead)

	var sig_slots: Array = ["HELMET", "CHEST", "BELT", "PANTS", "BOOTS", "MAIN_HAND"]
	var rad_slots: Array = ["NECKLACE", "SHOULDER", "RING", "GLOVES", "ACCESSORY", "OFF_HAND"]

	var sig_count := 0
	var rad_count := 0

	var sig_hp := 0
	var sig_atk := 0
	var sig_def := 0
	var sig_spd := 0
	var sig_matk := 0

	var rad_crit := 0.0
	var rad_cdmg := 0.0
	var rad_eva := 0.0
	var rad_ls := 0
	var rad_dr := 0
	var rad_pen := 0

	for s_k in equips.keys():
		var it: Dictionary = equips[s_k] as Dictionary
		var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else it
		var enh: int = _extract_item_enhance_level(it)
		var enh_b: float = 1.0 + float(enh) * 0.05
		var v2: Dictionary = tmpl.get("v2Stats", {}) if tmpl.get("v2Stats") is Dictionary else {}

		if s_k in sig_slots:
			sig_count += 1
			sig_hp += int(float(tmpl.get("bonusHp", 0)) * enh_b)
			sig_atk += int(float(tmpl.get("bonusAttack", tmpl.get("atkBonus", 0))) * enh_b)
			sig_def += int(float(tmpl.get("bonusDefense", tmpl.get("defBonus", 0))) * enh_b)
			sig_spd += int(tmpl.get("bonusSpeed", tmpl.get("spdBonus", 0)))
			sig_matk += int(float(tmpl.get("bonusMatk", 0)) * enh_b)
		elif s_k in rad_slots:
			rad_count += 1
			rad_crit += float(v2.get("critRate", 0.0))
			rad_cdmg += float(v2.get("critDamage", 0.0))
			rad_eva += float(v2.get("evasion", 0.0))
			rad_ls += int(v2.get("lifesteal", 0))
			rad_dr += int(v2.get("damageReduction", 0))
			rad_pen += int(v2.get("armorPen", v2.get("magicPen", 0)))

	var cols_split := HBoxContainer.new()
	cols_split.add_theme_constant_override("separation", 14)
	cols_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_set_bonus_vbox.add_child(cols_split)

	# --- COLUMN 1: BỘ CHỮ KÝ ---
	var sig_card := PanelContainer.new()
	sig_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	s_style.border_width_left = 2
	s_style.border_color = Color(1.0, 0.85, 0.40, 0.9)
	s_style.corner_radius_top_left = 6
	s_style.corner_radius_top_right = 6
	s_style.corner_radius_bottom_left = 6
	s_style.corner_radius_bottom_right = 6
	sig_card.add_theme_stylebox_override("panel", s_style)
	cols_split.add_child(sig_card)

	var s_m := MarginContainer.new()
	s_m.add_theme_constant_override("margin_left", 10)
	s_m.add_theme_constant_override("margin_top", 10)
	s_m.add_theme_constant_override("margin_right", 10)
	s_m.add_theme_constant_override("margin_bottom", 10)
	sig_card.add_child(s_m)

	var s_vbox := VBoxContainer.new()
	s_vbox.add_theme_constant_override("separation", 6)
	s_m.add_child(s_vbox)

	var s_head := Label.new()
	s_head.text = "📜 BỘ TRANG BỊ CHỮ KÝ"
	s_head.add_theme_font_size_override("font_size", 13)
	s_head.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	s_vbox.add_child(s_head)

	var s_cnt := Label.new()
	s_cnt.text = "Đang kích hoạt: %d / 6 món" % sig_count
	s_cnt.add_theme_font_size_override("font_size", 11)
	s_cnt.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if sig_count >= 2 else Color(0.7, 0.75, 0.85))
	s_vbox.add_child(s_cnt)

	s_vbox.add_child(HSeparator.new())

	var s_stats_lbl := Label.new()
	s_stats_lbl.text = "Chỉ số từ trang bị chữ ký:\n• ❤️ HP: +%d\n• ⚔️ Công Vật Lý (ATK): +%d\n• 🛡️ Phòng Ngự (DEF): +%d\n• 💨 Tốc Độ (SPD): +%d\n• 🔮 Công Phép (MATK): +%d" % [sig_hp, sig_atk, sig_def, sig_spd, sig_matk]
	s_stats_lbl.add_theme_font_size_override("font_size", 11)
	s_stats_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	s_vbox.add_child(s_stats_lbl)

	s_vbox.add_child(HSeparator.new())

	var s_bonuses := [
		{"need": 2, "desc": "Bộ 2 món: Tăng 10% Tấn Công & Phòng Thủ"},
		{"need": 4, "desc": "Bộ 4 món: Tăng 15% Max HP & Sát thương Kỹ năng"},
		{"need": 6, "desc": "Bộ 6 món: Khai phóng Chữ Ký (+20% Toàn Diện)"}
	]
	for b in s_bonuses:
		var act: bool = (sig_count >= int(b["need"]))
		var b_lbl := Label.new()
		b_lbl.text = "%s %s" % [("✅" if act else "🔒"), str(b["desc"])]
		b_lbl.add_theme_font_size_override("font_size", 10)
		b_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if act else Color(0.55, 0.6, 0.7))
		s_vbox.add_child(b_lbl)

	# --- COLUMN 2: BỘ LẤP LÁNH ---
	var rad_card := PanelContainer.new()
	rad_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
	r_style.border_width_left = 2
	r_style.border_color = Color(0.35, 0.85, 1.0, 0.9)
	r_style.corner_radius_top_left = 6
	r_style.corner_radius_top_right = 6
	r_style.corner_radius_bottom_left = 6
	r_style.corner_radius_bottom_right = 6
	rad_card.add_theme_stylebox_override("panel", r_style)
	cols_split.add_child(rad_card)

	var r_m := MarginContainer.new()
	r_m.add_theme_constant_override("margin_left", 10)
	r_m.add_theme_constant_override("margin_top", 10)
	r_m.add_theme_constant_override("margin_right", 10)
	r_m.add_theme_constant_override("margin_bottom", 10)
	rad_card.add_child(r_m)

	var r_vbox := VBoxContainer.new()
	r_vbox.add_theme_constant_override("separation", 6)
	r_m.add_child(r_vbox)

	var r_head := Label.new()
	r_head.text = "✨ BỘ TRANG BỊ LẤP LÁNH"
	r_head.add_theme_font_size_override("font_size", 13)
	r_head.add_theme_color_override("font_color", Color(0.45, 0.9, 1.0))
	r_vbox.add_child(r_head)

	var r_cnt := Label.new()
	r_cnt.text = "Đang kích hoạt: %d / 6 món" % rad_count
	r_cnt.add_theme_font_size_override("font_size", 11)
	r_cnt.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if rad_count >= 2 else Color(0.7, 0.75, 0.85))
	r_vbox.add_child(r_cnt)

	r_vbox.add_child(HSeparator.new())

	var r_stats_lbl := Label.new()
	r_stats_lbl.text = "Chỉ số từ trang bị lấp lánh:\n• 💥 Tỷ Lệ Bạo Kích: +%.1f%%\n• ⚡ ST Bạo Kích: +%.1f%%\n• 🌀 Né Tránh: +%.1f%%\n• 🩸 Hút Máu: +%d%%\n• 🛡️ Giảm ST: +%d%%\n• 🗡️ Xuyên Giáp/Phép: +%d" % [rad_crit, rad_cdmg, rad_eva, rad_ls, rad_dr, rad_pen]
	r_stats_lbl.add_theme_font_size_override("font_size", 11)
	r_stats_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	r_vbox.add_child(r_stats_lbl)

	r_vbox.add_child(HSeparator.new())

	var r_bonuses := [
		{"need": 2, "desc": "Bộ 2 món: +8% Bạo Kích & Né Tránh"},
		{"need": 4, "desc": "Bộ 4 món: +12% Hút Máu & Giảm Sát Thương"},
		{"need": 6, "desc": "Bộ 6 món: Hào Quang Thần Thánh (Khiên hộ mệnh khi HP < 30%)"}
	]
	for b in r_bonuses:
		var act: bool = (rad_count >= int(b["need"]))
		var b_lbl := Label.new()
		b_lbl.text = "%s %s" % [("✅" if act else "🔒"), str(b["desc"])]
		b_lbl.add_theme_font_size_override("font_size", 10)
		b_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if act else Color(0.55, 0.6, 0.7))
		r_vbox.add_child(b_lbl)

	var tip_lbl := Label.new()
	tip_lbl.text = "💡 Mẹo: Trang bị đủ 2, 4 hoặc 6 món cùng hệ Bộ Chữ Ký hoặc Bộ Lấp Lánh để nhận hiệu ứng kích hoạt mạnh nhất."
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_font_size_override("font_size", 10)
	tip_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_set_bonus_vbox.add_child(tip_lbl)

func _build_awaken_modal() -> void:
	_awaken_modal_backdrop = ColorRect.new()
	_awaken_modal_backdrop.name = "AwakenModalBackdrop"
	_awaken_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_awaken_modal_backdrop.color = Color(0.03, 0.05, 0.09, 0.84)
	_awaken_modal_backdrop.visible = false
	add_child(_awaken_modal_backdrop)

	var modal_center := CenterContainer.new()
	modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_awaken_modal_backdrop.add_child(modal_center)

	_awaken_panel = PanelContainer.new()
	_awaken_panel.name = "AwakenPanel"
	_awaken_panel.clip_contents = true
	_awaken_panel.custom_minimum_size = Vector2(560, 480)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.08, 0.10, 0.17, 0.98)
	mstyle.border_width_left = 2
	mstyle.border_width_top = 2
	mstyle.border_width_right = 2
	mstyle.border_width_bottom = 2
	mstyle.border_color = Color(1.0, 0.78, 0.28, 0.95)
	mstyle.corner_radius_top_left = 10
	mstyle.corner_radius_top_right = 10
	mstyle.corner_radius_bottom_left = 10
	mstyle.corner_radius_bottom_right = 10
	_awaken_panel.add_theme_stylebox_override("panel", mstyle)
	modal_center.add_child(_awaken_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_awaken_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	_awaken_header_label = Label.new()
	_awaken_header_label.text = "NGHI THỨC THỨC TỈNH HUYẾT MẠCH"
	_awaken_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_awaken_header_label.add_theme_font_size_override("font_size", 16)
	_awaken_header_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
	vbox.add_child(_awaken_header_label)

	var sub_header := Label.new()
	sub_header.text = "Khai mở huyết mạch cổ đại • Ban Ấn Ký Huyết Mạch & Nâng Cấp Kỹ Năng"
	sub_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_header.add_theme_font_size_override("font_size", 12)
	sub_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(sub_header)

	vbox.add_child(HSeparator.new())

	_awaken_info_label = Label.new()
	_awaken_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_awaken_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_awaken_info_label.add_theme_font_size_override("font_size", 13)
	_awaken_info_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vbox.add_child(_awaken_info_label)

	vbox.add_child(HSeparator.new())

	_awaken_req_box = VBoxContainer.new()
	_awaken_req_box.add_theme_constant_override("separation", 6)
	_awaken_req_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_awaken_req_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_confirm_awaken_btn = Button.new()
	_confirm_awaken_btn.text = "🌟 Xác Nhận Thức Tỉnh Huyết Mạch"
	_confirm_awaken_btn.custom_minimum_size = Vector2(0, 42)
	_confirm_awaken_btn.pressed.connect(_on_confirm_awaken_pressed)
	vbox.add_child(_confirm_awaken_btn)

	_close_awaken_btn = Button.new()
	_close_awaken_btn.text = "✖ Đóng Cửa Sổ Thức Tỉnh"
	_close_awaken_btn.pressed.connect(func():
		if _awaken_modal_backdrop != null:
			_awaken_modal_backdrop.visible = false
	)
	vbox.add_child(_close_awaken_btn)

func _build_breakthrough_modal() -> void:
	_breakthrough_modal_backdrop = ColorRect.new()
	_breakthrough_modal_backdrop.name = "BreakthroughModalBackdrop"
	_breakthrough_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_breakthrough_modal_backdrop.color = Color(0.03, 0.05, 0.09, 0.84)
	_breakthrough_modal_backdrop.visible = false
	add_child(_breakthrough_modal_backdrop)

	var modal_center := CenterContainer.new()
	modal_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_breakthrough_modal_backdrop.add_child(modal_center)

	_breakthrough_panel = PanelContainer.new()
	_breakthrough_panel.name = "BreakthroughPanel"
	_breakthrough_panel.clip_contents = true
	_breakthrough_panel.custom_minimum_size = Vector2(560, 480)
	var mstyle := StyleBoxFlat.new()
	mstyle.bg_color = Color(0.08, 0.10, 0.17, 0.98)
	mstyle.border_width_left = 2
	mstyle.border_width_top = 2
	mstyle.border_width_right = 2
	mstyle.border_width_bottom = 2
	mstyle.border_color = Color(0.35, 0.85, 1.0, 0.95)
	mstyle.corner_radius_top_left = 10
	mstyle.corner_radius_top_right = 10
	mstyle.corner_radius_bottom_left = 10
	mstyle.corner_radius_bottom_right = 10
	_breakthrough_panel.add_theme_stylebox_override("panel", mstyle)
	modal_center.add_child(_breakthrough_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	_breakthrough_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	_breakthrough_header_label = Label.new()
	_breakthrough_header_label.text = "⚡ NGHI THỨC ĐỘT PHÁ CẤP ĐỘ (BREAKTHROUGH)"
	_breakthrough_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breakthrough_header_label.add_theme_font_size_override("font_size", 16)
	_breakthrough_header_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	vbox.add_child(_breakthrough_header_label)

	var sub_header := Label.new()
	sub_header.text = "Phá vỡ bình cảnh cấp độ • Mở rộng trần cấp +10 & Tăng trưởng thuộc tính"
	sub_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_header.add_theme_font_size_override("font_size", 12)
	sub_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(sub_header)

	vbox.add_child(HSeparator.new())

	_breakthrough_info_label = Label.new()
	_breakthrough_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_breakthrough_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_breakthrough_info_label.add_theme_font_size_override("font_size", 13)
	_breakthrough_info_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	vbox.add_child(_breakthrough_info_label)

	vbox.add_child(HSeparator.new())

	_breakthrough_req_box = VBoxContainer.new()
	_breakthrough_req_box.add_theme_constant_override("separation", 6)
	_breakthrough_req_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_breakthrough_req_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	_confirm_breakthrough_btn = Button.new()
	_confirm_breakthrough_btn.text = "⚡ Xác Nhận Đột Phá Cấp Độ"
	_confirm_breakthrough_btn.custom_minimum_size = Vector2(0, 42)
	_confirm_breakthrough_btn.pressed.connect(_on_confirm_breakthrough_pressed)
	vbox.add_child(_confirm_breakthrough_btn)

	_close_breakthrough_btn = Button.new()
	_close_breakthrough_btn.text = "✖ Đóng Cửa Sổ Đột Phá"
	_close_breakthrough_btn.pressed.connect(func():
		if _breakthrough_modal_backdrop != null:
			_breakthrough_modal_backdrop.visible = false
	)
	vbox.add_child(_close_breakthrough_btn)

func _build_3d_pedestal_scene(sub_vp: SubViewport) -> void:
	var root_3d := Node3D.new()
	sub_vp.add_child(root_3d)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.78, 0.95)
	env.ambient_light_energy = 0.95
	env_node.environment = env
	root_3d.add_child(env_node)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.15, 4.15)
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.05, 0.0), Vector3.UP)
	cam.fov = 42.0
	root_3d.add_child(cam)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42, 32, 0)
	key_light.light_color = Color(1.0, 0.96, 0.90)
	key_light.light_energy = 1.35
	root_3d.add_child(key_light)

	_pedestal_light = OmniLight3D.new()
	_pedestal_light.position = Vector3(0.0, 1.6, 1.2)
	_pedestal_light.light_color = Color(0.35, 0.82, 1.0)
	_pedestal_light.light_energy = 1.8
	_pedestal_light.omni_range = 6.0
	root_3d.add_child(_pedestal_light)

	_pedestal_pivot = Node3D.new()
	root_3d.add_child(_pedestal_pivot)

	# Stone Pedestal Base
	var base_mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05
	cyl.bottom_radius = 1.22
	cyl.height = 0.28
	base_mesh.mesh = cyl
	base_mesh.position = Vector3(0, -0.14, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.18, 0.22, 0.30)
	bmat.metallic = 0.35
	bmat.roughness = 0.55
	base_mesh.material_override = bmat
	_pedestal_pivot.add_child(base_mesh)

	# Glowing Rune Ring
	_pedestal_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.08
	torus.outer_radius = 1.20
	_pedestal_ring.mesh = torus
	_pedestal_ring.position = Vector3(0, 0.02, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.35, 0.85, 1.0)
	rmat.emission_enabled = true
	rmat.emission = Color(0.35, 0.85, 1.0)
	rmat.emission_energy_multiplier = 2.6
	_pedestal_ring.material_override = rmat
	root_3d.add_child(_pedestal_ring)

func _update_3d_pedestal_hero(h: Dictionary) -> void:
	if _pedestal_pivot == null:
		return
	if _pedestal_actor != null and is_instance_valid(_pedestal_actor):
		_pedestal_actor.queue_free()
		_pedestal_actor = null

	if h.is_empty():
		return

	_pedestal_actor = UnitActorScene.instantiate()
	_pedestal_pivot.add_child(_pedestal_actor)
	_pedestal_actor.position = Vector3.ZERO
	_pedestal_actor.setup_combat_unit({
		"id": str(h.get("id", "")),
		"name": str(h.get("name", "Hero")),
		"side": "HERO",
		"rarity": int(h.get("rarity", 1)),
		"classCode": str(h.get("classCode", h.get("heroClass", "WARRIOR"))),
		"hp": int(h.get("hp", 100)),
		"maxHp": int(h.get("maxHp", 100)),
		"mp": int(h.get("mp", 100)),
		"maxMp": int(h.get("maxMp", 100))
	})
	if _pedestal_actor.name_label != null:
		_pedestal_actor.name_label.visible = false
	if _pedestal_actor.hp_label != null:
		_pedestal_actor.hp_label.visible = false

	var star := int(h.get("rarity", 1))
	var aura_col := Color(0.35, 0.85, 1.0)
	if star >= 5:
		aura_col = Color(1.0, 0.84, 0.22)
	elif star == 4:
		aura_col = Color(0.84, 0.42, 1.0)
	elif star == 3:
		aura_col = Color(0.32, 0.92, 0.62)

	if _pedestal_light != null:
		_pedestal_light.light_color = aura_col
	if _pedestal_ring != null and _pedestal_ring.material_override is StandardMaterial3D:
		var rmat: StandardMaterial3D = _pedestal_ring.material_override
		rmat.albedo_color = aura_col
		rmat.emission = aura_col

func _on_preview_attack_3d() -> void:
	if _pedestal_actor != null and is_instance_valid(_pedestal_actor):
		var forward_pos := _pedestal_actor.global_position + Vector3(0, 0, 1.2)
		await _pedestal_actor.play_attack_towards(forward_pos)

func _play_3d_star_promotion_burst() -> void:
	if _pedestal_pivot == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.6
	torus.outer_radius = 0.85
	ring.mesh = torus
	ring.position = Vector3(0, 0.2, 0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.88, 0.25, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.22)
	mat.emission_energy_multiplier = 4.5
	ring.material_override = mat
	_pedestal_pivot.add_child(ring)

	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "position:y", 2.4, 0.85)
	tw.tween_property(ring, "scale", Vector3(2.2, 1.0, 2.2), 0.85)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.85)
	tw.chain().tween_callback(ring.queue_free)

# ==============================================================================
# HERO LIST & FILTERING
# ==============================================================================

func _update_sort_button_labels() -> void:
	var labels := [
		"🔥 Lực Chiến " + ("▲" if _grid_sort_ascending and _grid_sort_mode == 0 else "▼"),
		"📈 Cấp Độ " + ("▲" if _grid_sort_ascending and _grid_sort_mode == 1 else "▼"),
		"⭐ Sao " + ("▲" if _grid_sort_ascending and _grid_sort_mode == 2 else "▼"),
		"🔤 Tên " + ("Z-A ▼" if _grid_sort_ascending and _grid_sort_mode == 3 else "A-Z ▲")
	]
	for i in range(_sort_buttons.size()):
		if i < labels.size():
			_sort_buttons[i].text = labels[i]
			_sort_buttons[i].modulate = Color(1.0, 0.92, 0.42) if i == _grid_sort_mode else Color(0.82, 0.88, 0.96)

func _sort_filtered_heroes() -> void:
	match _grid_sort_mode:
		0: # Combat Power
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var cpa := int(a.get("combatPower", 0))
				var cpb := int(b.get("combatPower", 0))
				if cpa != cpb:
					return (cpa < cpb) if _grid_sort_ascending else (cpa > cpb)
				return int(a.get("level", 1)) > int(b.get("level", 1))
			)
		1: # Level
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var lva := int(a.get("level", 1))
				var lvb := int(b.get("level", 1))
				if lva != lvb:
					return (lva < lvb) if _grid_sort_ascending else (lva > lvb)
				return int(a.get("combatPower", 0)) > int(b.get("combatPower", 0))
			)
		2: # Rarity / Stars
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var sta := int(a.get("rarity", 1))
				var stb := int(b.get("rarity", 1))
				if sta != stb:
					return (sta < stb) if _grid_sort_ascending else (sta > stb)
				return int(a.get("combatPower", 0)) > int(b.get("combatPower", 0))
			)
		3: # Name A-Z / Z-A
			_filtered_heroes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var cmp := str(a.get("name", "")).nocasecmp_to(str(b.get("name", "")))
				return (cmp > 0) if _grid_sort_ascending else (cmp < 0)
			)

func _refresh_hero_list(preserve_hero_id: String = "") -> void:
	for i in range(_filter_buttons.size()):
		_filter_buttons[i].modulate = Color(1.0, 0.92, 0.42) if i == _roster_filter_mode else Color(0.82, 0.88, 0.96)
	_update_sort_button_labels()

	hero_item_list.clear()
	_filtered_heroes.clear()

	for h in GameState.heroes:
		if not (h is Dictionary):
			continue
		var hid := str(h.get("id", ""))
		var star := int(h.get("rarity", 1))
		var in_party := GameState.active_party_ids.has(hid)
		if _roster_filter_mode == 1 and not in_party:
			continue
		if _roster_filter_mode == 2 and star < 4:
			continue
		if _roster_filter_mode == 3 and star > 3:
			continue
		_filtered_heroes.append(h)

	_sort_filtered_heroes()

	if _grid_total_label != null:
		_grid_total_label.text = "TỔNG SỐ #%d" % _filtered_heroes.size()

	if _filtered_heroes.is_empty():
		status_label.text = "Không có Tướng nào khớp bộ lọc hiện tại."
		_selected_hero = {}
		_update_3d_pedestal_hero({})
		if not _in_detail_view:
			_render_hero_grid()
		return

	var select_idx := 0
	for i in range(_filtered_heroes.size()):
		var h: Dictionary = _filtered_heroes[i]
		var hid := str(h.get("id", ""))
		if preserve_hero_id != "" and hid == preserve_hero_id:
			select_idx = i
		elif preserve_hero_id == "" and not _selected_hero.is_empty() and hid == str(_selected_hero.get("id", "")):
			select_idx = i
		var star := int(h.get("rarity", 1))
		var lvl := int(h.get("level", 1))
		var max_lvl := int(h.get("maxLevel", star * 10))
		var in_party := GameState.active_party_ids.has(hid)
		var is_locked := bool(h.get("isLocked", false))
		var state_str := str(h.get("state", "ALIVE"))
		var prefix := ("⚔️ " if in_party else "") + ("🔒 " if is_locked else "")
		var state_tag := " [TỬ TRẬN]" if state_str == "DEAD" else (" [THƯƠNG NẶNG]" if state_str == "DISABLED" else "")
		var txt := "%s%s %s (Lv.%d/%d)%s" % [
			prefix,
			"★".repeat(clampi(star, 1, 7)),
			str(h.get("name", "Hero")),
			lvl,
			max_lvl,
			state_tag
		]
		hero_item_list.add_item(txt)

	hero_item_list.select(select_idx)
	_selected_hero = _filtered_heroes[select_idx]

	if _in_detail_view:
		_display_hero_details(_selected_hero)
		if _promote_modal_backdrop != null and _promote_modal_backdrop.visible:
			await _load_promote_preview()
		if _breakthrough_modal_backdrop != null and _breakthrough_modal_backdrop.visible:
			await _load_breakthrough_preview()
		if _awaken_modal_backdrop != null and _awaken_modal_backdrop.visible:
			await _load_awaken_preview()
	else:
		_render_hero_grid()

func _on_hero_selected(index: int) -> void:
	if index < 0 or index >= _filtered_heroes.size():
		return
	_selected_hero = _filtered_heroes[index]
	if _in_detail_view:
		_display_hero_details(_selected_hero)
		if _promote_modal_backdrop != null and _promote_modal_backdrop.visible:
			await _load_promote_preview()
		if _breakthrough_modal_backdrop != null and _breakthrough_modal_backdrop.visible:
			await _load_breakthrough_preview()
		if _awaken_modal_backdrop != null and _awaken_modal_backdrop.visible:
			await _load_awaken_preview()

func _open_hero_detail(h: Dictionary) -> void:
	_in_detail_view = true
	_selected_hero = h
	if _grid_view_container != null:
		_grid_view_container.visible = false
	if _main_layout != null:
		_main_layout.visible = true
	back_btn.text = "⬅ Quay lại Danh Sách Tướng"
	var title_lbl: Label = get_node_or_null("MarginContainer/VBoxContainer/TopBar/Title") as Label
	if title_lbl != null:
		title_lbl.text = "🛡️ CHI TIẾT ANH HÙNG: %s" % str(h.get("name", "Hero"))
	_display_hero_details(_selected_hero)
	status_label.text = "🛡️ Đang xem hồ sơ chi tiết [%s] — 3D Pedestal, Chỉ số, Kỹ năng, Ấn ký & Trang bị." % str(h.get("name", "Hero"))

func _close_hero_detail() -> void:
	if _stats_detail_modal_backdrop != null:
		_stats_detail_modal_backdrop.visible = false
	if _set_bonus_modal_backdrop != null:
		_set_bonus_modal_backdrop.visible = false
	_update_pedestal_equipment_overlay(false)
	_in_detail_view = false
	if _main_layout != null:
		_main_layout.visible = false
	if _grid_view_container != null:
		_grid_view_container.visible = true
	back_btn.text = "⬅ Về Căn Cứ 3D"
	var title_lbl: Label = get_node_or_null("MarginContainer/VBoxContainer/TopBar/Title") as Label
	if title_lbl != null:
		title_lbl.text = "🛡️ DOANH TRẠI TƯỚNG & THĂNG SAO (PICK ME UP STYLE)"
	_render_hero_grid()
	status_label.text = "🛡️ Doanh Trại sẵn sàng — Chọn Tướng để xem Mô hình 3D, Chỉ số, Kỹ năng, Ấn ký Imprint, Trang bị & Thăng Sao."

func _on_nav_prev_hero_pressed() -> void:
	if _filtered_heroes.is_empty():
		return
	var cur_id: String = str(_selected_hero.get("id", ""))
	var cur_idx: int = 0
	for i in range(_filtered_heroes.size()):
		if str(_filtered_heroes[i].get("id", "")) == cur_id:
			cur_idx = i
			break
	var prev_idx: int = (cur_idx - 1 + _filtered_heroes.size()) % _filtered_heroes.size()
	_selected_hero = _filtered_heroes[prev_idx]
	var title_lbl: Label = get_node_or_null("MarginContainer/VBoxContainer/TopBar/Title") as Label
	if title_lbl != null:
		title_lbl.text = "🛡️ CHI TIẾT ANH HÙNG: %s" % str(_selected_hero.get("name", "Hero"))
	_display_hero_details(_selected_hero)

func _on_nav_next_hero_pressed() -> void:
	if _filtered_heroes.is_empty():
		return
	var cur_id: String = str(_selected_hero.get("id", ""))
	var cur_idx: int = 0
	for i in range(_filtered_heroes.size()):
		if str(_filtered_heroes[i].get("id", "")) == cur_id:
			cur_idx = i
			break
	var next_idx: int = (cur_idx + 1) % _filtered_heroes.size()
	_selected_hero = _filtered_heroes[next_idx]
	var title_lbl: Label = get_node_or_null("MarginContainer/VBoxContainer/TopBar/Title") as Label
	if title_lbl != null:
		title_lbl.text = "🛡️ CHI TIẾT ANH HÙNG: %s" % str(_selected_hero.get("name", "Hero"))
	_display_hero_details(_selected_hero)

func _render_hero_grid() -> void:
	if _hero_grid_container == null:
		return
	for c in _hero_grid_container.get_children():
		c.queue_free()

	if _grid_total_label != null:
		_grid_total_label.text = "TỔNG SỐ #%d" % _filtered_heroes.size()

	for i in range(_filter_buttons.size()):
		_filter_buttons[i].modulate = Color(1.0, 0.92, 0.42) if i == _roster_filter_mode else Color(0.82, 0.88, 0.96)
	_update_sort_button_labels()

	if _filtered_heroes.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Không tìm thấy Tướng nào phù hợp bộ lọc hiện tại."
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		_hero_grid_container.add_child(empty_lbl)
		return

	for h in _filtered_heroes:
		if h is Dictionary:
			var card := _build_hero_card(h)
			_hero_grid_container.add_child(card)

func _draw_card_occult_rings(canvas: Control, rarity_col: Color) -> void:
	var c: Vector2 = canvas.size / 2.0
	var ring_col := Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.26)
	var thin_ring_col := Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.16)
	var spoke_col := Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.14)

	# Concentric summoning rings (Pick Me Up Tarot halo)
	canvas.draw_arc(c, 58.0, 0.0, TAU, 48, ring_col, 1.5, true)
	canvas.draw_arc(c, 44.0, 0.0, TAU, 36, thin_ring_col, 1.0, true)
	canvas.draw_arc(c, 30.0, 0.0, TAU, 28, thin_ring_col, 1.0, true)

	# Cardinal crosshair ticks
	canvas.draw_line(c - Vector2(66.0, 0.0), c - Vector2(50.0, 0.0), spoke_col, 1.2, true)
	canvas.draw_line(c + Vector2(50.0, 0.0), c + Vector2(66.0, 0.0), spoke_col, 1.2, true)
	canvas.draw_line(c - Vector2(0.0, 66.0), c - Vector2(0.0, 50.0), spoke_col, 1.2, true)
	canvas.draw_line(c + Vector2(0.0, 50.0), c + Vector2(0.0, 66.0), spoke_col, 1.2, true)

	# Diagonal occult ticks (45 deg)
	var d45 := Vector2(0.7071, 0.7071)
	canvas.draw_line(c + d45 * 52.0, c + d45 * 62.0, spoke_col, 1.0, true)
	canvas.draw_line(c - d45 * 52.0, c - d45 * 62.0, spoke_col, 1.0, true)
	var d135 := Vector2(-0.7071, 0.7071)
	canvas.draw_line(c + d135 * 52.0, c + d135 * 62.0, spoke_col, 1.0, true)
	canvas.draw_line(c - d135 * 52.0, c - d135 * 62.0, spoke_col, 1.0, true)

func _build_hero_card(h: Dictionary) -> Control:
	var hid: String = str(h.get("id", ""))
	var star: int = int(h.get("rarity", 1))
	var lvl: int = int(h.get("level", 1))
	var promo_rank: int = int(h.get("promotionRank", 0))
	var star_ceiling: int = int(h.get("starCeiling", star * 10))
	var max_lvl: int = int(h.get("maxLevel", mini(star_ceiling, (promo_rank + 1) * 10)))
	var cls: String = str(h.get("classCode", h.get("heroClass", "WARRIOR")))
	var elem: String = str(h.get("element", "NEUTRAL"))
	var awaken_rank: int = int(h.get("awakeningRank", 0))
	var in_party: bool = GameState.active_party_ids.has(hid)
	var is_locked: bool = bool(h.get("isLocked", false))
	var hname: String = str(h.get("name", "Hero"))
	var state_str: String = str(h.get("state", "ALIVE"))
	var rarity_col: Color = _get_rarity_border_color(star)

	var d_stats: Dictionary = h.get("derivedStats", {}) if h.get("derivedStats") is Dictionary else {}
	var atk: int = int(d_stats.get("attack", h.get("attack", 10)))
	var def_val: int = int(d_stats.get("defense", h.get("defense", 10)))
	var mhp: int = int(d_stats.get("maxHp", h.get("maxHp", 100)))
	var spd: int = int(d_stats.get("speed", h.get("speed", 10)))
	var cp: int = int(h.get("combatPower", mhp + atk * 4 + def_val * 3 + spd * 2))

	# Outer Card Panel (Pick Me Up Tarot proportions ~230x335)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(230, 335)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cstyle := StyleBoxFlat.new()
	cstyle.bg_color = Color(0.065, 0.075, 0.10, 0.98)
	cstyle.border_width_left = 3 if star >= 5 else 2
	cstyle.border_width_top = 3 if star >= 5 else 2
	cstyle.border_width_right = 3 if star >= 5 else 2
	cstyle.border_width_bottom = 3 if star >= 5 else 2
	cstyle.border_color = rarity_col
	cstyle.corner_radius_top_left = 10
	cstyle.corner_radius_top_right = 10
	cstyle.corner_radius_bottom_left = 10
	cstyle.corner_radius_bottom_right = 10
	cstyle.shadow_size = 6
	cstyle.shadow_color = Color(0, 0, 0, 0.55)
	card.add_theme_stylebox_override("panel", cstyle)

	# Inset margin for double-line ornate border
	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override("margin_left", 4)
	outer_margin.add_theme_constant_override("margin_top", 4)
	outer_margin.add_theme_constant_override("margin_right", 4)
	outer_margin.add_theme_constant_override("margin_bottom", 4)
	card.add_child(outer_margin)

	# Inner Inset Frame
	var inner_frame := PanelContainer.new()
	var if_style := StyleBoxFlat.new()
	if_style.bg_color = Color(0, 0, 0, 0)
	if_style.border_width_left = 1
	if_style.border_width_top = 1
	if_style.border_width_right = 1
	if_style.border_width_bottom = 1
	if_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.38)
	if_style.corner_radius_top_left = 6
	if_style.corner_radius_top_right = 6
	if_style.corner_radius_bottom_left = 6
	if_style.corner_radius_bottom_right = 6
	inner_frame.add_theme_stylebox_override("panel", if_style)
	outer_margin.add_child(inner_frame)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 6)
	content_margin.add_theme_constant_override("margin_top", 5)
	content_margin.add_theme_constant_override("margin_right", 6)
	content_margin.add_theme_constant_override("margin_bottom", 6)
	inner_frame.add_child(content_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(vbox)

	# 1. Header Row: Top Celestial Crest + Party/Lock Status
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 4)
	vbox.add_child(header_row)

	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer_left)

	# Top Center Celestial Compass Emblem (Pick Me Up tarot crest)
	var crest_lbl := Label.new()
	crest_lbl.text = "✦ ☼ ✦"
	crest_lbl.add_theme_font_size_override("font_size", 9)
	crest_lbl.add_theme_color_override("font_color", rarity_col.lerp(Color.WHITE, 0.25))
	header_row.add_child(crest_lbl)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer_right)

	if in_party:
		var party_pill := PanelContainer.new()
		var pp_style := StyleBoxFlat.new()
		pp_style.bg_color = Color(0.85, 0.20, 0.20, 0.95)
		pp_style.corner_radius_top_left = 3
		pp_style.corner_radius_top_right = 3
		pp_style.corner_radius_bottom_left = 3
		pp_style.corner_radius_bottom_right = 3
		party_pill.add_theme_stylebox_override("panel", pp_style)
		var pp_margin := MarginContainer.new()
		pp_margin.add_theme_constant_override("margin_left", 4)
		pp_margin.add_theme_constant_override("margin_right", 4)
		pp_margin.add_theme_constant_override("margin_top", 1)
		pp_margin.add_theme_constant_override("margin_bottom", 1)
		party_pill.add_child(pp_margin)
		var party_lbl := Label.new()
		party_lbl.text = "⚔️ PVE"
		party_lbl.add_theme_font_size_override("font_size", 8)
		party_lbl.add_theme_color_override("font_color", Color.WHITE)
		pp_margin.add_child(party_lbl)
		header_row.add_child(party_pill)

	if is_locked:
		var lock_lbl := Label.new()
		lock_lbl.text = "🔒"
		lock_lbl.add_theme_font_size_override("font_size", 10)
		header_row.add_child(lock_lbl)

	# 2. Hero Avatar Box with Concentric Occult Halo (Pick Me Up center arch)
	var avatar_box := PanelContainer.new()
	avatar_box.custom_minimum_size = Vector2(0, 155)
	avatar_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var ab_style := StyleBoxFlat.new()
	ab_style.bg_color = Color(0.045, 0.055, 0.08, 0.95).lerp(_get_hero_element_color(elem), 0.08)
	ab_style.border_width_left = 1
	ab_style.border_width_top = 1
	ab_style.border_width_right = 1
	ab_style.border_width_bottom = 1
	ab_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.25)
	ab_style.corner_radius_top_left = 6
	ab_style.corner_radius_top_right = 6
	ab_style.corner_radius_bottom_left = 6
	ab_style.corner_radius_bottom_right = 6
	avatar_box.add_theme_stylebox_override("panel", ab_style)
	vbox.add_child(avatar_box)

	# Halo Canvas for drawing concentric summoning rings
	var halo_canvas := Control.new()
	halo_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo_canvas.draw.connect(_draw_card_occult_rings.bind(halo_canvas, rarity_col))
	avatar_box.add_child(halo_canvas)

	# Center Hero Silhouette (centered on occult halo rings)
	var icon_center := CenterContainer.new()
	icon_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	avatar_box.add_child(icon_center)

	var big_icon := Label.new()
	big_icon.text = _get_hero_class_icon(cls)
	big_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big_icon.add_theme_font_size_override("font_size", 48)
	big_icon.modulate = Color(1.0, 1.0, 1.0, 0.90)
	icon_center.add_child(big_icon)

	# Overlay badges (Awakening top-left, Class pill at bottom-center border)
	var av_overlay := MarginContainer.new()
	av_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	av_overlay.add_theme_constant_override("margin_left", 6)
	av_overlay.add_theme_constant_override("margin_top", 6)
	av_overlay.add_theme_constant_override("margin_right", 6)
	av_overlay.add_theme_constant_override("margin_bottom", 4)
	avatar_box.add_child(av_overlay)

	if awaken_rank > 0:
		var awk_pill := PanelContainer.new()
		awk_pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		awk_pill.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var awk_style := StyleBoxFlat.new()
		awk_style.bg_color = Color(0.10, 0.35, 0.48, 0.92)
		awk_style.corner_radius_top_left = 3
		awk_style.corner_radius_top_right = 3
		awk_style.corner_radius_bottom_left = 3
		awk_style.corner_radius_bottom_right = 3
		awk_pill.add_theme_stylebox_override("panel", awk_style)
		var awk_lbl := Label.new()
		awk_lbl.text = "⚡ +%d" % awaken_rank
		awk_lbl.add_theme_font_size_override("font_size", 9)
		awk_lbl.add_theme_color_override("font_color", Color(0.5, 0.95, 1.0))
		awk_pill.add_child(awk_lbl)
		av_overlay.add_child(awk_pill)

	# Class Pill at bottom edge, horizontally centered (viền dưới, ở giữa trên các sao)
	var class_pill := PanelContainer.new()
	class_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	class_pill.size_flags_vertical = Control.SIZE_SHRINK_END
	var cp_style := StyleBoxFlat.new()
	cp_style.bg_color = Color(0.06, 0.08, 0.12, 0.92)
	cp_style.border_width_left = 1
	cp_style.border_width_top = 1
	cp_style.border_width_right = 1
	cp_style.border_width_bottom = 1
	cp_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.45)
	cp_style.corner_radius_top_left = 3
	cp_style.corner_radius_top_right = 3
	cp_style.corner_radius_bottom_left = 3
	cp_style.corner_radius_bottom_right = 3
	class_pill.add_theme_stylebox_override("panel", cp_style)
	var cp_margin := MarginContainer.new()
	cp_margin.add_theme_constant_override("margin_left", 7)
	cp_margin.add_theme_constant_override("margin_right", 7)
	cp_margin.add_theme_constant_override("margin_top", 1)
	cp_margin.add_theme_constant_override("margin_bottom", 1)
	class_pill.add_child(cp_margin)
	var class_lbl := Label.new()
	class_lbl.text = "%s %s" % [_get_hero_class_icon(cls), cls.to_upper()]
	class_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_lbl.add_theme_font_size_override("font_size", 9)
	class_lbl.add_theme_color_override("font_color", _get_hero_element_color(elem))
	cp_margin.add_child(class_lbl)
	av_overlay.add_child(class_pill)

	# Dead / disabled status overlay
	if state_str == "DEAD" or state_str == "DISABLED":
		var dead_panel := PanelContainer.new()
		dead_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		var dp_style := StyleBoxFlat.new()
		dp_style.bg_color = Color(0.4, 0.05, 0.05, 0.78)
		dead_panel.add_theme_stylebox_override("panel", dp_style)
		var dead_lbl := Label.new()
		dead_lbl.text = "TỬ TRẬN" if state_str == "DEAD" else "THƯƠNG NẶNG"
		dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dead_lbl.add_theme_font_size_override("font_size", 14)
		dead_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		dead_panel.add_child(dead_lbl)
		avatar_box.add_child(dead_panel)

	# 3. Centered Glowing Stars (Directly above nameplate banner, matching Image 2)
	var star_box := HBoxContainer.new()
	star_box.alignment = BoxContainer.ALIGNMENT_CENTER
	star_box.add_theme_constant_override("separation", 4)
	vbox.add_child(star_box)

	var star_lbl := Label.new()
	star_lbl.text = "★".repeat(clampi(star, 1, 7))
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_lbl.add_theme_font_size_override("font_size", 15)
	star_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.32))
	star_box.add_child(star_lbl)

	# 4. Iconic Pick Me Up Nameplate Banner (< HERO NAME >)
	var name_plate := PanelContainer.new()
	name_plate.custom_minimum_size = Vector2(0, 26)
	var np_style := StyleBoxFlat.new()
	np_style.bg_color = Color(0.04, 0.05, 0.07, 0.98)
	np_style.border_width_left = 1
	np_style.border_width_top = 1
	np_style.border_width_right = 1
	np_style.border_width_bottom = 1
	np_style.border_color = Color(rarity_col.r, rarity_col.g, rarity_col.b, 0.70)
	np_style.corner_radius_top_left = 3
	np_style.corner_radius_top_right = 3
	np_style.corner_radius_bottom_left = 3
	np_style.corner_radius_bottom_right = 3
	name_plate.add_theme_stylebox_override("panel", np_style)
	vbox.add_child(name_plate)

	var np_margin := MarginContainer.new()
	np_margin.add_theme_constant_override("margin_left", 6)
	np_margin.add_theme_constant_override("margin_right", 6)
	np_margin.add_theme_constant_override("margin_top", 3)
	np_margin.add_theme_constant_override("margin_bottom", 3)
	name_plate.add_child(np_margin)

	var name_lbl := Label.new()
	name_lbl.text = "<  %s  >" % hname.to_upper()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	np_margin.add_child(name_lbl)

	# 5. Tactical Status Ribbon (Level on left, Combat Power on right)
	var ribbon := HBoxContainer.new()
	ribbon.add_theme_constant_override("separation", 4)
	vbox.add_child(ribbon)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv.%d" % lvl
	lvl_lbl.add_theme_font_size_override("font_size", 12)
	lvl_lbl.add_theme_color_override("font_color", Color.WHITE)
	ribbon.add_child(lvl_lbl)

	var max_lvl_lbl := Label.new()
	max_lvl_lbl.text = "/%d" % max_lvl
	max_lvl_lbl.add_theme_font_size_override("font_size", 10)
	max_lvl_lbl.add_theme_color_override("font_color", Color(0.68, 0.75, 0.85))
	ribbon.add_child(max_lvl_lbl)

	var ribbon_spacer := Control.new()
	ribbon_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.add_child(ribbon_spacer)

	var cp_lbl := Label.new()
	cp_lbl.text = "🔥 LC: %s" % _format_num(cp)
	cp_lbl.add_theme_font_size_override("font_size", 11)
	cp_lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.25))
	ribbon.add_child(cp_lbl)

	# Full-card Click overlay button
	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_child(click_btn)

	click_btn.mouse_entered.connect(func():
		card.modulate = Color(1.15, 1.15, 1.15)
	)
	click_btn.mouse_exited.connect(func():
		card.modulate = Color(1.0, 1.0, 1.0)
	)
	click_btn.pressed.connect(func():
		_open_hero_detail(h)
	)

	return card

func _display_hero_details(h: Dictionary) -> void:
	var hid := str(h.get("id", ""))
	var star := int(h.get("rarity", 1))
	var level := int(h.get("level", 1))
	var promo_rank := int(h.get("promotionRank", 0))
	var star_ceiling := int(h.get("starCeiling", star * 10))
	var max_lvl := int(h.get("maxLevel", mini(star_ceiling, (promo_rank + 1) * 10)))
	var cls := str(h.get("classCode", h.get("heroClass", "UNCLASSIFIED")))
	var elem := str(h.get("element", "NEUTRAL"))
	var awaken_rank := int(h.get("awakeningRank", 0))
	var in_party := GameState.active_party_ids.has(hid)
	var is_locked := bool(h.get("isLocked", false))

	hero_name_label.text = "%s %s%s" % [
		"★".repeat(clampi(star, 1, 7)),
		str(h.get("name", "Hero")),
		(" [Thức Tỉnh +%d]" % awaken_rank) if awaken_rank > 0 else ""
	]
	hero_star_label.text = "%d★ (Đột phá +%d)" % [star, promo_rank]
	hero_class_label.text = "Hệ: %s (%s)" % [cls, elem]
	if _breadcrumb_class_label != null:
		_breadcrumb_class_label.text = "%s / %s" % [elem.to_upper(), cls.to_upper()]
	hero_level_label.text = "Lv.%d/%d" % [level, max_lvl]
	if star_ceiling > max_lvl:
		hero_level_label.text += " (Trần: %d)" % star_ceiling

	var d_stats: Dictionary = h.get("derivedStats", {}) if h.get("derivedStats") is Dictionary else {}
	var atk := int(d_stats.get("attack", h.get("attack", 10)))
	var def_val := int(d_stats.get("defense", h.get("defense", 10)))
	var mhp := int(d_stats.get("maxHp", h.get("maxHp", 100)))
	var spd := int(d_stats.get("speed", h.get("speed", 10)))
	var cp := int(h.get("combatPower", mhp + atk * 4 + def_val * 3 + spd * 2))
	hero_cp_label.text = "🔥 LC: %s" % _format_num(cp)

	if _party_toggle_btn != null:
		_party_toggle_btn.text = "✅ Trong Đội PvE (Bấm để Rời)" if in_party else "⚔️ Đưa Vào Đội Hình PvE"
	if _lock_toggle_btn != null:
		_lock_toggle_btn.text = "🔒 Đã Khóa" if is_locked else "🔓 Khóa Bảo Vệ"

	# Determine milestone: Breakthrough vs Star Promotion
	var is_at_max_lvl := (level >= max_lvl)
	var needs_breakthrough := (star_ceiling > max_lvl)
	var can_star_promote := (star < 5 and not needs_breakthrough)

	if is_at_max_lvl:
		if needs_breakthrough:
			open_promote_btn.disabled = false
			open_promote_btn.text = "⚡ Khai Mở Đột Phá Bậc +%d (Mở Khóa Lv.%d)!" % [promo_rank + 1, mini(star_ceiling, (promo_rank + 2) * 10)]
		elif can_star_promote:
			open_promote_btn.disabled = false
			open_promote_btn.text = "🌟 Khai Mở Nghi Thức Thăng Lên %d★ (Pick Me Up)!" % (star + 1)
		else:
			open_promote_btn.disabled = true
			open_promote_btn.text = "🌟 Đã Đạt Cấp Độ & Phẩm Chất Tối Đa (5★ Lv.%d)" % max_lvl
	else:
		if needs_breakthrough:
			open_promote_btn.disabled = false
			open_promote_btn.text = "⚡ Xem Nghi Thức Đột Phá Bậc +%d (Cần đạt Lv.%d — Hiện tại: Lv.%d)" % [promo_rank + 1, max_lvl, level]
		elif can_star_promote:
			open_promote_btn.disabled = false
			open_promote_btn.text = "★ Xem Nghi Thức Thăng Lên %d★ (Cần đạt Lv.%d — Hiện tại: Lv.%d)" % [star + 1, max_lvl, level]
		else:
			open_promote_btn.disabled = true
			open_promote_btn.text = "🌟 Đã Đạt Phẩm Chất Sao Tối Đa (5★)"

	_update_3d_pedestal_hero(h)
	_render_active_profile_tab()
	_fetch_hero_imprints_async(hid)

func _fetch_hero_imprints_async(hero_id: String) -> void:
	if hero_id.is_empty():
		return
	var res := await ApiClient.get_req("/api/heroes/%s/imprints" % hero_id)
	if res["ok"] and res["data"] is Array and str(_selected_hero.get("id", "")) == hero_id:
		_hero_imprints = res["data"]
		if _active_profile_tab == 2:
			_render_active_profile_tab()

# ==============================================================================
# 4-TAB DEEP HERO PROFILE RENDERER
# ==============================================================================

func _update_selected_hero_from_gamestate() -> void:
	var hid := str(_selected_hero.get("id", ""))
	if hid.is_empty():
		return
	for h in GameState.heroes:
		if h is Dictionary and str(h.get("id", "")) == hid:
			_selected_hero = h
			break

func _render_active_profile_tab() -> void:
	if _tab_content_vbox == null:
		return
	_update_selected_hero_from_gamestate()
	for i in range(_tab_buttons.size()):
		var is_cur := (i == _active_profile_tab)
		_tab_buttons[i].modulate = Color(1.0, 0.92, 0.42) if is_cur else Color(0.80, 0.88, 0.96)

	for child in _tab_content_vbox.get_children():
		child.queue_free()

	if _selected_hero.is_empty():
		return

	match _active_profile_tab:
		0:
			_update_pedestal_equipment_overlay(false)
			_render_tab_stats_and_training(_selected_hero)
		1:
			_update_pedestal_equipment_overlay(false)
			_render_tab_skills_and_awakening(_selected_hero)
		2:
			_update_pedestal_equipment_overlay(false)
			_render_tab_imprints(_selected_hero)
		3:
			_update_pedestal_equipment_overlay(true)
			_render_tab_equipment(_selected_hero)

func _add_tab_header(title: String, color: Color = Color(1.0, 0.88, 0.38)) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", color)
	_tab_content_vbox.add_child(lbl)

func _add_tab_info(text: String, color: Color = Color(0.88, 0.92, 0.98)) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", color)
	_tab_content_vbox.add_child(lbl)

func _render_tab_stats_and_training(h: Dictionary) -> void:
	if _tab_content_vbox == null:
		return
	for c in _tab_content_vbox.get_children():
		c.queue_free()

	var hid := str(h.get("id", ""))
	var star := int(h.get("rarity", 1))
	var lvl := int(h.get("level", 1))
	var max_lvl := int(h.get("maxLevel", star * 10))

	var d_stats: Dictionary = h.get("derivedStats", {}) if h.get("derivedStats") is Dictionary else {}
	var v2_stats: Dictionary = h.get("v2Stats", {}) if h.get("v2Stats") is Dictionary else {}
	var max_hp := int(d_stats.get("maxHp", h.get("maxHp", 100)))
	var atk := int(d_stats.get("attack", h.get("attack", 10)))
	var def_val := int(d_stats.get("defense", h.get("defense", 10)))
	var spd := int(d_stats.get("speed", h.get("speed", 10)))

	var crit_raw := float(v2_stats.get("critRate", 5.0))
	var crit_pct := crit_raw * 100.0 if (crit_raw <= 1.0 and crit_raw > 0.0) else crit_raw
	var crit_dmg_raw := float(v2_stats.get("critDamage", 150.0))
	var crit_dmg := crit_dmg_raw * 100.0 if (crit_dmg_raw <= 3.0 and crit_dmg_raw > 0.0) else crit_dmg_raw
	var cp := int(h.get("combatPower", max_hp + atk * 4 + def_val * 3 + spd * 2))

	# Sub-header: Stats (Honkai Star Rail style)
	var header_bar := HBoxContainer.new()
	header_bar.add_theme_constant_override("separation", 6)
	_tab_content_vbox.add_child(header_bar)

	var sub_head := Label.new()
	sub_head.text = "THÔNG SỐ CHIẾN ĐẤU (STATS)"
	sub_head.add_theme_font_size_override("font_size", 14)
	sub_head.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	header_bar.add_child(sub_head)

	# Essential Stats Panel (Clean key-value rows matching HSR screenshot)
	var stats_card := PanelContainer.new()
	stats_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc_style := StyleBoxFlat.new()
	sc_style.bg_color = Color(0.08, 0.11, 0.18, 0.92)
	sc_style.border_width_left = 1
	sc_style.border_width_top = 1
	sc_style.border_width_right = 1
	sc_style.border_width_bottom = 1
	sc_style.border_color = Color(0.25, 0.38, 0.55, 0.5)
	sc_style.corner_radius_top_left = 8
	sc_style.corner_radius_top_right = 8
	sc_style.corner_radius_bottom_left = 8
	sc_style.corner_radius_bottom_right = 8
	stats_card.add_theme_stylebox_override("panel", sc_style)
	_tab_content_vbox.add_child(stats_card)

	var sc_margin := MarginContainer.new()
	sc_margin.add_theme_constant_override("margin_left", 14)
	sc_margin.add_theme_constant_override("margin_top", 10)
	sc_margin.add_theme_constant_override("margin_right", 14)
	sc_margin.add_theme_constant_override("margin_bottom", 10)
	stats_card.add_child(sc_margin)

	var sc_vbox := VBoxContainer.new()
	sc_vbox.add_theme_constant_override("separation", 7)
	sc_margin.add_child(sc_vbox)

	var stat_items := [
		{"icon": "❤️", "name": "Sinh Lực (HP)", "val": _format_num(max_hp), "col": Color(1.0, 0.45, 0.45)},
		{"icon": "⚔️", "name": "Tấn Công (ATK)", "val": _format_num(atk), "col": Color(1.0, 0.75, 0.4)},
		{"icon": "🛡️", "name": "Phòng Thủ (DEF)", "val": _format_num(def_val), "col": Color(0.45, 0.75, 1.0)},
		{"icon": "👟", "name": "Tốc Độ (SPD)", "val": _format_num(spd), "col": Color(0.45, 0.95, 0.7)},
		{"icon": "🎯", "name": "Tỷ Lệ Bạo (CRIT Rate)", "val": "%.1f%%" % crit_pct, "col": Color(1.0, 0.85, 0.35)},
		{"icon": "💥", "name": "ST Bạo Kích (CRIT DMG)", "val": "%.1f%%" % crit_dmg, "col": Color(1.0, 0.55, 0.25)},
		{"icon": "🔥", "name": "Lực Chiến (CP)", "val": _format_num(cp), "col": Color(1.0, 0.6, 0.2)}
	]

	for item in stat_items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		sc_vbox.add_child(row)

		var ilbl := Label.new()
		ilbl.text = "%s  %s" % [item["icon"], item["name"]]
		ilbl.add_theme_font_size_override("font_size", 13)
		ilbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.98))
		ilbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ilbl)

		var vlbl := Label.new()
		vlbl.text = item["val"]
		vlbl.add_theme_font_size_override("font_size", 13)
		vlbl.add_theme_color_override("font_color", item["col"])
		row.add_child(vlbl)

	# Stats Details Button (Honkai Star Rail pill button)
	var detail_btn_row := HBoxContainer.new()
	_tab_content_vbox.add_child(detail_btn_row)

	var detail_btn_spacer := Control.new()
	detail_btn_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_btn_row.add_child(detail_btn_spacer)

	var stats_detail_btn := Button.new()
	stats_detail_btn.text = "🔍 Chi Tiết Chỉ Số (Toàn Bộ)"
	stats_detail_btn.custom_minimum_size = Vector2(200, 32)
	stats_detail_btn.add_theme_font_size_override("font_size", 12)
	var sdb_style := StyleBoxFlat.new()
	sdb_style.bg_color = Color(0.12, 0.18, 0.28, 0.9)
	sdb_style.border_width_left = 1
	sdb_style.border_width_top = 1
	sdb_style.border_width_right = 1
	sdb_style.border_width_bottom = 1
	sdb_style.border_color = Color(0.35, 0.65, 0.95, 0.8)
	sdb_style.corner_radius_top_left = 16
	sdb_style.corner_radius_top_right = 16
	sdb_style.corner_radius_bottom_left = 16
	sdb_style.corner_radius_bottom_right = 16
	stats_detail_btn.add_theme_stylebox_override("normal", sdb_style)
	stats_detail_btn.pressed.connect(_open_stats_detail_modal)
	detail_btn_row.add_child(stats_detail_btn)

	_tab_content_vbox.add_child(HSeparator.new())

	# Smooth EXP progress bar
	var cur_exp_val := int(h.get("exp", "0"))
	var next_exp_raw: Variant = h.get("nextLevelExp")
	var cur_lvl_exp_val := int(h.get("currentLevelExp", "0"))
	var exp_pct := 100.0
	var exp_detail_text := ""
	if next_exp_raw != null:
		var next_exp_val := int(next_exp_raw)
		var span := maxi(1, next_exp_val - cur_lvl_exp_val)
		var earned := clampi(cur_exp_val - cur_lvl_exp_val, 0, span)
		exp_pct = clampf(float(earned) / float(span) * 100.0, 0.0, 100.0)
		var remaining := maxi(0, next_exp_val - cur_exp_val)
		exp_detail_text = "📈 EXP: %s / %s (%.1f%%) — Cần thêm: %s EXP để lên Lv.%d" % [
			_format_num(cur_exp_val), _format_num(next_exp_val), exp_pct, _format_num(remaining), lvl + 1
		]
	else:
		exp_detail_text = "📈 EXP: %s (ĐÃ ĐẠT CẤP ĐỘ TRẦN HIỆN TẠI)" % _format_num(cur_exp_val)

	var exp_lbl := Label.new()
	exp_lbl.text = exp_detail_text
	exp_lbl.add_theme_font_size_override("font_size", 11)
	exp_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 0.98))
	_tab_content_vbox.add_child(exp_lbl)

	var exp_pbar := ProgressBar.new()
	exp_pbar.min_value = 0.0
	exp_pbar.max_value = 100.0
	exp_pbar.value = exp_pct
	exp_pbar.custom_minimum_size = Vector2(0, 10)
	exp_pbar.show_percentage = false
	exp_pbar.modulate = Color(0.35, 0.85, 1.0)
	_tab_content_vbox.add_child(exp_pbar)

	# Level-Up Section: 3 Book Types (x1, x10, x100) & Quantity Selector
	var book_defs := [
		{
			"id": "SAMPLE_HERO_EXP_100",
			"name": "Sơ Cấp (+1k)",
			"icon": "📘"
		},
		{
			"id": "SAMPLE_HERO_EXP_1000",
			"name": "Trung Cấp (+100k)",
			"icon": "📗"
		},
		{
			"id": "SAMPLE_HERO_EXP_10000",
			"name": "Cao Cấp (+10M)",
			"icon": "📙"
		}
	]

	var cur_book_id := _selected_exp_book_id
	var cur_book_count := int(GameState.materials.get(cur_book_id, 0))
	var is_max_reach := lvl >= max_lvl
	
	var lvl_box := VBoxContainer.new()
	lvl_box.add_theme_constant_override("separation", 6)

	var lvl_header := Label.new()
	lvl_header.text = "📘 NÂNG CẤP HERO BẰNG SÁCH EXP (CHỌN LOẠI SÁCH):"
	lvl_header.add_theme_font_size_override("font_size", 13)
	lvl_header.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	lvl_box.add_child(lvl_header)

	var book_sel_row := HBoxContainer.new()
	book_sel_row.add_theme_constant_override("separation", 6)
	for binfo in book_defs:
		var bid := str(binfo["id"])
		var bcnt := int(GameState.materials.get(bid, 0))
		var is_cur := (bid == cur_book_id)
		var bbtn := Button.new()
		bbtn.text = "%s %s: %s" % [str(binfo["icon"]), str(binfo["name"]), _format_num(bcnt)]
		bbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bbtn.custom_minimum_size = Vector2(0, 30)
		bbtn.add_theme_font_size_override("font_size", 11)
		if is_cur:
			bbtn.modulate = Color(1.25, 1.25, 1.0)
		else:
			bbtn.modulate = Color(0.7, 0.75, 0.8)
		bbtn.pressed.connect(func():
			_selected_exp_book_id = bid
			_render_active_profile_tab()
		)
		book_sel_row.add_child(bbtn)
	lvl_box.add_child(book_sel_row)

	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 6)

	# 1. Nút tăng cấp tối đa
	var max_btn := Button.new()
	max_btn.text = "⚡ Đạt Cấp Trần (Lv.%d)" % max_lvl
	max_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_btn.custom_minimum_size = Vector2(0, 34)
	max_btn.disabled = (cur_book_count <= 0 or is_max_reach)
	max_btn.pressed.connect(func(): _on_level_up_hero(1, true, cur_book_id))
	lvl_row.add_child(max_btn)

	# 2. Chọn số lượng bằng SpinBox + Nút đọc
	var spin_box := SpinBox.new()
	spin_box.min_value = 1
	spin_box.max_value = maxi(1, cur_book_count)
	spin_box.value = clampi(10, 1, maxi(1, cur_book_count))
	spin_box.custom_minimum_size = Vector2(80, 34)
	lvl_row.add_child(spin_box)

	var use_qty_btn := Button.new()
	use_qty_btn.text = "📖 Đọc Sách"
	use_qty_btn.custom_minimum_size = Vector2(100, 34)
	use_qty_btn.disabled = (cur_book_count <= 0 or is_max_reach)
	use_qty_btn.pressed.connect(func(): _on_level_up_hero(int(spin_box.value), false, cur_book_id))
	lvl_row.add_child(use_qty_btn)

	# 3. Phím tắt nhanh +1, +10, +50
	var plus1_btn := Button.new()
	plus1_btn.text = "+1"
	plus1_btn.custom_minimum_size = Vector2(36, 34)
	plus1_btn.disabled = (cur_book_count <= 0 or is_max_reach)
	plus1_btn.pressed.connect(func(): _on_level_up_hero(1, false, cur_book_id))
	lvl_row.add_child(plus1_btn)

	var plus10_btn := Button.new()
	plus10_btn.text = "+10"
	plus10_btn.custom_minimum_size = Vector2(42, 34)
	plus10_btn.disabled = (cur_book_count < 10 or is_max_reach)
	plus10_btn.pressed.connect(func(): _on_level_up_hero(10, false, cur_book_id))
	lvl_row.add_child(plus10_btn)

	var plus50_btn := Button.new()
	plus50_btn.text = "+50"
	plus50_btn.custom_minimum_size = Vector2(42, 34)
	plus50_btn.disabled = (cur_book_count < 50 or is_max_reach)
	plus50_btn.pressed.connect(func(): _on_level_up_hero(50, false, cur_book_id))
	lvl_row.add_child(plus50_btn)

	lvl_box.add_child(lvl_row)
	_tab_content_vbox.add_child(lvl_box)

func _render_tab_skills_and_awakening(h: Dictionary) -> void:
	if _tab_content_vbox == null:
		return
	for c in _tab_content_vbox.get_children():
		c.queue_free()

	var hid := str(h.get("id", ""))
	var star := int(h.get("rarity", 1))
	var hlvl := int(h.get("level", 1))
	var awaken_rank := int(h.get("awakeningRank", 0))
	var max_awk := _get_hero_max_imprint_slots(star)
	var skill_books := int(GameState.materials.get("SAMPLE_HERO_SKILL_BOOK", 0))

	_add_tab_header("⚔️ KỸ NĂNG HỆ PHÁI & CƠ CHẾ AUTO/MANUAL (Sách Kỹ Năng: %d)" % skill_books, Color(0.58, 0.94, 1.0))

	var skills: Array = h.get("skills", []) if h.get("skills") is Array else []
	if skills.is_empty():
		_add_tab_info("ℹ️ Tướng này hiện chưa có kỹ năng hệ phái chuyên biệt.", Color(0.8, 0.85, 0.92))
	else:
		for sk in skills:
			if not (sk is Dictionary):
				continue
			var sk_code := str(sk.get("code", ""))
			var sk_name := str(sk.get("name", sk_code))
			var sk_desc := str(sk.get("description", "Kỹ năng chiến đấu."))
			var sk_lvl := int(sk.get("skillLevel", 1))
			var sk_max := int(sk.get("maxLevel", 5))
			var req_lvl := int(sk.get("unlockLevel", 1))
			var is_unlocked := bool(sk.get("isUnlocked", false))
			var mode := str(sk.get("behaviorMode", "AUTO"))
			var eff_val := float(sk.get("skillEffectValue", sk.get("effectValue", 100)))

			var sk_card := PanelContainer.new()
			var cstyle := StyleBoxFlat.new()
			cstyle.bg_color = Color(0.09, 0.13, 0.20, 0.92)
			cstyle.border_width_left = 2
			cstyle.border_color = Color(0.35, 0.88, 0.65) if is_unlocked else Color(0.45, 0.50, 0.60)
			cstyle.corner_radius_top_left = 6
			cstyle.corner_radius_bottom_left = 6
			sk_card.add_theme_stylebox_override("panel", cstyle)
			_tab_content_vbox.add_child(sk_card)

			var sm := MarginContainer.new()
			sm.add_theme_constant_override("margin_left", 10)
			sm.add_theme_constant_override("margin_top", 8)
			sm.add_theme_constant_override("margin_right", 10)
			sm.add_theme_constant_override("margin_bottom", 8)
			sk_card.add_child(sm)

			var sv := VBoxContainer.new()
			sv.add_theme_constant_override("separation", 6)
			sm.add_child(sv)

			var slbl := Label.new()
			slbl.text = "%s %s (Lv.%d/%d) — Hiệu lực: %d%% [Chế độ: %s]\n   %s (Mở khóa ở Lv.%d)" % [
				"✅" if is_unlocked else "🔒",
				sk_name, sk_lvl, sk_max, int(eff_val), mode, sk_desc, req_lvl
			]
			slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slbl.add_theme_font_size_override("font_size", 13)
			sv.add_child(slbl)

			var sbtn_row := HBoxContainer.new()
			sbtn_row.add_theme_constant_override("separation", 8)
			sv.add_child(sbtn_row)

			if not is_unlocked:
				var ubtn := Button.new()
				ubtn.text = "🔓 Mở Khóa Kỹ Năng (Yêu cầu Lv.%d)" % req_lvl
				ubtn.disabled = hlvl < req_lvl
				ubtn.pressed.connect(func(): _on_unlock_skill_pressed(hid, sk_code, sk_name))
				sbtn_row.add_child(ubtn)
			else:
				var upg_btn := Button.new()
				upg_btn.text = "📕 Nâng Cấp Kỹ Năng (Lv.%d ➔ %d)" % [sk_lvl, sk_lvl + 1]
				upg_btn.disabled = (sk_lvl >= sk_max or skill_books <= 0)
				upg_btn.pressed.connect(func(): _on_upgrade_skill_pressed(hid, sk_code, sk_name))
				sbtn_row.add_child(upg_btn)

				var next_mode := "MANUAL" if mode == "AUTO" else "AUTO"
				var mbtn := Button.new()
				mbtn.text = "🤖 Đổi sang %s" % next_mode
				mbtn.pressed.connect(func(): _on_toggle_skill_behavior(hid, sk_code, next_mode))
				sbtn_row.add_child(mbtn)

	_tab_content_vbox.add_child(HSeparator.new())
	_add_tab_header("🌟 THỨC TỈNH HUYẾT MẠCH (BẬC HIỆN TẠI: +%d / +%d)" % [awaken_rank, max_awk], Color(1.0, 0.86, 0.35))
	_add_tab_info("• Mỗi bậc Thức Tỉnh tăng +10 toàn bộ STR/INT/STA/AGI, nâng +1 cấp kỹ năng và mở khóa 1 Ô Ấn Ký Huyết Mạch (Imprint)!", Color(0.95, 0.88, 0.72))
	var awk_btn := Button.new()
	if awaken_rank >= max_awk:
		awk_btn.text = "🌟 Đã Đạt Bậc Thức Tỉnh Tối Đa (Bậc +%d)" % max_awk
		awk_btn.disabled = true
	else:
		awk_btn.text = "🩸 Xem Nghi Thức Thức Tỉnh Huyết Mạch (Bậc +%d ➔ +%d)" % [awaken_rank, awaken_rank + 1]
		awk_btn.disabled = false
	awk_btn.custom_minimum_size = Vector2(0, 36)
	awk_btn.pressed.connect(_on_open_awaken_pressed)
	_tab_content_vbox.add_child(awk_btn)

func _render_tab_imprints(h: Dictionary) -> void:
	if _tab_content_vbox == null:
		return
	for c in _tab_content_vbox.get_children():
		c.queue_free()

	var star := int(h.get("rarity", 1))
	var awaken_rank := int(h.get("awakeningRank", 0))
	var max_slots := _get_hero_max_imprint_slots(star)
	var unlocked_slots := clampi(awaken_rank, 0, max_slots)

	_add_tab_header("💠 Ô ẤN KÝ HUYẾT MẠCH (%d MỞ KHÓA / %d TỐI ĐA • %d ĐÃ KHẢM)" % [unlocked_slots, max_slots, _hero_imprints.size()], Color(0.84, 0.65, 1.0))
	_add_tab_info("• Mặc định tất cả các Ô Ấn Ký đều KHÓA 🔒.\n• Mỗi bậc Thức Tỉnh Huyết Mạch mở khóa 1 Ô (ở trạng thái Trống ⭕).\n• Ấn Ký Huyết Mạch rơi từ Dungeon / Tháp Chinh Phạt với tỉ lệ cực thấp (tính năng khảm sẽ sớm ra mắt).", Color(0.86, 0.82, 0.98))

	var imp_grid := GridContainer.new()
	imp_grid.columns = 2
	imp_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	imp_grid.add_theme_constant_override("h_separation", 8)
	imp_grid.add_theme_constant_override("v_separation", 8)
	_tab_content_vbox.add_child(imp_grid)

	for slot_i in range(max_slots):
		var slot_card := PanelContainer.new()
		slot_card.clip_contents = true
		slot_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sstyle := StyleBoxFlat.new()
		sstyle.border_width_left = 3
		sstyle.corner_radius_top_left = 6
		sstyle.corner_radius_bottom_left = 6

		var m := MarginContainer.new()
		m.add_theme_constant_override("margin_left", 8)
		m.add_theme_constant_override("margin_top", 6)
		m.add_theme_constant_override("margin_right", 8)
		m.add_theme_constant_override("margin_bottom", 6)
		slot_card.add_child(m)

		var lbl := Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 12)

		if slot_i < unlocked_slots:
			# Ô ĐÃ ĐƯỢC MỞ KHÓA BỞI THỨC TỈNH
			if slot_i < _hero_imprints.size() and _hero_imprints[slot_i] is Dictionary:
				# Đã khảm Ấn Ký
				var row: Dictionary = _hero_imprints[slot_i]
				var owned: Dictionary = row.get("owned", {}) if row.get("owned") is Dictionary else {}
				var def: Dictionary = row.get("definition", {}) if row.get("definition") is Dictionary else {}
				var imp_name := str(def.get("name", owned.get("imprintCode", "Ấn Ký")))
				var imp_rank := str(def.get("rank", "A"))
				var rank_lvl := int(owned.get("rankLevel", 1))
				var b_str := int(def.get("bonusStr", 0))
				var b_int := int(def.get("bonusInt", 0))
				var b_sta := int(def.get("bonusSta", 0))
				var b_agi := int(def.get("bonusAgi", 0))
				var ability := str(def.get("abilityDescription", def.get("abilityCode", "Nội tại huyết mạch")))
				sstyle.bg_color = Color(0.12, 0.10, 0.22, 0.94)
				sstyle.border_color = Color(1.0, 0.84, 0.25)
				lbl.text = "💠 [Ô #%d • ĐÃ KHẢM • Hạng %s Lv.%d] %s\n+STR %d | +INT %d | +STA %d | +AGI %d\n✨ %s" % [
					slot_i + 1, imp_rank, rank_lvl, imp_name, b_str, b_int, b_sta, b_agi, ability
				]
			else:
				# Đã mở khóa nhưng đang ở trạng thái Trống
				sstyle.bg_color = Color(0.08, 0.14, 0.16, 0.94)
				sstyle.border_color = Color(0.35, 0.85, 0.65)
				lbl.text = "⭕ [Ô #%d • ĐÃ MỞ KHÓA] Chưa Khảm Ấn Ký\n(Ô Trống sẵn sàng khảm. Tìm kiếm Ấn Ký tại Dungeon / Tháp Chinh Phạt với tỉ lệ cực thấp)." % (slot_i + 1)
		else:
			# Ô ĐANG BỊ KHÓA
			sstyle.bg_color = Color(0.08, 0.08, 0.10, 0.94)
			sstyle.border_color = Color(0.35, 0.35, 0.42, 0.7)
			lbl.text = "🔒 [Ô #%d • ĐANG BỊ KHÓA]\nCần Thức Tỉnh Huyết Mạch Bậc +%d để mở khóa ô này." % [slot_i + 1, slot_i + 1]

		slot_card.add_theme_stylebox_override("panel", sstyle)
		m.add_child(lbl)
		imp_grid.add_child(slot_card)

	# Tab Kỹ Năng đã có nút Mở Nghi Thức Thức Tỉnh Huyết Mạch, tab Ấn Ký hiển thị trạng thái các ô.

func _get_hero_equipped_items_map(hero_id: String) -> Dictionary:
	var result := {}
	var list_to_check: Array = GameState.equipment_list
	if list_to_check.is_empty():
		list_to_check = GameState.crafting_overview.get("equipment", [])

	for it in list_to_check:
		if not (it is Dictionary):
			continue
		var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else it
		var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else {}
		var eq_hero := str(eq.get("equippedHeroId", it.get("equippedHeroId", "")))
		var loc := str(eq.get("location", it.get("location", "")))
		if eq_hero == hero_id and loc == "EQUIPPED":
			var slot := str(tmpl.get("slotType", eq.get("slotType", it.get("slotType", "ACCESSORY")))).to_upper()
			if not result.has(slot):
				result[slot] = it
			elif slot == "ACCESSORY":
				if not result.has("SHOULDER"):
					result["SHOULDER"] = it
				elif not result.has("NECKLACE"):
					result["NECKLACE"] = it
				elif not result.has("RING"):
					result["RING"] = it
	return result

func _get_inventory_equipment_list() -> Array:
	var result := []
	var list_to_check: Array = GameState.equipment_list
	if list_to_check.is_empty():
		list_to_check = GameState.crafting_overview.get("equipment", [])

	for it in list_to_check:
		if not (it is Dictionary):
			continue
		var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else it
		var loc := str(eq.get("location", it.get("location", "")))
		var eq_hero := str(eq.get("equippedHeroId", it.get("equippedHeroId", "")))
		if loc == "INVENTORY" or eq_hero == "":
			result.append(it)
	return result

func _extract_item_slot_type(it: Dictionary) -> String:
	var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else {}
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	for d in [tmpl, eq, it]:
		for k in ["slotType", "slot_type", "slot", "type"]:
			if d.has(k) and str(d[k]).strip_edges() != "":
				return str(d[k]).strip_edges().to_upper()
	return ""

func _extract_item_rarity(it: Dictionary) -> int:
	var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else {}
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	for d in [tmpl, eq, it]:
		for k in ["rarity", "starLevel", "star_level", "stars"]:
			if d.has(k) and int(d[k]) > 0:
				return int(d[k])
	return 1

func _extract_item_enhance_level(it: Dictionary) -> int:
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else {}
	for d in [eq, it, tmpl]:
		for k in ["enhanceLevel", "enhance_level", "enhance"]:
			if d.has(k):
				return int(d[k])
	return 0

func _extract_item_id(it: Dictionary) -> String:
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	for d in [eq, it]:
		if d.has("id") and str(d["id"]).strip_edges() != "":
			return str(d["id"]).strip_edges()
	return ""

func _extract_item_equipped_hero_id(it: Dictionary) -> String:
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	for d in [eq, it]:
		for k in ["equippedHeroId", "equipped_hero_id"]:
			if d.has(k) and str(d[k]).strip_edges() != "":
				return str(d[k]).strip_edges()
	return ""

func _extract_item_name(it: Dictionary) -> String:
	var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else {}
	var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else {}
	for d in [tmpl, it, eq]:
		if d.has("name") and str(d["name"]).strip_edges() != "":
			return str(d["name"]).strip_edges()
	return "Trang bị"

func _is_item_matching_slot(item_slot: String, target_slot: String) -> bool:
	if item_slot == target_slot:
		return true
	if (target_slot in ["ACCESSORY", "RING", "NECKLACE", "SHOULDER", "GLOVES"]) and (item_slot in ["ACCESSORY", "RING", "NECKLACE", "SHOULDER", "GLOVES"]):
		return true
	return false

func _update_pedestal_equipment_overlay(is_visible: bool) -> void:
	if _pedestal_equipment_overlay == null:
		return
	if not is_visible or _selected_hero.is_empty():
		_pedestal_equipment_overlay.visible = false
		return

	_pedestal_equipment_overlay.visible = true

	if _pedestal_left_slots_vbox == null or _pedestal_right_slots_vbox == null:
		return

	for c in _pedestal_left_slots_vbox.get_children():
		c.queue_free()
	for c in _pedestal_right_slots_vbox.get_children():
		c.queue_free()

	var hid: String = str(_selected_hero.get("id", ""))
	var hname: String = str(_selected_hero.get("name", "Hero"))
	var equips: Dictionary = _get_hero_equipped_items_map(hid)

	# Left Flank: Bộ Chữ Ký (6 ô đối xứng bên trái model 3D)
	var left_slots: Array = [
		{"id": "HELMET", "name": "Mũ Giáp", "icon": "🪖"},
		{"id": "CHEST", "name": "Áo Giáp", "icon": "🥋"},
		{"id": "BELT", "name": "Thắt Lưng", "icon": "📿"},
		{"id": "PANTS", "name": "Quần Giáp", "icon": "👖"},
		{"id": "BOOTS", "name": "Giày Giáp", "icon": "👢"},
		{"id": "MAIN_HAND", "name": "VK Chính", "icon": "🗡️"}
	]
	for s_info in left_slots:
		var slot_card: Control = _build_pedestal_slot_card(s_info, equips.get(s_info["id"]), hid, hname)
		_pedestal_left_slots_vbox.add_child(slot_card)

	# Right Flank: Bộ Lấp Lánh (6 ô đối xứng bên phải model 3D)
	var right_slots: Array = [
		{"id": "NECKLACE", "name": "Dây Chuyền", "icon": "📿"},
		{"id": "SHOULDER", "name": "Giáp Vai", "icon": "🔰"},
		{"id": "RING", "name": "Nhẫn Ngọc", "icon": "💍"},
		{"id": "GLOVES", "name": "Găng Tay", "icon": "🧤"},
		{"id": "ACCESSORY", "name": "Pháp Bảo", "icon": "🔮"},
		{"id": "OFF_HAND", "name": "VK Phụ", "icon": "🛡️"}
	]
	for s_info in right_slots:
		var slot_card: Control = _build_pedestal_slot_card(s_info, equips.get(s_info["id"]), hid, hname)
		_pedestal_right_slots_vbox.add_child(slot_card)

func _build_pedestal_slot_card(slot_info: Dictionary, item_data: Variant, _hid: String, _hname: String) -> Control:
	var slot_id: String = str(slot_info.get("id", ""))
	var slot_name: String = str(slot_info.get("name", slot_id))
	var slot_icon: String = str(slot_info.get("icon", "🛡️"))
	var is_equipped: bool = (item_data is Dictionary and not (item_data as Dictionary).is_empty())
	var is_selected: bool = (slot_id == _equipment_selected_slot)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(88, 56)
	card.clip_contents = true

	var sstyle := StyleBoxFlat.new()
	sstyle.corner_radius_top_left = 6
	sstyle.corner_radius_top_right = 6
	sstyle.corner_radius_bottom_left = 6
	sstyle.corner_radius_bottom_right = 6

	var item_name_str := "[+ Trống]"
	var star_count := 0
	var enh_lvl := 0
	var item_rarity_col := Color(0.35, 0.45, 0.55)

	if is_equipped:
		var it: Dictionary = item_data as Dictionary
		item_name_str = _extract_item_name(it)
		star_count = _extract_item_rarity(it)
		enh_lvl = _extract_item_enhance_level(it)
		item_rarity_col = _get_rarity_border_color(star_count)

	if is_selected:
		sstyle.bg_color = Color(0.12, 0.18, 0.28, 0.95)
		sstyle.border_width_left = 2
		sstyle.border_width_top = 2
		sstyle.border_width_right = 2
		sstyle.border_width_bottom = 2
		sstyle.border_color = Color(0.35, 0.95, 1.0)
	elif is_equipped:
		sstyle.bg_color = Color(0.06, 0.09, 0.15, 0.88)
		sstyle.border_width_left = 1
		sstyle.border_width_top = 1
		sstyle.border_width_right = 1
		sstyle.border_width_bottom = 1
		sstyle.border_color = item_rarity_col
	else:
		sstyle.bg_color = Color(0.04, 0.06, 0.10, 0.78)
		sstyle.border_width_left = 1
		sstyle.border_width_top = 1
		sstyle.border_width_right = 1
		sstyle.border_width_bottom = 1
		sstyle.border_color = Color(0.22, 0.30, 0.40, 0.6)

	card.add_theme_stylebox_override("panel", sstyle)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_bottom", 3)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 1)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top_row)

	var slot_title := Label.new()
	slot_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_title.text = "%s %s" % [slot_icon, slot_name]
	slot_title.add_theme_font_size_override("font_size", 9)
	slot_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45) if is_selected else Color(0.8, 0.88, 0.95))
	slot_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(slot_title)

	if enh_lvl > 0:
		var enh_lbl := Label.new()
		enh_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		enh_lbl.text = "+%d" % enh_lvl
		enh_lbl.add_theme_font_size_override("font_size", 9)
		enh_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		top_row.add_child(enh_lbl)

	var item_lbl := Label.new()
	item_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_lbl.text = item_name_str
	item_lbl.clip_text = true
	item_lbl.add_theme_font_size_override("font_size", 9)
	item_lbl.add_theme_color_override("font_color", item_rarity_col if is_equipped else Color(0.45, 0.55, 0.65))
	vbox.add_child(item_lbl)

	var star_lbl := Label.new()
	star_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_lbl.text = ("★".repeat(star_count)) if is_equipped else "Chưa mặc"
	star_lbl.add_theme_font_size_override("font_size", 8)
	star_lbl.add_theme_color_override("font_color", item_rarity_col if is_equipped else Color(0.35, 0.45, 0.55))
	vbox.add_child(star_lbl)

	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	click_btn.pressed.connect(func():
		_equipment_selected_slot = slot_id
		_equipment_inspected_item_id = ""
		_update_pedestal_equipment_overlay(true)
		_render_tab_equipment(_selected_hero)
	)
	card.add_child(click_btn)

	return card

func _render_tab_equipment(h: Dictionary) -> void:
	if _tab_content_vbox == null:
		return
	for c in _tab_content_vbox.get_children():
		c.queue_free()

	var hid: String = str(h.get("id", ""))
	var hname: String = str(h.get("name", "Hero"))

	var equips: Dictionary = _get_hero_equipped_items_map(hid)
	var all_equipment: Array = GameState.equipment_list
	if all_equipment.is_empty():
		all_equipment = GameState.crafting_overview.get("equipment", [])

	var all_slots_info: Array = [
		{"id": "HELMET", "name": "Mũ Giáp", "icon": "🪖"},
		{"id": "CHEST", "name": "Áo Giáp", "icon": "🥋"},
		{"id": "BELT", "name": "Thắt Lưng", "icon": "📿"},
		{"id": "PANTS", "name": "Quần Giáp", "icon": "👖"},
		{"id": "BOOTS", "name": "Giày Giáp", "icon": "👢"},
		{"id": "MAIN_HAND", "name": "VK Chính", "icon": "🗡️"},
		{"id": "NECKLACE", "name": "Dây Chuyền", "icon": "📿"},
		{"id": "SHOULDER", "name": "Giáp Vai", "icon": "🔰"},
		{"id": "RING", "name": "Nhẫn Ngọc", "icon": "💍"},
		{"id": "GLOVES", "name": "Găng Tay", "icon": "🧤"},
		{"id": "ACCESSORY", "name": "Pháp Bảo", "icon": "🔮"},
		{"id": "OFF_HAND", "name": "VK Phụ", "icon": "🛡️"}
	]

	var current_slot_name: String = "Mũ Giáp"
	var current_slot_icon: String = "🪖"
	for s_entry in all_slots_info:
		if str(s_entry["id"]) == _equipment_selected_slot:
			current_slot_name = str(s_entry["name"])
			current_slot_icon = str(s_entry["icon"])
			break

	# Top Header & Fast Actions Row
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 8)

	var title_lbl := Label.new()
	title_lbl.text = "%s Ô TRANG BỊ: %s" % [current_slot_icon, current_slot_name.to_upper()]
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.45, 0.92, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var quick_eq_btn := Button.new()
	quick_eq_btn.text = "⚡ Trang Bị Nhanh"
	quick_eq_btn.custom_minimum_size = Vector2(120, 28)
	quick_eq_btn.add_theme_font_size_override("font_size", 11)
	quick_eq_btn.modulate = Color(1.0, 0.92, 0.45)
	quick_eq_btn.pressed.connect(func(): _on_quick_equip_pressed(hid, hname))
	header_hbox.add_child(quick_eq_btn)

	var quick_uneq_btn := Button.new()
	quick_uneq_btn.text = "🔄 Tháo Đồ Nhanh"
	quick_uneq_btn.custom_minimum_size = Vector2(115, 28)
	quick_uneq_btn.add_theme_font_size_override("font_size", 11)
	quick_uneq_btn.modulate = Color(1.0, 0.65, 0.65)
	quick_uneq_btn.pressed.connect(func(): _on_quick_unequip_pressed(hid, hname))
	header_hbox.add_child(quick_uneq_btn)

	_tab_content_vbox.add_child(header_hbox)

	# Collect matching items for _equipment_selected_slot
	var matching_items: Array = []
	var equipped_in_slot: Dictionary = equips.get(_equipment_selected_slot, {})

	if not equipped_in_slot.is_empty():
		matching_items.append(equipped_in_slot)

	for it in all_equipment:
		if not (it is Dictionary):
			continue
		var item_id: String = _extract_item_id(it)
		if not equipped_in_slot.is_empty():
			var eq_id: String = _extract_item_id(equipped_in_slot)
			if item_id == eq_id:
				continue

		var item_slot: String = _extract_item_slot_type(it)
		if _is_item_matching_slot(item_slot, _equipment_selected_slot):
			matching_items.append(it)

	# Apply rarity filter if set
	var filtered_items: Array = []
	for it in matching_items:
		var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else it
		var r_star: int = int(tmpl.get("rarity", 1))
		if _equipment_rarity_filter == 5 and r_star < 5:
			continue
		elif _equipment_rarity_filter == 4 and r_star != 4:
			continue
		elif _equipment_rarity_filter == 3 and r_star > 3:
			continue
		filtered_items.append(it)

	# Determine inspected item:
	var inspected_item: Dictionary = {}
	if not _equipment_inspected_item_id.is_empty():
		for it in filtered_items:
			var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else it
			var item_id: String = str(eq.get("id", it.get("id", "")))
			if item_id == _equipment_inspected_item_id:
				inspected_item = it
				break

	if inspected_item.is_empty() and not filtered_items.is_empty():
		inspected_item = filtered_items[0]
		var eq_0: Dictionary = inspected_item.get("equipment", {}) if inspected_item.get("equipment") is Dictionary else inspected_item
		_equipment_inspected_item_id = str(eq_0.get("id", inspected_item.get("id", "")))

	# =========================================================================
	# GENSHIN ARTIFACT 2-COLUMN SPLIT
	# =========================================================================
	var genshin_split := HBoxContainer.new()
	genshin_split.add_theme_constant_override("separation", 10)
	genshin_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	genshin_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tab_content_vbox.add_child(genshin_split)

	# --- COLUMN 1: ARTIFACT GRID (Kho Thánh Di Vật / Trang Bị) ---
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(210, 0)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.0
	left_col.add_theme_constant_override("separation", 6)
	genshin_split.add_child(left_col)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 4)
	left_col.add_child(filter_row)

	var filter_lbl := Label.new()
	filter_lbl.text = "%s (%d)" % [current_slot_name, filtered_items.size()]
	filter_lbl.add_theme_font_size_override("font_size", 11)
	filter_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	filter_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(filter_lbl)

	for f_opt in [
		{"label": "Tất Cả", "val": 0},
		{"label": "5★", "val": 5},
		{"label": "4★", "val": 4},
		{"label": "1-3★", "val": 3}
	]:
		var f_btn := Button.new()
		f_btn.text = str(f_opt["label"])
		f_btn.custom_minimum_size = Vector2(38, 22)
		f_btn.add_theme_font_size_override("font_size", 9)
		if _equipment_rarity_filter == int(f_opt["val"]):
			f_btn.modulate = Color(1.0, 0.88, 0.35)
		else:
			f_btn.modulate = Color(0.75, 0.85, 0.95)
		f_btn.pressed.connect(func():
			_equipment_rarity_filter = int(f_opt["val"])
			_render_tab_equipment(_selected_hero)
		)
		filter_row.add_child(f_btn)

	var grid_scroll := ScrollContainer.new()
	grid_scroll.custom_minimum_size = Vector2(0, 300)
	grid_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(grid_scroll)

	if filtered_items.is_empty():
		var empty_box := CenterContainer.new()
		empty_box.custom_minimum_size = Vector2(0, 180)
		empty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var empty_lbl := Label.new()
		empty_lbl.text = "📦 Không có trang bị nào cho ô [%s]\ntrong Túi Đồ hoặc trên Tướng." % current_slot_name
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		empty_box.add_child(empty_lbl)
		grid_scroll.add_child(empty_box)
	else:
		var art_grid := GridContainer.new()
		art_grid.columns = 2
		art_grid.add_theme_constant_override("h_separation", 6)
		art_grid.add_theme_constant_override("v_separation", 6)
		art_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_scroll.add_child(art_grid)

		for it in filtered_items:
			var eq: Dictionary = it.get("equipment", {}) if it.get("equipment") is Dictionary else it
			var tmpl: Dictionary = it.get("template", {}) if it.get("template") is Dictionary else it
			var item_id: String = str(eq.get("id", it.get("id", "")))
			var item_name: String = str(tmpl.get("name", it.get("name", "Trang bị")))
			var estar: int = int(tmpl.get("rarity", eq.get("starLevel", 1)))
			var eenh: int = int(eq.get("enhanceLevel", it.get("enhanceLevel", 0)))
			var eq_hero_id: String = str(eq.get("equippedHeroId", it.get("equippedHeroId", "")))
			var is_curr_hero: bool = (eq_hero_id == hid and not hid.is_empty())
			var is_inspected: bool = (item_id == _equipment_inspected_item_id)
			var r_col: Color = _get_rarity_border_color(estar)

			var art_card := PanelContainer.new()
			art_card.custom_minimum_size = Vector2(96, 68)
			art_card.clip_contents = true

			var astyle := StyleBoxFlat.new()
			astyle.corner_radius_top_left = 6
			astyle.corner_radius_top_right = 6
			astyle.corner_radius_bottom_left = 6
			astyle.corner_radius_bottom_right = 6

			if is_inspected:
				astyle.bg_color = Color(0.12, 0.18, 0.28, 0.96)
				astyle.border_width_left = 2
				astyle.border_width_top = 2
				astyle.border_width_right = 2
				astyle.border_width_bottom = 2
				astyle.border_color = Color(0.35, 0.95, 1.0)
			else:
				astyle.bg_color = Color(0.06, 0.08, 0.13, 0.90)
				astyle.border_width_left = 1
				astyle.border_width_top = 1
				astyle.border_width_right = 1
				astyle.border_width_bottom = 1
				astyle.border_color = r_col

			art_card.add_theme_stylebox_override("panel", astyle)

			var am := MarginContainer.new()
			am.mouse_filter = Control.MOUSE_FILTER_IGNORE
			am.add_theme_constant_override("margin_left", 4)
			am.add_theme_constant_override("margin_top", 4)
			am.add_theme_constant_override("margin_right", 4)
			am.add_theme_constant_override("margin_bottom", 4)
			art_card.add_child(am)

			var avbox := VBoxContainer.new()
			avbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			avbox.add_theme_constant_override("separation", 2)
			am.add_child(avbox)

			var atop := HBoxContainer.new()
			atop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var aicon := Label.new()
			aicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			aicon.text = current_slot_icon
			aicon.add_theme_font_size_override("font_size", 9)
			atop.add_child(aicon)

			var astar_lbl := Label.new()
			astar_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			astar_lbl.text = "★".repeat(estar)
			astar_lbl.add_theme_font_size_override("font_size", 8)
			astar_lbl.add_theme_color_override("font_color", r_col)
			astar_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			atop.add_child(astar_lbl)

			if eenh > 0:
				var aenh_lbl := Label.new()
				aenh_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				aenh_lbl.text = "+%d" % eenh
				aenh_lbl.add_theme_font_size_override("font_size", 8)
				aenh_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
				atop.add_child(aenh_lbl)
			avbox.add_child(atop)

			var aname_lbl := Label.new()
			aname_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			aname_lbl.text = item_name
			aname_lbl.clip_text = true
			aname_lbl.add_theme_font_size_override("font_size", 9)
			aname_lbl.add_theme_color_override("font_color", r_col)
			avbox.add_child(aname_lbl)

			var astatus_lbl := Label.new()
			astatus_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if is_curr_hero:
				astatus_lbl.text = "✅ Đang mặc"
				astatus_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
			elif not eq_hero_id.is_empty():
				astatus_lbl.text = "👤 Đang dùng"
				astatus_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
			else:
				astatus_lbl.text = "📦 Trong Túi"
				astatus_lbl.add_theme_color_override("font_color", Color(0.65, 0.80, 0.95))
			astatus_lbl.add_theme_font_size_override("font_size", 8)
			avbox.add_child(astatus_lbl)

			var abtn := Button.new()
			abtn.flat = true
			abtn.set_anchors_preset(Control.PRESET_FULL_RECT)
			abtn.pressed.connect(func():
				_equipment_inspected_item_id = item_id
				_render_tab_equipment(_selected_hero)
			)
			art_card.add_child(abtn)
			art_grid.add_child(art_card)

	# --- COLUMN 2: GENSHIN ARTIFACT DETAILS & ACTIONS ---
	var right_detail_card := PanelContainer.new()
	right_detail_card.custom_minimum_size = Vector2(240, 0)
	right_detail_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_detail_card.size_flags_stretch_ratio = 1.15
	var rd_style := StyleBoxFlat.new()
	rd_style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	rd_style.border_width_left = 1
	rd_style.border_width_top = 1
	rd_style.border_width_right = 1
	rd_style.border_width_bottom = 1
	rd_style.border_color = Color(0.25, 0.38, 0.55, 0.6)
	rd_style.corner_radius_top_left = 8
	rd_style.corner_radius_top_right = 8
	rd_style.corner_radius_bottom_left = 8
	rd_style.corner_radius_bottom_right = 8
	right_detail_card.add_theme_stylebox_override("panel", rd_style)
	genshin_split.add_child(right_detail_card)

	var rdm := MarginContainer.new()
	rdm.add_theme_constant_override("margin_left", 12)
	rdm.add_theme_constant_override("margin_top", 10)
	rdm.add_theme_constant_override("margin_right", 12)
	rdm.add_theme_constant_override("margin_bottom", 10)
	right_detail_card.add_child(rdm)

	var rdvbox := VBoxContainer.new()
	rdvbox.add_theme_constant_override("separation", 6)
	rdm.add_child(rdvbox)

	if inspected_item.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "👈 Hãy chọn một trang bị ở danh sách bên trái để kiểm tra chi tiết và trang bị!"
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		rdvbox.add_child(empty_lbl)
	else:
		var insp_eq: Dictionary = inspected_item.get("equipment", {}) if inspected_item.get("equipment") is Dictionary else inspected_item
		var insp_tmpl: Dictionary = inspected_item.get("template", {}) if inspected_item.get("template") is Dictionary else inspected_item
		var insp_id: String = str(insp_eq.get("id", inspected_item.get("id", "")))
		var insp_name: String = str(insp_tmpl.get("name", inspected_item.get("name", "Trang bị")))
		var insp_star: int = int(insp_tmpl.get("rarity", insp_eq.get("starLevel", 1)))
		var insp_enh: int = int(insp_eq.get("enhanceLevel", inspected_item.get("enhanceLevel", 0)))
		var insp_hero_id: String = str(insp_eq.get("equippedHeroId", inspected_item.get("equippedHeroId", "")))
		var is_on_curr_hero: bool = (insp_hero_id == hid and not hid.is_empty())
		var insp_r_col: Color = _get_rarity_border_color(insp_star)
		var enh_bonus: float = 1.0 + float(insp_enh) * 0.05

		var i_hp: int = int(float(insp_tmpl.get("bonusHp", 0)) * enh_bonus)
		var i_atk: int = int(float(insp_tmpl.get("bonusAttack", insp_tmpl.get("atkBonus", 0))) * enh_bonus)
		var i_def: int = int(float(insp_tmpl.get("bonusDefense", insp_tmpl.get("defBonus", 0))) * enh_bonus)
		var i_spd: int = int(insp_tmpl.get("bonusSpeed", insp_tmpl.get("spdBonus", 0)))
		var i_matk: int = int(float(insp_tmpl.get("bonusMatk", 0)) * enh_bonus)

		var v2: Dictionary = insp_tmpl.get("v2Stats", {}) if insp_tmpl.get("v2Stats") is Dictionary else {}
		var i_crit: float = float(v2.get("critRate", 0.0))
		var i_cdmg: float = float(v2.get("critDamage", 0.0))
		var i_eva: float = float(v2.get("evasion", 0.0))
		var i_ls: int = int(v2.get("lifesteal", 0))
		var i_dr: int = int(v2.get("damageReduction", 0))
		var i_pen: int = int(v2.get("armorPen", v2.get("magicPen", 0)))
		var i_acc: int = int(v2.get("accuracy", 0))

		# Header: Name, Stars, Type
		var d_head := HBoxContainer.new()
		var d_name := Label.new()
		d_name.text = insp_name
		d_name.clip_text = true
		d_name.add_theme_font_size_override("font_size", 14)
		d_name.add_theme_color_override("font_color", insp_r_col)
		d_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d_head.add_child(d_name)

		var d_star := Label.new()
		d_star.text = "★".repeat(insp_star)
		d_star.add_theme_font_size_override("font_size", 12)
		d_star.add_theme_color_override("font_color", insp_r_col)
		d_head.add_child(d_star)
		rdvbox.add_child(d_head)

		var d_subhead := Label.new()
		d_subhead.text = "%s %s • Cấp Cường Hóa +%d / 20" % [current_slot_icon, current_slot_name, insp_enh]
		d_subhead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d_subhead.add_theme_font_size_override("font_size", 10)
		d_subhead.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		rdvbox.add_child(d_subhead)

		rdvbox.add_child(HSeparator.new())

		# Main Stat Banner (Genshin Style)
		var main_stat_box := PanelContainer.new()
		var ms_style := StyleBoxFlat.new()
		ms_style.bg_color = Color(0.10, 0.14, 0.22, 0.95)
		ms_style.corner_radius_top_left = 6
		ms_style.corner_radius_top_right = 6
		ms_style.corner_radius_bottom_left = 6
		ms_style.corner_radius_bottom_right = 6
		ms_style.border_width_left = 3
		ms_style.border_color = insp_r_col
		main_stat_box.add_theme_stylebox_override("panel", ms_style)

		var ms_m := MarginContainer.new()
		ms_m.add_theme_constant_override("margin_left", 8)
		ms_m.add_theme_constant_override("margin_top", 6)
		ms_m.add_theme_constant_override("margin_right", 8)
		ms_m.add_theme_constant_override("margin_bottom", 6)
		main_stat_box.add_child(ms_m)

		var ms_vbox := VBoxContainer.new()
		ms_vbox.add_theme_constant_override("separation", 2)
		ms_m.add_child(ms_vbox)

		var ms_title := Label.new()
		ms_title.text = "THUỘC TÍNH CHÍNH"
		ms_title.add_theme_font_size_override("font_size", 9)
		ms_title.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		ms_vbox.add_child(ms_title)

		var ms_val_str := ""
		if i_atk > 0:
			ms_val_str = "⚔️ Tấn Công: +%d" % i_atk
		elif i_def > 0:
			ms_val_str = "🛡️ Phòng Ngự: +%d" % i_def
		elif i_hp > 0:
			ms_val_str = "❤️ Sinh Lực: +%d" % i_hp
		elif i_matk > 0:
			ms_val_str = "🔮 Công Phép: +%d" % i_matk
		elif i_spd > 0:
			ms_val_str = "💨 Tốc Độ: +%d" % i_spd
		else:
			ms_val_str = "✨ Toàn Diện: +15"

		var ms_val_lbl := Label.new()
		ms_val_lbl.text = ms_val_str
		ms_val_lbl.add_theme_font_size_override("font_size", 16)
		ms_val_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		ms_vbox.add_child(ms_val_lbl)

		# Comparison with currently equipped item in this slot (if any)
		if not equipped_in_slot.is_empty():
			var cur_eq_dict: Dictionary = equipped_in_slot.get("equipment", {}) if equipped_in_slot.get("equipment") is Dictionary else equipped_in_slot
			var cur_id: String = str(cur_eq_dict.get("id", equipped_in_slot.get("id", "")))
			if cur_id != insp_id:
				var cur_tmpl: Dictionary = equipped_in_slot.get("template", {}) if equipped_in_slot.get("template") is Dictionary else equipped_in_slot
				var c_enh: int = int(cur_eq_dict.get("enhanceLevel", equipped_in_slot.get("enhanceLevel", 0)))
				var c_enh_b: float = 1.0 + float(c_enh) * 0.05
				var c_atk: int = int(float(cur_tmpl.get("bonusAttack", cur_tmpl.get("atkBonus", 0))) * c_enh_b)
				var c_def: int = int(float(cur_tmpl.get("bonusDefense", cur_tmpl.get("defBonus", 0))) * c_enh_b)
				var c_hp: int = int(float(cur_tmpl.get("bonusHp", 0)) * c_enh_b)
				var d_atk: int = i_atk - c_atk
				var d_def: int = i_def - c_def
				var d_hp: int = i_hp - c_hp
				var cmp_parts: Array[String] = []
				if d_atk != 0: cmp_parts.append("%s%d ATK" % [("▲ +" if d_atk > 0 else "▼ "), d_atk])
				if d_def != 0: cmp_parts.append("%s%d DEF" % [("▲ +" if d_def > 0 else "▼ "), d_def])
				if d_hp != 0: cmp_parts.append("%s%d HP" % [("▲ +" if d_hp > 0 else "▼ "), d_hp])
				if not cmp_parts.is_empty():
					var cmp_lbl := Label.new()
					cmp_lbl.text = "So với đang mặc: %s" % ", ".join(cmp_parts)
					cmp_lbl.add_theme_font_size_override("font_size", 9)
					cmp_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if (d_atk >= 0 and d_def >= 0 and d_hp >= 0) else Color(1.0, 0.8, 0.4))
					ms_vbox.add_child(cmp_lbl)

		rdvbox.add_child(main_stat_box)

		# Substats List
		var sub_header := Label.new()
		sub_header.text = "THUỘC TÍNH PHỤ"
		sub_header.add_theme_font_size_override("font_size", 10)
		sub_header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		rdvbox.add_child(sub_header)

		var sub_list_vbox := VBoxContainer.new()
		sub_list_vbox.add_theme_constant_override("separation", 2)
		rdvbox.add_child(sub_list_vbox)

		var sub_lines: Array[String] = []
		if i_crit > 0.0: sub_lines.append("• 💥 Tỷ lệ bạo kích: +%.1f%%" % i_crit)
		if i_cdmg > 0.0: sub_lines.append("• ⚡ Sát thương bạo kích: +%.1f%%" % i_cdmg)
		if i_eva > 0.0: sub_lines.append("• 🌀 Né tránh: +%.1f%%" % i_eva)
		if i_ls > 0: sub_lines.append("• 🩸 Hút máu: +%d%%" % i_ls)
		if i_dr > 0: sub_lines.append("• 🛡️ Giảm sát thương: +%d%%" % i_dr)
		if i_pen > 0: sub_lines.append("• 🗡️ Xuyên giáp/phép: +%d" % i_pen)
		if i_acc > 0: sub_lines.append("• 🎯 Chính xác: +%d" % i_acc)
		if i_spd > 0 and ms_val_str.find("Tốc Độ") == -1: sub_lines.append("• 💨 Tốc độ: +%d" % i_spd)
		if i_hp > 0 and ms_val_str.find("Sinh Lực") == -1: sub_lines.append("• ❤️ Sinh lực: +%d" % i_hp)
		if i_def > 0 and ms_val_str.find("Phòng Ngự") == -1: sub_lines.append("• 🛡️ Phòng ngự: +%d" % i_def)

		if sub_lines.is_empty():
			sub_lines.append("• ✨ Không có thuộc tính phụ kích hoạt.")

		for line_txt in sub_lines:
			var s_lbl := Label.new()
			s_lbl.text = line_txt
			s_lbl.add_theme_font_size_override("font_size", 10)
			s_lbl.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98))
			sub_list_vbox.add_child(s_lbl)

		# Set Bonus Block
		rdvbox.add_child(HSeparator.new())
		var set_header := Label.new()
		set_header.text = "KÍCH HOẠT THUỘC TÍNH BỘ SET"
		set_header.add_theme_font_size_override("font_size", 10)
		set_header.add_theme_color_override("font_color", Color(0.45, 0.90, 1.0))
		rdvbox.add_child(set_header)

		var set_desc := Label.new()
		set_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		set_desc.text = "● Bộ 2 món: Tăng 15% Sát thương tổng thể\n● Bộ 4 món: Kích hoạt hiệu ứng Chữ Ký / Lấp Lánh khi vào trận"
		set_desc.add_theme_font_size_override("font_size", 9)
		set_desc.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		rdvbox.add_child(set_desc)

		# Status Banner
		var stat_lbl := Label.new()
		if is_on_curr_hero:
			stat_lbl.text = "✅ Đang trang bị trên [%s]" % hname
			stat_lbl.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65))
		elif not insp_hero_id.is_empty():
			stat_lbl.text = "⚠️ Đang mặc trên tướng khác (Trang bị sẽ chuyển sang %s)" % hname
			stat_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		else:
			stat_lbl.text = "📦 Đang nằm trong Túi Đồ (Chưa ai mặc)"
			stat_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0))
		stat_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stat_lbl.add_theme_font_size_override("font_size", 10)
		rdvbox.add_child(stat_lbl)

		# Action Buttons Row
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)
		rdvbox.add_child(btn_row)

		if is_on_curr_hero:
			var unequip_btn := Button.new()
			unequip_btn.text = "🔄 Gỡ Trang Bị"
			unequip_btn.custom_minimum_size = Vector2(110, 32)
			unequip_btn.add_theme_font_size_override("font_size", 11)
			unequip_btn.modulate = Color(1.0, 0.65, 0.65)
			unequip_btn.pressed.connect(func(): _on_unequip_pressed(insp_id, insp_name))
			btn_row.add_child(unequip_btn)
		else:
			var equip_btn := Button.new()
			equip_btn.text = "🔄 Thay Thế" if not equipped_in_slot.is_empty() else "🛡️ Trang Bị"
			equip_btn.custom_minimum_size = Vector2(110, 32)
			equip_btn.add_theme_font_size_override("font_size", 11)
			equip_btn.modulate = Color(0.45, 0.95, 0.65)
			equip_btn.pressed.connect(func(): _on_equip_pressed(insp_id, insp_name, hid, hname))
			btn_row.add_child(equip_btn)

		var enh_btn := Button.new()
		enh_btn.text = "⬆️ Cường Hóa"
		enh_btn.custom_minimum_size = Vector2(100, 32)
		enh_btn.add_theme_font_size_override("font_size", 11)
		enh_btn.modulate = Color(1.0, 0.85, 0.35)
		enh_btn.pressed.connect(func(): _on_enhance_eq_pressed(insp_id, insp_name))
		btn_row.add_child(enh_btn)

# ==============================================================================
# PICK ME UP STAR PROMOTION RITUAL (FIXED & UPGRADED SCHEMA)
# ==============================================================================

func _on_open_promote_pressed() -> void:
	if _selected_hero.is_empty():
		return
	var star := int(_selected_hero.get("rarity", 1))
	var promo_rank := int(_selected_hero.get("promotionRank", 0))
	var star_ceiling := int(_selected_hero.get("starCeiling", star * 10))
	var max_lvl := int(_selected_hero.get("maxLevel", mini(star_ceiling, (promo_rank + 1) * 10)))

	if star_ceiling > max_lvl:
		# Hero needs Breakthrough!
		if _breakthrough_modal_backdrop != null:
			_breakthrough_modal_backdrop.visible = true
		await _load_breakthrough_preview()
	else:
		# Hero needs Star Promotion!
		if _promote_modal_backdrop != null:
			_promote_modal_backdrop.visible = true
		promote_panel.visible = true
		await _load_promote_preview()

func _load_breakthrough_preview() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	if hero_id.is_empty():
		return

	status_label.text = "🔮 Đang kiểm tra điều kiện Nghi Thức Đột Phá Cấp Độ..."
	var res := await ApiClient.get_req("/api/heroes/%s/breakthrough/preview" % hero_id)

	for c in _breakthrough_req_box.get_children():
		c.queue_free()

	if not res["ok"] or not (res["data"] is Dictionary):
		status_label.text = "❌ Lỗi nạp thông tin đột phá: " + str(res["error"])
		return

	_breakthrough_preview_data = res["data"]
	var h_info: Dictionary = _breakthrough_preview_data.get("hero", {})
	var reqs: Dictionary = _breakthrough_preview_data.get("requirements", {})
	var proj: Dictionary = _breakthrough_preview_data.get("projected", {})
	var can_bt := bool(_breakthrough_preview_data.get("canPromote", false))

	var cur_rank := int(h_info.get("currentRank", 0))
	var next_rank := int(h_info.get("nextRank", cur_rank + 1))
	var cur_max := int(h_info.get("currentMaxLevel", (cur_rank + 1) * 10))
	var next_max := int(h_info.get("nextMaxLevel", (next_rank + 1) * 10))
	var star_ceil := int(h_info.get("starCeiling", int(h_info.get("rarity", 1)) * 10))
	var hname := str(h_info.get("name", _selected_hero.get("name", "Hero")))

	_breakthrough_header_label.text = "⚡ NGHI THỨC ĐỘT PHÁ CẤP ĐỘ: BẬC +%d ➔ +%d" % [cur_rank, next_rank]

	var hp_val := int(proj.get("maxHp", 0))
	var atk_val := int(proj.get("attack", 0))
	var def_val := int(proj.get("defense", 0))
	var spd_val := int(proj.get("speed", 0))

	_breakthrough_info_label.text = (
		"📈 ĐỘT PHÁ GIỚI HẠN CẤP ĐỘ KHI ĐẠT BẬC +%d:\n" % next_rank +
		"   • Mở khóa giới hạn cấp: Lv.%d ➔ Lv.%d (Trần tiềm năng sao: Lv.%d)\n" % [cur_max, next_max, star_ceil] +
		"   • Tăng trưởng chỉ số: +5% Toàn bộ HP, Tấn công, Phòng thủ, Tốc độ\n" +
		"   • Thuộc tính sau Đột Phá: HP %d | ATK %d | DEF %d | SPD %d" % [hp_val, atk_val, def_val, spd_val]
	)

	var req_lbl := Label.new()
	req_lbl.text = "📋 ĐIỀU KIỆN & NGUYÊN LIỆU KHAI MỞ ĐỘT PHÁ:"
	req_lbl.add_theme_font_size_override("font_size", 13)
	req_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_breakthrough_req_box.add_child(req_lbl)

	# Level requirement
	var req_lvl := int(reqs.get("requiredHeroLevel", next_rank * 10))
	var cur_lvl := int(h_info.get("level", 1))
	var meets_lvl := bool(reqs.get("meetsLevel", cur_lvl >= req_lvl))
	var lvl_line := Label.new()
	lvl_line.text = "   • 🎯 Cấp độ yêu cầu: Lv.%d / %d — %s" % [
		cur_lvl, req_lvl,
		("Đủ điều kiện ✅" if meets_lvl else "Chưa đạt cấp yêu cầu ❌")
	]
	lvl_line.add_theme_font_size_override("font_size", 12)
	lvl_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if meets_lvl else Color(1.0, 0.45, 0.45))
	_breakthrough_req_box.add_child(lvl_line)

	# Star requirement
	var req_star := int(reqs.get("requiredStar", next_rank + 1))
	var cur_star := int(h_info.get("rarity", 1))
	var meets_star := bool(reqs.get("meetsStar", cur_star >= req_star))
	var star_line := Label.new()
	star_line.text = "   • ⭐ Phẩm chất Sao: Tối thiểu %d★ (Hero hiện tại: %d★) — %s" % [
		req_star, cur_star,
		("Đủ điều kiện ✅" if meets_star else "Cần Thăng Sao trước ❌")
	]
	star_line.add_theme_font_size_override("font_size", 12)
	star_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if meets_star else Color(1.0, 0.45, 0.45))
	_breakthrough_req_box.add_child(star_line)

	# Material requirement
	var mat_qty := int(reqs.get("materialQuantity", next_rank * 5))
	var cur_mat := int(reqs.get("currentMaterialCount", 0))
	var has_mat := bool(reqs.get("hasEnoughMaterial", cur_mat >= mat_qty))
	var mat_line := Label.new()
	mat_line.text = "   • 💠 Dấu ấn Đột Phá Hero: %d / %d (Hiện có: %s) — %s" % [
		cur_mat, mat_qty, _format_num(cur_mat),
		("Đủ điều kiện ✅" if has_mat else "Thiếu nguyên liệu ❌")
	]
	mat_line.add_theme_font_size_override("font_size", 12)
	mat_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if has_mat else Color(1.0, 0.45, 0.45))
	_breakthrough_req_box.add_child(mat_line)

	# Silver requirement
	var silver_cost := int(reqs.get("silverCost", 5000))
	var has_silver := bool(reqs.get("hasEnoughSilver", GameState.silver_coins >= silver_cost))
	var silver_line := Label.new()
	silver_line.text = "   • 🪙 Chi phí Vàng (Bạc): %s (Hiện có: %s) — %s" % [
		_format_num(silver_cost), _format_num(GameState.silver_coins),
		("Đủ điều kiện ✅" if has_silver else "Thiếu Vàng ❌")
	]
	silver_line.add_theme_font_size_override("font_size", 12)
	silver_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if has_silver else Color(1.0, 0.45, 0.45))
	_breakthrough_req_box.add_child(silver_line)

	_confirm_breakthrough_btn.disabled = not can_bt
	_confirm_breakthrough_btn.text = "⚡ Xác Nhận Đột Phá Bậc +%d (Mở Khóa Lv.%d)" % [next_rank, next_max]
	status_label.text = "Sẵn sàng Đột phá Cấp độ cho [%s]." % hname

func _on_confirm_breakthrough_pressed() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	var hname := str(_selected_hero.get("name", "Hero"))
	if hero_id.is_empty():
		return
	_confirm_breakthrough_btn.disabled = true
	status_label.text = "⚡ Đang tiến hành Nghi Thức Đột Phá Cấp Độ cho [%s]..." % hname

	var res := await ApiClient.post_req("/api/heroes/%s/breakthrough" % hero_id, {})
	if not res["ok"]:
		status_label.text = "❌ Đột phá thất bại: " + str(res["error"])
		_confirm_breakthrough_btn.disabled = false
		return

	_play_3d_star_promotion_burst()
	var new_rank := int(res["data"].get("promotionRank", 1)) if res["data"] is Dictionary else 1
	var new_max := int(res["data"].get("maxLevel", (new_rank + 1) * 10)) if res["data"] is Dictionary else 20
	status_label.text = "🎉 ĐỘT PHÁ THÀNH CÔNG! [%s] đã đạt Bậc Đột Phá +%d, mở khóa giới hạn Lv.%d!" % [hname, new_rank, new_max]
	if _breakthrough_modal_backdrop != null:
		_breakthrough_modal_backdrop.visible = false
	await _sync_all_roster_data(hero_id)

func _load_promote_preview() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	if hero_id.is_empty():
		return

	status_label.text = "🔮 Đang kiểm tra điều kiện Nghi Thức Thăng Sao (Pick Me Up)..."
	var res := await ApiClient.get_req("/api/heroes/%s/promote-star/preview" % hero_id)
	if not res["ok"] or not (res["data"] is Dictionary):
		status_label.text = "❌ Lỗi nạp thông tin thăng sao: " + str(res["error"])
		return

	_preview_data = res["data"]
	_selected_fodder_ids.clear()
	fodder_item_list.clear()

	var h_info: Dictionary = _preview_data.get("hero", {}) if _preview_data.get("hero") is Dictionary else {}
	var reqs: Dictionary = _preview_data.get("requirements", {}) if _preview_data.get("requirements") is Dictionary else {}
	var proj: Dictionary = _preview_data.get("projectedStats", {}) if _preview_data.get("projectedStats") is Dictionary else {}
	var available_fodders: Array = _preview_data.get("availableFodders", []) if _preview_data.get("availableFodders") is Array else []

	var cur_star := int(h_info.get("currentStar", _selected_hero.get("rarity", 1)))
	var next_star := int(h_info.get("nextStar", cur_star + 1))
	var cur_lvl := int(h_info.get("currentLevel", _selected_hero.get("level", 1)))
	var req_lvl := int(reqs.get("requiredLevel", cur_star * 10))
	var next_max_lvl := int(h_info.get("nextMaxLevel", next_star * 10))
	var cur_slots := int(h_info.get("currentImprintSlots", 1))
	var next_slots := int(h_info.get("nextImprintSlots", cur_slots))
	var req_fodder := int(reqs.get("requiredFodderCount", cur_star))
	var silver_cost := int(reqs.get("silverCost", 10000))

	var proj_text := ""
	if not proj.is_empty():
		var p_base: Dictionary = proj.get("base", {}) if proj.get("base") is Dictionary else {}
		proj_text = "\n📈 Đột phá chỉ số sau khi lên %d★:\n   • Giới hạn Cấp: Lv.%d ➔ Lv.%d | Ô Ấn Ký: %d ➔ %d\n   • HP: %d | ATK: %d | DEF: %d\n   • STR %d | INT %d | STA %d | AGI %d" % [
			next_star, req_lvl, next_max_lvl, cur_slots, next_slots,
			int(proj.get("maxHp", 0)), int(proj.get("attack", 0)), int(proj.get("defense", 0)),
			int(p_base.get("str", 0)), int(p_base.get("int", 0)), int(p_base.get("sta", 0)), int(p_base.get("agi", 0))
		]

	var lvl_status := "✅ Đã đạt Lv.%d/%d" % [cur_lvl, req_lvl] if cur_lvl >= req_lvl else "⚠️ Chưa đủ cấp (Hiện tại Lv.%d / Cần Lv.%d)" % [cur_lvl, req_lvl]
	promote_info_label.text = (
		"🌟 NGHI THỨC HỢP NHẤT: %d★ ➔ %d★\n" % [cur_star, next_star] +
		"• Điều kiện Cấp: %s\n" % lvl_status +
		"• Phôi hiến tế: Cần %d Tướng %d★ (Hiện có %d phôi khả dụng)\n" % [req_fodder, cur_star, available_fodders.size()] +
		"• Chi phí: 🪙 %d Vàng (Hiện có: %d)" % [silver_cost, GameState.silver_coins] +
		proj_text
	)

	if _quick_level_for_promote_btn != null:
		var b1 := int(GameState.materials.get("SAMPLE_HERO_EXP_100", 0))
		var b2 := int(GameState.materials.get("SAMPLE_HERO_EXP_1000", 0))
		var b3 := int(GameState.materials.get("SAMPLE_HERO_EXP_10000", 0))
		var total_exp_books := b1 + b2 + b3
		_quick_level_for_promote_btn.visible = (cur_lvl < req_lvl)
		_quick_level_for_promote_btn.text = "📘 Đọc Sách EXP Cho Lên Lv.%d Ngay (Tổng Sách: %s)" % [req_lvl, _format_num(total_exp_books)]
		_quick_level_for_promote_btn.disabled = (total_exp_books <= 0)

	if available_fodders.is_empty():
		fodder_item_list.add_item("(Chưa có Tướng %d★ rảnh rỗi để hiến tế — Bấm Triệu Hồi Nhanh ở cột trái!)" % cur_star)
		confirm_promote_btn.disabled = true
		if _auto_pick_fodder_btn != null:
			_auto_pick_fodder_btn.disabled = true
	else:
		for f in available_fodders:
			if f is Dictionary:
				var txt := "★%d %s (Lv.%d) — Hệ %s" % [
					int(f.get("rarity", cur_star)),
					str(f.get("name", "Hero")),
					int(f.get("level", 1)),
					str(f.get("heroClass", "UNCLASSIFIED"))
				]
				fodder_item_list.add_item(txt)
		confirm_promote_btn.disabled = true
		if _auto_pick_fodder_btn != null:
			_auto_pick_fodder_btn.disabled = available_fodders.size() < req_fodder

	status_label.text = "Hãy chọn đủ %d Tướng %d★ làm phôi hợp nhất." % [req_fodder, cur_star]

func _on_auto_pick_fodders_pressed() -> void:
	var available_fodders: Array = _preview_data.get("availableFodders", []) if _preview_data.get("availableFodders") is Array else []
	var reqs: Dictionary = _preview_data.get("requirements", {}) if _preview_data.get("requirements") is Dictionary else {}
	var req_fodder := int(reqs.get("requiredFodderCount", 1))
	if available_fodders.size() < req_fodder:
		return

	_selected_fodder_ids.clear()
	fodder_item_list.deselect_all()
	for i in range(req_fodder):
		fodder_item_list.select(i, false)
		var fid := str(available_fodders[i].get("id", ""))
		if fid != "":
			_selected_fodder_ids.append(fid)

	_update_confirm_promote_button_state()

func _on_fodder_selected(index: int, selected: bool) -> void:
	var available_fodders: Array = _preview_data.get("availableFodders", []) if _preview_data.get("availableFodders") is Array else []
	if index < 0 or index >= available_fodders.size():
		return

	var f_id := str(available_fodders[index].get("id", ""))
	if selected:
		if not _selected_fodder_ids.has(f_id):
			_selected_fodder_ids.append(f_id)
	else:
		_selected_fodder_ids.erase(f_id)

	_update_confirm_promote_button_state()

func _update_confirm_promote_button_state() -> void:
	var h_info: Dictionary = _preview_data.get("hero", {}) if _preview_data.get("hero") is Dictionary else {}
	var reqs: Dictionary = _preview_data.get("requirements", {}) if _preview_data.get("requirements") is Dictionary else {}
	var req_fodder := int(reqs.get("requiredFodderCount", 1))
	var cur_lvl := int(h_info.get("currentLevel", _selected_hero.get("level", 1)))
	var req_lvl := int(reqs.get("requiredLevel", 10))
	var has_silver := bool(reqs.get("hasEnoughSilver", true))

	status_label.text = "Đã chọn: %d / %d phôi tướng hiến tế." % [_selected_fodder_ids.size(), req_fodder]
	confirm_promote_btn.disabled = not (
		_selected_fodder_ids.size() == req_fodder
		and cur_lvl >= req_lvl
		and has_silver
	)

func _on_confirm_promote_pressed() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	if hero_id.is_empty():
		return
	confirm_promote_btn.disabled = true
	status_label.text = "🌟 Đang tiến hành Đại Nghi Thức Hợp Nhất Thăng Sao..."

	var res := await ApiClient.post_req("/api/heroes/%s/promote-star" % hero_id, {
		"fodderHeroIds": _selected_fodder_ids
	})

	if not res["ok"]:
		status_label.text = "❌ Thăng sao thất bại: " + str(res["error"])
		confirm_promote_btn.disabled = false
		return

	_play_3d_star_promotion_burst()
	var new_star := int(res["data"].get("newStar", 2)) if res["data"] is Dictionary else 2
	status_label.text = "🎉 ĐỘT PHÁ THÀNH CÔNG! [%s] đã thăng cấp lên %d★!" % [str(_selected_hero.get("name", "Hero")), new_star]
	if _promote_modal_backdrop != null:
		_promote_modal_backdrop.visible = false
	await _sync_all_roster_data(hero_id)

func _on_close_promote_pressed() -> void:
	if _promote_modal_backdrop != null:
		_promote_modal_backdrop.visible = false

# ==============================================================================
# AWAKENING BLOODLINE RITUAL MODAL (THỨC TỈNH HUYẾT MẠCH)
# ==============================================================================

func _on_open_awaken_pressed() -> void:
	if _awaken_modal_backdrop != null:
		_awaken_modal_backdrop.visible = true
	await _load_awaken_preview()

func _load_awaken_preview() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	if hero_id.is_empty():
		return

	status_label.text = "🔮 Đang kiểm tra điều kiện Nghi Thức Thức Tỉnh Huyết Mạch..."
	var res := await ApiClient.get_req("/api/heroes/%s/awaken/preview" % hero_id)

	for c in _awaken_req_box.get_children():
		c.queue_free()

	var cur_rank := int(_selected_hero.get("awakeningRank", 0))
	var star := int(_selected_hero.get("rarity", 1))
	var max_rank := _get_hero_max_imprint_slots(star)
	var next_rank := cur_rank + 1
	var is_max := cur_rank >= max_rank

	if not res["ok"] or not (res["data"] is Dictionary):
		_awaken_header_label.text = "🌟 NGHI THỨC THỨC TỈNH HUYẾT MẠCH: BẬC +%d ➔ +%d" % [cur_rank, next_rank]
		if is_max:
			_awaken_info_label.text = "🌟 Hero này đã đạt Bậc Thức Tỉnh tối đa (+%d)! Toàn bộ %d ô ấn ký huyết mạch cổ đại đã được khai mở trọn vẹn." % [max_rank, max_rank]
			_confirm_awaken_btn.disabled = true
			_confirm_awaken_btn.text = "🌟 Đã Đạt Bậc Thức Tỉnh Tối Đa (+%d)" % max_rank
		else:
			_awaken_info_label.text = (
				"⚡ ĐỘT PHÁ THUỘC TÍNH HUYẾT MẠCH (Bậc +%d ➔ +%d):\n" % [cur_rank, next_rank] +
				"   • Thuộc tính gốc: +10 STR | +10 INT | +10 STA | +10 AGI\n" +
				"   • Sinh lực & Chiến lực: Tăng +5% Max HP & Tăng vọt Lực Chiến\n" +
				"   • Kỹ năng chiến đấu: Tăng +1 Cấp độ kỹ năng chuyên biệt\n" +
				"   • Ấn Ký Huyết Mạch (Imprint): Mở khóa thêm 1 Ô Ấn Ký (trạng thái Trống - sẵn sàng khảm)\n" +
				"   • Đặc điểm tính cách: Khai mở Thiên Phú Thần Thoại ngẫu nhiên (Dragon Heart, Phoenix Blood...)"
			)
			_confirm_awaken_btn.disabled = false
			_confirm_awaken_btn.text = "🌟 Khai Mở Thức Tỉnh Huyết Mạch (+%d)" % next_rank
		return

	_awaken_preview_data = res["data"]
	var h_info: Dictionary = _awaken_preview_data.get("hero", {})
	var reqs: Dictionary = _awaken_preview_data.get("requirements", {})
	var proj: Dictionary = _awaken_preview_data.get("projected", {})
	var can_awaken := bool(_awaken_preview_data.get("canAwaken", false))

	cur_rank = int(h_info.get("currentRank", cur_rank))
	star = int(h_info.get("rarity", star))
	max_rank = int(h_info.get("maxRank", _get_hero_max_imprint_slots(star)))
	next_rank = int(h_info.get("nextRank", cur_rank + 1))
	is_max = bool(h_info.get("isMax", cur_rank >= max_rank))
	var hname := str(h_info.get("name", _selected_hero.get("name", "Hero")))

	_awaken_header_label.text = "🌟 NGHI THỨC THỨC TỈNH HUYẾT MẠCH: BẬC +%d ➔ +%d" % [cur_rank, next_rank]

	if is_max:
		_awaken_info_label.text = "🌟 [%s] đã đạt Bậc Thức Tỉnh tối đa (+%d)!\nToàn bộ %d ô ấn ký huyết mạch cổ đại đã được khai phá trọn vẹn." % [hname, max_rank, max_rank]
		_confirm_awaken_btn.disabled = true
		_confirm_awaken_btn.text = "🌟 Đã Đạt Bậc Thức Tỉnh Tối Đa (+%d)" % max_rank
		return

	var str_val := int(proj.get("str", 0))
	var int_val := int(proj.get("int", 0))
	var sta_val := int(proj.get("sta", 0))
	var agi_val := int(proj.get("agi", 0))

	_awaken_info_label.text = (
		"⚡ ĐỘT PHÁ THUỘC TÍNH KHI ĐẠT BẬC +%d:\n" % next_rank +
		"   • 4 Chỉ số cơ bản: +10 Toàn bộ ➔ STR %d | INT %d | STA %d | AGI %d\n" % [str_val, int_val, sta_val, agi_val] +
		"   • Sinh lực & Chiến lực: Tăng +5% Max HP & Tăng vọt Lực Chiến\n" +
		"   • Kỹ năng chiến đấu: Tăng +1 Cấp độ kỹ năng chuyên biệt\n" +
		"   • Ấn Ký Huyết Mạch (Imprint): Mở khóa thêm 1 Ô Ấn Ký (trạng thái Trống - sẵn sàng khảm)\n" +
		"   • Thiên phú Thần Thoại: Khai mở năng lực ẩn (Dragon Heart, Phoenix Blood, Void Touch...)"
	)

	# Build requirements box
	var req_lbl := Label.new()
	req_lbl.text = "📋 ĐIỀU KIỆN & NGUYÊN LIỆU KHAI MỞ NGHI THỨC:"
	req_lbl.add_theme_font_size_override("font_size", 13)
	req_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	_awaken_req_box.add_child(req_lbl)

	var mat_qty := int(reqs.get("materialQuantity", next_rank * 3))
	var cur_mat := int(reqs.get("currentMaterialCount", 0))
	var has_mat := bool(reqs.get("hasEnoughMaterial", cur_mat >= mat_qty))
	var mat_line := Label.new()
	mat_line.text = "   • 💎 Lõi Thức Tỉnh Hero: %d / %d (Hiện có: %s) — %s" % [
		cur_mat, mat_qty, _format_num(cur_mat),
		("Đủ điều kiện ✅" if has_mat else "Thiếu nguyên liệu ❌")
	]
	mat_line.add_theme_font_size_override("font_size", 12)
	mat_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if has_mat else Color(1.0, 0.45, 0.45))
	_awaken_req_box.add_child(mat_line)

	var silver_cost := int(reqs.get("silverCost", 5000 * next_rank))
	var has_silver := bool(reqs.get("hasEnoughSilver", GameState.silver_coins >= silver_cost))
	var silver_line := Label.new()
	silver_line.text = "   • 🪙 Chi phí Vàng (Bạc): %s (Hiện có: %s) — %s" % [
		_format_num(silver_cost), _format_num(GameState.silver_coins),
		("Đủ điều kiện ✅" if has_silver else "Thiếu Vàng ❌")
	]
	silver_line.add_theme_font_size_override("font_size", 12)
	silver_line.add_theme_color_override("font_color", Color(0.45, 0.95, 0.65) if has_silver else Color(1.0, 0.45, 0.45))
	_awaken_req_box.add_child(silver_line)

	_confirm_awaken_btn.disabled = not can_awaken
	_confirm_awaken_btn.text = "🌟 Khai Mở Thức Tỉnh Huyết Mạch (+%d)" % next_rank
	status_label.text = "Sẵn sàng khai mở Nghi thức Thức Tỉnh Huyết Mạch cho [%s]." % hname

func _on_confirm_awaken_pressed() -> void:
	var hero_id := str(_selected_hero.get("id", ""))
	var hname := str(_selected_hero.get("name", "Hero"))
	if hero_id.is_empty():
		return
	_confirm_awaken_btn.disabled = true
	status_label.text = "🌟 Đang tiến hành Đại Nghi Thức Thức Tỉnh Huyết Mạch cho [%s]..." % hname

	var res := await ApiClient.post_req("/api/heroes/%s/awaken" % hero_id, {})
	if not res["ok"]:
		status_label.text = "❌ Thức tỉnh thất bại: " + str(res["error"])
		_confirm_awaken_btn.disabled = false
		return

	_play_3d_star_promotion_burst()
	var new_rank := int(res["data"].get("awakeningRank", 1)) if res["data"] is Dictionary else 1
	var trait_str := str(res["data"].get("newTrait", "")) if res["data"] is Dictionary else ""
	var trait_info := (" • Thiên phú: %s" % trait_str) if trait_str != "" else ""
	status_label.text = "🎉 THỨC TỈNH THÀNH CÔNG! [%s] đã đạt Thức Tỉnh Bậc +%d%s!" % [hname, new_rank, trait_info]
	if _awaken_modal_backdrop != null:
		_awaken_modal_backdrop.visible = false
	await _sync_all_roster_data(hero_id)

# ==============================================================================
# HERO PROGRESSION, PARTY, LOCK & QUICK SUMMON API ACTIONS
# ==============================================================================

func _format_num(val: int) -> String:
	var s := str(absi(val))
	var res := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		res = s[i] + res
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			res = "," + res
	return ("-" if val < 0 else "") + res

func _on_level_up_hero(quantity: int = 1, to_max: bool = false, book_item_id: String = "") -> void:
	var hid := str(_selected_hero.get("id", ""))
	var hname := str(_selected_hero.get("name", "Hero"))
	if hid.is_empty():
		return
	var chosen_book := book_item_id if book_item_id != "" else _selected_exp_book_id
	status_label.text = "📘 Đang tăng cấp cho [%s]..." % hname
	var res := await ApiClient.post_req("/api/heroes/%s/level-up" % hid, {
		"quantity": quantity,
		"amount": quantity,
		"toMax": to_max,
		"bookItemId": chosen_book
	})
	if res["ok"] and res["data"] is Dictionary:
		var hero_info: Dictionary = res["data"].get("hero", {})
		var new_lvl := int(hero_info.get("level", _selected_hero.get("level", 1)))
		var books_used := int(res["data"].get("booksUsed", quantity))
		var rem_qty := int(res["data"].get("materialQuantity", 0))
		var used_book := str(res["data"].get("bookItemId", chosen_book))
		GameState.materials[used_book] = rem_qty

		_selected_hero["level"] = new_lvl
		_selected_hero["exp"] = hero_info.get("exp", _selected_hero.get("exp", "0"))
		if hero_info.has("hp"):
			_selected_hero["hp"] = hero_info["hp"]
		if hero_info.has("maxHp"):
			_selected_hero["maxHp"] = hero_info["maxHp"]
		if hero_info.has("attack"):
			_selected_hero["attack"] = hero_info["attack"]
		if hero_info.has("defense"):
			_selected_hero["defense"] = hero_info["defense"]
		if hero_info.has("speed"):
			_selected_hero["speed"] = hero_info["speed"]

		_render_active_profile_tab()
		var msg := "🎉 [%s] đã dùng %d Sách EXP và đạt Lv.%d! (Còn %s quyển)" % [
			hname, books_used, new_lvl, _format_num(rem_qty)
		]
		status_label.text = msg
		await _sync_all_roster_data(hid)
		status_label.text = msg
	else:
		status_label.text = "❌ Không thể dùng Sách EXP: " + str(res["error"])

func _on_quick_level_up_hero() -> void:
	var best_book := "SAMPLE_HERO_EXP_100"
	if int(GameState.materials.get("SAMPLE_HERO_EXP_10000", 0)) > 0:
		best_book = "SAMPLE_HERO_EXP_10000"
	elif int(GameState.materials.get("SAMPLE_HERO_EXP_1000", 0)) > 0:
		best_book = "SAMPLE_HERO_EXP_1000"
	await _on_level_up_hero(1, true, best_book)
	if _promote_modal_backdrop != null and _promote_modal_backdrop.visible:
		await _load_promote_preview()
	if _breakthrough_modal_backdrop != null and _breakthrough_modal_backdrop.visible:
		await _load_breakthrough_preview()

func _on_train_stat_pressed(hid: String, hname: String, stat_code: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/train" % hid, {
		"stat": stat_code,
		"points": 1
	})
	if res["ok"]:
		status_label.text = "💪 [%s] đã rèn luyện +1 %s thành công!" % [hname, stat_code.to_upper()]
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "ℹ️ Chưa thể huấn luyện: " + str(res["error"])

func _on_unlock_skill_pressed(hid: String, sk_code: String, sk_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/skills/%s/unlock" % [hid, sk_code], {})
	if res["ok"]:
		status_label.text = "🔓 Đã mở khóa kỹ năng [%s]!" % sk_name
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "ℹ️ Không thể mở khóa kỹ năng: " + str(res["error"])

func _on_upgrade_skill_pressed(hid: String, sk_code: String, sk_name: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/skills/%s/upgrade" % [hid, sk_code], {})
	if res["ok"]:
		status_label.text = "📕 Đã nâng cấp kỹ năng [%s]!" % sk_name
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "ℹ️ Không thể nâng cấp kỹ năng: " + str(res["error"])

func _on_toggle_skill_behavior(hid: String, sk_code: String, mode: String) -> void:
	var res := await ApiClient.patch_req("/api/heroes/%s/skills/%s/behavior" % [hid, sk_code], {
		"behaviorMode": mode
	})
	if res["ok"]:
		status_label.text = "🤖 Đã chuyển cơ chế kỹ năng sang [%s]!" % mode
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "❌ Lỗi đổi chế độ kỹ năng: " + str(res["error"])

func _on_awaken_hero_pressed(hid: String, hname: String) -> void:
	var res := await ApiClient.post_req("/api/heroes/%s/awaken" % hid, {})
	if res["ok"]:
		_play_3d_star_promotion_burst()
		status_label.text = "🌟 [%s] đã Thức Tỉnh Huyết Mạch và mở khóa thêm Ô Ấn Ký mới!" % hname
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "ℹ️ Chưa đủ nguyên liệu Thức Tỉnh: " + str(res["error"])

func _on_quick_equip_pressed(hid: String, hname: String) -> void:
	if hid.is_empty():
		return
	status_label.text = "⚡ Đang tự động tìm và trang bị những món tối ưu nhất cho [%s]..." % hname
	var res := await ApiClient.put_req("/api/equipment/heroes/%s/quick-equip" % hid, {})
	if res["ok"] and res["data"] is Dictionary:
		var count := int(res["data"].get("equippedCount", 0))
		if count > 0:
			status_label.text = "🎉 Đã tự động trang bị %d món tốt nhất cho [%s]!" % [count, hname]
		else:
			status_label.text = "ℹ️ [%s] đã mặc trang bị tối ưu nhất hiện có trong Kho!" % hname
		await GameState.refresh_equipment()
		await GameState.refresh_crafting()
		await GameState.refresh_heroes()
		_update_selected_hero_from_gamestate()
		_display_hero_details(_selected_hero)
	else:
		status_label.text = "❌ Lỗi trang bị nhanh: " + str(res["error"])

func _on_quick_unequip_pressed(hid: String, hname: String) -> void:
	if hid.is_empty():
		return
	status_label.text = "🔄 Đang tháo toàn bộ trang bị của [%s] về Kho..." % hname
	var res := await ApiClient.post_req("/api/equipment/heroes/%s/quick-unequip" % hid, {})
	if res["ok"] and res["data"] is Dictionary:
		var count := int(res["data"].get("unequippedCount", 0))
		status_label.text = "📦 Đã tháo toàn bộ %d trang bị của [%s] về Kho đồ!" % [count, hname]
		await GameState.refresh_equipment()
		await GameState.refresh_crafting()
		await GameState.refresh_heroes()
		_update_selected_hero_from_gamestate()
		_display_hero_details(_selected_hero)
	else:
		status_label.text = "❌ Lỗi tháo đồ nhanh: " + str(res["error"])

func _on_equip_pressed(item_id: String, item_name: String, hid: String, hname: String) -> void:
	var res := await ApiClient.put_req("/api/equipment/%s/equip" % item_id, { "heroId": hid })
	if res["ok"]:
		status_label.text = "🛡️ Đã mặc [%s] cho [%s]!" % [item_name, hname]
		await GameState.refresh_equipment()
		await GameState.refresh_crafting()
		await GameState.refresh_heroes()
		_update_selected_hero_from_gamestate()
		_display_hero_details(_selected_hero)
	else:
		status_label.text = "❌ Không thể mặc trang bị: " + str(res["error"])

func _on_unequip_pressed(item_id: String, item_name: String) -> void:
	var hid := str(_selected_hero.get("id", ""))
	var res := await ApiClient.post_req("/api/equipment/%s/unequip" % item_id, {})
	if res["ok"]:
		status_label.text = "📦 Đã tháo [%s] về Nhà Kho!" % item_name
		await GameState.refresh_equipment()
		await GameState.refresh_crafting()
		await GameState.refresh_heroes()
		_update_selected_hero_from_gamestate()
		_display_hero_details(_selected_hero)
	else:
		status_label.text = "❌ Không thể tháo trang bị: " + str(res["error"])

func _on_enhance_eq_pressed(item_id: String, item_name: String) -> void:
	var hid := str(_selected_hero.get("id", ""))
	var res := await ApiClient.post_req("/api/crafting/equipment/%s/enhance" % item_id, {})
	if res["ok"]:
		status_label.text = "✨ Cường hóa thành công [%s]!" % item_name
		await GameState.refresh_equipment()
		await GameState.refresh_crafting()
		await GameState.refresh_heroes()
		_update_selected_hero_from_gamestate()
		_display_hero_details(_selected_hero)
	else:
		status_label.text = "❌ Không thể cường hóa: " + str(res["error"])

func _on_toggle_party_pressed() -> void:
	var hid := str(_selected_hero.get("id", ""))
	var hname := str(_selected_hero.get("name", "Hero"))
	if hid.is_empty():
		return
	var next_party := GameState.active_party_ids.duplicate()
	if next_party.has(hid):
		next_party.erase(hid)
	else:
		if next_party.size() >= 5:
			status_label.text = "⚠️ Đội hình tối đa 5 Tướng! Hãy bỏ bớt 1 Tướng trước."
			return
		next_party.append(hid)

	var res := await ApiClient.put_req("/api/combat/party", { "heroIds": next_party })
	if res["ok"]:
		GameState.set_active_party(next_party)
		status_label.text = "⚔️ Đã cập nhật Đội hình PvE cho [%s] (%d/5 Tướng)!" % [hname, next_party.size()]
		_refresh_hero_list(hid)
	else:
		status_label.text = "❌ Không thể cập nhật đội hình: " + str(res["error"])

func _on_toggle_lock_pressed() -> void:
	var hid := str(_selected_hero.get("id", ""))
	var cur_lock := bool(_selected_hero.get("isLocked", false))
	if hid.is_empty():
		return
	var res := await ApiClient.patch_req("/api/heroes/%s/lock" % hid, {
		"isLocked": not cur_lock
	})
	if res["ok"]:
		status_label.text = "🔒 Đã khóa bảo vệ Tướng!" if not cur_lock else "🔓 Đã mở khóa Tướng (Có thể dùng làm phôi Thăng Sao)."
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "❌ Không thể đổi trạng thái khóa: " + str(res["error"])

func _on_quick_summon_in_barracks() -> void:
	var hid := str(_selected_hero.get("id", ""))
	status_label.text = "✨ Đang triệu hồi nhanh ×10 để bổ sung Tướng & Phôi Thăng Sao..."
	var b_res := await ApiClient.get_req("/api/gacha/banners")
	if not b_res["ok"] or not (b_res["data"] is Array) or (b_res["data"] as Array).is_empty():
		status_label.text = "❌ Không tìm thấy Banner triệu hồi."
		return
	if GameState.normal_scrolls < 10 and GameState.silver_coins >= 100000:
		await ApiClient.post_req("/api/economy/exchange-scrolls", { "amount": 10 - GameState.normal_scrolls })
	var banner_id := str((b_res["data"] as Array)[0].get("id", ""))
	var idem_key := "godot-roster-summon-%d-%d" % [Time.get_unix_time_from_system(), randi()]
	var res := await ApiClient.post_req(
		"/api/gacha/summon",
		{ "bannerId": banner_id, "rollCount": 10 },
		{ "Idempotency-Key": idem_key }
	)
	if res["ok"]:
		_play_3d_star_promotion_burst()
		status_label.text = "🌟 Đã triệu hồi ×10 thành công! Danh sách Tướng & Phôi đã được cập nhật."
		await _sync_all_roster_data(hid)
	else:
		status_label.text = "❌ Không thể triệu hồi: " + str(res["error"])

func _on_back_pressed() -> void:
	if _stats_detail_modal_backdrop != null and _stats_detail_modal_backdrop.visible:
		_stats_detail_modal_backdrop.visible = false
		return
	if _in_detail_view:
		_close_hero_detail()
	else:
		get_tree().change_scene_to_file("res://scenes/base/isometric_base_3d.tscn")
