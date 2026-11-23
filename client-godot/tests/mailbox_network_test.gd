extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("MAILBOX: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("MB_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("MB_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("MB_TEST_MASTER")
	await run_flow()
	print("MAILBOX_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	await GameState.refresh_profile()
	var modal = load("res://scripts/ui/mailbox_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()
	await get_tree().process_frame
	expect(modal._tab_buttons.size() == 2, "MailboxModal has 2 tabs (Mailbox, Ledger)")
	expect(modal._messages.size() >= 1, "Mailbox loads seeded mail message")
	if not modal._messages.is_empty():
		var silver_before := GameState.silver_coins
		await modal.claim_message(str(modal._messages[0].get("id", "")))
		expect(GameState.silver_coins > silver_before, "Claiming mail grants attached Silver reward")
	modal._switch_tab(1)
	await get_tree().process_frame
	expect(modal._active_tab == 1, "Switching to Economy Ledger tab works")
	modal.queue_free()
