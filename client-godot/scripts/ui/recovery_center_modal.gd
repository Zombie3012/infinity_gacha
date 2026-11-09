class_name RecoveryCenterModal
extends Control

## Recovery Center (Trung Tâm Hồi Phục) Modal Dialog
## Utilizes Universal Hero Card & CardGridBrowser to manage hero healing,
## recovery bed slots (2/4/6), waiting queue, and Quick Heal (Bình Thuốc).

signal closed

const CardGridBrowserScript = preload("res://scripts/ui/card_grid_browser.gd")
const UniversalHeroCardScript = preload("res://scripts/ui/universal_hero_card.gd")

var browser
var title_label: Label
var subtitle_label: Label
var bed_info_label: Label
var medicine_info_label: Label
var banner_label: Label
var beds_container: HBoxContainer
var auto_select_btn: Button
var quick_heal_btn: Button
var cancel_treat_btn: Button

var facility_level: int = 1
var bed_capacity: int = 2
var max_queue: int = 6
var active_treatments: Array = []
var queued_treatments: Array = []
var medicine_count: int = 0
var assigned_worker_name: String = ""

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	_build_ui()
	refresh_facility_data()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# 1. Dark Backdrop Dimmer
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.04, 0.06, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# Click outside to close can be optional, keep modal safe
			pass
	)
	add_child(backdrop)

	# 2. Main Centered Window Container
	var center_wrap := CenterContainer.new()
	center_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center_wrap)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 690)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.07, 0.09, 0.13, 0.98)
	p_style.border_width_left = 2
	p_style.border_width_top = 2
	p_style.border_width_right = 2
	p_style.border_width_bottom = 2
	p_style.border_color = Color(0.20, 0.80, 0.55, 0.85) # Emerald border
	p_style.corner_radius_top_left = 12
	p_style.corner_radius_top_right = 12
	p_style.corner_radius_bottom_left = 12
	p_style.corner_radius_bottom_right = 12
	p_style.shadow_size = 14
	p_style.shadow_color = Color(0, 0, 0, 0.65)
	panel.add_theme_stylebox_override("panel", p_style)
	center_wrap.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# 3. Header Row: Title, Subtitle & Close Button
	var header_row := HBoxContainer.new()
	header_row.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(header_row)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_box.add_theme_constant_override("separation", 2)
	header_row.add_child(title_box)

	title_label = Label.new()
	title_label.text = "✚ RECOVERY CENTER – TRUNG TÂM HỒI PHỤC"
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.40, 0.95, 0.70))
	title_box.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Cấp 1 • 2 Giường bệnh • 1 Hero phụ trách • Hồi phục sinh lực & xóa thương tích"
	subtitle_label.add_theme_font_size_override("font_size", 12)
	subtitle_label.add_theme_color_override("font_color", Color(0.72, 0.85, 0.95))
	title_box.add_child(subtitle_label)

	var close_btn := Button.new()
	close_btn.text = " ✖ "
	close_btn.custom_minimum_size = Vector2(36, 32)
	close_btn.pressed.connect(close_modal)
	header_row.add_child(close_btn)

	# 4. Facility Ribbon (Beds, Queue, Medicine & Quick Actions)
	var ribbon_panel := PanelContainer.new()
	var r_style := StyleBoxFlat.new()
	r_style.bg_color = Color(0.10, 0.13, 0.19, 0.95)
	r_style.border_width_left = 1
	r_style.border_width_top = 1
	r_style.border_width_right = 1
	r_style.border_width_bottom = 1
	r_style.border_color = Color(0.25, 0.35, 0.48)
	r_style.corner_radius_top_left = 8
	r_style.corner_radius_top_right = 8
	r_style.corner_radius_bottom_left = 8
	r_style.corner_radius_bottom_right = 8
	ribbon_panel.add_theme_stylebox_override("panel", r_style)
	root_vbox.add_child(ribbon_panel)

	var r_margin := MarginContainer.new()
	r_margin.add_theme_constant_override("margin_left", 12)
	r_margin.add_theme_constant_override("margin_top", 8)
	r_margin.add_theme_constant_override("margin_right", 12)
	r_margin.add_theme_constant_override("margin_bottom", 8)
	ribbon_panel.add_child(r_margin)

	var ribbon_row := HBoxContainer.new()
	ribbon_row.add_theme_constant_override("separation", 14)
	r_margin.add_child(ribbon_row)

	var stat_vbox := VBoxContainer.new()
	stat_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_vbox.add_theme_constant_override("separation", 2)
	ribbon_row.add_child(stat_vbox)

	bed_info_label = Label.new()
	bed_info_label.text = "🛏️ Giường bệnh: 0/2 Đang dùng • ⏳ Hàng chờ: 0/6"
	bed_info_label.add_theme_font_size_override("font_size", 13)
	bed_info_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.45))
	stat_vbox.add_child(bed_info_label)

	medicine_info_label = Label.new()
	medicine_info_label.text = "💊 Bình thuốc dự trữ: 0 | 👨‍⚕️ Phụ trách: Chưa có"
	medicine_info_label.add_theme_font_size_override("font_size", 12)
	medicine_info_label.add_theme_color_override("font_color", Color(0.70, 0.90, 1.0))
	stat_vbox.add_child(medicine_info_label)

	# Quick Toolbar Buttons
	auto_select_btn = Button.new()
	auto_select_btn.text = "⚡ Tự Động Chọn"
	auto_select_btn.tooltip_text = "Tự động chọn Hero có HP thấp nhất / bị thương nặng nhất để đưa vào điều trị."
	auto_select_btn.custom_minimum_size = Vector2(130, 34)
	auto_select_btn.modulate = Color(0.4, 0.9, 1.0)
	auto_select_btn.pressed.connect(_on_auto_select_pressed)
	ribbon_row.add_child(auto_select_btn)

	quick_heal_btn = Button.new()
	quick_heal_btn.text = "💊 Quick Heal"
	quick_heal_btn.tooltip_text = "Hồi phục tức thì 100% HP và xóa vết thương cho các Hero được chọn bằng Bình Thuốc."
	quick_heal_btn.custom_minimum_size = Vector2(115, 34)
	quick_heal_btn.modulate = Color(1.0, 0.85, 0.35)
	quick_heal_btn.pressed.connect(_on_quick_heal_pressed)
	ribbon_row.add_child(quick_heal_btn)

	cancel_treat_btn = Button.new()
	cancel_treat_btn.text = "❌ Hủy Giường"
	cancel_treat_btn.tooltip_text = "Hủy điều trị cho các Hero đang chọn để nhường giường cho Hero khác."
	cancel_treat_btn.custom_minimum_size = Vector2(105, 34)
	cancel_treat_btn.modulate = Color(1.0, 0.5, 0.5)
	cancel_treat_btn.pressed.connect(_on_cancel_treatment_pressed)
	ribbon_row.add_child(cancel_treat_btn)

	# 5. Status message banner
	banner_label = Label.new()
	banner_label.text = "💡 Chọn các Hero cần hồi phục từ danh sách bên dưới rồi nhấn Hồi phục."
	banner_label.add_theme_font_size_override("font_size", 12)
	banner_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.92))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(banner_label)

	# 6. Universal Card Grid Browser
	browser = CardGridBrowserScript.new()
	browser.browser_type = CardGridBrowserScript.BrowserType.HERO
	browser.hero_context_mode = UniversalHeroCardScript.ContextMode.RECOVERY
	browser.grid_columns = 3
	browser.card_selectable = true
	browser.multi_select_enabled = true
	browser.max_selection = 12
	root_vbox.add_child(browser)

	browser.configure_header("Chọn Hero hồi phục", ["Tất cả", "Cần hồi phục", "Đang hồi phục", "Đã khỏe"])
	browser.set_action_button("✚ Hồi phục Hero đã chọn", "Hồi phục")
	browser.action_confirmed.connect(_on_admit_selected_heroes)

