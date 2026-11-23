extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("AUTH_ACCOUNT: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("AA_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("AA_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("AA_TEST_MASTER")
	await run_flow()
	print("AUTH_ACCOUNT_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var sec := await ApiClient.get_req("/api/auth/security")
	expect(sec.get("ok", false), "GET /api/auth/security succeeds")
	var ids := await ApiClient.get_req("/api/account/identities")
	expect(ids.get("ok", false), "GET /api/account/identities succeeds")
	var rec := await ApiClient.post_req("/api/account/recovery-token", {})
	expect(rec.get("ok", false), "POST /api/account/recovery-token succeeds")

	var profile = load("res://scripts/ui/player_profile_modal.gd").new()
	add_child(profile)
	profile.setup(4)
	await get_tree().process_frame
	expect(profile._tab_buttons.size() == 5 and profile._active_tab == 4, "PlayerProfileModal includes tab 4 (Bảo Mật & Tài Khoản)")
	profile.queue_free()
