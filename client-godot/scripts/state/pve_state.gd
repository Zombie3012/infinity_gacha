extends Node

## Persistent PvE client state. Server owns movement, combat and rewards.
## Never stores authentication tokens. Retains a command key across timeouts/restarts.
signal snapshot_changed
signal message_changed(message: String, is_error: bool)
signal command_changed
signal battle_completed(battle_id: String)

const POLL_SECONDS := 1.0
const ACTIVE_STATUSES := ["IDLE", "MOVING", "FIGHTING"]
var snapshot: Dictionary = {}
var selected_party_id: String = ""
var selected_squad_id: String = ""
var selected_battle_id: String = ""
var pending_command: Dictionary = {}
var polling_enabled: bool = false
var connected: bool = false
var command_busy: bool = false
var _poll_busy: bool = false
var _poll_elapsed: float = 0.0
var _cursor: int = 0
var _cursor_map_id: String = ""
var _account_scope: String = ""
var _server_time: float = 0.0
var _server_tick: int = 0
var _scope_generation: int = 0

func _process(delta: float) -> void:
	if not polling_enabled or not GameState.is_logged_in():
		return
	_poll_elapsed += delta
	if _poll_elapsed >= POLL_SECONDS and not _poll_busy:
		_poll_elapsed = 0.0
		refresh()

func activate() -> void:
	if _account_scope != GameState.master_id:
		deactivate()
		_account_scope = GameState.master_id
		snapshot = {}
		_cursor = 0
		_cursor_map_id = ""
		selected_squad_id = ""
		selected_party_id = ""
		pending_command = {}
		_load_pending()
	polling_enabled = true
	_poll_elapsed = 0.0
	await refresh()

func deactivate() -> void:
	_scope_generation += 1
	_account_scope = ""
	polling_enabled = false
	connected = false
	_poll_busy = false
	command_busy = false
	snapshot = {}
	pending_command = {}
	_cursor = 0
	_cursor_map_id = ""
	selected_party_id = ""
	selected_squad_id = ""
	selected_battle_id = ""
	snapshot_changed.emit()
	command_changed.emit()

func server_now() -> float:
	return _server_time + float(Time.get_ticks_msec() - _server_tick) / 1000.0

static func parse_time(value: String) -> float:
	if value.length() < 19:
		return 0.0
	var parts := value.trim_suffix("Z").split(".")
	var seconds := float(Time.get_unix_time_from_datetime_string(parts[0]))
	if parts.size() > 1:
		seconds += float("0." + parts[1])
	return seconds

static func optional_id(value: Variant) -> String:
	return value if value is String else ""

func refresh() -> bool:
	if _poll_busy or not GameState.is_logged_in():
		return false
	_poll_busy = true
	var generation := _scope_generation
	var request_master := GameState.master_id
	var endpoint := "/api/pve/state?cursor=%d" % _cursor
	if not _cursor_map_id.is_empty():
		endpoint += "&mapId=" + _cursor_map_id.uri_encode()
	var result: Dictionary = await ApiClient.get_req(endpoint)
	if generation != _scope_generation:
		return false
	_poll_busy = false
	if request_master != GameState.master_id:
		connected = false
		return false
	if not result.get("ok", false) or not (result.get("data") is Dictionary):
		connected = false
		message_changed.emit(error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), true)
		command_changed.emit()
		return false
	var recovered := not connected
	connected = true
	var data: Dictionary = result["data"]
	_server_time = parse_time(str(data.get("serverNow", "")))
	_server_tick = Time.get_ticks_msec()
	snapshot = data
	var map_value: Variant = data.get("map")
	_cursor_map_id = str(map_value.get("id", "")) if map_value is Dictionary else ""
	_cursor = int(data.get("cursor", 0))
	var refresh_game := false
	var notice: Dictionary = {}
	for event_value in data.get("events", []):
		if not (event_value is Dictionary):
			continue
		var kind := str(event_value.get("kind", ""))
		var event_data: Dictionary = event_value.get("data", {})
		var event_notice := _event_notice(kind, event_data)
		if not event_notice.is_empty():
			notice = event_notice
		if kind in ["RESOURCE_COLLECTED", "CONSUMABLES_RECOVERED", "BATTLE_STARTED", "BATTLE_COMPLETED", "MAP_CLEARED", "SQUAD_DEPLOYED"]:
			refresh_game = true
		if kind == "BATTLE_COMPLETED":
			battle_completed.emit(str(event_data.get("battleId", "")))
	snapshot_changed.emit()
	command_changed.emit()
	if not notice.is_empty():
		message_changed.emit(str(notice["message"]), bool(notice.get("error", false)))
	elif recovered:
		message_changed.emit("Đã kết nối và đồng bộ bản đồ." if pending_command.is_empty() else "Có lệnh chưa xác nhận. Bấm Thử lại lệnh để kiểm tra kết quả.", not pending_command.is_empty())
	if refresh_game:
		await refresh_game_data()
	return true

