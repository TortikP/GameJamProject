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
const DEFAULT_HUB_MAP_PATH: String = "res://data/maps/office_intro.json"

var _game: GameData = null
var _game_path: String = ""
var _hub_map_path: String = ""
var _in_hub: bool = false
var _starting_attempt_from_hub: bool = false
var current_index: int = 0

# Editor-return slot (035-game-editor v1.1). Set by the Game Editor right
# before navigating to Map Editor on a row's "Edit" click; consumed by Game
# Editor's _ready when the user returns. Survives a Map-Editor → Playtest →
# Back-to-Editor cycle (only Game Editor's _ready or an explicit clear()
# consumes it). Cleared on main menu entry like everything else.
var _queued_editor_path: String = ""


# ── State queries ───────────────────────────────────────────────────────────

func has_active_game() -> bool:
	return _game != null


func game_name() -> String:
	if _game == null:
		return ""
	return _game.name


func game_path() -> String:
	return _game_path


func uses_hub() -> bool:
	return _hub_map_path != ""


func hub_map_path() -> String:
	return _hub_map_path


func is_in_hub() -> bool:
	return _in_hub


func is_starting_attempt_from_hub() -> bool:
	return _starting_attempt_from_hub


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
	if _in_hub:
		return {}
	if _game == null:
		return {}
	return _game.get_level(current_index)


func current_map_path() -> String:
	if _in_hub:
		return _hub_map_path
	var lv: Dictionary = current_level()
	return String(lv.get("map_path", ""))


func current_cutscene_id() -> StringName:
	var lv: Dictionary = current_level()
	return StringName(String(lv.get("cutscene_id", &"")))


func current_is_intro() -> bool:
	if _in_hub:
		return false
	var lv: Dictionary = current_level()
	return bool(lv.get("is_intro", false))


# ── Lifecycle ───────────────────────────────────────────────────────────────

## Loads a .game.json file, validates it, sets current_index=0, and queues
## the first level into ActiveLevel so that the next change_scene → godmode
## starts that level. Returns true on success.
func load_game(path: String) -> bool:
	if not _load_game_data(path):
		return false
	_hub_map_path = ""
	_in_hub = false
	_queue_current_level()
	GameLogger.info("ActiveGame", "Loaded game '%s' (%d levels) from %s" % [_game.name, _game.size(), path])
	EventBus.campaign_level_started.emit(current_index, current_map_path())
	return true


func load_game_to_hub(path: String, hub_map_path: String = DEFAULT_HUB_MAP_PATH) -> bool:
	if not _load_game_data(path):
		return false
	_hub_map_path = hub_map_path
	_in_hub = true
	_queue_current_level()
	GameLogger.info("ActiveGame", "Loaded game '%s' into hub %s" % [_game.name, _hub_map_path])
	EventBus.campaign_level_started.emit(-1, current_map_path())
	return true


func start_campaign_attempt() -> bool:
	if _game == null:
		GameLogger.warn("ActiveGame", "start_campaign_attempt: no active game")
		return false
	current_index = 0
	_in_hub = false
	_queue_current_level()
	_starting_attempt_from_hub = true
	EventBus.campaign_level_started.emit(current_index, current_map_path())
	_starting_attempt_from_hub = false
	return true


func return_to_hub() -> bool:
	if _game == null or _hub_map_path == "":
		GameLogger.warn("ActiveGame", "return_to_hub: no active hub")
		return false
	_in_hub = true
	current_index = 0
	_queue_current_level()
	EventBus.campaign_level_started.emit(-1, current_map_path())
	return true


func restore_from_save(data: Dictionary) -> bool:
	var path: String = String(data.get("game_path", ""))
	if path == "":
		GameLogger.error("ActiveGame", "restore_from_save: missing game_path")
		return false
	if not _load_game_data(path):
		return false
	current_index = clampi(int(data.get("current_index", 0)), 0, max(0, _game.size() - 1))
	_hub_map_path = String(data.get("hub_map_path", ""))
	if bool(data.get("uses_hub", false)) and _hub_map_path == "":
		_hub_map_path = DEFAULT_HUB_MAP_PATH
	_in_hub = bool(data.get("in_hub", false))
	_queue_current_level()
	GameLogger.info("ActiveGame", "Restored game '%s' at index=%d hub=%s" % [_game.name, current_index, str(_in_hub)])
	return true


func emit_current_level_started() -> void:
	EventBus.campaign_level_started.emit(-1 if _in_hub else current_index, current_map_path())


func _load_game_data(path: String) -> bool:
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
	return true


func restart() -> bool:
	if _game_path == "":
		GameLogger.warn("ActiveGame", "restart: no game path")
		return false
	return load_game(_game_path)


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
	_hub_map_path = ""
	_in_hub = false
	_starting_attempt_from_hub = false
	current_index = 0
	_queued_editor_path = ""


# ── Editor-return slot ──────────────────────────────────────────────────────

## Called by Game Editor right before change_scene to map editor.
## `path` is the .game.json the Game Editor should re-open with on return.
func queue_for_editor(path: String) -> void:
	_queued_editor_path = path


func has_queued_for_editor() -> bool:
	return _queued_editor_path != ""


## Returns the queued path AND clears the slot. Use exactly once on the
## Game Editor side.
func consume_queued_for_editor() -> String:
	var p: String = _queued_editor_path
	_queued_editor_path = ""
	return p


# ── Internals ───────────────────────────────────────────────────────────────

func _queue_current_level() -> void:
	var path: String = current_map_path()
	if path == "":
		GameLogger.error("ActiveGame", "_queue_current_level: current map_path empty (index=%d)" % current_index)
		return
	ActiveLevel.queue(path)
