extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("HERO_DEV: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("HD_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("HD_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("HD_TEST_MASTER")
	await run_flow()
	print("HERO_DEV_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	var hero_id := OS.get_environment("HD_HERO_ID")
	var lock_res := await ApiClient.patch_req("/api/heroes/%s/lock" % hero_id, {"isLocked": true})
	expect(lock_res.get("ok", false), "PATCH /api/heroes/:id/lock succeeds")
	var unlock_res := await ApiClient.patch_req("/api/heroes/%s/lock" % hero_id, {"isLocked": false})
	expect(unlock_res.get("ok", false), "PATCH /api/heroes/:id/lock unlock succeeds")

	var lvl_res := await ApiClient.post_req("/api/heroes/%s/level-up" % hero_id, {"bookItemId": "SAMPLE_HERO_EXP_100", "quantity": 1})
	expect(lvl_res.get("ok", false), "POST /api/heroes/:id/level-up succeeds")

	var promo_prev := await ApiClient.get_req("/api/heroes/%s/promote/preview" % hero_id)
	expect(promo_prev.get("ok", false), "GET /api/heroes/:id/promote/preview succeeds")
	var star_prev := await ApiClient.get_req("/api/heroes/%s/promote-star/preview" % hero_id)
	expect(star_prev.get("ok", false), "GET /api/heroes/:id/promote-star/preview succeeds")
	var bt_prev := await ApiClient.get_req("/api/heroes/%s/breakthrough/preview" % hero_id)
	expect(bt_prev.get("ok", false), "GET /api/heroes/:id/breakthrough/preview succeeds")

	var imp_res := await ApiClient.get_req("/api/heroes/%s/imprints" % hero_id)
	expect(imp_res.get("ok", false), "GET /api/heroes/:id/imprints succeeds")
	var all_imp := await ApiClient.get_req("/api/imprints")
	expect(all_imp.get("ok", false), "GET /api/imprints succeeds")
