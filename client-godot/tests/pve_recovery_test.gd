extends Node

## Three separate engine processes test ambiguous writes and offline movement.
var _checks: int = 0
var _failures: int = 0
var _completed: bool = false

func expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("PVE RECOVERY: " + description)

func _ready() -> void:
	var watchdog := get_tree().create_timer(25.0)
	watchdog.timeout.connect(func(): push_error("PvE recovery test timed out"); get_tree().quit(1))
	ApiClient.base_url = OS.get_environment("PVE_TEST_API_URL")
	ApiClient.set_auth_token(OS.get_environment("PVE_TEST_ACCESS_TOKEN"))
	GameState.master_id = OS.get_environment("PVE_TEST_MASTER_ID")
	await PveState.activate()
	PveState.polling_enabled = false
	expect(PveState.connected, "The restarted client loads its own map")
	var phase := OS.get_environment("PVE_TEST_PHASE")
	match phase:
		"ambiguous": await _ambiguous_deploy()
		"resume": await _resume_and_move()
		"offline": await _offline_and_account_switch()
		_: expect(false, "Runner supplies a valid phase")
	print("PVE_RECOVERY_TESTS: %s, %d checks, %d failures" % [phase, _checks, _failures])
	get_tree().quit(1 if _failures else 0)

func _ambiguous_deploy() -> void:
	var endpoint := "/api/pve/parties/%s/deploy" % OS.get_environment("PVE_TEST_PARTY_ID")
	await ApiClient.post_req("/__pve_test/drop-next", {"endpoint": endpoint})
	var result: Dictionary = await PveState.send_command(endpoint)
	expect(not result.get("ok", false) and int(result.get("status", -1)) == 0, "A committed deployment can lose its HTTP response")
	expect(not PveState.pending_command.is_empty(), "An ambiguous command retains its key in memory")
	var saved := FileAccess.get_file_as_string(PveState._pending_path())
	var persisted: Variant = JSON.parse_string(saved)
	expect(persisted is Dictionary and persisted.get("key") == PveState.pending_command.get("key"), "The exact retry key is on disk before the game exits")
	expect(not saved.contains(ApiClient.auth_token), "Pending command storage contains no access token")

func _resume_and_move() -> void:
	expect(not PveState.pending_command.is_empty(), "A fresh engine process restores the unconfirmed command")
	var key := str(PveState.pending_command.get("key", ""))
	await ApiClient.post_req("/__pve_test/delay-next-state", {})
	_delayed_refresh()
	await get_tree().create_timer(0.05).timeout
	var result: Dictionary = await PveState.retry_pending()
	expect(result.get("ok", false), "Retry recovers the committed deployment result")
	expect(not key.is_empty() and PveState.pending_command.is_empty(), "Only an acknowledged result clears the persisted retry")
	expect(PveState.active_squads().size() == 1, "Retry creates exactly one deployed squad")
	expect(int(PveState.snapshot.get("food", 0)) == 990, "Deployment rations are charged once across client restarts")
	expect(_completed and not PveState.command_busy, "Command controls wait for an earlier poll and the authoritative refresh")
	if PveState.active_squads().is_empty():
		return
	var squad_id := str(PveState.active_squads()[0].get("id", ""))
	var moving: Dictionary = await PveState.send_command("/api/pve/squads/%s/move" % squad_id, {"x": 1, "y": 0})
	expect(moving.get("ok", false), "A real movement order is persisted before disconnecting")
	expect(int(PveState.squad_by_id(squad_id).get("x", -1)) == 0, "Disconnect happens before the one-second arrival")

func _delayed_refresh() -> void:
	await PveState.refresh()
	_completed = true

func _offline_and_account_switch() -> void:
	var squads: Array = PveState.active_squads()
	expect(squads.size() == 1 and int(squads[0].get("x", -1)) == 1, "Offline movement resumes after both the API and game restart")
	expect(int(PveState.snapshot.get("food", 0)) == 990, "Reloading an arrival does not charge another dispatch")
	var first_master := GameState.master_id
	var first_token := ApiClient.auth_token
	await ApiClient.post_req("/__pve_test/delay-next-state", {})
	_delayed_refresh()
	await get_tree().create_timer(0.05).timeout
	GameState.master_id = OS.get_environment("PVE_TEST_OTHER_MASTER_ID")
	ApiClient.set_auth_token(OS.get_environment("PVE_TEST_OTHER_TOKEN"))
	await PveState.activate()
	PveState.polling_enabled = false
	while not _completed:
		await get_tree().process_frame
	expect(PveState.connected and PveState.snapshot.get("map") == null, "A late response from account A cannot overwrite account B's empty map")
	expect(PveState.snapshot.get("squads", []).is_empty(), "Account switching never reuses another Master's squads")
	expect(PveState.pending_command.is_empty(), "Account switching never reuses another Master's pending command")
	# Clean only these disposable accounts' local pending files.
	var other_path := ProjectSettings.globalize_path(PveState._pending_path())
	DirAccess.remove_absolute(other_path)
	GameState.master_id = first_master
	ApiClient.set_auth_token(first_token)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PveState._pending_path()))
	PveState.deactivate()
