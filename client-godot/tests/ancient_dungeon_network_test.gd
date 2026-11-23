extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("DUNGEON: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("DG_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("DG_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("DG_TEST_MASTER")
	await run_flow()
	print("ANCIENT_DUNGEON_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	# 1. Verify PveModeModal removed CONQUEST and enabled DUNGEON + EXPEDITION
	var mode_modal = load("res://scripts/ui/pve_mode_modal.gd").new()
	add_child(mode_modal)
	mode_modal.setup()
	await get_tree().process_frame
	var ids: Array = []
	var all_open := true
	for m in mode_modal._modes:
		ids.append(str(m.get("id", "")))
		if not bool(m.get("available", false)):
			all_open = false
	expect(not ids.has("CONQUEST") and ids.has("DUNGEON") and ids.has("EXPEDITION") and all_open, "PveModeModal removed CONQUEST and enabled DUNGEON & EXPEDITION")
	mode_modal.queue_free()

	# 2. AncientDungeonModal flow
	var modal = load("res://scripts/ui/ancient_dungeon_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()
	await get_tree().process_frame
	expect(not modal._templates.is_empty(), "Dungeon templates loaded")
	await modal.enter_floor(1)
	expect(not modal._active_instance.is_empty(), "Entered floor 1 dungeon instance")
	var iid := str(modal._active_instance.get("id", ""))
	if not iid.is_empty():
		await modal.explore_active(iid)
		expect(modal._log_lines.size() >= 2, "Explore room appends event log")
		await modal.retreat_active(iid)
		expect(modal._active_instance.is_empty(), "Retreat closes active dungeon instance")
	modal.queue_free()
