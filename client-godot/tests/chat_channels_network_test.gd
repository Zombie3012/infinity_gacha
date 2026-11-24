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

	# 4. Simulate reload: new ChatPanelModal loads persisted Alliance & Private history
	modal.queue_free()
	await get_tree().process_frame
	var modal2 = load("res://scripts/ui/chat_panel_modal.gd").new()
	add_child(modal2)
	await get_tree().process_frame
	await modal2.switch_channel(1)
	expect(modal2._messages_label.text.contains("Chào anh em Liên Minh!"), "Alliance chat persists after reload")
	await modal2.switch_channel(2)
	modal2._recipient_input.text = OS.get_environment("CHAT_PEER_NAME")
	await modal2.refresh_messages()
	expect(modal2._messages_label.text.contains("Tin nhắn mật!"), "Private chat persists after reload")

	# 5. Real-time EventBus SSE delivery test
	EventBus.chat_message_received.emit({
		"channel": "PRIVATE",
		"message": {"id": "sse-rt-1", "senderMasterId": "peer", "senderName": OS.get_environment("CHAT_PEER_NAME"), "recipientName": "Me", "body": "Tin nhắn SSE tức thì!"}
	})
	await get_tree().process_frame
	expect(modal2._messages_label.text.contains("Tin nhắn SSE tức thì!"), "ChatPanelModal receives real-time SSE message immediately")

	# 6. P3-31: Share Hero & Battle Report to Chat
	var hero_txt: String = modal2.format_hero_share({"name": "Lucifer", "rarity": 5, "level": 40, "classCode": "MAGE", "combatPower": 3500})
	var battle_txt: String = modal2.format_battle_share({"settlement": {"floor": 5}}, {"winner": "HERO", "rounds": 3, "totalDamage": 1200})
	var s_hero: Dictionary = await modal2.share_to_channel(0, hero_txt)
	var s_bat: Dictionary = await modal2.share_to_channel(1, battle_txt)
	expect(s_hero.get("ok", false) and hero_txt.contains("KHOE TƯỚNG") and s_bat.get("ok", false) and battle_txt.contains("CHIẾN BÁO"), "P3-31 Hero & Battle share messages post cleanly to World/Alliance chat")

	modal2.queue_free()
