extends Control

signal closed

const ItemCard = preload("res://scripts/ui/universal_item_card.gd")
const CATEGORY_NAMES := {"CONSUMABLE": "Tiêu hao", "MATERIAL": "Nguyên liệu", "DEVELOPMENT": "Phát triển Hero", "FOOD": "Thức ăn", "EQUIPMENT": "Trang bị", "SCROLL": "Thiên Thư"}
var _items: Array = []
var _selected: Dictionary = {}
var _pending_purchase: Dictionary = {}
var _busy := false
var _category := ""
var _grid: GridContainer
var _search: LineEdit
var _balance: Label
var _notice: Label
var _description: RichTextLabel
var _quantity: SpinBox
var _buy_button: Button
var _close_button: Button
var _count: Label
var _panel: PanelContainer

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.03, 0.07, 0.92)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	_panel = panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.08, 0.13)
	style.border_color = Color(0.65, 0.49, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := Label.new()
	title.text = "🎈 THƯƠNG THUYỀN KHINH KHÍ"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title)
	_close_button = Button.new()
	_close_button.text = "Đóng"
	_close_button.pressed.connect(func(): closed.emit(); queue_free())
	header.add_child(_close_button)
	_balance = Label.new()
	body.add_child(_balance)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "Tìm tên vật phẩm..."
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text): _render_items())
	filters.add_child(_search)
	var categories := OptionButton.new()
	var category_keys := [""]
	categories.add_item("Tất cả")
	for code in CATEGORY_NAMES:
		category_keys.append(code)
		categories.add_item(str(CATEGORY_NAMES[code]))
	categories.item_selected.connect(func(index):
		_category = category_keys[index]
		_render_items()
	)
	filters.add_child(categories)
	_count = Label.new()
	body.add_child(_count)
	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	scroll.resized.connect(func(): _grid.columns = maxi(1, mini(5, int(scroll.size.x / 180.0))))
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 250
	columns.add_child(details)
	_description = RichTextLabel.new()
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_description.selection_enabled = true
	details.add_child(_description)
	var quantity_label := Label.new()
	quantity_label.text = "Số lượng"
	details.add_child(quantity_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 99
	_quantity.step = 1
	_quantity.value_changed.connect(func(_value): _update_purchase())
	details.add_child(_quantity)
	_buy_button = Button.new()
	_buy_button.custom_minimum_size.y = 45
	_buy_button.pressed.connect(_purchase)
	details.add_child(_buy_button)
	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_notice)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	_set_busy(true)
	await GameState.refresh_profile()
	await _load_catalog()

func _fit_panel() -> void:
	var available := get_viewport_rect().size - Vector2(48, 48)
	_panel.custom_minimum_size = Vector2(minf(1120, available.x), minf(700, available.y))

func _set_busy(value: bool) -> void:
	_busy = value
	_close_button.disabled = value
	_quantity.editable = not value and _pending_purchase.is_empty()
	_update_purchase()

func _load_catalog() -> void:
	_set_busy(true)
	_notice.text = "Khinh khí cầu đang dỡ hàng..."
	var response: Dictionary = await ApiClient.get_req("/api/shop")
	if not is_inside_tree(): return
	if not bool(response.get("ok", false)):
		_set_busy(false)
		_notice.text = str(response.get("error", "Không thể tải cửa hàng."))
		return
	_items = response.get("data", {}).get("items", [])
	var selection: Dictionary = {}
	for item in _items:
		if str(item.get("code", "")) == str(_selected.get("code", "")): selection = item
	if selection.is_empty() and not _items.is_empty(): selection = _items[0]
	_selected = selection
	_set_busy(false)
	_render_items()
	_render_detail()
	_notice.text = "Chọn vật phẩm rồi mua. Hàng đã mua được chuyển thẳng vào kho tương ứng."

