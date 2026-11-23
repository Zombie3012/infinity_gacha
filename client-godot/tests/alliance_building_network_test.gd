extends Node

var checks := 0
var failed := false

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("ALLIANCE_BLDG: " + message)

func _ready() -> void:
	ApiClient.base_url = OS.get_environment("AL_TEST_URL")
	ApiClient.set_auth_token(OS.get_environment("AL_TEST_TOKEN"))
	GameState.master_id = OS.get_environment("AL_TEST_MASTER")
	await run_flow()
	print("ALLIANCE_BUILDING_NETWORK: %d checks, %s" % [checks, "FAILED" if failed else "PASS"])
	get_tree().quit(1 if failed else 0)

func run_flow() -> void:
	# 1. Verify BasePlot3D renders ALLIANCE_HALL with Vietnamese nameplate
	var plot: Node3D = load("res://scenes/base/base_plot_3d.tscn").instantiate()
	add_child(plot)
	plot.setup_plot(1, true, {"buildingType": "ALLIANCE_HALL", "typeName": "Đại Sảnh Liên Minh", "level": 1, "status": "READY"})
	await get_tree().process_frame
	expect(plot.title_label.text == "Liên minh", "BasePlot3D shows 'Liên minh' nameplate for ALLIANCE_HALL")
	plot.queue_free()

	# 2. AllianceModal CRUD flow
	var modal = load("res://scripts/ui/alliance_modal.gd").new()
	add_child(modal)
	await modal.refresh_all()
	var c_res: Dictionary = await modal.create_alliance("Thiên Long Hội", "TLH")
	if not c_res.get("ok", false):
		push_error("CREATE ALLIANCE ERR: " + str(c_res))
	expect(c_res.get("ok", false), "Create alliance succeeds")
	expect(modal._alliance_data.get("alliance") is Dictionary, "AllianceModal refreshes created alliance")
	var n_res: Dictionary = await modal.update_notice("Chào mừng thành viên mới!")
	expect(n_res.get("ok", false), "Update alliance notice succeeds")
	var d_res: Dictionary = await modal.disband_alliance()
	expect(d_res.get("ok", false), "Disband alliance succeeds")
	modal.queue_free()
