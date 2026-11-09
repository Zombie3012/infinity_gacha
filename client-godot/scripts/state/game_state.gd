extends Node
class_name GameStateSingleton

## Central Game State manager for the Master player
## Synchronizes player data, currencies, base buildings, materials, and hero rosters from the Backend

const DEFAULT_DEMO_USERNAME := "demo"
const DEFAULT_DEMO_PASSWORD := "demo12345"
const DEFAULT_DEMO_MASTER_NAME := "Demo Master"

var account_id: String = ""
var master_id: String = ""
var master_name: String = "Demo Master"
var master_level: int = 30
var master_exp: int = 0
var silver_coins: int = 5000000
var gem_stones: int = 50000

var world_level: int = 1
var current_floor: int = 12
var base_zones: int = 3
var unlocked_lobby_floors: int = 3
const PLOTS_PER_ZONE: int = 8
const MAX_BASE_ZONES: int = 6
var unlocked_plots: int = 24

var heroes: Array = []
var active_party_ids: Array = []
var base_overview: Dictionary = {}
var crafting_overview: Dictionary = {}
var equipment_list: Array = []
var materials: Dictionary = {
	"WOOD": 0,
	"STONE": 0,
	"RATION": 0,
	"RAW_FOOD": 0,
	"ENHANCEMENT_STONE": 0,
	"SAMPLE_HERO_EXP_100": 0
}
var normal_scrolls: int = 0
var floor_assigned_hero_ids: Dictionary = {} # floor_num (int) -> Array[String hero_id]

var world_base_pos: Vector2i = Vector2i(0, 0)
var world_unlocked: bool = false
var selected_avatar_hero_id: String = ""

func get_party_combat_power() -> int:
	var total_cp: int = 0
	if active_party_ids.size() > 0:
		for h in heroes:
			if h is Dictionary and active_party_ids.has(str(h.get("id", ""))):
				total_cp += calculate_hero_cp(h)
	else:
		var cps: Array = []
		for h in heroes:
			if h is Dictionary:
				cps.append(calculate_hero_cp(h))
		cps.sort()
		cps.reverse()
		for i in range(mini(5, cps.size())):
			total_cp += int(cps[i])
	return total_cp

static func calculate_hero_cp(hero: Dictionary) -> int:
	var cp_val := int(hero.get("combatPower", 0))
	if cp_val > 0:
		return cp_val
	var mhp := int(hero.get("maxHp", hero.get("hp", 100)))
	var atk := int(hero.get("atk", hero.get("attack", 25)))
	var def_v := int(hero.get("def", hero.get("defense", 15)))
	var spd := int(hero.get("spd", hero.get("speed", 10)))
	var str_v := int(hero.get("str", 10))
	var agi_v := int(hero.get("agi", 10))
	var int_v := int(hero.get("int", 10))
	var sta_v := int(hero.get("sta", 10))
	return mhp + atk * 4 + def_v * 3 + spd * 2 + (str_v + agi_v + int_v + sta_v) * 5

func get_master_max_exp() -> int:
	return maxi(1000, master_level * 1000)

func redeem_giftcode(code: String) -> Dictionary:
	var payload := {"code": code}
	var res = await ApiClient.post_req("/api/giftcodes/redeem", payload)
	if res.get("ok", false):
		await refresh_profile()
		await refresh_inventory()
		return {"ok": true, "data": res.get("data", {})}
	return {"ok": false, "error": res.get("error", "Lỗi nhận mã quà tặng.")}

func is_logged_in() -> bool:
	return ApiClient.auth_token != "" and master_id != ""

## Automatically logs into the default `demo` account so login screens can be bypassed during fast testing
func ensure_demo_session() -> bool:
	if is_logged_in():
		return true

	var res := await ApiClient.post_req("/api/auth/login", {
		"username": DEFAULT_DEMO_USERNAME,
		"password": DEFAULT_DEMO_PASSWORD
	})
	if not res["ok"]:
		res = await ApiClient.post_req("/api/auth/register", {
			"username": DEFAULT_DEMO_USERNAME,
			"password": DEFAULT_DEMO_PASSWORD
		})

	if not res["ok"] or not (res.get("data") is Dictionary):
		return false

	var data: Dictionary = res["data"]
	var token := str(data.get("accessToken", data.get("token", "")))
	if token.is_empty():
		return false

	ApiClient.set_auth_token(token)
	var profile_ok := await refresh_profile()
	if not profile_ok or master_id.is_empty():
		var init_res := await ApiClient.post_req("/api/masters/init", {
			"masterName": DEFAULT_DEMO_MASTER_NAME
		})
		if init_res["ok"]:
			await refresh_profile()

	return is_logged_in()

