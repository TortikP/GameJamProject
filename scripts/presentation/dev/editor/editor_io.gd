extends Node
class_name EditorIO

## EditorIO — file-system + grid-sync I/O for the level editor.
##
## Owned by EditorController; lives as a child Node (not RefCounted)
## because autosave needs a Timer (Node-only) and the lifecycle ties
## naturally to the controller.
##
## ## Responsibilities
##
##   - save / load / playtest snapshot via LevelSerializer.
##   - autosave debounce (1.5s) into __autosave__.json.
##   - autosave restore inspection (24h TTL).
##   - grid-sync: rebuild TileMapLayer + overlays from LevelData.
##
## ## Does NOT own
##
##   - Modal UI (controller handles ConfirmModal for autosave restore — see
##     spec.md AC21 / plan §Φ-2 "Решение про restore prompt").
##   - Toasts (controller emits via EventBus — IO returns bool/null and
##     controller decides what to communicate).
##   - Validation (062 will add hooks here).
##
## ## Hard cap: 200 lines (AC34).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

const MAPS_DIR: String = "res://data/maps/"
const AUTOSAVE_PATH: String = "res://data/maps/__autosave__.json"
const PLAYTEST_PATH: String = "res://data/maps/__playtest__.json"
const AUTOSAVE_DEBOUNCE_SEC: float = 1.5
const AUTOSAVE_MAX_AGE_SEC: int = 86400  # 24h


## Emitted after a successful autosave-restore (controller fires this
## once it has applied the restored level to its in-memory state).
## Reserved for future consumers (validator, history). 060 has no
## subscribers — see plan §Φ-2 for rationale.
signal autosave_restored(level: LevelData)
signal load_completed(level: LevelData)
signal save_completed(path: String)


var _grid: HexGrid
var _objects_overlay: Node              # weak typing — overlay scripts not class_name'd
var _spawners_overlay: Node
var _autosave_timer: Timer
var _autosave_pending_level: LevelData = null


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DEBOUNCE_SEC
	_autosave_timer.timeout.connect(_on_autosave_fire)
	add_child(_autosave_timer)


## Inject node references after _ready. Overlays may be null in Φ-2;
## they're wired in Φ-6 once level_editor.tscn adds the overlay nodes.
func setup(grid: HexGrid, objects_overlay: Node, spawners_overlay: Node) -> void:
	_grid = grid
	_objects_overlay = objects_overlay
	_spawners_overlay = spawners_overlay


# ── Save / Load ───────────────────────────────────────────────────

## Explicit save to data/maps/<name>.json. On success, clears autosave
## (the canonical level is now on disk, the shadow is stale). Returns
## false on serializer failure — controller reports via toast.
func save(level: LevelData) -> bool:
	var path := MAPS_DIR + level.name + ".json"
	var ok := LevelSerializer.save(level, path)
	if ok:
		clear_autosave()
		save_completed.emit(path)
	return ok


## Load from explicit path. Returns null on failure (controller toasts).
## Does NOT mutate _grid — caller is expected to call refresh_grid_from_level
## after applying the returned level to its own state.
func load_from(path: String) -> LevelData:
	var loaded := LevelSerializer.load_from(path)
	if loaded != null:
		load_completed.emit(loaded)
	return loaded


## Snapshot the current level into __playtest__.json so godmode can pick
## it up via ActiveLevel.queue. Used by EditorController._on_playtest in
## Φ-6 — no callers in Φ-2.
func write_playtest_snapshot(level: LevelData) -> bool:
	return LevelSerializer.save(level, PLAYTEST_PATH)


# ── Autosave ──────────────────────────────────────────────────────

## Restart the debounce timer pointing at `level`. The level reference is
## captured by ref — if the level mutates again before the timer fires,
## the next enqueue_autosave call replaces the captured reference, and
## the actual write at fire time reflects state-as-of-fire (which is what
## we want — autosave should match the visible editor state, not the
## point-in-time when the user first started editing).
func enqueue_autosave(level: LevelData) -> void:
	_autosave_pending_level = level
	if _autosave_timer != null:
		_autosave_timer.start(AUTOSAVE_DEBOUNCE_SEC)


## Delete the autosave file if present. Called automatically from save()
## on success (canonical state is now on disk) and from the controller
## when the user picks "Discard" in the restore prompt.
func clear_autosave() -> void:
	if FileAccess.file_exists(AUTOSAVE_PATH):
		var err := DirAccess.remove_absolute(AUTOSAVE_PATH)
		if err != OK:
			GameLogger.warn("EditorIO",
				"clear_autosave: remove_absolute err=%d" % err)


## Inspect autosave state for the controller's _ready restore decision.
## Returns {prompt_needed: bool, age_sec: int}.
##   - File missing → {false, 0}.
##   - File older than 24h → silent delete, returns {false, 0}.
##   - File present and fresh → {true, age}.
##
## Controller is responsible for opening ConfirmModal — IO has no
## scene-tree opinions (plan §Φ-2 "Решение про restore prompt").
func check_autosave_on_ready() -> Dictionary:
	var result := {"prompt_needed": false, "age_sec": 0}
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return result
	var modified: int = int(FileAccess.get_modified_time(AUTOSAVE_PATH))
	var now: int = int(Time.get_unix_time_from_system())
	var age: int = max(0, now - modified)
	if age > AUTOSAVE_MAX_AGE_SEC:
		clear_autosave()
		return result
	result["prompt_needed"] = true
	result["age_sec"] = age
	return result


func _on_autosave_fire() -> void:
	if _autosave_pending_level == null:
		return
	var ok := LevelSerializer.save(_autosave_pending_level, AUTOSAVE_PATH)
	if not ok:
		GameLogger.warn("EditorIO", "autosave write failed")
	_autosave_pending_level = null


# ── Grid sync ─────────────────────────────────────────────────────

## Rebuild TileMapLayer + overlays from LevelData. Clears existing cells
## first so the post-Load case works (previous in-memory level may have
## had different cells). Overlays may be null in Φ-2 — they're wired in
## Φ-6 once level_editor.tscn adds the nodes.
func refresh_grid_from_level(level: LevelData) -> void:
	if _grid != null and _grid.tile_map_layer != null:
		_grid.tile_map_layer.clear()
		for cell in level.floor_cells:
			var coord: Vector2i = cell["coord"]
			var source_id: int = int(cell["source_id"])
			var atlas: Vector2i = cell["atlas_coord"]
			_grid.tile_map_layer.set_cell(coord, source_id, atlas)
	if _objects_overlay != null and _objects_overlay.has_method("refresh"):
		_objects_overlay.refresh(level.objects)
	if _spawners_overlay != null and _spawners_overlay.has_method("refresh"):
		_spawners_overlay.refresh(level.spawners)
