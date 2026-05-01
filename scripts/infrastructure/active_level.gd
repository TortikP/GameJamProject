extends Node

## ActiveLevel — single-slot queue of "the next scene to load this level".
##
## Set by:
##   - Map editor on Playtest (writes __playtest__.json then queues it)
##   - Main menu on "Load Custom Level" (queues a user-picked file)
##   - Pause menu on "Back to Editor" (re-queues the playtest origin)
## Read by:
##   - GodmodeController in _ready() — if has_queued() it loads via LevelLoader
##     instead of running the procedural _paint_grid() / _place_player() path
##   - MapEditorController in _ready() — if has_queued() it applies that
##     LevelData on top of the initial canvas (so Back-to-Editor reopens
##     the same map being playtested)
##
## consume() clears the slot — same path will not re-trigger on the next scene.
##
## playtest_origin_path is a separate slot tracking "this run came from the
## editor's Playtest button". Pause menu shows Back-to-Editor only when this
## is set; cleared on main-menu transitions to avoid stale state across runs.

var queued_path: String = ""
var playtest_origin_path: String = ""


func queue(path: String) -> void:
	queued_path = path


func consume() -> String:
	var p := queued_path
	queued_path = ""
	return p


func has_queued() -> bool:
	return queued_path != ""


func clear() -> void:
	queued_path = ""


# ── Playtest origin tracking ────────────────────────────────────────────────

## Marks "this is the path the editor wrote for Playtest". Pause menu and
## godmode's Ctrl+E use this to enable Back-to-Editor.
func mark_playtest(path: String) -> void:
	playtest_origin_path = path


func can_return_to_editor() -> bool:
	return playtest_origin_path != ""


func get_playtest_origin() -> String:
	return playtest_origin_path


func clear_playtest_origin() -> void:
	playtest_origin_path = ""
