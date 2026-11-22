extends Control

## Main Hub Scene for Godot 4 Client

@onready var master_name_label: Label = %MasterNameLabel
@onready var level_label: Label = %LevelLabel
@onready var silver_label: Label = %SilverLabel
@onready var gems_label: Label = %GemsLabel
@onready var hero_count_label: Label = %HeroCountLabel
@onready var log_label: Label = %LogLabel

@onready var summon_btn: Button = %SummonBtn
@onready var roster_btn: Button = %RosterBtn
@onready var combat_btn: Button = %CombatBtn
@onready var refresh_btn: Button = %RefreshBtn
@onready var logout_btn: Button = %LogoutBtn

func _ready() -> void:
	EventBus.currency_updated.connect(_on_currency_updated)
	EventBus.heroes_updated.connect(_on_heroes_updated)
	
	summon_btn.pressed.connect(_on_summon_pressed)
	roster_btn.pressed.connect(_on_roster_pressed)
	combat_btn.pressed.connect(_on_combat_pressed)
	refresh_btn.pressed.connect(_on_refresh_pressed)
	logout_btn.pressed.connect(_on_logout_pressed)
	logout_btn.visible = false
	
	await GameState.ensure_demo_session()
	_update_ui()

func _update_ui() -> void:
	master_name_label.text = "Master: " + GameState.master_name
	level_label.text = "Lv." + str(GameState.master_level)
	silver_label.text = "🪙 Bạc: " + str(GameState.silver_coins)
	gems_label.text = "💎 Gem: " + str(GameState.gem_stones)
	hero_count_label.text = "Số Tướng sở hữu: " + str(GameState.owned_hero_count())

func _on_currency_updated(silver: int, gems: int) -> void:
	silver_label.text = "🪙 Bạc: " + str(silver)
	gems_label.text = "💎 Gem: " + str(gems)

func _on_heroes_updated(hero_list: Array) -> void:
	hero_count_label.text = "Số Tướng sở hữu: " + str(hero_list.size())

func _on_refresh_pressed() -> void:
	log_label.text = "Đang đồng bộ dữ liệu..."
	await GameState.refresh_profile()
	await GameState.refresh_heroes()
	_update_ui()
	log_label.text = "Đã đồng bộ dữ liệu mới nhất!"

func _on_summon_pressed() -> void:
	log_label.text = "Đang triệu hồi tướng..."
	var res = await ApiClient.post_req("/api/gacha/summon", {
		"bannerCode": "STANDARD",
		"amount": 1
	})
	if res["ok"]:
		var results = res["data"].get("results", [])
		if results.size() > 0:
			var h = results[0]
			log_label.text = "🎉 Triệu hồi thành công: " + str(h.get("name", "Tướng")) + " (" + str(h.get("rarity", 1)) + "★)"
		else:
			log_label.text = "Triệu hồi hoàn tất."
		await GameState.refresh_profile()
		await GameState.refresh_heroes()
		_update_ui()
	else:
		log_label.text = "Lỗi triệu hồi: " + str(res["error"])

func _on_roster_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/heroes/hero_roster.tscn")

func _on_combat_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/pve/pve_map.tscn")

func _on_logout_pressed() -> void:
	GameState.clear()
	get_tree().change_scene_to_file("res://scenes/auth/login_screen.tscn")