func _render_items() -> void:
	if _grid == null: return
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var shown := 0
	for item in _items:
		if _category != "" and str(item.get("category", "")) != _category: continue
		if not _search.text.is_empty() and not str(item.get("name", "")).to_lower().contains(_search.text.to_lower()): continue
		var card = ItemCard.new()
		_grid.add_child(card)
		card.setup(item)
		card.add_badge("%s bạc" % str(item.get("priceSilver", "1")), Color(0.2, 0.32, 0.38), Color(1, 0.9, 0.55))
		card.item_clicked.connect(func(_data):
			if _busy or not _pending_purchase.is_empty(): return
			_selected = item
			_render_detail()
		)
		shown += 1
	_count.text = "%d / %d mặt hàng • Độ hiếm 1–7★" % [shown, _items.size()]

func _render_detail() -> void:
	if _selected.is_empty():
		_description.text = "Chưa có mặt hàng."
	else:
		_description.text = "%s\n%s\n%s\n\n%s\n\nĐơn giá: %s bạc" % [_selected.get("name", ""), "★".repeat(clampi(int(_selected.get("rarity", 1)), 1, 7)), CATEGORY_NAMES.get(str(_selected.get("category", "")), "Vật phẩm"), _selected.get("description", ""), str(_selected.get("priceSilver", "1"))]
		var remaining: Variant = _selected.get("remainingToday")
		if remaining != null: _description.text += "\nCòn mua hôm nay: %d" % int(remaining)
	_update_purchase()

func _update_purchase() -> void:
	if _buy_button == null: return
	_balance.text = "🪙 Bạc hiện có: %d" % GameState.silver_coins
	if not _pending_purchase.is_empty():
		_buy_button.text = "Kiểm tra lại giao dịch"
		_buy_button.disabled = _busy
		return
	var cost := int(_selected.get("priceSilver", 1)) * int(_quantity.value)
	_buy_button.text = "Mua %d — %d bạc" % [int(_quantity.value), cost]
	var remaining: Variant = _selected.get("remainingToday")
	_buy_button.disabled = _busy or _selected.is_empty() or GameState.silver_coins < cost or (remaining != null and int(remaining) <= 0)

func _purchase() -> void:
	if _busy or _buy_button.disabled: return
	if _pending_purchase.is_empty():
		_pending_purchase = {"itemCode": str(_selected.get("code", "")), "quantity": int(_quantity.value), "key": "shop-" + Crypto.new().generate_random_bytes(16).hex_encode()}
	_set_busy(true)
	_notice.text = "Đang giao dịch..."
	var response: Dictionary = await ApiClient.post_req("/api/shop/purchase", {"itemCode": _pending_purchase["itemCode"], "quantity": _pending_purchase["quantity"]}, {"Idempotency-Key": _pending_purchase["key"]})
	if not is_inside_tree(): return
	if not bool(response.get("ok", false)):
		var status := int(response.get("status", 0))
		if status == 0 or status >= 500:
			_set_busy(false)
			_notice.text = "Chưa xác nhận được giao dịch. Bấm kiểm tra lại để nhận kết quả, không tạo lần mua mới."
			return
		_pending_purchase = {}
		await GameState.refresh_profile()
		if not is_inside_tree(): return
		_set_busy(false)
		var error := str(response.get("error", "Không thể mua vật phẩm."))
		match error:
			"ERR_SHOP_INSUFFICIENT_FUNDS": error = "Không đủ bạc để mua số lượng này."
			"ERR_SHOP_DAILY_LIMIT_EXCEEDED": error = "Đã hết số lượng có thể mua hôm nay."
			"ERR_SHOP_ITEM_ROTATED_OUT": error = "Mặt hàng hiện không được bán."
		_notice.text = error
		return
	var result: Dictionary = response.get("data", {})
	_pending_purchase = {}
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	await GameState.refresh_equipment()
	if not is_inside_tree(): return
	await _load_catalog()
	_notice.text = "Đã mua %d món, thanh toán %d bạc." % [int(result.get("purchased", 0)), int(result.get("silverSpent", 0))]
