extends Node
class_name GameStateSingleton

## Central Game State manager for the Master player
## Synchronizes player data, currencies, base buildings, materials, and hero rosters from the Backend

const DEFAULT_DEMO_USERNAME := "demo"
const DEFAULT_DEMO_PASSWORD := "demo12345"
const DEFAULT_DEMO_MASTER_NAME := "Demo Master"

var account_id: String = ""
var master_id: String = ""
var master_name: String = ""
var silver_coins: int = 0
var gem_stones: int = 0
var is_synced: bool = false
var sync_error: String = ""

var world_level: int = 1
var current_floor: int = 0
var base_zones: int = 0
var unlocked_lobby_floors: int = 1
const PLOTS_PER_ZONE: int = 8
const MAX_BASE_ZONES: int = 6
var unlocked_plots: int = 0

var heroes: Array = []
var active_party_ids: Array = []
var base_overview: Dictionary = {}
var crafting_overview: Dictionary = {}
var equipment_list: Array = []
var inventory_items: Array = []
var summon_scrolls_list: Array = []
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
var away_expedition_hero_ids: Array = []
var personality_map: Dictionary = {} # hero_id -> Dictionary
var castle_activity_log: Array[String] = []
const DeviceProfileScript := preload("res://scripts/core/device_profile.gd")

var graphics_quality: String = "HIGH"
var device_profile: Dictionary = {}
var world_graphics_settings: Dictionary = {}

func _ready() -> void:
	_load_graphics_settings()

func is_mobile_platform() -> bool:
	if device_profile.is_empty():
		device_profile = DeviceProfileScript.detect_hardware()
	return bool(device_profile.get("is_mobile", false))

func get_device_profile() -> Dictionary:
	if device_profile.is_empty():
		device_profile = DeviceProfileScript.detect_hardware()
	return device_profile.duplicate()

func get_world_graphics_settings() -> Dictionary:
	if world_graphics_settings.is_empty():
		_load_graphics_settings()
	return world_graphics_settings.duplicate()

func set_graphics_quality(q: String) -> void:
	var is_mob := is_mobile_platform()
	world_graphics_settings = DeviceProfileScript.get_preset_settings(q, is_mob)
	graphics_quality = str(world_graphics_settings.get("quality", "HIGH"))
	_apply_and_persist_graphics_settings()

func update_world_graphics_setting(key: String, value: Variant) -> void:
	if world_graphics_settings.is_empty():
		_load_graphics_settings()
	var merged := world_graphics_settings.duplicate()
	merged[key] = value
	world_graphics_settings = DeviceProfileScript.sanitize_settings(merged, is_mobile_platform())
	graphics_quality = str(world_graphics_settings.get("quality", graphics_quality))
	_apply_and_persist_graphics_settings()

func reset_graphics_to_device_default() -> void:
	device_profile = DeviceProfileScript.detect_hardware()
	var rec := str(device_profile.get("recommended_preset", "HIGH"))
	set_graphics_quality(rec)