func refresh_facility_data() -> void:
	banner_label.text = "⏳ Đang tải thông tin Trung Tâm Hồi Phục..."
	var res: Dictionary = await ApiClient.get_req("/api/medical/overview")

	if res["ok"] and res["data"] is Dictionary:
		var d: Dictionary = res["data"]
		var fac: Dictionary = d.get("facility", {})
		facility_level = int(fac.get("level", 1))
		bed_capacity = int(d.get("capacity", facility_level * 2))
		max_queue = int(d.get("maxQueue", bed_capacity * 3))
		active_treatments = d.get("activeTreatments", [])
		queued_treatments = d.get("queuedTreatments", [])
		var beds_free: int = int(d.get("bedsFree", 0))

		var workers: Array = fac.get("workers", [])
		if not workers.is_empty() and workers[0] is Dictionary:
			assigned_worker_name = str(workers[0].get("heroName", "Y Sĩ"))
		else:
			assigned_worker_name = "Chưa phân công"

		subtitle_label.text = "Cấp %d • %d Giường bệnh • Phụ trách: %s • 2/4/6 slot chữa trị theo Level" % [
			facility_level, bed_capacity, assigned_worker_name
		]

		bed_info_label.text = "🛏️ Giường bệnh: %d/%d (Trống: %d) • ⏳ Hàng chờ: %d/%d" % [
			active_treatments.size(), bed_capacity, beds_free,
			queued_treatments.size(), max_queue
		]

	# Refresh medicine inventory
	await GameState.refresh_inventory()
	medicine_count = int(GameState.materials.get("MEDICINE", 0))
	medicine_info_label.text = "💊 Bình thuốc dự trữ: %d | 👨‍⚕️ Phụ trách: %s" % [
		medicine_count, assigned_worker_name
	]

	# Refresh heroes list & annotate with treatment state
	await GameState.refresh_heroes()
	var heroes_list: Array = []
	var active_ids: Dictionary = {}
	for t in active_treatments:
		if t is Dictionary:
			active_ids[str(t.get("heroId", ""))] = t

	var queue_ids: Dictionary = {}
	for q in queued_treatments:
		if q is Dictionary:
			queue_ids[str(q.get("heroId", ""))] = q

	for h in GameState.heroes:
		if h is Dictionary:
			var h_dup: Dictionary = h.duplicate()
			var hid := str(h_dup.get("id", ""))
			if active_ids.has(hid):
				h_dup["isTreating"] = true
				h_dup["treatmentInfo"] = active_ids[hid]
			elif queue_ids.has(hid):
				h_dup["isQueued"] = true
				h_dup["queueInfo"] = queue_ids[hid]
			heroes_list.append(h_dup)

	browser.set_items(heroes_list, false)
	banner_label.text = "💡 Chọn các Hero cần hồi phục từ danh sách bên dưới rồi nhấn Hồi phục."

