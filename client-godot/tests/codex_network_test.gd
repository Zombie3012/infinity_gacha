extends Node

var checks := 0
var failed := false

func expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed = true
		push_error("CODEX_NETWORK: " + msg)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("CODEX_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("CODEX_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("CODEX_TEST_MASTER")
	GameState.record_castle_activity("Nâng cấp Nhà Bếp lên Cấp 2")

	var modal: Control = load("res://scripts/ui/codex_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()

	expect(modal._tab_buttons.size() == 4, "CodexModal has 4 tabs")
	expect(modal._status_lbl.text.contains("Đã tải:"), "CodexModal finishes loading codex data from backend")
	modal.switch_tab(1)
	await get_tree().process_frame
	expect(modal._body_holder.get_child_count() == 1, "Tab 1 renders ItemGridBrowser for gear 1★-7★")
	modal.switch_tab(2)
	await get_tree().process_frame
	expect(modal._body_holder.get_child_count() == 1, "Tab 2 renders Alchemy codex")
	modal.switch_tab(3)
	await get_tree().process_frame
	var log_txt := ""
	for lbl in modal._body_holder.find_children("*", "Label", true, false):
		log_txt += lbl.text + "\n"
	expect(log_txt.contains("Nâng cấp Nhà Bếp"), "Tab 3 renders Castle Activity Log")

	modal.queue_free()
	await get_tree().process_frame
	print("CODEX_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