func _event_notice(kind: String, data: Dictionary) -> Dictionary:
	var squad := squad_by_id(str(data.get("squadId", "")))
	var team := str(squad.get("name", "Đội chinh phạt"))
	match kind:
		"BATTLE_STARTED":
			return {"message": "%s bắt đầu giao chiến thủ công. Mở trận để điều khiển trong 10 giây.%s" % [team, " Đội bị phục kích!" if bool(data.get("ambush", false)) else ""]}
		"CONSUMABLES_RECOVERED":
			return {"message": "%s đã nhặt vật phẩm tiêu hao rơi trên map." % team}
		"RESOURCE_COLLECTED":
			return {"message": "%s đã thu %d %s." % [team, int(data.get("quantity", 0)), str(data.get("itemId", ""))]}
		"BATTLE_COMPLETED":
			var winner := str(data.get("winner", "DRAW"))
			var outcome := "chiến thắng" if winner == "HERO" else "thất bại" if winner == "ENEMY" else "hòa"
			var message := "%s vừa %s. +%d Silver, +%d EXP/Hero. Chiến báo đã lưu." % [team, outcome, int(data.get("silverReward", 0)), int(data.get("heroExpReward", 0))]
			if not data.get("deaths", []).is_empty():
				message += " %d Hero không còn khả năng chiến đấu." % data["deaths"].size()
			return {"message": message, "error": winner != "HERO"}
		"SQUAD_EXHAUSTED":
			return {"message": "%s đã dừng vì Hero quá đói hoặc mệt. Thu hồi đội để hồi phục tại căn cứ." % team, "error": true}
		"AUTO_STOPPED":
			return {"message": "%s đã khám phá hết các ô có thể tiếp cận và dừng auto." % team}
		"MAP_CLEARED":
			return {"message": "Đã hạ boss tầng %d và thu hồi các đội. Bấm tiến vào tầng %d để tiếp tục." % [int(data.get("floor", 1)), int(data.get("nextFloor", 2))]}
	return {}

func refresh_game_data() -> void:
	var request_master := GameState.master_id
	for refresh_data in [GameState.refresh_profile, GameState.refresh_heroes, GameState.refresh_inventory,
		GameState.refresh_equipment, GameState.refresh_party, GameState.refresh_base_overview]:
		if request_master != GameState.master_id:
			return
		await refresh_data.call()

func send_command(endpoint: String, body: Dictionary = {}, method: int = HTTPClient.METHOD_POST) -> Dictionary:
	if command_busy or not pending_command.is_empty():
		return {"ok": false, "error": "ERR_PVE_PENDING_COMMAND"}
	if not connected:
		message_changed.emit("Mất kết nối. Hãy tải lại trạng thái trước khi ra lệnh.", true)
		return {"ok": false, "error": "ERR_NETWORK_CONNECTION"}
	var random_bytes := Crypto.new().generate_random_bytes(16)
	pending_command = {"key": "pve-" + random_bytes.hex_encode(), "endpoint": endpoint,
		"body": body.duplicate(true), "method": method, "masterId": GameState.master_id}
	if not _save_pending():
		pending_command = {}
		message_changed.emit("Không lưu được lệnh an toàn trên máy. Hãy kiểm tra quyền ghi dữ liệu game.", true)
		return {"ok": false, "error": "ERR_PVE_LOCAL_SAVE"}
	return await retry_pending()

