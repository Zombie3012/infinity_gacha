extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("GACHA_FLOW: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("GACHA_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("GACHA_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("GACHA_TEST_MASTER")
	await run_flow()
	print("GACHA_FLOW_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	var b_res := await ApiClient.get_req("/api/gacha/banners")
	expect(b_res.get("ok", false) and b_res.get("data") is Array and not (b_res["data"] as Array).is_empty(), "Fetch active gacha banners")
	if not b_res.get("ok", false): return

	var banners: Array = b_res["data"]
	var normal_banner: Dictionary = {}
	var special_banner: Dictionary = {}
	for b in banners:
		if str(b.get("bannerType", "")).to_upper() == "NORMAL" and normal_banner.is_empty():
			normal_banner = b
		elif str(b.get("bannerType", "")).to_upper() == "SPECIAL" and special_banner.is_empty():
			special_banner = b

	expect(not normal_banner.is_empty() and not special_banner.is_empty(), "Both NORMAL and SPECIAL banners available")

	# 1. Exchange silver for 1 normal scroll
	var silver_before := GameState.silver_coins
	var ex_res := await ApiClient.post_req("/api/economy/exchange-scrolls", {"amount": 1})
	expect(ex_res.get("ok", false), "Exchange silver for 1 Normal Scroll succeeds")
	await GameState.refresh_profile()
	await GameState.refresh_inventory()
	expect(GameState.silver_coins == silver_before - 10000 and GameState.normal_scrolls >= 1, "Silver deducted and Normal Scroll granted")

	# 2. Summon NORMAL x1
	var s1 := await ApiClient.post_req("/api/gacha/summon", {"bannerId": normal_banner["id"], "rollCount": 1}, {"Idempotency-Key": "gacha-n-1"})
	expect(s1.get("ok", false), "NORMAL x1 summon succeeds")

	# 3. Summon SPECIAL x1 (100 Gems)
	var gem_before := GameState.gem_stones
	var s2 := await ApiClient.post_req("/api/gacha/summon", {"bannerId": special_banner["id"], "rollCount": 1}, {"Idempotency-Key": "gacha-s-1"})
	expect(s2.get("ok", false), "SPECIAL x1 summon succeeds")
	await GameState.refresh_profile()
	expect(GameState.gem_stones == gem_before - 100, "SPECIAL summon deducts 100 Gems")

	# 4. Insufficient gems refusal
	var s_fail := await ApiClient.post_req("/api/gacha/summon", {"bannerId": special_banner["id"], "rollCount": 10}, {"Idempotency-Key": "gacha-s-fail"})
	expect(not s_fail.get("ok", false), "SPECIAL x10 fails when Gems are insufficient")

	# 5. SummonBannerModal UI + History view
	var modal = load("res://scripts/ui/summon_banner_modal.gd").new()
	add_child(modal)
	modal.setup(banners)
	await get_tree().process_frame
	await modal._open_history_view()
	await get_tree().process_frame
	var hist_text := ""
	for lbl in modal.find_children("*", "Label", true, false):
		hist_text += lbl.text + "\n"
	expect(hist_text.contains("Anh Hùng") or hist_text.contains("Vật Phẩm"), "SummonBannerModal renders real gacha history from API")
	modal.queue_free()

	# 6. SummonResultModal (1★..5★ cap, UniversalHeroCard/UniversalItemCard, Skip & Summon Again)
	var res_modal: Control = load("res://scripts/ui/summon_result_modal.gd").new()
	res_modal.setup(10, [
		{"rewardType": "HERO", "rewardName": "Võ Sĩ Vàng", "rarity": 7, "isDuplicate": false},
		{"rewardType": "MATERIAL", "rewardName": "Gỗ Sồi", "rarity": 1, "quantity": 5},
	], 7, str(normal_banner["id"]), "NORMAL")
	add_child(res_modal)
	await get_tree().process_frame
	res_modal.skip_reveal()
	await get_tree().process_frame
	expect(res_modal._highest_rarity == 5 and res_modal._card_wrappers.size() == 2 and res_modal._revealed_all, "SummonResultModal caps max gacha rarity at 5★ and reveals all cards on Skip")
	var again_calls: Array = []
	res_modal.summon_again_requested.connect(func(rc: int, bid: String, btype: String): again_calls.append([rc, bid, btype]))
	res_modal._again_btn.pressed.emit()
	await get_tree().process_frame
	expect(again_calls.size() == 1 and again_calls[0][0] == 10, "SummonResultModal emits summon_again_requested")
