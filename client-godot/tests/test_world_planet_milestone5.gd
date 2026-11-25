extends Node
## Targeted headless verification for Expedition Fantasy Planet — Milestone 5:
## PlanetMarkerSystem (Player Position Dot + Wonder + Fleet Beacons), HorizontalMinimap (2:1),
## WorldMapManager facade, and full WorldRtsMap integration (2D tactical <-> 3D Planet Globe).

const WorldRtsMapScene := preload("res://scenes/world/world_rts_map.tscn")

var _checks := 0
var _failures := 0

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func():
		printerr("WATCHDOG_TIMEOUT: test_world_planet_milestone5")
		get_tree().quit(1)
	)
	_run_tests()

func _expect(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL: %s" % msg)

func _run_tests() -> void:
	var rts_map: Control = WorldRtsMapScene.instantiate()
	add_child(rts_map)
	await get_tree().process_frame

	_expect(rts_map.world_map_manager != null, "WorldRtsMap must create WorldMapManager")
	_expect(rts_map._minimap != null, "WorldRtsMap must create HorizontalMinimap")
	_expect(rts_map._minimap.custom_minimum_size.x > rts_map._minimap.custom_minimum_size.y * 1.8,
		"Minimap must be horizontal 2:1 aspect ratio, got %s" % [rts_map._minimap.custom_minimum_size])

	# A locked world's API response explicitly returns null coordinates.
	var locked_snapshot := {
		"unlocked": false, "clearedFloor": 1, "requiredFloor": 25,
		"worldGrid": {"width": 600, "height": 300},
		"base": null, "chunkCenter": null,
		"portState": {"portLevel": 0, "airships": []},
		"tiles": [], "activeFleets": [], "nearbyPlayers": [],
	}
	rts_map.apply_snapshot(locked_snapshot)
	await get_tree().process_frame
	_expect(rts_map._snapshot.get("base") is Dictionary,
		"Locked snapshot must safely reach renderers with dictionary coordinates")
	_expect(rts_map._snapshot.get("chunkCenter") is Dictionary,
		"Explicit null chunkCenter must use the base fallback")
	_expect(locked_snapshot["base"] == null and locked_snapshot["chunkCenter"] == null,
		"Applying a snapshot must not rewrite the caller's null coordinates")
	_expect(not rts_map._centered_once, "Locked world must leave initial camera centering pending")
	rts_map._center_on_base()
	rts_map.apply_snapshot({})
	_expect(rts_map._last_chunk_center == Vector2i(100, 100),
		"Legacy snapshots without coordinates must retain the default center")
	rts_map.apply_snapshot({"base": {"x": 412, "y": 186}, "chunkCenter": null})
	_expect(rts_map._last_chunk_center == Vector2i(412, 186),
		"A null chunkCenter must fall back to the actual base coordinates")

	# Apply realistic Expedition RTS snapshot after the locked response.
	rts_map.apply_snapshot({
		"unlocked": true,
		"clearedFloor": 25,
		"requiredFloor": 25,
		"base": {"x": 104, "y": 105},
		"portState": {"portLevel": 2, "airships": []},
		"tiles": [
			{"id": "tile-4-5", "x": 104, "y": 105, "terrain": "PLAINS", "isBase": true, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
			{"id": "tile-5-5", "x": 105, "y": 105, "terrain": "RUINS", "isBase": false, "visible": true, "homeLit": false, "visionSecondsRemaining": 3400, "dungeon": {"id": "d1", "name": "Cổng Hư Không", "rank": "A", "recommendedPower": 9000, "maxPartySize": 15}},
			{"id": "tile-7-6", "x": 107, "y": 106, "terrain": "FOREST", "isBase": false, "visible": false, "homeLit": false, "visionSecondsRemaining": 0, "dungeon": null},
		],
		"activeFleets": [
			{"id": "f1", "mission": "SCOUT", "status": "TRAVELING", "secondsRemaining": 35, "progressRatio": 0.5, "fromX": 104, "fromY": 105, "toX": 107, "toY": 106, "tileId": "tile-7-6", "airship": {"name": "Scout #1", "blueprintCode": "SCOUT_SKIFF"}},
			{"id": "f2", "mission": "DUNGEON", "status": "STRANDED", "secondsRemaining": 0, "progressRatio": 1.0, "fromX": 104, "fromY": 105, "toX": 105, "toY": 105, "tileId": "tile-5-5", "airship": {"name": "Attack #1", "blueprintCode": "WAR_DREADNOUGHT"}},
		],
	}, [
		{"id": "h1", "name": "Hero1", "state": "ALIVE", "hp": 100},
	])
	await get_tree().process_frame

	var mgr = rts_map.world_map_manager
	var marker_sys = mgr.marker_system
	_expect(marker_sys != null and marker_sys.player_marker != null, "PlanetMarkerSystem & PlayerMarker must exist")

	# 1. Verify screen-center starts on Base (104, 105) in 2D Tactical mode + Solar-Scale & 1-Draw-Call Budget!
	var c_grid: Vector2i = rts_map._get_screen_center_coord()
	_expect(abs(c_grid.x - 104) <= 1 and abs(c_grid.y - 105) <= 1,
		"Initial camera center must focus on Base (104,105), got %s" % [c_grid])
	_expect(not mgr.is_planet_3d_mode(), "Must start in 2D Tactical mode")
	_expect(rts_map._mode_toggle_btn.text == "🌐", "Toggle button must show icon-only '🌐' in 2D mode")

	var sb: Dictionary = mgr.get_sector_bounds()
	var sector_lat_span := absf(float(sb.get("lat_max", 0.0)) - float(sb.get("lat_min", 0.0)))
	_expect(sector_lat_span < 1.0, "Solar-Scale 12x12 sector must be < 1.0 deg wide, got %.3f" % sector_lat_span)

	var lod0: Dictionary = mgr.get_lod_snapshot()
	_expect(float(lod0.get("region_label_alpha", 1.0)) <= 0.01, "Region labels must stay hidden at Tactical LOD 0")
	_expect(int(mgr.get_active_draw_calls()) == 1, "Level 1 Tactical view must cull global shells to 1 Draw Call (LocalTerrainPatch), got %d" % int(mgr.get_active_draw_calls()))

	# Verify Dual-Resolution PlanetFogManager (Base revealed, far continent fogged!)
	var base_ll: Vector2 = mgr.get_player_base_lat_lon()
	var base_rev: float = float(mgr.fog_manager.call("sample_reveal_at_lat_lon", base_ll.x, base_ll.y))
	var far_rev: float = float(mgr.fog_manager.call("sample_reveal_at_lat_lon", -28.0, -80.0))
	_expect(base_rev > 0.85, "Player base must be clearly revealed in local fog mask, got %.2f" % base_rev)
	_expect(far_rev < 0.10, "Distant unexplored Ashen Rift must stay fogged, got %.2f" % far_rev)

	# Verify 3D Tactical Ground Props & Terrain Splatting active at Tactical Chiến Khu (and culled in 3D Globe!)
	_expect(mgr.terrain_splat != null and mgr.terrain_splat.get("splat_tex") is Texture2D, "TacticalTerrainSplat must produce Texture2D")
	_expect(mgr.tactical_props != null and mgr.tactical_props.visible, "TacticalGroundProps3D must be visible at zoom=0.85")
	_expect(int(mgr.tactical_props.call("get_prop_count")) >= 2, "TacticalGroundProps3D must populate Base Citadel & Dungeon Portal")
	# Verify analytic screen picking accuracy under 22-deg strategic camera tilt
	var proj_base: Dictionary = mgr.call("project_grid_to_screen", 104.0, 105.0)
	var pick_base: Dictionary = mgr.call("pick_at_screen", proj_base["pos"])
	_expect(bool(pick_base.get("hit", false)), "Tilted 22-deg tactical pick must hit ground plane")
	var pg: Vector2 = pick_base.get("grid", Vector2.ZERO)
	_expect(absf(pg.x - 104.0) < 0.25 and absf(pg.y - 105.0) < 0.25,
		"Tilted 22-deg pick round-trip must return (104,105), got %s" % [pg])

	# Verify Vertical Zoom Rail & Region Inspector Card
	_expect(rts_map._zoom_slider != null and rts_map._altitude_lbl != null, "Vertical Altitude Zoom Rail must exist")
	rts_map.open_region_inspector({"name": "Sa Mạc Pha Lê", "continent_id": "crystal_wastes", "biome": "crystal_desert", "elevation": 1200, "explored": false}, -14.0, 62.0)
	_expect(rts_map._region_card.visible, "RegionInspectorCard must open cleanly")
	rts_map._region_card.visible = false

	# 2. Toggle into 3D Planet Globe mode and settle transition
	rts_map.toggle_planet_3d_view()
	for _i in range(70):
		mgr.camera_controller.step_update(0.05)
		mgr._process(0.05)
	await get_tree().process_frame

	_expect(mgr.is_planet_3d_mode(), "Toggle must transition into 3D Planet mode")
	_expect(mgr.get_morph_factor() > 0.95, "Morph factor must converge to ~1.0, got %.3f" % mgr.get_morph_factor())
	_expect(int(mgr.get_active_draw_calls()) <= 3, "3D Globe render budget must stay <= 3 Draw Calls, got %d" % int(mgr.get_active_draw_calls()))
	_expect(not mgr.tactical_props.visible, "TacticalGroundProps3D must cull to invisible (0 GPU cost) in 3D Globe mode")
	_expect(float(mgr.get_virtual_altitude_km()) > 500000.0, "3D Solar-Scale orbit altitude must read > 500,000 km, got %.0f" % float(mgr.get_virtual_altitude_km()))
	_expect(marker_sys.player_marker.visible, "Glowing 3D PlayerMarker dot must be visible in 3D Planet mode")

	# Verify PlayerMarker sits right on top of the 3D sphere surface (radius 10.0 + height offset)
	var pm_dist: float = marker_sys.player_marker.position.length()
	_expect(pm_dist > 10.05 and pm_dist < 10.45,
		"PlayerMarker must rest accurately on sphere surface (~10.18), got %.3f" % pm_dist)

	# Verify pooled active fleet beacons are visible on the 3D planet
	var visible_fleets := 0
	for fn in marker_sys._fleet_nodes:
		if fn.visible:
			visible_fleets += 1
	_expect(visible_fleets == 2, "Expected 2 active fleet beacons on 3D planet, got %d" % visible_fleets)
	_expect(rts_map._mode_toggle_btn.text == "🗺️", "Toggle button must flip to icon-only '🗺️' in 3D mode")

	# 3. Verify clicking HorizontalMinimap navigates smoothly to another continent (Crystal Wastes)
	rts_map._on_minimap_navigate(-14.0, 62.0)
	for _i in range(60):
		mgr.camera_controller.step_update(0.05)
	var focus_ll: Vector2 = mgr.get_focus_lat_lon()
	_expect(absf(focus_ll.x - (-14.0)) < 0.6 and absf(focus_ll.y - 62.0) < 0.6,
		"HorizontalMinimap navigation must fly camera to Crystal Wastes, got %s" % [focus_ll])

	# 4. Verify Center-on-Base flies smoothly back to Base (104, 105) in 2D Tactical mode
	rts_map._center_on_base()
	for _i in range(70):
		mgr.camera_controller.step_update(0.05)
		mgr._process(0.05)
	await get_tree().process_frame
	_expect(not mgr.is_planet_3d_mode(), "Center-on-Base must un-morph back into 2D Tactical mode")
	var back_grid: Vector2i = rts_map._get_screen_center_coord()
	_expect(abs(back_grid.x - 104) <= 1 and abs(back_grid.y - 105) <= 1,
		"Center-on-Base must return to Base (104,105), got %s" % [back_grid])

	# 5. Full-Planet 600x300 Seeded Grid Mode (RTS Random Spawn on Crystal Wastes + OCEAN + Nearby Rival Castle!)
	rts_map._centered_once = false
	rts_map.apply_snapshot({
		"unlocked": true,
		"clearedFloor": 25,
		"requiredFloor": 25,
		"worldGrid": {"width": 600, "height": 300},
		"chunkCenter": {"x": 420, "y": 185, "radius": 12},
		"base": {"x": 420, "y": 185, "continentId": "crystal_wastes"},
		"nearbyPlayers": [
			{"masterId": "rival-1", "masterName": "RivalLord", "x": 422, "y": 185, "continentId": "crystal_wastes", "shieldActive": true, "visible": true},
		],
		"portState": {"portLevel": 2, "airships": []},
		"tiles": [
			{"id": "pt-420-185", "x": 420, "y": 185, "terrain": "PLAINS", "continentId": "crystal_wastes", "isBase": true, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
			{"id": "pt-421-185", "x": 421, "y": 185, "terrain": "OCEAN", "continentId": "great_ocean", "isBase": false, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
			{"id": "pt-422-185", "x": 422, "y": 185, "terrain": "HILLS", "continentId": "crystal_wastes", "isBase": false, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
			{"id": "pt-420-186", "x": 420, "y": 186, "terrain": "FOREST", "continentId": "crystal_wastes", "isBase": false, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
		],
		"activeFleets": [],
	})
	await get_tree().process_frame

	_expect(bool(mgr.call("is_full_planet_grid")), "600x300 worldGrid must activate full-planet grid mode")
	var cw_ll: Vector2 = mgr.call("grid_to_lat_lon", 420.0, 185.0)
	_expect(cw_ll.x < -15.0 and cw_ll.y > 60.0,
		"Full-planet grid (420,185) must map to Crystal Wastes southern-east hemisphere, got %s" % [cw_ll])
	var cw_rt: Vector2 = mgr.call("lat_lon_to_grid", cw_ll.x, cw_ll.y)
	_expect(absf(cw_rt.x - 420.0) < 0.05 and absf(cw_rt.y - 185.0) < 0.05,
		"Full-planet lat_lon_to_grid must round-trip (420,185), got %s" % [cw_rt])
	var cw_center: Vector2i = rts_map._get_screen_center_coord()
	_expect(abs(cw_center.x - 420) <= 1 and abs(cw_center.y - 185) <= 1,
		"Camera must center on Crystal Wastes Base (420,185), got %s" % [cw_center])
	_expect(mgr.tactical_props._other_citadels_root.get_child_count() == 1,
		"TacticalGroundProps3D must render 1 rival 3D Citadel for visible nearbyPlayer")
	var cw_rev: float = float(mgr.fog_manager.call("sample_reveal_at_lat_lon", cw_ll.x, cw_ll.y))
	var north_rev: float = float(mgr.fog_manager.call("sample_reveal_at_lat_lon", 62.0, -90.0))
	_expect(cw_rev > 0.85, "Crystal Wastes base must be revealed in dynamic local fog mask, got %.2f" % cw_rev)
	_expect(north_rev < 0.10, "Distant Frostspire Crown must stay fogged, got %.2f" % north_rev)

	# 6. Verify Zero Dead-Zone Fleet Continuity + 60 FPS Live Interpolation + Dirty-Hash Caching!
	var scout_snap := {
		"unlocked": true,
		"clearedFloor": 25,
		"requiredFloor": 25,
		"worldGrid": {"width": 600, "height": 300},
		"chunkCenter": {"x": 420, "y": 185, "radius": 12},
		"base": {"x": 420, "y": 185, "continentId": "crystal_wastes"},
		"nearbyPlayers": [],
		"portState": {"portLevel": 2, "airships": []},
		"tiles": [
			{"id": "pt-420-185", "x": 420, "y": 185, "terrain": "PLAINS", "isBase": true, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
		],
		"activeFleets": [
			{"id": "f_live", "mission": "SCOUT", "status": "TRAVELING", "secondsRemaining": 40, "totalDurationSeconds": 80, "progressRatio": 0.5, "fromX": 420, "fromY": 185, "toX": 426, "toY": 185, "tileId": "pt-426-185", "airship": {"name": "Scout #1", "blueprintCode": "SCOUT_SKIFF"}},
		],
	}
	rts_map.apply_snapshot(scout_snap)
	var splat_c1: int = int(mgr.get("splat_rebuild_count"))
	var props_c1: int = int(mgr.get("props_rebuild_count"))
	# Re-applying identical snapshot (simulating 3s poll) MUST skip redundant 128x128 splat & 3D props rebuilds!
	rts_map.apply_snapshot(scout_snap)
	_expect(int(mgr.get("splat_rebuild_count")) == splat_c1, "Identical snapshot poll must skip redundant TerrainSplat rebuild")
	_expect(int(mgr.get("props_rebuild_count")) == props_c1, "Identical snapshot poll must skip redundant TacticalGroundProps3D rebuild")

	# Verify 60 FPS client-side live fleet interpolation
	var r0: float = mgr.compute_live_fleet_ratio(scout_snap["activeFleets"][0], 0.0)
	var r1: float = mgr.compute_live_fleet_ratio(scout_snap["activeFleets"][0], 20.0)
	_expect(absf(r0 - 0.5) < 0.001 and absf(r1 - 0.75) < 0.001,
		"Live fleet ratio must interpolate smoothly (0.5 -> 0.75 after 20s/80s), got %.3f -> %.3f" % [r0, r1])

	# Verify Minimap coordinate input jump (X, Y) + clicking fleet box jumps to live mid-flight position!
	rts_map._coord_x_edit.text = "430"
	rts_map._coord_y_edit.text = "190"
	rts_map._navigate_to_input_coords()
	for _i in range(45):
		mgr.camera_controller.step_update(0.05)
	var jumped_c: Vector2i = rts_map._get_screen_center_coord()
	_expect(abs(jumped_c.x - 430) <= 1 and abs(jumped_c.y - 190) <= 1,
		"Minimap coordinate input (430,190) must fly camera to (430,190), got %s" % [jumped_c])

	rts_map._elapsed_since_sync = 20.0 # live ratio = 0.75 -> (424.5, 185.0)
	rts_map._focus_fleet_live("f_live")
	for _i in range(45):
		mgr.camera_controller.step_update(0.05)
	var live_ship_c: Vector2i = rts_map._get_screen_center_coord()
	_expect(abs(live_ship_c.x - 425) <= 1 and abs(live_ship_c.y - 185) <= 1,
		"Clicking fleet box must fly camera to ship's live position (~424.5,185), got %s" % [live_ship_c])

	# Sweep entire zoom range [0.00 .. 1.00] in 0.02 increments -> ZERO dead-zone where Scout disappears!
	var dead_zone_hits := 0
	for zi in range(51):
		var z_test := float(zi) * 0.02
		mgr.camera_controller.set_focus_immediate(cw_ll.x, cw_ll.y, z_test)
		mgr._sync_3d_overlays()
		var lod_z: Dictionary = mgr.get_lod_snapshot()
		var f_alpha := float(lod_z.get("fleet_overlay_alpha", 0.0))
		var b_vis: bool = marker_sys._fleet_nodes.size() > 0 and bool(marker_sys._fleet_nodes[0].visible)
		if f_alpha < 0.12 and not b_vis:
			dead_zone_hits += 1
	_expect(dead_zone_hits == 0, "Scout ship must stay visible across ALL zoom levels [0..1] with ZERO dead-zone, got %d gaps" % dead_zone_hits)

	# 7. Verify Automatic PC vs Mobile Device Detection + Mobile Hybrid Guardrails + Avatar Master Settings Tab!
	var DeviceProfileScript = load("res://scripts/core/device_profile.gd")
	var mob_low: Dictionary = DeviceProfileScript.classify_hardware("Android", true, "Mali-G57 MC2", 4)
	_expect(mob_low["platform"] == "MOBILE" and mob_low["recommended_preset"] == "LOW" and not bool(mob_low["can_unlock_planet_wide"]),
		"Low-end Android must auto-detect MOBILE/LOW Hybrid without Planet-Wide unlock, got %s" % [mob_low])

	var mob_flagship: Dictionary = DeviceProfileScript.classify_hardware("iOS", true, "Apple A17 Pro GPU", 6)
	_expect(mob_flagship["platform"] == "MOBILE" and mob_flagship["recommended_preset"] == "MEDIUM",
		"Flagship iOS must auto-detect MOBILE/MEDIUM Hybrid, got %s" % [mob_flagship])
	var mob_clamped: Dictionary = DeviceProfileScript.sanitize_settings({
		"quality": "PLANET_WIDE", "streaming_mode": "PLANET_WIDE", "world_render_radius": 32, "msaa_3d": int(Viewport.MSAA_4X), "max_fps": 240,
	}, true)
	_expect(mob_clamped["streaming_mode"] == "HYBRID" and int(mob_clamped["world_render_radius"]) <= 12 and int(mob_clamped["msaa_3d"]) <= int(Viewport.MSAA_2X) and int(mob_clamped["max_fps"]) <= 60,
		"Mobile guardrails must clamp PLANET_WIDE back to HYBRID R<=12 MSAA<=2x FPS<=60, got %s" % [mob_clamped])

	var pc_rtx: Dictionary = DeviceProfileScript.classify_hardware("Windows", false, "NVIDIA GeForce RTX 4070", 16)
	_expect(pc_rtx["platform"] == "PC" and pc_rtx["recommended_preset"] == "ULTRA" and bool(pc_rtx["can_unlock_planet_wide"]),
		"RTX PC must auto-detect PC/ULTRA with full unlock, got %s" % [pc_rtx])
	var pc_pw: Dictionary = DeviceProfileScript.get_preset_settings("PLANET_WIDE", false)
	_expect(pc_pw["streaming_mode"] == "PLANET_WIDE" and int(pc_pw["world_render_radius"]) == 32 and float(pc_pw["props_density"]) >= 1.49,
		"PC PLANET_WIDE preset must unlock R=32 and 150%% props density, got %s" % [pc_pw])

	# Verify Avatar Master -> PlayerProfileModal Tab 1 (Settings) renders cleanly and updates live WorldRtsMap!
	var prev_q := GameState.graphics_quality
	var prof_script = load("res://scripts/ui/player_profile_modal.gd")
	var prof_modal: Control = prof_script.new()
	add_child(prof_modal)
	prof_modal.setup(1)
	await get_tree().process_frame
	GameState.set_graphics_quality("PLANET_WIDE")
	await get_tree().process_frame
	_expect(int(mgr.tactical_props.get("render_distance_tiles")) == 32,
		"Setting PLANET_WIDE on PC must update TacticalGroundProps3D render_distance_tiles to 32, got %d" % int(mgr.tactical_props.get("render_distance_tiles")))
	GameState.set_graphics_quality(prev_q)
	prof_modal.queue_free()

	rts_map.queue_free()
	print("PLANET_MILESTONE5: %d checks, %s" % [_checks, "PASS" if _failures == 0 else ("FAILED (%d)" % _failures)])
	get_tree().quit(0 if _failures == 0 else 1)