func retry_pending() -> Dictionary:
	if command_busy or pending_command.is_empty():
		return {"ok": false, "error": "ERR_PVE_NO_PENDING_COMMAND"}
	if str(pending_command.get("masterId", "")) != GameState.master_id:
		return {"ok": false, "error": "ERR_PVE_ACCOUNT_CHANGED"}
	command_busy = true
	var generation := _scope_generation
	command_changed.emit()
	var request: Dictionary = pending_command.duplicate(true)
	var result: Dictionary = await ApiClient.api_request(str(request["endpoint"]),
		int(request["method"]), request.get("body", {}), {"Idempotency-Key": str(request["key"])})
	if generation != _scope_generation:
		return {"ok": false, "error": "ERR_PVE_ACCOUNT_CHANGED"}
	if str(request["masterId"]) != GameState.master_id:
		command_busy = false
		command_changed.emit()
		return {"ok": false, "error": "ERR_PVE_ACCOUNT_CHANGED"}
	var status := int(result.get("status", 0))
	if result.get("ok", false) or (status >= 400 and status < 500 and status not in [401, 403, 408, 425, 429]):
		pending_command = {}
		_save_pending()
	if result.get("ok", false):
		message_changed.emit("Đã nhận lệnh. Đang đồng bộ bản đồ...", false)
		# A poll that started before the command may contain the old squad state.
		while _poll_busy and generation == _scope_generation:
			await get_tree().process_frame
		if generation != _scope_generation:
			return {"ok": false, "error": "ERR_PVE_ACCOUNT_CHANGED"}
		await refresh()
	else:
		message_changed.emit(error_message(str(result.get("error", "ERR_NETWORK_CONNECTION"))), true)
	if generation != _scope_generation:
		return {"ok": false, "error": "ERR_PVE_ACCOUNT_CHANGED"}
	command_busy = false
	command_changed.emit()
	return result

func active_squads() -> Array:
	return snapshot.get("squads", []).filter(func(squad): return str(squad.get("status", "")) in ACTIVE_STATUSES)

func squad_by_id(squad_id: String) -> Dictionary:
	for squad in snapshot.get("squads", []):
		if str(squad.get("id", "")) == squad_id:
			return squad
	return {}

func reserved_hero_ids() -> Array:
	var ids: Array = []
	for squad in active_squads():
		for member in squad.get("plan", {}).get("members", []):
			ids.append(str(member.get("heroId", "")))
	return ids

func _pending_path() -> String:
	# Only a server-generated UUID is used as a filename component.
	return "user://pve_pending_%s.json" % GameState.master_id.validate_filename()

func _save_pending() -> bool:
	var file := FileAccess.open(_pending_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(pending_command))
	file.flush()
	return file.get_error() == OK

func _load_pending() -> void:
	if not FileAccess.file_exists(_pending_path()):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(_pending_path()))
	if value is Dictionary and str(value.get("masterId", "")) == GameState.master_id and str(value.get("endpoint", "")).begins_with("/api/pve/"):
		if value.get("body") is Dictionary and str(value.get("key", "")).length() > 0 and int(value.get("method", -1)) in [HTTPClient.METHOD_POST, HTTPClient.METHOD_PUT]:
			pending_command = value

