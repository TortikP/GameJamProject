extends Node

## ActiveLevel — single-slot queue of "the next scene to load this level".
##
## Set by:
##   - Map editor on Playtest (writes __playtest__.json then queues it)
##   - Main menu on "Load Custom Level" (queues a user-picked file)
## Read by:
##   - GodmodeController in _ready() — if has_queued() it loads via LevelLoader
##     instead of running the procedural _paint_grid() / _place_player() path
##
## consume() clears the slot — same path will not re-trigger on the next scene.

var queued_path: String = ""


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
