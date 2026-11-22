extends Node

var checks: int = 0
var failed: bool = false

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("MEDICAL NETWORK: " + description)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("MEDICAL_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("MEDICAL_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("MEDICAL_TEST_MASTER")
	await run_flow()
	print("MEDICAL_NETWORK_TESTS: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	expect(await GameState.refresh_profile(), "Load authenticated profile")
	expect(await GameState.refresh_heroes(), "Load actual injured Heroes")
	var recovery: Control = load("res://scripts/ui/recovery_center_modal.gd").new()
	add_child(recovery)
	var deadline := Time.get_ticks_msec() + 10000
	while recovery.browser.all_items.size() != 3 and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	expect(recovery.assigned_worker_name == "Chưa phân công", "Overview loads the real /api/medical endpoint")
	expect(recovery.medicine_count == 2, "Overview and inventory load medicine")
	var patients: Array = recovery.browser.all_items.duplicate(true)
	expect(patients.size() == 3, "All three living injured Heroes appear")
	if patients.size() != 3:
		recovery.queue_free()
		return
	await recovery._on_admit_selected_heroes(patients)
	expect(recovery.active_treatments.size() == 2 and recovery.queued_treatments.size() == 1, "Batch admits two beds and queues one patient")
	expect(recovery.bed_info_label.text.contains("2/2") and recovery.bed_info_label.text.contains("1/6"), "Bed and queue counters reflect committed server state")
	expect(recovery.browser.all_items.filter(func(h): return bool(h.get("isTreating", false))).size() == 2, "Active patients are marked as treating")
	expect(recovery.browser.all_items.filter(func(h): return bool(h.get("isQueued", false))).size() == 1, "Queued patient is marked as queued")
	await recovery._on_admit_selected_heroes(recovery.browser.all_items)
	expect(recovery.banner_label.text.contains("đều đang trong giường"), "Already admitted patients are not submitted again")
	recovery._on_auto_select_pressed()
	expect(recovery.browser.get_selected_items().is_empty(), "Auto-select excludes patients already admitted or queued")
	recovery.browser.select_items_by_ids([recovery.queued_treatments[0].get("heroId", "")])
	await recovery._on_cancel_treatment_pressed()
	expect(recovery.queued_treatments.is_empty(), "Cancel releases the queued patient")
	var active_ids: Array = recovery.active_treatments.map(func(t): return str(t.get("heroId", "")))
	recovery.browser.select_items_by_ids(active_ids)
	await recovery._on_quick_heal_pressed()
	expect(recovery.active_treatments.is_empty(), "Quick Heal completes both active treatments")
	expect(recovery.medicine_count == 0, "Quick Heal consumes one medicine per healed Hero")
	expect(recovery.browser.all_items.filter(func(h): return float(h.get("hp", 0)) >= float(h.get("maxHp", 1))).size() == 2, "Healed Heroes have full HP in refreshed roster")
	expect(recovery.bed_info_label.text.contains("0/2"), "Completed treatments release both beds")
	recovery.queue_free()
