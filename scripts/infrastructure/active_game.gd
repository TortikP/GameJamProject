extends Node

## ActiveGame — campaign-level cousin of ActiveLevel.
##
## Holds the loaded GameData + which level the player is currently on.
## Set by:
##   - Main menu Load Game button → ActiveGame.load_game(path)
##   - Game editor Playtest button → writes __playtest_game__.game.json then load_game
## Read by:
##   - CampaignController on level_completed → advance() or campaign_finished
##   - CampaignController on scene_ready → checks current level for is_intro/cutscene_id
##   - Optional HUD widgets reading current_index for "Level N of M"
##
## Important: ActiveGame DOES NOT load LevelData itself. It just keeps the
## map_path of the current level queued in ActiveLevel — godmode_controller
## (the existing path) handles map loading. This keeps 035 a thin layer over
## 020/024 instead of forking the load path.
##
## Lifetime: cleared on main menu entry (main_menu._ready), survives all
## change_scene calls between the levels of one game.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _game: GameData = null
var _game_path: String = ""
var current_index: int = 0


# ── State queries ───────────────────────────────────────────────────────────

func has_active_game() -> bool:
	return _game != null


func game_name() -> String:
	if _game == null:
		return ""
	return _game.name


func total_levels() -> int:
	if _game == null:
		return 0
	return _game.size()


func is_last_level() -> bool:
	if _game == null:
		return false
	return _game.is_last_index(current_index)


## Returns the dict for the current level, or {} if no active game / out of range.
func current_level() -> Dictionary:
	if _game == null:
		return {}
	return _game.get_level(current_index)


func current_map_path() -> String:
	var lv: Dictionary = current_level()
	return String(lv.get("map_path", ""))


func current_cutscene_id() -> StringName:
	var lv: Dictionary = current_level()
	return StringName(String(lv.get("cutscene_id", &"")))


func current_is_intro() -> bool:
	var lv: Dictionary = current_level()
	return bool(lv.get("is_intro", false))


# ── Lifecycle ───────────────────────────────────────────────────────────────

## Loads a .game.json file, validates it, sets current_index=0, and queues
## the first level into ActiveLevel so that the next change_scene → godmode
## starts that level. Returns true on success.
func load_game(path: String) -> bool:
	var game := GameSerializer.load_from(path)
	if game == null:
		GameLogger.error("ActiveGame", "load_game: serializer returned null for %s" % path)
		return false
	var msgs: Array[String] = game.validate()
	for m: String in msgs:
		if m.begins_with("REJECT"):
			GameLogger.error("ActiveGame", "load_game rejected: %s" % m)
			return false
		else:
			GameLogger.warn("ActiveGame", "load_game: %s" % m)

	_game = game
	_game_path = path
	current_index = 0
	_queue_current_level()
	GameLogger.info("ActiveGame", "Loaded game '%s' (%d levels) from %s" % [_game.name, _game.size(), path])
	EventBus.campaign_level_started.emit(current_index, current_map_path())
	return true


## Advances to the next level. Caller (CampaignController) is responsible for
## checking is_last_level() FIRST — calling advance() past the end is a no-op
## with a warn log.
func advance() -> void:
	if _game == null:
		GameLogger.warn("ActiveGame", "advance: no active game")
		return
	if is_last_level():
		GameLogger.warn("ActiveGame", "advance: already at last level (index=%d)" % current_index)
		return
	current_index += 1
	_queue_current_level()
	GameLogger.info("ActiveGame", "Advanced to level %d/%d (%s)" % [
		current_index, _game.size() - 1, current_map_path()
	])
	EventBus.campaign_level_started.emit(current_index, current_map_path())


## Clears all state. Called by main_menu._ready() so leaving back to the menu
## fully resets the campaign. Does NOT clear ActiveLevel — that has its own
## clear() at the same call site.
func clear() -> void:
	_game = null
	_game_path = ""
	current_index = 0


# ── Internals ───────────────────────────────────────────────────────────────

func _queue_current_level() -> void:
	var path: String = current_map_path()
	if path == "":
		GameLogger.error("ActiveGame", "_queue_current_level: current map_path empty (index=%d)" % current_index)
		return
	ActiveLevel.queue(path)
