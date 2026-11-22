extends Control
signal configured(config: Dictionary)
const Ui = preload("res://scripts/ui/pve_ui.gd")
const ITEMS := ["", "MEDICINE", "MANA_POTION", "STRENGTH_POTION"]
const NAMES := ["Để trống", "Thuốc điều trị", "Thuốc ma lực", "Thuốc cường lực"]
var config: Dictionary = {}
var _types: Array[OptionButton] = []
var _counts: Array[SpinBox] = []
var _threshold: SpinBox
var _hp_threshold: SpinBox
var _strength: CheckBox

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.9)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := Ui.panel(center, 620)
	Ui.label(box, "TÚI TIÊU HAO • 5 Ô × 4 VẬT PHẨM", 21, Ui.GOLD)
	Ui.label(box, "Trừ kho khi triển khai. Số dư trả kho khi thu hồi; tử trận sẽ rơi tại chỗ.", 13)
	var slots: Array = config.get("slots", [null, null, null, null, null])
	for i in range(5):
		var row := HBoxContainer.new()
		box.add_child(row)
		Ui.label(row, "Ô %d" % [i + 1])
		var type := OptionButton.new()
		for label in NAMES: type.add_item(label)
		type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(type)
		var count := SpinBox.new()
		count.min_value = 1
		count.max_value = 4
		count.value = 1
		row.add_child(count)
		if i < slots.size() and slots[i] is Dictionary:
			type.select(maxi(0, ITEMS.find(str(slots[i].get("itemId", "")))))
			count.value = int(slots[i].get("quantity", 1))
		_types.append(type)
		_counts.append(count)
	Ui.label(box, "Ngoài trận: tự điều trị khi HP dưới (%) • 0 = tắt", 14)
	_hp_threshold = SpinBox.new()
	_hp_threshold.min_value = 0
	_hp_threshold.max_value = 100
	_hp_threshold.value = int(config.get("autoHpBelow", 30))
	box.add_child(_hp_threshold)
	Ui.label(box, "Tự dùng thuốc ma lực khi MP dưới (%) • 0 = tắt", 14)
	_threshold = SpinBox.new()
	_threshold.min_value = 0
	_threshold.max_value = 100
	_threshold.value = int(config.get("autoManaBelow", 30))
	box.add_child(_threshold)
	_strength = CheckBox.new()
	_strength.text = "Tự dùng thuốc cường lực ở lượt đầu khi chưa có hiệu ứng"
	_strength.button_pressed = bool(config.get("autoStrength", true))
	box.add_child(_strength)
	Ui.label(box, "MEDICINE dùng ngoài trận. Trong trận: tối đa 2 loại/lượt, mỗi loại 1 viên.", 13, Ui.MUTED)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	Ui.button(actions, "Áp dụng vào bản nháp đội", func():
		var selected: Array = []
		for i in range(5):
			selected.append(null if _types[i].selected == 0 else {"itemId": ITEMS[_types[i].selected], "quantity": int(_counts[i].value)})
		configured.emit({"slots": selected, "autoHpBelow": int(_hp_threshold.value), "autoManaBelow": int(_threshold.value), "autoStrength": _strength.button_pressed})
		queue_free()
	)
	Ui.button(actions, "Hủy", queue_free)
