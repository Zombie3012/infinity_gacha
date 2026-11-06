extends Node
class_name EventBusSingleton

## Global Event Bus for Infinite Gacha Godot 4 Client
## Emits decoupled events across scenes and systems

signal currency_updated(silver_coins: int, gem_stones: int)
signal master_profile_updated(profile: Dictionary)
signal heroes_updated(heroes: Array)
signal party_updated(hero_ids: Array)
signal base_updated(overview: Dictionary)
signal inventory_updated(materials: Dictionary)
signal expedition_updated()
signal battle_started(battle_data: Dictionary)
signal battle_finished(result: Dictionary)
signal notification_requested(text: String, is_error: bool)