## Refreshes master profile and currencies from GET /api/me
func refresh_profile() -> bool:
	var res = await ApiClient.get_req("/api/me")
	if not res["ok"]:
		return false
		
	var data = res["data"]
	if data is Dictionary and data.has("master") and data["master"] != null:
		var m = data["master"]
		master_id = str(m.get("id", ""))
		account_id = str(m.get("accountId", ""))
		master_name = str(m.get("masterName", ""))
		master_level = int(m.get("level", 1))
		master_exp = int(m.get("exp", 0))
		silver_coins = int(m.get("silverCoins", 0))
		gem_stones = int(m.get("gems", m.get("gemStones", 0)))
		EventBus.currency_updated.emit(silver_coins, gem_stones)
		EventBus.master_profile_updated.emit(m)
		load_floor_assignments()
		
	return true

## Refreshes owned heroes from GET /api/heroes
func refresh_heroes() -> bool:
	var res = await ApiClient.get_req("/api/heroes")
	if not res["ok"]:
		return false
		
	if res["data"] is Array:
		heroes = res["data"]
		EventBus.heroes_updated.emit(heroes)
		return true
		
	return false

## Refreshes 3D Base overview (Zones, Plots, Buildings, Workers, Blueprints) from GET /api/base/overview
func refresh_base_overview() -> bool:
	var res = await ApiClient.get_req("/api/base/overview")
	if not res["ok"] or not (res["data"] is Dictionary):
		return false
		
	base_overview = res["data"]
	if base_overview.has("master") and base_overview["master"] is Dictionary:
		silver_coins = int(base_overview["master"].get("silverCoins", silver_coins))
		EventBus.currency_updated.emit(silver_coins, gem_stones)
	if base_overview.has("world") and base_overview["world"] is Dictionary:
		var w: Dictionary = base_overview["world"]
		current_floor = int(w.get("currentFloor", 1))
		world_level = int(w.get("worldLevel", 1))
		base_zones = int(w.get("baseZones", 1))
		unlocked_lobby_floors = int(w.get("unlockedLobbyFloors", maxi(base_zones, 1 + int(master_level / 15))))
		unlocked_plots = maxi(int(w.get("plots", base_zones * PLOTS_PER_ZONE)), unlocked_lobby_floors * PLOTS_PER_ZONE)
	EventBus.base_updated.emit(base_overview)
	return true

## Refreshes Forge crafting recipes and equipment instances from GET /api/crafting
func refresh_crafting() -> bool:
	var res = await ApiClient.get_req("/api/crafting")
	if not res["ok"] or not (res["data"] is Dictionary):
		return false
	crafting_overview = res["data"]
	return true

## Refreshes equipment instances with full metadata from GET /api/equipment
func refresh_equipment() -> bool:
	var res = await ApiClient.get_req("/api/equipment")
	if not res["ok"] or not (res["data"] is Array):
		return false
	equipment_list = res["data"]
	return true

## Refreshes materials (WOOD, STONE, RATION) and summon scrolls from GET /api/inventory
func refresh_inventory() -> bool:
	var res = await ApiClient.get_req("/api/inventory")
	if not res["ok"] or not (res["data"] is Dictionary):
		return false
		
	var data: Dictionary = res["data"]
	materials["WOOD"] = 0
	materials["STONE"] = 0
	materials["RATION"] = 0
	materials["RAW_FOOD"] = 0
	materials["FOOD"] = 0
	materials["FOOD_RAW"] = 0
	materials["IRON"] = 0
	materials["SAMPLE_HERO_EXP_100"] = 0
	materials["SAMPLE_HERO_EXP_1000"] = 0
	materials["SAMPLE_HERO_EXP_10000"] = 0
	materials["SAMPLE_HERO_AWAKENING_CORE"] = 0
	materials["SAMPLE_HERO_PROMOTION_SEAL"] = 0
	materials["SAMPLE_HERO_SKILL_BOOK"] = 0
	normal_scrolls = 0
	
	var items: Array = data.get("items", [])
	for item in items:
		if item is Dictionary:
			var item_id := str(item.get("itemId", ""))
			var qty := int(item.get("quantity", 0))
			materials[item_id] = qty
	materials["RATION"] = int(materials.get("FOOD", 0)) + int(materials.get("RATION", 0))
	materials["RAW_FOOD"] = int(materials.get("FOOD_RAW", 0)) + int(materials.get("RAW_FOOD", 0))
			
	var scrolls: Array = data.get("summonScrolls", [])
	for s in scrolls:
		if s is Dictionary and str(s.get("scrollType", "")) == "NORMAL":
			normal_scrolls = int(s.get("quantity", 0))
			
	EventBus.inventory_updated.emit(materials)
	return true

