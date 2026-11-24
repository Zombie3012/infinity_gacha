extends Node
## Targeted headless verification for Expedition Fantasy Planet — Milestone 3 & 4:
## WorldMap3D scene, PlanetCameraController (2D Pan / Zoom / Seamless Morph / 360 Orbit),
## analytic screen picking & projection, back-hemisphere culling, and 4-tier PlanetLODController.

const WorldMap3DScene := preload("res://world_map/scenes/world_map_3d.tscn")
const PlanetPreviewScene := preload("res://world_map/scenes/planet_preview.tscn")

var _checks := 0
var _failures := 0

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		printerr("WATCHDOG_TIMEOUT: test_world_planet_milestone3")
		get_tree().quit(1)
	)
	_run_tests()

func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: %s" % msg)

func _run_tests() -> void:
	# 1. Verify starfield sky shader loads cleanly
	var sky_sh = load("res://world_map/shaders/starfield_sky.gdshader")
	_expect(sky_sh is Shader, "starfield_sky.gdshader must load")

	# 2. Instantiate WorldMap3D inside a SubViewport (mirrors production WorldRtsMap layout!)
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var world_3d := WorldMap3DScene.instantiate()
	sv.add_child(world_3d)
	await get_tree().process_frame
	await get_tree().process_frame

	_expect(world_3d.planet_renderer != null, "WorldMap3D must create PlanetRenderer")
	_expect(world_3d.camera != null, "WorldMap3D must create Camera3D")
	_expect(world_3d.camera_controller != null, "WorldMap3D must create PlanetCameraController")
	_expect(world_3d.lod_controller != null, "WorldMap3D must create PlanetLODController")

	var ctrl = world_3d.camera_controller
	var lod = world_3d.lod_controller
	var renderer = world_3d.planet_renderer

	# 3. Verify all 4 LOD tiers & seamless morph curve across zoom 1.0 -> 0.0
	ctrl.set_focus_immediate(19.0, -11.0, 0.85)
	_expect(is_equal_approx(ctrl.morph_factor, 0.0), "Zoom 0.85 must have morph=0.0")
	_expect(lod.current_tier == 0, "Zoom 0.85 must be LOD 0 (Tactical), got %d" % lod.current_tier)
	_expect(lod.tactical_overlay_alpha > 0.95, "Tactical overlay must be fully visible at LOD 0")
	_expect(not renderer.atmosphere_mesh_instance.visible, "Atmosphere hidden at LOD 0")

	ctrl.set_focus_immediate(19.0, -11.0, 0.48)
	_expect(lod.current_tier == 1, "Zoom 0.48 must be LOD 1 (Regional), got %d" % lod.current_tier)
	_expect(lod.region_label_alpha > 0.5, "Region labels must be visible at LOD 1")

	ctrl.set_focus_immediate(19.0, -11.0, 0.20)
	_expect(lod.current_tier == 2, "Zoom 0.20 must be LOD 2 (Continental), got %d" % lod.current_tier)
	_expect(ctrl.morph_factor > 0.0 and ctrl.morph_factor < 1.0, "Zoom 0.20 must be mid-morph, got %.3f" % ctrl.morph_factor)

	ctrl.set_focus_immediate(19.0, -11.0, 0.0)
	_expect(is_equal_approx(ctrl.morph_factor, 1.0), "Zoom 0.0 must have morph=1.0")
	_expect(lod.current_tier == 3, "Zoom 0.0 must be LOD 3 (Planetary), got %d" % lod.current_tier)
	_expect(renderer.atmosphere_mesh_instance.visible, "Atmosphere must be visible in 3D globe mode")
	_expect(lod.tactical_overlay_alpha < 0.01, "Tactical overlay must fade completely out in 3D globe mode")

	# 4. Verify screen projection & analytic picking round-trip in 2D Flat mode (morph = 0)
	ctrl.set_focus_immediate(19.0, -11.0, 0.78)
	await get_tree().process_frame
	var proj_2d: Dictionary = ctrl.project_lat_lon_to_screen(19.0, -11.0)
	_expect(bool(proj_2d.get("visible", false)), "Focus point must be visible in 2D mode")
	var screen_center := Vector2(640.0, 360.0)
	_expect((proj_2d["pos"] as Vector2).distance_to(screen_center) < 3.0,
		"Focus point must project to screen center in 2D, got %s" % [proj_2d["pos"]])
	var pick_2d: Dictionary = ctrl.pick_lat_lon_at_screen(proj_2d["pos"])
	_expect(bool(pick_2d.get("hit", false)), "2D screen pick must hit flat plane")
	_expect(absf(float(pick_2d["lat"]) - 19.0) < 0.25 and absf(float(pick_2d["lon"]) - (-11.0)) < 0.25,
		"2D pick round-trip mismatch: got (%.2f, %.2f)" % [pick_2d["lat"], pick_2d["lon"]])

	# 5. Verify screen projection, analytic picking & back-hemisphere culling in 3D Globe mode (morph = 1)
	ctrl.set_focus_immediate(19.0, -11.0, 0.0)
	await get_tree().process_frame
	var proj_3d: Dictionary = ctrl.project_lat_lon_to_screen(19.0, -11.0)
	_expect(bool(proj_3d.get("visible", false)), "Focus point must be visible on front of 3D globe")
	_expect((proj_3d["pos"] as Vector2).distance_to(screen_center) < 3.0,
		"Focus point must stay centered after 2D->3D morph (zero jump!), got %s" % [proj_3d["pos"]])
	var pick_3d: Dictionary = ctrl.pick_lat_lon_at_screen(proj_3d["pos"])
	_expect(bool(pick_3d.get("hit", false)), "3D screen pick must hit globe")
	_expect(absf(float(pick_3d["lat"]) - 19.0) < 0.35 and absf(float(pick_3d["lon"]) - (-11.0)) < 0.35,
		"3D pick round-trip mismatch: got (%.2f, %.2f)" % [pick_3d["lat"], pick_3d["lon"]])

	# Opposite side of planet must be culled by front-hemisphere check
	var proj_back: Dictionary = ctrl.project_lat_lon_to_screen(-19.0, 169.0)
	_expect(not bool(proj_back.get("visible", true)), "Antipode on far side of 3D globe must be hidden")

	# 6. Verify 360-degree orbit wrap across +/-180 deg meridian & smooth fly_to convergence
	ctrl.set_focus_immediate(0.0, 175.0, 0.0)
	ctrl.apply_screen_drag(Vector2(-200.0, 0.0), Vector2(1280.0, 720.0))
	for _i in range(40):
		ctrl.step_update(0.05)
	_expect(ctrl.focus_lon < 0.0 and ctrl.focus_lon > -180.0,
		"360 deg horizontal orbit must wrap cleanly across +180 -> negative lon, got %.2f" % ctrl.focus_lon)

	ctrl.fly_to_lat_lon(-14.0, 62.0, 0.65)
	for _i in range(60):
		ctrl.step_update(0.05)
	_expect(absf(ctrl.focus_lat - (-14.0)) < 0.4 and absf(ctrl.focus_lon - 62.0) < 0.4 and absf(ctrl.zoom_level - 0.65) < 0.02,
		"fly_to_lat_lon must converge smoothly onto Crystal Wastes, got (%.2f, %.2f, z=%.2f)" % [ctrl.focus_lat, ctrl.focus_lon, ctrl.zoom_level])

	# 7. Verify updated interactive PlanetPreview scene instantiates cleanly
	var preview := PlanetPreviewScene.instantiate()
	add_child(preview)
	await get_tree().process_frame
	_expect(preview.get_node_or_null("WorldMap3D") != null, "PlanetPreview must host WorldMap3D")
	preview.queue_free()
	sv.queue_free()

	print("PLANET_MILESTONE3_4: %d checks, %s" % [_checks, "PASS" if _failures == 0 else ("FAILED (%d)" % _failures)])
	get_tree().quit(0 if _failures == 0 else 1)
