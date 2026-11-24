extends Node

var checks := 0
var failed := false

func expect(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failed = true
		push_error("FRIENDS_NETWORK: " + msg)

func _ready() -> void:
	var url := OS.get_environment("FRIENDS_TEST_URL")
	var token_a := OS.get_environment("FRIENDS_TOKEN_A")
	var master_a := OS.get_environment("FRIENDS_MASTER_A")
	var token_b := OS.get_environment("FRIENDS_TOKEN_B")
	var master_b := OS.get_environment("FRIENDS_MASTER_B")
	var name_b := OS.get_environment("FRIENDS_NAME_B")

	ApiClient.base_url = url
	ApiClient.set_auth_token(token_a)
	GameState.master_id = master_a

	var modal: Control = load("res://scripts/ui/friends_modal.gd").new()
	add_child(modal)
	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Search Master B
	var search_res: Dictionary = await modal.search_masters(name_b)
	expect(search_res.get("ok", false), "Search Master B succeeds")
	var found_b := false
	for r in modal._search_results:
		if str(r.get("masterId", "")) == master_b:
			found_b = true
	expect(found_b, "Search results contain Master B")

	# 2. Master A sends friend request to Master B
	var req_res: Dictionary = await modal.send_request(master_b)
	expect(req_res.get("ok", false), "Master A sends friend request to Master B")

	# 3. Switch to Master B and accept request
	ApiClient.set_auth_token(token_b)
	GameState.master_id = master_b
	await modal.refresh_all()
	expect(modal._incoming_requests.size() == 1, "Master B sees 1 incoming request")
	var rid := str(modal._incoming_requests[0].get("requestId", ""))
	var acc_res: Dictionary = await modal.accept_request(rid)
	expect(acc_res.get("ok", false), "Master B accepts friend request")
	expect(modal._friends.size() == 1 and str(modal._friends[0].get("friendMasterId", "")) == master_a, "Master B lists Master A as friend")

	# 4. Master A sends daily gift, Master B claims all gifts
	ApiClient.set_auth_token(token_a)
	GameState.master_id = master_a
	await modal.refresh_all()
	var gift_res: Dictionary = await modal.send_gift(master_b)
	expect(gift_res.get("ok", false), "Master A sends daily gift to Master B")

	var prof_res: Dictionary = await modal.view_profile(master_b)
	expect(prof_res.get("ok", false) and str(prof_res.get("data", {}).get("profile", {}).get("masterId", "")) == master_b, "Master A views Master B public profile")

	var visit_res: Dictionary = await modal.visit_friend_base(master_b, name_b)
	expect(visit_res.get("ok", false) and str(visit_res.get("data", {}).get("master", {}).get("masterId", "")) == master_b, "Master A visits Master B Castle Base (P3-24)")

	ApiClient.set_auth_token(token_b)
	GameState.master_id = master_b
	await modal.refresh_all()
	expect(modal._unclaimed_gift_count == 1, "Master B has 1 unclaimed gift")
	var claim_res: Dictionary = await modal.claim_all_gifts()
	expect(claim_res.get("ok", false) and int(claim_res.get("data", {}).get("claimedCount", 0)) == 1, "Master B claims all gifts (+200 silver)")

	# 5. Cross-link: ChatPanelModal open_private_with & Friends quick row
	var chat: Control = load("res://scripts/ui/chat_panel_modal.gd").new()
	add_child(chat)
	chat.open_private_with(name_b)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(chat._active_channel == 2 and chat._recipient_input.text == name_b, "ChatPanelModal opens Private tab prefilled with friend name")
	chat.queue_free()

	# 6. Master A blocks Master B -> Master B cannot send private chat to Master A
	ApiClient.set_auth_token(token_a)
	GameState.master_id = master_a
	var blk_res: Dictionary = await modal.block_master(master_b)
	expect(blk_res.get("ok", false), "Master A blocks Master B")

	ApiClient.set_auth_token(token_b)
	var pm_res: Dictionary = await ApiClient.post_req("/api/chat/private", {"recipientMasterId": master_a, "body": "Blocked test"})
	expect(not pm_res.get("ok", false), "Blocked Master B cannot send private message to Master A")

	# 7. Unblock & cleanup
	ApiClient.set_auth_token(token_a)
	var unb_res: Dictionary = await modal.unblock_master(master_b)
	expect(unb_res.get("ok", false), "Master A unblocks Master B")

	modal.queue_free()
	await get_tree().process_frame
	print("FRIENDS_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)