## Refreshes active PvE party from GET /api/combat/party
func refresh_party() -> bool:
	var res = await ApiClient.get_req("/api/combat/party")
	if not res["ok"] or not (res["data"] is Array):
		return false
	var ids: Array = []
	for row in res["data"]:
		if row is Dictionary:
			var hid := str(row.get("heroId", ""))
			if hid == "" and row.has("hero") and row["hero"] is Dictionary:
				hid = str(row["hero"].get("id", ""))
			if hid != "":
				ids.append(hid)
	active_party_ids = ids
	EventBus.party_updated.emit(active_party_ids)
	return true

## Sets the active party of hero IDs
func set_active_party(hero_ids: Array) -> void:
	active_party_ids = hero_ids
	EventBus.party_updated.emit(active_party_ids)

func get_hero_by_id(id: String) -> Dictionary:
	for h in heroes:
		if str(h.get("id", "")) == id:
			return h
	return {}

## Returns a Dictionary mapping heroInstanceId -> { "building": Dictionary, "slotIndex": int }
func get_worker_assignment_map() -> Dictionary:
	var result: Dictionary = {}
	var buildings: Array = base_overview.get("buildings", [])
	for b in buildings:
		if not (b is Dictionary):
			continue
		var workers: Array = b.get("workers", [])
		for idx in range(workers.size()):
			var w = workers[idx]
			if w is Dictionary:
				var hid := str(w.get("heroInstanceId", ""))
				if hid != "":
					result[hid] = {
						"building": b,
						"slotIndex": idx
					}
	return result

func get_building_on_plot(plot_index: int) -> Dictionary:
	var buildings: Array = base_overview.get("buildings", [])
	for b in buildings:
		if b is Dictionary and int(b.get("plotIndex", -1)) == plot_index:
			return b
	return {}

## Returns eligible fodder heroes for star promotion (same star rating, not dead/disabled, not the target itself)
func get_eligible_fodders_for(target_hero_id: String, star: int) -> Array:
	var result: Array = []
	for h in heroes:
		var hid := str(h.get("id", ""))
		if hid == target_hero_id:
			continue
		if int(h.get("rarity", 1)) == star and str(h.get("state", "IDLE")) != "DEAD" and str(h.get("state", "IDLE")) != "DISABLED":
			result.append(h)
	return result

func get_assigned_heroes_for_floor(floor_num: int) -> Array:
	var ids: Variant = floor_assigned_hero_ids.get(floor_num, null)
	if ids is Array:
		return ids
	return []

func set_assigned_heroes_for_floor(floor_num: int, hero_ids: Array) -> void:
	var clean_ids: Array = []
	for hid in hero_ids:
		var s := str(hid)
		if s != "" and not clean_ids.has(s) and clean_ids.size() < 6:
			clean_ids.append(s)
	floor_assigned_hero_ids[floor_num] = clean_ids
	_save_floor_assignments()

func clear_assigned_heroes_for_floor(floor_num: int) -> void:
	if floor_assigned_hero_ids.has(floor_num):
		floor_assigned_hero_ids.erase(floor_num)
		_save_floor_assignments()

func _get_floor_assignment_save_path() -> String:
	var mid := master_id if master_id != "" else "demo"
	return "user://lobby_floor_heroes_%s.json" % mid

func load_floor_assignments() -> void:
	var path := _get_floor_assignment_save_path()
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var txt := file.get_as_text()
			var json = JSON.parse_string(txt)
			if json is Dictionary:
				floor_assigned_hero_ids.clear()
				for k in json.keys():
					var arr: Variant = json[k]
					if arr is Array:
						floor_assigned_hero_ids[int(k)] = arr

func _save_floor_assignments() -> void:
	var path := _get_floor_assignment_save_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(floor_assigned_hero_ids))

func clear() -> void:
	account_id = ""
	master_id = ""
	master_name = ""
	master_level = 1
	master_exp = 0
	silver_coins = 0
	gem_stones = 0
	world_level = 1
	current_floor = 1
	base_zones = 1
	unlocked_plots = PLOTS_PER_ZONE
	heroes.clear()
	active_party_ids.clear()
	base_overview.clear()
	materials = { "WOOD": 0, "STONE": 0, "RATION": 0, "RAW_FOOD": 0 }
	normal_scrolls = 0
	ApiClient.clear_auth_token()
