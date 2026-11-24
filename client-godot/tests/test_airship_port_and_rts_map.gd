extends Node
## Targeted headless verification for AirshipPortModal (Dock Grid + Tech Tree) and WorldRtsMap scene.

func _ready() -> void:
	# Mandatory 20s watchdog timer so headless Godot never hangs
	get_tree().create_timer(20.0).timeout.connect(func():
		printerr("WATCHDOG_TIMEOUT: test_airship_port_and_rts_map")
		get_tree().quit(1)
	)
	_run_tests()

func _run_tests() -> void:
	# 0. Verify magic_hall_modal.gd compiles cleanly with autoloads (Bến Thiên Hành Tech Tree in Research tab)
	var magic_script = load("res://scripts/ui/magic_hall_modal.gd")
	assert(magic_script != null, "magic_hall_modal.gd must load")

	# 1. Load and test AirshipPortModal with mock 5x5 dock + 4 ship classes
	var port_script = load("res://scripts/ui/airship_port_modal.gd")
	assert(port_script != null, "airship_port_modal.gd must load")
	var port_modal: Control = port_script.new()
	add_child(port_modal)
	port_modal.apply_state({
		"unlockedByFloor": true,
		"clearedFloor": 25,
		"requiredFloor": 25,
		"portBuilt": true,
		"portLevel": 2,
		"dock": {"width": 5, "height": 5},
		"silverCoins": 25000,
		"blueprints": [
			{"code": "SCOUT_SKIFF", "name": "Thuyền Trinh Sát", "sizeClass": "SMALL", "gridW": 2, "gridH": 2, "maxHeroes": 3, "baseSpeedMult": 1.8, "radarRadius": 2, "baseMaxHp": 100, "craftCostSilver": 1500, "craftSeconds": 30, "unlocked": true, "roleSummary": "Scout"},
			{"code": "TRANSPORT_CARRIER", "name": "Tàu Vận Tải", "sizeClass": "LARGE", "gridW": 4, "gridH": 5, "maxHeroes": 15, "baseSpeedMult": 1.05, "radarRadius": 1, "baseMaxHp": 320, "craftCostSilver": 8000, "craftSeconds": 120, "unlocked": true, "roleSummary": "15 Heroes"},
		],
		"techTree": [
			{"code": "TECH_SHIP_SCOUT", "branch": "SHIPYARD", "name": "Scout", "description": "Unlock Scout", "costSilver": 500, "requiredPortLevel": 1, "unlocked": true, "canUnlock": false},
		],
		"airships": [
			{"id": "s1", "name": "Scout #1", "blueprintCode": "SCOUT_SKIFF", "sizeClass": "SMALL", "gridW": 2, "gridH": 2, "footprintW": 2, "footprintH": 2, "dockX": 0, "dockY": 0, "rotation": 0, "level": 1, "hp": 100, "maxHp": 100, "status": "DOCKED", "maxHeroes": 3, "speedMult": 1.8, "radarRadius": 2, "powerBonusPct": 0},
		],
	})
	port_modal.queue_free()

	# 2. Load and test WorldRtsMap scene with Fog of War + Emerging Dungeon + Active Fleet + Stranded SOS
	var rts_scene: PackedScene = load("res://scenes/world/world_rts_map.tscn")
	assert(rts_scene != null, "world_rts_map.tscn must load")
	var rts_map: Control = rts_scene.instantiate()
	add_child(rts_map)
	rts_map.apply_snapshot({
		"unlocked": true,
		"clearedFloor": 25,
		"requiredFloor": 25,
		"base": {"x": 100, "y": 100},
		"portState": {
			"portLevel": 2,
			"visionDurationSeconds": 3600,
			"airships": [
				{"id": "s1", "name": "Scout #1", "blueprintCode": "SCOUT_SKIFF", "status": "DOCKED", "maxHeroes": 3, "speedMult": 1.8, "hp": 100, "maxHp": 100},
				{"id": "s2", "name": "Transport #1", "blueprintCode": "TRANSPORT_CARRIER", "status": "DOCKED", "maxHeroes": 15, "speedMult": 1.05, "hp": 320, "maxHp": 320},
			],
		},
		"tiles": [
			{"id": "tile-0-0", "x": 100, "y": 100, "terrain": "PLAINS", "isBase": true, "visible": true, "homeLit": true, "visionSecondsRemaining": -1, "dungeon": null},
			{"id": "tile-1-0", "x": 101, "y": 100, "terrain": "RUINS", "isBase": false, "visible": true, "homeLit": false, "visionSecondsRemaining": 3500, "dungeon": {"id": "d1", "name": "Cổng Hư Không (Raid)", "rank": "A", "recommendedPower": 9000, "maxPartySize": 15, "bossName": "Chúa Tể Hư Không"}},
			{"id": "tile-5-5", "x": 105, "y": 105, "terrain": "FOREST", "isBase": false, "visible": false, "homeLit": false, "visionSecondsRemaining": 0, "dungeon": null},
		],
		"activeFleets": [
			{"id": "f1", "mission": "SCOUT", "status": "TRAVELING", "secondsRemaining": 45, "progressRatio": 0.4, "fromX": 100, "fromY": 100, "toX": 105, "toY": 105, "tileId": "tile-5-5", "airship": {"name": "Scout #1"}},
			{"id": "f2", "mission": "DUNGEON", "status": "STRANDED", "secondsRemaining": 0, "progressRatio": 1.0, "fromX": 100, "fromY": 100, "toX": 101, "toY": 100, "tileId": "tile-1-0", "airship": {"name": "Attack #1"}},
		],
	}, [
		{"id": "h1", "name": "Hero1", "state": "ALIVE", "hp": 100},
		{"id": "h2", "name": "Hero2", "state": "ALIVE", "hp": 100},
		{"id": "h_dead", "name": "OrinDead", "state": "DEAD", "hp": 0},
		{"id": "h_dis", "name": "DisabledHero", "state": "DISABLED", "hp": 0},
		{"id": "h_zero", "name": "ZeroHpHero", "state": "ALIVE", "hp": 0},
	])

	await get_tree().process_frame
	# 3. Verify dedicated 2-Column WorldDispatchModal (no KNIGHT class + GARRISON support + excludes ALL dead/disabled/0-HP heroes)
	var tile_dungeon := {"id": "tile-1-0", "x": 101, "y": 100, "terrain": "RUINS", "visible": true, "dungeon": {"id": "d1", "name": "Cổng Hư Không (Raid)", "rank": "A", "recommendedPower": 9000, "maxPartySize": 15, "bossName": "Chúa Tể Hư Không"}}
	var dispatch_modal = rts_map.open_dispatch_modal(tile_dungeon, "GARRISON", "")
	assert(dispatch_modal != null, "WorldDispatchModal must instantiate for GARRISON")
	assert(not dispatch_modal.CLASS_NAMES.has("KNIGHT"), "KNIGHT must be removed from class filter")
	assert(dispatch_modal._filtered_sorted_heroes().size() == 2, "WorldDispatchModal must completely exclude DEAD, DISABLED, and 0-HP heroes")
	dispatch_modal.toggle_hero("h1")
	dispatch_modal.toggle_hero("h2")
	assert(dispatch_modal._selected_hero_ids.size() == 2, "Must support toggling individual heroes in WorldDispatchModal")
	dispatch_modal.toggle_hero("h1")
	assert(dispatch_modal._selected_hero_ids.size() == 1, "Must support deselecting individual heroes")
	# 4. Verify Floating Tile Overlay + Collapsed Fleet Panel + Screen-Center Coord + WorldReportsModal
	assert(not rts_map._fleet_expanded, "Fleet panel must be collapsed by default")
	var center_coord: Vector2i = rts_map._get_screen_center_coord()
	assert(center_coord.x >= 90 and center_coord.x <= 120, "Screen-center coordinate must resolve cleanly")
	rts_map._selected_tile_id = "tile-5-5"
	rts_map._rebuild_tile_popover()
	assert(rts_map._tile_popover.visible, "Floating overlay must appear on clicked fogged tile")
	rts_map._selected_tile_id = "tile-1-0"
	rts_map._rebuild_tile_popover()
	assert(rts_map._tile_popover.visible, "Floating overlay must appear on clicked visible tile")

	var reports_modal = rts_map.open_reports_modal()
	assert(reports_modal != null, "WorldReportsModal must instantiate")
	reports_modal.apply_reports([
		{"id": "r1", "mission": "SCOUT", "status": "COMPLETED", "tile": {"x": 103, "y": 102, "terrain": "RUINS"}, "heroes": [{"name": "Hero1"}], "result": {"kind": "SCOUT_REPORT", "visionDurationSeconds": 3600, "dungeonFound": null}},
		{"id": "r2", "mission": "DUNGEON", "status": "COMPLETED", "tile": {"x": 101, "y": 100, "terrain": "FOREST"}, "heroes": [{"name": "Hero1"}], "result": {"kind": "DUNGEON_REPORT", "won": true, "rank": "A", "dungeonName": "Cổng Hư Không", "bossName": "Boss", "partyPower": 10000, "recommendedPower": 9000, "silverReward": 9500}},
	])
	print("GODOT_AIRSHIP_RTS_UI_PASS")
	get_tree().quit(0)
