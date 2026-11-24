class_name HeroDialogueBank
extends RefCounted

## Vietnamese Dialogue & Status Icon Bank for 3D Castle Heroes (P2-08)

const CLASS_LINES := {
	"WARRIOR": [
		"🛡️ Thanh kiếm này đã sẵn sàng bảo vệ Lâu Đài!",
		"⚔️ Hôm nay tập thêm 200 nhát chém nữa nào!",
	],
	"MAGE": [
		"✨ Dòng chảy ma lực quanh Tháp hôm nay rất ổn định.",
		"📚 Ta vừa giải mã thêm một cổ ngữ nguyên tố mới.",
	],
	"ARCHER": [
		"🏹 Gió tầng thượng rất thuận lợi để ngắm bắn!",
		"🎯 Không mục tiêu nào thoát khỏi tầm mắt ta.",
	],
	"PRIEST": [
		"🌿 Nguyện ánh sáng ban phước cho toàn bộ Lâu Đài.",
		"🩹 Ai bị thương hãy ghé Trung Tâm Hồi Phục nhé!",
	],
	"THIEF": [
		"🗡️ Bước chân nhẹ như gió, chẳng ai phát hiện đâu.",
		"💎 Nghe nói tầng Tháp mới có kho báu hiếm lắm!",
	],
}

const NEED_LINES := {
	"HUNGRY": [
		"🍖 Bụng đói meo rồi, phải ghé Nhà Bếp kiếm gì ăn thôi!",
		"🍲 Mùi thức ăn từ Nhà Bếp thơm quá đi mất!",
	],
	"TIRED": [
		"💤 Mắt díp cả lại rồi, về Ký Túc Xá chợp mắt chút...",
		"🛏️ Hôm nay làm việc hết công suất rồi, cần nghỉ ngơi.",
	],
	"INJURED": [
		"🩹 Vết thương cần được băng bó lại cẩn thận.",
		"💊 Nghỉ ở Trung Tâm Hồi Phục một lát là khỏe ngay.",
	],
	"WORK": [
		"⚒️ Thêm một mẻ sản xuất nữa cho Lâu Đài thịnh vượng!",
		"🏗️ Công trình đang vận hành trơn tru lắm!",
	],
}

const SOCIAL_PAIRS := [
	["👋 Chào %s! Hôm nay cậu thấy Lâu Đài thế nào?", "😊 Rất tuyệt %s ạ! Master chăm lo chu đáo lắm."],
	["⚔️ Tối nay rảnh đi tập luyện cùng tớ không %s?", "🔥 Được đấy %s! Nhớ giữ sức cho Tháp PvE nhé."],
	["🍖 Bữa trưa hôm nay ở Nhà Bếp ngon tuyệt nhỉ %s!", "😋 Công nhận %s! Ăn no mới có sức làm việc."],
	["✨ Nghe nói sắp có Anh Hùng mới được triệu hồi đấy %s!", "🌟 Thật hả %s? Mong là đồng đội mạnh mẽ!"],
]

static func pick_ambient_line(class_code: String, routine_goal: String, mood: String = "NEUTRAL") -> String:
	var goal := routine_goal.to_upper()
	if NEED_LINES.has(goal):
		var arr: Array = NEED_LINES[goal]
		return str(arr[randi() % arr.size()])
	var m := mood.to_upper()
	if m == "HAPPY" or m == "EXCITED":
		return "✨ Hôm nay tâm trạng thật phấn chấn!"
	if m == "SAD" or m == "STRESSED":
		return "😔 Hơi căng thẳng một chút, mong được Master quan tâm..."
	var cc := class_code.to_upper()
	if CLASS_LINES.has(cc):
		var carr: Array = CLASS_LINES[cc]
		return str(carr[randi() % carr.size()])
	return "💬 Lâu Đài hôm nay thật yên bình!"

static func pick_social_pair(name_a: String, name_b: String) -> Array[String]:
	var pair: Array = SOCIAL_PAIRS[randi() % SOCIAL_PAIRS.size()]
	var line_a := str(pair[0]) % name_b
	var line_b := str(pair[1]) % name_a
	return [line_a, line_b]

static func status_icon_for(routine_goal: String, building_type: String = "") -> String:
	match routine_goal.to_upper():
		"HUNGRY": return "🍖"
		"TIRED": return "💤"
		"INJURED": return "🩹"
		"WORK":
			var bt := building_type.to_upper()
			if bt in ["LIBRARY", "ACADEMY", "RESEARCH"]:
				return "📚"
			return "⚒️"
		_: return "✨"