func _on_auto_select_pressed() -> void:
	var free_beds := maxi(0, bed_capacity - active_treatments.size())
	var free_queue := maxi(0, max_queue - queued_treatments.size())
	var total_free := free_beds + free_queue
	if total_free <= 0:
		banner_label.text = "⚠️ Giường bệnh và Hàng chờ hiện đã đầy (%d/%d)!" % [active_treatments.size() + queued_treatments.size(), bed_capacity + max_queue]
		return

	var count: int = int(browser.auto_select_recovery_candidates(total_free))
	if count > 0:
		banner_label.text = "⚡ Đã tự động chọn %d Hero có HP thấp nhất / bị thương nặng nhất!" % count
	else:
		banner_label.text = "❤️ Toàn bộ Anh Hùng đều đang khỏe mạnh (100% HP) hoặc đang điều trị!"

func _on_admit_selected_heroes(selected_items: Array) -> void:
	if selected_items.is_empty():
		return

	var hero_ids: Array = []
	for it in selected_items:
		var hid := str(it.get("id", ""))
		var is_treating := bool(it.get("isTreating", false))
		var is_queued := bool(it.get("isQueued", false))
		if not is_treating and not is_queued:
			hero_ids.append(hid)

	if hero_ids.is_empty():
		banner_label.text = "⚠️ Các Hero đã chọn đều đang trong giường hoặc hàng chờ rồi!"
		return

	banner_label.text = "⏳ Đang chuyển %d Hero vào Trung Tâm Hồi Phục..." % hero_ids.size()
	var res: Dictionary = await ApiClient.post_req("/api/medical/treatments/batch", {
		"heroIds": hero_ids
	})

	if res["ok"] and res["data"] is Dictionary:
		var admitted: int = int(res["data"].get("admitted", 0))
		var queued: int = int(res["data"].get("queued", 0))
		banner_label.text = "✅ Thành công! Đưa %d Hero vào giường điều trị, %d Hero vào hàng chờ." % [admitted, queued]
		await refresh_facility_data()
	else:
		var err_msg := str(res.get("error", "Lỗi gửi yêu cầu điều trị"))
		banner_label.text = "❌ Thất bại: %s" % err_msg

