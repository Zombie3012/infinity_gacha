extends Node
class_name EventBusSingleton

## Global Event Bus for Infinite Gacha Godot 4 Client
## Emits decoupled events across scenes and systems

@warning_ignore("unused_signal")
signal currency_updated(silver_coins: int, gem_stones: int)
@warning_ignore("unused_signal")
signal master_profile_updated(profile: Dictionary)
@warning_ignore("unused_signal")
signal heroes_updated(heroes: Array)
@warning_ignore("unused_signal")
signal party_updated(hero_ids: Array)
@warning_ignore("unused_signal")
signal base_updated(overview: Dictionary)
@warning_ignore("unused_signal")
signal inventory_updated(materials: Dictionary)
@warning_ignore("unused_signal")
signal expedition_updated()
@warning_ignore("unused_signal")
signal battle_started(battle_data: Dictionary)
@warning_ignore("unused_signal")
signal battle_finished(result: Dictionary)
@warning_ignore("unused_signal")
signal notification_requested(text: String, is_error: bool)
@warning_ignore("unused_signal")
signal badges_updated(counts: Dictionary)
@warning_ignore("unused_signal")
signal chat_message_received(payload: Dictionary)
@warning_ignore("unused_signal")
signal graphics_quality_changed(quality: String)
@warning_ignore("unused_signal")
signal world_graphics_settings_changed(settings: Dictionary)