func _apply_and_persist_graphics_settings() -> void:
	var target_fps := int(world_graphics_settings.get("max_fps", 60))
	if target_fps > 0:
		Engine.max_fps = target_fps
	var payload := world_graphics_settings.duplicate()
	payload["auto_detected_once"] = true
	var f := FileAccess.open("user://graphics_settings.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()
	EventBus.graphics_quality_changed.emit(graphics_quality)
	EventBus.world_graphics_settings_changed.emit(world_graphics_settings.duplicate())

func _load_graphics_settings() -> void:
	device_profile = DeviceProfileScript.detect_hardware()
	var is_mob := bool(device_profile.get("is_mobile", false))
	var rec := str(device_profile.get("recommended_preset", "HIGH"))
	var loaded_ok := false

	if FileAccess.file_exists("user://graphics_settings.json"):
		var f := FileAccess.open("user://graphics_settings.json", FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				if bool(parsed.get("auto_detected_once", false)):
					world_graphics_settings = DeviceProfileScript.sanitize_settings(parsed, is_mob)
					loaded_ok = true
				elif parsed.has("quality"):
					world_graphics_settings = DeviceProfileScript.get_preset_settings(str(parsed.get("quality", rec)), is_mob)
					loaded_ok = true

	if not loaded_ok:
		world_graphics_settings = DeviceProfileScript.get_preset_settings(rec, is_mob)
		var save_payload := world_graphics_settings.duplicate()
		save_payload["auto_detected_once"] = true
		var wf := FileAccess.open("user://graphics_settings.json", FileAccess.WRITE)
		if wf != null:
			wf.store_string(JSON.stringify(save_payload))
			wf.close()

	graphics_quality = str(world_graphics_settings.get("quality", rec))
	var target_fps := int(world_graphics_settings.get("max_fps", 60))
	if target_fps > 0:
		Engine.max_fps = target_fps

var world_base_pos: Vector2i = Vector2i(0, 0)
var world_unlocked: bool = false
var selected_avatar_hero_id: String = ""

var badge_counts: Dictionary = {
	"mailbox": 0,
	"events": 0,
	"friends": 0,
	"chat": 0,
}

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
		var init_res := await ApiClient.post_req("/api/master/init", {
			"masterName": DEFAULT_DEMO_MASTER_NAME
		})
		if init_res["ok"]:
			await refresh_profile()

	return is_logged_in()

## Refreshes master profile and currencies from GET /api/me
func refresh_profile() -> bool:
	var res = await ApiClient.get_req("/api/me")
	if not res["ok"]:
		sync_error = str(res.get("error", "Không thể đồng bộ hồ sơ Master."))
		return false
		
	var data = res["data"]
	if data is Dictionary and data.has("master") and data["master"] != null:
		var m = data["master"]
		master_id = str(m.get("id", ""))
		account_id = str(m.get("accountId", ""))
		master_name = str(m.get("masterName", ""))
		silver_coins = int(m.get("silverCoins", 0))
		gem_stones = int(m.get("gems", m.get("gemStones", 0)))
		is_synced = true
		sync_error = ""
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
		if not selected_avatar_hero_id.is_empty() and not is_hero_alive(get_hero_by_id(selected_avatar_hero_id)):
			selected_avatar_hero_id = ""
		active_party_ids = active_party_ids.filter(func(id): return is_hero_alive(get_hero_by_id(str(id))))
		for floor_num in floor_assigned_hero_ids:
			floor_assigned_hero_ids[floor_num] = get_assigned_heroes_for_floor(int(floor_num)).filter(func(id): return is_hero_alive(get_hero_by_id(str(id))))
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
		unlocked_lobby_floors = int(w.get("unlockedLobbyFloors", 2))
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
	materials.clear()
	materials["WOOD"] = 0
	materials["STONE"] = 0
	materials["RATION"] = 0
	materials["RAW_FOOD"] = 0
	materials["FOOD"] = 0
	materials["FOOD_RAW"] = 0
	materials["IRON"] = 0
	materials["MEDICINE"] = 0
	materials["SAMPLE_HERO_EXP_100"] = 0
	materials["SAMPLE_HERO_EXP_1000"] = 0
	materials["SAMPLE_HERO_EXP_10000"] = 0
	materials["SAMPLE_HERO_AWAKENING_CORE"] = 0
	materials["SAMPLE_HERO_PROMOTION_SEAL"] = 0
	materials["SAMPLE_HERO_SKILL_BOOK"] = 0
	normal_scrolls = 0
	inventory_items.clear()
	summon_scrolls_list.clear()
	
	var items: Array = data.get("items", [])
	for item in items:
		if item is Dictionary:
			var item_id := str(item.get("itemId", ""))
			var qty := int(item.get("quantity", 0))
			materials[item_id] = qty
			if qty > 0:
				inventory_items.append(item.duplicate(true))
	materials["RATION"] = int(materials.get("FOOD", 0)) + int(materials.get("RATION", 0))
	materials["RAW_FOOD"] = int(materials.get("FOOD_RAW", 0)) + int(materials.get("RAW_FOOD", 0))
			
	var scrolls: Array = data.get("summonScrolls", [])
	for s in scrolls:
		if s is Dictionary:
			var stype := str(s.get("scrollType", ""))
			var sqty := int(s.get("quantity", 0))
			if stype == "NORMAL":
				normal_scrolls = sqty
			if sqty > 0:
				var s_name := "Thiên Thư Triệu Hồi Thường" if stype == "NORMAL" else ("Thiên Thư %s" % stype)
				summon_scrolls_list.append({
					"id": "SCROLL_%s" % stype,
					"itemId": "SCROLL_%s" % stype,
					"name": s_name,
					"description": "Dùng tại Triệu Hồi Đàn để triệu hồi Hero mới.",
					"category": "TICKET",
					"rarity": 3 if stype == "NORMAL" else 5,
					"starLevel": 3 if stype == "NORMAL" else 5,
					"slot": "SCROLL",
					"quantity": sqty,
					"canUse": false,
					"source": "Kho Triệu Hồi",
				})
			
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

static func is_hero_alive(hero: Dictionary) -> bool:
	return not hero.is_empty() and str(hero.get("state", "")).to_upper() not in ["DEAD", "DISABLED"] and float(hero.get("hp", 1)) > 0

static func is_hero_available(hero: Dictionary) -> bool:
	return is_hero_alive(hero) and not is_hero_pve_deployed(hero) and not bool(hero.get("onExpedition", false))

func refresh_away_heroes() -> void:
	var res := await ApiClient.get_req("/api/world/heroes/away")
	away_expedition_hero_ids.clear()
	if res.get("ok", false):
		var d = res.get("data")
		var arr: Array = d if d is Array else (d.get("heroIds", []) if d is Dictionary else [])
		for item in arr:
			if item is Dictionary:
				away_expedition_hero_ids.append(str(item.get("heroId", item.get("id", ""))))
			else:
				away_expedition_hero_ids.append(str(item))
	for h in heroes:
		if h is Dictionary:
			h["onExpedition"] = away_expedition_hero_ids.has(str(h.get("id", "")))

static func hero_life_label(hero: Dictionary) -> String:
	match str(hero.get("state", "")).to_upper():
		"DEAD": return "TỬ TRẬN"
		"DISABLED": return "TỬ TRẬN"
	return "" if is_hero_alive(hero) else "KHÔNG THỂ HOẠT ĐỘNG"

func owned_hero_count() -> int:
	return heroes.filter(func(h): return h is Dictionary and is_hero_alive(h)).size()

static func is_hero_pve_deployed(hero: Dictionary) -> bool:
	var deployment: Variant = hero.get("pveDeployment")
	return deployment is Dictionary and not deployment.is_empty()

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
		if int(h.get("rarity", 1)) == star and is_hero_available(h):
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
		if s != "" and is_hero_available(get_hero_by_id(s)) and not clean_ids.has(s) and clean_ids.size() < 6:
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
	PveState.deactivate()
	account_id = ""
	master_id = ""
	master_name = ""
	silver_coins = 0
	gem_stones = 0
	is_synced = false
	sync_error = ""
	world_level = 1
	current_floor = 0
	base_zones = 0
	unlocked_plots = 0
	heroes.clear()
	active_party_ids.clear()
	base_overview.clear()
	personality_map.clear()
	materials = { "WOOD": 0, "STONE": 0, "RATION": 0, "RAW_FOOD": 0 }
	normal_scrolls = 0
	badge_counts = { "mailbox": 0, "events": 0, "friends": 0, "chat": 0 }
	EventBus.badges_updated.emit(badge_counts)
	ApiClient.clear_auth_token()

func get_badge_count(key: String) -> int:
	return int(badge_counts.get(key, 0))

func set_badge_count(key: String, count: int) -> void:
	badge_counts[key] = maxi(0, count)
	EventBus.badges_updated.emit(badge_counts)

func increment_badge_count(key: String, delta: int = 1) -> void:
	set_badge_count(key, get_badge_count(key) + delta)

func refresh_notification_badges() -> void:
	if not is_logged_in():
		return
	var mail_unread := 0
	var m_res := await ApiClient.get_req("/api/mailbox")
	if m_res.get("ok", false):
		var md: Variant = m_res.get("data")
		var msgs: Array = md if md is Array else (md.get("messages", md.get("mails", [])) if md is Dictionary else [])
		for msg in msgs:
			if msg is Dictionary:
				var claimed := bool(msg.get("claimedAt", "") != "" and msg.get("claimedAt") != null) or bool(msg.get("isClaimed", false))
				if not claimed:
					mail_unread += 1
	badge_counts["mailbox"] = mail_unread

	var ev_claimable := 0
	var ev_res := await ApiClient.get_req("/api/events")
	if ev_res.get("ok", false):
		var ed: Variant = ev_res.get("data")
		var evs: Array = ed if ed is Array else (ed.get("events", []) if ed is Dictionary else [])
		for ev in evs:
			if ev is Dictionary:
				var missions: Variant = ev.get("missions", [])
				if missions is Array:
					for ms in missions:
						if ms is Dictionary:
							var prog := int(ms.get("progress", 0))
							var target := maxi(1, int(ms.get("targetValue", ms.get("targetCount", 1))))
							if not bool(ms.get("claimed", false)) and prog >= target:
								ev_claimable += 1

	var q_res := await ApiClient.get_req("/api/quests")
	if q_res.get("ok", false) and q_res.get("data") is Dictionary:
		var qd: Dictionary = q_res["data"]
		var quests: Variant = qd.get("quests", [])
		if quests is Array:
			for q in quests:
				if q is Dictionary:
					var status := str(q.get("status", "AVAILABLE")).to_upper()
					var prog := int(q.get("progress", 0))
					var target := maxi(1, int(q.get("targetValue", q.get("targetCount", 1))))
					if status == "COMPLETED" or (status == "ACTIVE" and prog >= target):
						ev_claimable += 1
		var achs: Variant = qd.get("achievements", [])
		if achs is Array:
			for a in achs:
				if a is Dictionary:
					var prog := int(a.get("progress", 0))
					var target := maxi(1, int(a.get("targetValue", a.get("targetCount", 1))))
					if not bool(a.get("claimed", false)) and prog >= target:
						ev_claimable += 1
	badge_counts["events"] = ev_claimable

	var friend_notif := 0
	var f_res := await ApiClient.get_req("/api/friends")
	if f_res.get("ok", false) and f_res.get("data") is Dictionary:
		friend_notif += int(f_res["data"].get("unclaimedGiftCount", 0))
	var fr_res := await ApiClient.get_req("/api/friends/requests")
	if fr_res.get("ok", false) and fr_res.get("data") is Dictionary:
		var inc: Variant = fr_res["data"].get("incoming", [])
		if inc is Array:
			friend_notif += inc.size()
	badge_counts["friends"] = friend_notif

	EventBus.badges_updated.emit(badge_counts)

func refresh_personality() -> bool:
	if not is_logged_in():
		return false
	var res := await ApiClient.get_req("/api/personality")
	if not res.get("ok", false) or not (res.get("data") is Dictionary):
		return false
	var list: Variant = res["data"].get("heroes", [])
	personality_map.clear()
	if list is Array:
		for item in list:
			if item is Dictionary:
				var hid := str(item.get("heroId", ""))
				if not hid.is_empty():
					personality_map[hid] = item
	for h in heroes:
		if h is Dictionary:
			var hid := str(h.get("id", ""))
			if personality_map.has(hid):
				var p: Dictionary = personality_map[hid]
				h["coreTrait"] = str(p.get("coreTrait", ""))
				h["socialTrait"] = str(p.get("socialTrait", ""))
				h["favoriteFood"] = str(p.get("favoriteFood", ""))
				h["loyaltyScore"] = int(p.get("loyaltyScore", 50))
				h["loyalty"] = int(p.get("loyaltyScore", 50))
				h["loyaltyState"] = str(p.get("loyaltyState", "NEUTRAL"))
				h["mood"] = str(p.get("loyaltyState", "Bình thường"))
	return true

func get_hero_personality(hero_id: String) -> Dictionary:
	if personality_map.has(hero_id):
		return personality_map[hero_id]
	return {}

func serve_favorite_meal(hero_id: String) -> Dictionary:
	var res := await ApiClient.post_req("/api/personality/heroes/%s/favorite-meal" % hero_id, {})
	if res.get("ok", false):
		await refresh_personality()
		await refresh_heroes()
	return res

func record_castle_activity(entry: String) -> void:
	var clean := entry.strip_edges()
	if clean.is_empty():
		return
	var dt := Time.get_time_string_from_system()
	castle_activity_log.push_front("[%s] %s" % [dt, clean])
	if castle_activity_log.size() > 60:
		castle_activity_log.resize(60)