func _on_quick_heal_pressed() -> void:
	var selected: Array = browser.get_selected_items()
	if selected.is_empty():
		banner_label.text = "⚠️ Vui lòng chọn ít nhất 1 Hero để Quick Heal bằng Bình Thuốc!"
		return

	var hero_ids: Array = []
	for it in selected:
		hero_ids.append(str(it.get("id", "")))

	if medicine_count < hero_ids.size():
		banner_label.text = "⚠️ Không đủ Bình Thuốc! Cần %d Bình nhưng chỉ có %d Bình." % [hero_ids.size(), medicine_count]
		return

	banner_label.text = "⏳ Đang dùng Bình Thuốc cấp cứu cho %d Hero..." % hero_ids.size()
	var res: Dictionary = await ApiClient.post_req("/api/medical/emergency/batch", {
		"heroIds": hero_ids
	})

	if res["ok"] and res["data"] is Dictionary:
		var healed: int = int(res["data"].get("healedCount", 0))
		var used: int = int(res["data"].get("medicineUsed", 0))
		banner_label.text = "✨ Quick Heal thành công! Đã hồi sinh 100% HP cho %d Hero (Tốn %d Bình Thuốc)." % [healed, used]
		await refresh_facility_data()
	else:
		var err_msg := str(res.get("error", "Lỗi thực hiện Quick Heal"))
		banner_label.text = "❌ Thất bại: %s" % err_msg

func _on_cancel_treatment_pressed() -> void:
	var selected: Array = browser.get_selected_items()
	if selected.is_empty():
		banner_label.text = "⚠️ Vui lòng chọn Hero đang trong giường/hàng chờ để hủy điều trị!"
		return

	var cancelled_count := 0
	for it in selected:
		var hid := str(it.get("id", ""))
		var is_treating := bool(it.get("isTreating", false))
		var is_queued := bool(it.get("isQueued", false))
		if is_treating or is_queued:
			var res: Dictionary = await ApiClient.delete_req("/api/medical/treatments/%s" % hid)
			if res["ok"]:
				cancelled_count += 1

	if cancelled_count > 0:
		banner_label.text = "✅ Đã hủy điều trị cho %d Hero, giường bệnh đã được giải phóng." % cancelled_count
		await refresh_facility_data()
	else:
		banner_label.text = "⚠️ Không có Hero nào trong số đã chọn đang ở trong giường điều trị."

func close_modal() -> void:
	closed.emit()
	queue_free()
