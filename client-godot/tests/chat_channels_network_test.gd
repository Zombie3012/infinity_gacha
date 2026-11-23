extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("CHAT_CHANNELS: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("CHAT_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("CHAT_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("CHAT_TEST_MASTER")
	await run_flow()
	print("CHAT_CHANNELS_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var modal = load("res://scripts/ui/chat_panel_modal.gd").new()
	add_child(modal)
	await get_tree().process_frame
	expect(modal._tab_buttons.size() == 3, "ChatPanelModal has 3 channel tabs")

	# 1. World chat
	modal._msg_input.text = "Xin chào Thế Giới!"
	var w_res: Dictionary = await modal.send_current_message()
	expect(w_res.get("ok", false) and modal._messages_label.text.contains("Xin chào Thế Giới!"), "World chat send & display works")

	# 2. Alliance chat
	await modal.switch_channel(1)
	modal._msg_input.text = "Chào anh em Liên Minh!"
	var a_res: Dictionary = await modal.send_current_message()
	expect(a_res.get("ok", false) and modal._messages_label.text.contains("Chào anh em Liên Minh!"), "Alliance chat send & display works")

	# 3. Private chat
	await modal.switch_channel(2)
	modal._recipient_input.text = OS.get_environment("CHAT_PEER_NAME")
	modal._msg_input.text = "Tin nhắn mật!"
	var p_res: Dictionary = await modal.send_current_message()
	if not p_res.get("ok", false):
		push_error("PRIVATE CHAT ERR: " + str(p_res))
	expect(p_res.get("ok", false) and modal._messages_label.text.contains("Tin nhắn mật!"), "Private chat send & display works")

	modal.queue_free()
