extends Node
## GameSpeed — central source of truth for all game timings.
##
## Reads `res://config/game_speed.cfg` at startup. Press F5 in-game to hot-reload
## without restarting. Always use this instead of hardcoded `create_timer()` calls.
##
## Usage:
##   await GameSpeed.wait("battle", "spell_resolve_speed")
##   var t: float = GameSpeed.get_value("ui", "dialogue_auto_advance_after_sec", 3.0)

const Logger = preload("res://scripts/infrastructure/logger.gd")

const CONFIG_PATH := "res://config/game_speed.cfg"

var _cfg: ConfigFile


func _ready() -> void:
	reload()


func reload() -> void:
	_cfg = ConfigFile.new()
	var err := _cfg.load(CONFIG_PATH)
	if err != OK:
		Logger.error("GameSpeed", "failed to load %s: %s" % [CONFIG_PATH, error_string(err)])
		return
	Logger.info("GameSpeed", "config reloaded")


func get_value(section: String, key: String, default: Variant = 1.0) -> Variant:
	if _cfg == null:
		return default
	return _cfg.get_value(section, key, default)


func wait(section: String, key: String, default: float = 0.5) -> void:
	var t: float = float(get_value(section, key, default))
	await get_tree().create_timer(t).timeout


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F5:
		reload()
