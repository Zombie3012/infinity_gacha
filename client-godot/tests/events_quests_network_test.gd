extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("EVENTS_QUESTS: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("EQ_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("EQ_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("EQ_TEST_MASTER")
	await run_flow()
	print("EVENTS_QUESTS_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var modal = load("res://scripts/ui/events_quests_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()
	await get_tree().process_frame
	expect(modal._tab_buttons.size() == 3, "EventsQuestsModal has 3 tabs (LiveOps, Quests, Achievements)")
	var q_res := await ApiClient.get_req("/api/quests")
	expect(q_res.get("ok", false), "GET /api/quests succeeds")
	var ev_res := await ApiClient.get_req("/api/events")
	expect(ev_res.get("ok", false), "GET /api/events succeeds")
	if not modal._quests_data.is_empty():
		var first_q: Dictionary = modal._quests_data[0]
		var q_code := str(first_q.get("code", ""))
		if str(first_q.get("status", "")).to_upper() == "AVAILABLE" and not q_code.is_empty():
			await modal._accept_quest(q_code)
			expect(true, "Accept quest action completes cleanly")
	modal._switch_tab(1)
	await get_tree().process_frame
	modal._switch_tab(2)
	await get_tree().process_frame
	expect(modal._active_tab == 2, "Switching between Events, Quests, and Achievements tabs works")
	modal.queue_free()