static func error_message(code: String) -> String:
	var messages := {
		"ERR_COMBAT_STALE_TURN": "Lượt đã thay đổi. Hãy chọn hành động cho lượt hiện tại.",
		"ERR_PVE_BATTLE_FINISHED": "Trận đã kết thúc hoặc chuyển sang tự động.",
		"ERR_COMBAT_ITEM_LIMIT": "Mỗi lượt chỉ dùng hai loại khác nhau, mỗi loại một viên.",
		"ERR_COMBAT_SKILL_UNAVAILABLE": "Kỹ năng chưa sẵn sàng hoặc không đủ MP.",
		"ERR_COMBAT_TARGET": "Chọn mục tiêu còn sống phù hợp với hành động.",
		"ERR_COMBAT_MP_FULL": "Hero đã đầy MP hoặc không có MP.",
		"ERR_COMBAT_HP_FULL": "Hero đã đầy HP và không có thương tích.",
		"ERR_COMBAT_BUFF_ACTIVE": "Hero đang có hiệu ứng cường lực, không thể cộng dồn.",
		"ERR_CONSUMABLE_STOCK": "Không đủ vật phẩm tiêu hao trong kho hoặc ô đã chọn.",
		"ERR_CONSUMABLE_CONFIG": "Mỗi Hero có năm ô, mỗi ô tối đa bốn vật phẩm cùng loại.",
		"ERR_PVE_RECALL_LOCKED": "Tầng này cấm thu hồi và dùng Đá dịch chuyển tới khi hoàn thành mục tiêu.",
		"ERR_PVE_TELEPORT_STONE_REQUIRED": "Cần 1 Đá dịch chuyển để tạo điểm thu hồi.",
		"ERR_PVE_RECALL_POINT_EXISTS": "Ô này đã có điểm thu hồi, không cần dùng thêm đá.",
		"ERR_PVE_SQUAD_MUST_STOP": "Đội cần dừng di chuyển trước khi dùng Đá dịch chuyển.",
		"ERR_PVE_DEV_ONLY": "Reset tháp chỉ được bật trên server phát triển.",
		"ERR_PVE_CATCHUP_PENDING": "Đang xử lý tiến độ khi bạn vắng mặt. Đợi đồng bộ rồi thử lại lệnh.",
		"ERR_PVE_AREA_MISMATCH": "Đội đã đổi khu vực. Hãy đồng bộ map và ra lệnh lại.",
		"ERR_PVE_INVALID_PORTAL": "Đội phải đứng đúng cửa trước khi đi qua.",
		"ERR_PVE_INVALID_DESTINATION": "Không có đường đi hợp lệ qua vùng đã khám phá tới ô này.",
		"ERR_PVE_SQUAD_PURSUED": "Quái đang truy đuổi hoặc tìm kiếm đội. Hãy thoát truy đuổi trước khi thu hồi.",
		"ERR_INSUFFICIENT_RATIONS": "Thiếu lương thực. Mỗi lần triển khai cần 10 FOOD cho mỗi Hero.",
		"ERR_PVE_SQUAD_LIMIT": "Đã triển khai tối đa 3 đội. Hãy thu hồi một đội trước.",
		"ERR_PVE_HERO_DEPLOYED": "Hero đang được triển khai. Hãy thu hồi đội trước khi thay đổi.",
		"ERR_PVE_PARTY_DEPLOYED": "Đội đang được triển khai; không thể sửa đội hình hoặc chiến thuật.",
		"ERR_PVE_HERO_BUSY": "Một Hero đang làm việc, điều trị, đi expedition hoặc tham gia trận khác.",
		"ERR_PVE_HERO_EXHAUSTED": "Hero quá đói, quá mệt hoặc đang nghỉ. Hãy hồi phục ở căn cứ.",
		"ERR_PVE_HERO_UNAVAILABLE": "Đội có Hero không thể ra trận. Hãy kiểm tra trạng thái và đội hình.",
		"ERR_PVE_INVALID_PLAN": "Xếp 1–5 Hero vào các ô khác nhau; mỗi Hero chỉ xuất hiện một lần.",
		"ERR_PVE_INVALID_PARTY": "Đội cần tên hợp lệ và 1–5 Hero khác nhau.",
		"ERR_PVE_SKILL_UNAVAILABLE": "Chiến thuật chứa kỹ năng Hero chưa mở khóa.",
		"ERR_PVE_DUPLICATE_PARTY_NAME": "Tên đội đã tồn tại. Hãy chọn tên khác.",
		"ERR_PVE_DESTINATION_UNDISCOVERED": "Chưa có đường đã khám phá. Hãy chọn ô ở rìa vùng đã mở.",
		"ERR_PVE_ALREADY_AT_DESTINATION": "Đội đang ở ô này.",
		"ERR_PVE_SQUAD_WITHDRAWN": "Đội đã rời map. Hãy triển khai lại nếu map chưa hoàn thành.",
		"ERR_PVE_SQUAD_FIGHTING": "Đội đang tự giao chiến. Chỉ có thể ra lệnh sau khi kết thúc trận.",
		"ERR_PVE_MAP_CLEARED": "Tầng đã hoàn thành. Hãy tiến vào tầng tiếp theo.",
		"ERR_PVE_LEGACY_COMBAT_ACTIVE": "Một trận đấu cũ chưa hoàn tất. Hãy kết thúc trận trước khi vào map.",
		"ERR_PVE_LEGACY_DUNGEON_ACTIVE": "Một phiên dungeon cũ chưa kết thúc. Hãy hoàn thành hoặc rời phiên đó trước.",
		"ERR_PVE_PENDING_COMMAND": "Có lệnh chưa xác nhận. Hãy dùng Thử lại lệnh trước khi thực hiện thao tác mới.",
		"ERR_NETWORK_TIMEOUT": "Kết nối hết thời gian chờ. Dùng Thử lại lệnh để kiểm tra kết quả an toàn.",
		"ERR_NETWORK_CONNECTION": "Mất kết nối. Lệnh chưa xác nhận sẽ giữ nguyên để thử lại an toàn.",
		"ERR_UNAUTHORIZED": "Phiên đăng nhập đã hết hạn. Hãy đăng nhập lại.",
	}
	return str(messages.get(code, "Không thể hoàn thành thao tác: " + code))
