extends Node2D
## MapEditorController — drives the map editor scene. Owns the LevelData being
## edited, mode/state, mouse handling, and the wiring between palettes and
## overlays.
##
## Scene tree assumptions (see scenes/dev/map_editor.tscn):
##   MapEditor (this script)
##   ├── EditorCamera (Camera2D)
##   ├── HexGrid (instance of scenes/arena/hex_grid.tscn)
##   │   ├── Terrain (TileMapLayer)
##   │   ├── VFXOverlay (TileMapLayer — unused, kept so HexGrid.initialize works)
##   │   ├── ObjectsOverlay (Node2D, objects_overlay.gd)
##   │   ├── SpawnersOverlay (Node2D, spawners_overlay.gd)
##   │   ├── HoverHighlight (Node2D, hover_highlight.gd)
##   │   └── DeleteHighlight (Node2D, delete_highlight.gd)
##   └── HUD (CanvasLayer)
##       ├── FloorPalettePanel (left-bottom)
##       ├── ObjectPalettePanel (right)
##       ├── LevelMetaPanel (right-top: name, save, load, playtest, exit)
##       ├── ToastLayer (instance)
##       └── ConfirmModal (instance)

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const LevelHistory = preload("res://scripts/presentation/dev/level_history.gd")
const GODMODE_TERRAIN: TileSet = preload("res://scenes/dev/godmode_terrain.tres")

const INITIAL_SOURCE_ID: int = 0
const INITIAL_ATLAS_COORD: Vector2i = Vector2i(0, 0)
const INITIAL_CANVAS_HALF: int = 12  # ⇒ 25×25 default paint, centered at origin

const MAPS_DIR: String = "res://data/maps/"
const AUTOSAVE_PATH: String = "res://data/maps/__autosave__.json"
const PLAYTEST_PATH: String = "res://data/maps/__playtest__.json"
const AUTOSAVE_DEBOUNCE_SEC: float = 1.5
const AUTOSAVE_MAX_AGE_SEC: int = 86400  # 24h

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const GODMODE_SCENE: String = "res://scenes/dev/godmode.tscn"

# ── Mode state machine ──────────────────────────────────────────────────────
enum Mode { IDLE, PLACING_FLOOR, ERASING_FLOOR, PLACING_OBJECT, PLACING_SPAWNER }

# ── Scene refs (resolved in _ready, exported for editor wiring) ─────────────
@export var grid: HexGrid
@export var camera: Camera2D
@export var objects_overlay_path: NodePath
@export var spawners_overlay_path: NodePath
@export var hover_highlight_path: NodePath
@export var delete_highlight_path: NodePath
@export var floor_palette_path: NodePath
@export var object_palette_path: NodePath
@export var meta_panel_path: NodePath
@export var confirm_modal_path: NodePath
@export var hotkey_overlay_path: NodePath

# Resolved nodes
var _objects_overlay: Node2D
var _spawners_overlay: Node2D
var _hover: Node2D
var _delete: Node2D
var _floor_palette: Node
var _object_palette: Node
var _meta_panel: Node
var _confirm_modal: Node
var _hotkey_overlay: Control
var _autosave_timer: Timer

# ── Editing state ───────────────────────────────────────────────────────────
var _level: LevelData = LevelData.new()
var _mode: int = Mode.IDLE
var _placing_source_id: int = INITIAL_SOURCE_ID
var _placing_atlas_coord: Vector2i = INITIAL_ATLAS_COORD
var _placing_object_id: StringName = &""
var _placing_spawner_kind: StringName = &""
var _placing_spawner_ref: StringName = &""
var _dirty: bool = false

# Drag-paint state (T-02): LMB held + last coord painted, anti-dup at micro-motion
var _lmb_held: bool = false
var _last_paint_coord: Vector2i = Vector2i(-1, -1)

# Silent-reject occupied-toast debounce (T-04): suppress spam during drag-paint
var _occupied_toast_until_msec: int = 0

# Undo/redo (T-07): snapshot stack across LMB-drag transactions and one-shot
# mutations (RMB delete, replace_all, load, tileset switch).
var _history: LevelHistory = LevelHistory.new()


func _ready() -> void:
	# 1. Resolve nodes
	if grid == null:
		grid = get_node_or_null("HexGrid") as HexGrid
	if grid == null:
		GameLogger.error("MapEditor", "HexGrid not found")
		return
	if grid.tile_map_layer == null:
		grid.tile_map_layer = grid.get_node_or_null("Terrain") as TileMapLayer
	if grid.vfx_overlay == null:
		grid.vfx_overlay = grid.get_node_or_null("VFXOverlay") as TileMapLayer

	if camera == null:
		camera = get_node_or_null("EditorCamera") as Camera2D

	_objects_overlay = _resolve(objects_overlay_path, "HexGrid/ObjectsOverlay")
	_spawners_overlay = _resolve(spawners_overlay_path, "HexGrid/SpawnersOverlay")
	_hover = _resolve(hover_highlight_path, "HexGrid/HoverHighlight")
	_delete = _resolve(delete_highlight_path, "HexGrid/DeleteHighlight")
	_floor_palette = _resolve(floor_palette_path, "HUD/FloorPalettePanel")
	_object_palette = _resolve(object_palette_path, "HUD/ObjectPalettePanel")
	_meta_panel = _resolve(meta_panel_path, "HUD/LevelMetaPanel")
	_confirm_modal = _resolve(confirm_modal_path, "HUD/ConfirmModal")
	_hotkey_overlay = _resolve(hotkey_overlay_path, "HUD/HotkeyOverlay") as Control

	# 2. Paint a default 25×25 canvas centered at origin so the user has a
	# starting surface. Map can grow anywhere up to ±MAP_HALF_LIMIT (500×500).
	grid.tile_map_layer.tile_set = GODMODE_TERRAIN
	if grid.vfx_overlay != null:
		grid.vfx_overlay.tile_set = GODMODE_TERRAIN
	for row in range(-INITIAL_CANVAS_HALF, INITIAL_CANVAS_HALF + 1):
		for col in range(-INITIAL_CANVAS_HALF, INITIAL_CANVAS_HALF + 1):
			grid.tile_map_layer.set_cell(
				Vector2i(col, row), INITIAL_SOURCE_ID, INITIAL_ATLAS_COORD)
	grid.initialize()
	# Mirror the painted cells into _level so Save reflects the default canvas.
	for cell: Vector2i in grid.tile_map_layer.get_used_cells():
		_level.floor_cells.append({
			"coord": cell,
			"source_id": grid.tile_map_layer.get_cell_source_id(cell),
			"atlas_coord": grid.tile_map_layer.get_cell_atlas_coords(cell),
		})

	# 3. Bind overlays
	if _objects_overlay != null and _objects_overlay.has_method("bind_registry"):
		_objects_overlay.bind_registry(grid.get_object_registry())
	# Center camera at origin so the user has a recognizable starting point.
	if camera != null and grid != null and grid.tile_map_layer != null:
		camera.position = grid.tile_map_layer.map_to_local(Vector2i.ZERO)

	# 4. Wire palettes / meta panel
	_wire_floor_palette()
	_wire_object_palette()
	_wire_meta_panel()

	# Pre-select the default floor tile so the user can immediately paint
	# without first clicking a palette button.
	set_mode_place_floor(INITIAL_SOURCE_ID, INITIAL_ATLAS_COORD)
	if _floor_palette != null and _floor_palette.has_method("select_tile"):
		_floor_palette.select_tile(INITIAL_SOURCE_ID, INITIAL_ATLAS_COORD)

	# 5. Autosave timer (recovery prompt deferred to step 7 once we know
	#    whether a queued level is taking precedence)
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = AUTOSAVE_DEBOUNCE_SEC
	_autosave_timer.timeout.connect(_do_autosave)
	add_child(_autosave_timer)

	# 6. Initial level baseline (empty until user paints)
	_set_clean()

	# 7. If we arrived here from a Back-to-Editor / queued path, load that
	# level on top of the initial canvas. Skip autosave recovery in this
	# case — the queued level is the explicit source of truth right now;
	# we don't want to nag about a stale __autosave__.json.
	if ActiveLevel.has_queued():
		var queued_path: String = ActiveLevel.consume()
		var loaded: LevelData = LevelSerializer.load_from(queued_path)
		if loaded != null:
			_apply_level(loaded)
			_set_clean()  # just-loaded state isn't yet a user edit
			GameLogger.info("MapEditor", "Resumed queued level: %s" % queued_path)
	else:
		_check_autosave_recovery.call_deferred()

	GameLogger.info("MapEditor", "ready. LMB=place/paint, RMB=delete (2-step), Erase from FloorPalette")


func _resolve(path: NodePath, fallback: String) -> Node:
	var n: Node = null
	if not path.is_empty():
		n = get_node_or_null(path)
	if n == null:
		n = get_node_or_null(fallback)
	return n


# ── Initial canvas / level state ────────────────────────────────────────────

# Empty canvas at startup — _level.tileset_path defaults to godmode in
# LevelData. Old _rebuild_level_floor_from_canvas / _tileset_path_for helpers
# were dropped along with the 25×25 initial paint; if a future "import current
# tileset" feature needs them, restore from git history.


func _center_camera() -> void:
	if camera == null or grid == null or grid.tile_map_layer == null:
		return
	# Average position of all painted cells
	var cells: Array[Vector2i] = grid.tile_map_layer.get_used_cells()
	if cells.is_empty():
		return
	var sum := Vector2.ZERO
	for c in cells:
		sum += grid.tile_map_layer.map_to_local(c)
	camera.position = sum / cells.size()


# ── Mode setters (called by palettes) ───────────────────────────────────────

func set_mode_idle() -> void:
	_mode = Mode.IDLE
	_clear_pending_delete()


func set_mode_place_floor(source_id: int, atlas_coord: Vector2i) -> void:
	_mode = Mode.PLACING_FLOOR
	_placing_source_id = source_id
	_placing_atlas_coord = atlas_coord
	_clear_pending_delete()


func set_mode_erase_floor() -> void:
	_mode = Mode.ERASING_FLOOR
	_clear_pending_delete()


func set_mode_place_object(object_id: StringName) -> void:
	_mode = Mode.PLACING_OBJECT
	_placing_object_id = object_id
	_clear_pending_delete()


func set_mode_place_spawner(kind: StringName, ref: StringName) -> void:
	_mode = Mode.PLACING_SPAWNER
	_placing_spawner_kind = kind
	_placing_spawner_ref = ref
	_clear_pending_delete()


func get_level() -> LevelData:
	return _level


# ── Input ───────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		_handle_key_event(event as InputEventKey)
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var coord: Vector2i = grid.coord_under_mouse_raw() if grid != null else Vector2i(-1, -1)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Alt+LMB → eyedropper (T-17). No drag, no history.
				if mb.alt_pressed:
					if coord != Vector2i(-1, -1):
						_eyedropper(coord)
					get_viewport().set_input_as_handled()
					return
				_lmb_held = true
				_last_paint_coord = Vector2i(-1, -1)
				_history.begin_transaction(_level)
				if coord != Vector2i(-1, -1):
					_handle_lmb(coord)
					_last_paint_coord = coord
				get_viewport().set_input_as_handled()
			else:
				if _lmb_held:
					_lmb_held = false
					_history.end_transaction(_level)
					_last_paint_coord = Vector2i(-1, -1)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if coord == Vector2i(-1, -1):
				return
			_handle_rmb(coord)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _lmb_held:
		if not _is_drag_paint_mode():
			return
		var coord: Vector2i = grid.coord_under_mouse_raw() if grid != null else Vector2i(-1, -1)
		if coord == Vector2i(-1, -1):
			return
		if coord != _last_paint_coord:
			_paint_at(coord)
			_last_paint_coord = coord


## Drag-paint allowed for placing-floor / erasing / placing-object / placing
## non-player spawner. Player spawner is a singleton — no drag.
func _is_drag_paint_mode() -> bool:
	match _mode:
		Mode.PLACING_FLOOR, Mode.ERASING_FLOOR, Mode.PLACING_OBJECT:
			return true
		Mode.PLACING_SPAWNER:
			return _placing_spawner_kind != &"player"
		_:
			return false


## Editor shortcuts. Captured here (not via Input map) because they're
## editor-scoped — godmode arena defines its own bindings and we don't want
## a global conflict.
func _handle_key_event(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	# Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z — undo/redo (T-10)
	if event.ctrl_pressed and event.keycode == KEY_Z:
		if event.shift_pressed:
			_perform_redo()
		else:
			_perform_undo()
		get_viewport().set_input_as_handled()
		return
	if event.ctrl_pressed and event.keycode == KEY_Y:
		_perform_redo()
		get_viewport().set_input_as_handled()
		return
	# Ctrl+S — save (T-11)
	if event.ctrl_pressed and event.keycode == KEY_S:
		_on_save_requested()
		get_viewport().set_input_as_handled()
		return
	# 1-9 — quick palette select (T-19). Bare digits only (no Ctrl/Alt/Shift)
	# so we don't clash with future shortcuts.
	if not event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			_quick_select(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
			return
		# H — toggle hotkey cheatsheet overlay (T-23)
		if event.keycode == KEY_H:
			if _hotkey_overlay != null:
				_hotkey_overlay.visible = not _hotkey_overlay.visible
			get_viewport().set_input_as_handled()
			return


## Eyedropper (T-16): under cursor — pick spawner > object > floor (in that
## priority). The matching palette button is toggled programmatically, which
## emits the usual signal and switches the controller into the right mode.
func _eyedropper(coord: Vector2i) -> void:
	# Spawner first (rendered over object/floor visually, semantically "on top").
	for s in _level.spawners:
		if s.coord == coord:
			if _object_palette != null and _object_palette.has_method("select_spawner"):
				_object_palette.select_spawner(s.kind, s.ref)
			return
	# Object next.
	for o in _level.objects:
		if o.coord == coord:
			if _object_palette != null and _object_palette.has_method("select_object"):
				_object_palette.select_object(o.object_id)
			return
	# Floor last.
	for f in _level.floor_cells:
		if f.coord == coord:
			if _floor_palette != null and _floor_palette.has_method("select_tile"):
				_floor_palette.select_tile(f.source_id, f.atlas_coord)
			return
	# Empty hex — no-op (don't switch mode).


## Quick palette select (T-19): route to the palette matching current mode.
## Floor / Erase / Idle → floor palette. Object / Spawner → object palette.
func _quick_select(idx: int) -> void:
	match _mode:
		Mode.PLACING_OBJECT, Mode.PLACING_SPAWNER:
			if _object_palette != null and _object_palette.has_method("select_nth"):
				_object_palette.select_nth(idx)
		_:
			if _floor_palette != null and _floor_palette.has_method("select_nth"):
				_floor_palette.select_nth(idx)


func _perform_undo() -> void:
	if not _history.can_undo():
		EventBus.ui_toast_requested.emit("Нечего отменять", 1.0, &"info")
		return
	var restored: LevelData = _history.undo(_level)
	_apply_level(restored, false)
	_mark_dirty()
	EventBus.ui_toast_requested.emit("Undo", 0.6, &"info")


func _perform_redo() -> void:
	if not _history.can_redo():
		EventBus.ui_toast_requested.emit("Нечего повторять", 1.0, &"info")
		return
	var restored: LevelData = _history.redo(_level)
	_apply_level(restored, false)
	_mark_dirty()
	EventBus.ui_toast_requested.emit("Redo", 0.6, &"info")


# ── LMB — placement table ───────────────────────────────────────────────────

func _handle_lmb(coord: Vector2i) -> void:
	# LMB always cancels pending delete (regardless of mode).
	_clear_pending_delete()
	_paint_at(coord)


## Pure paint operation — no input-side-effects (pending-delete clear, etc.).
## Safe to call multiple times during a drag-paint without retriggering them.
func _paint_at(coord: Vector2i) -> void:
	match _mode:
		Mode.IDLE:
			pass  # drag-existing is P3 stretch (T019)
		Mode.PLACING_FLOOR:
			_place_floor(coord, _placing_source_id, _placing_atlas_coord)
		Mode.ERASING_FLOOR:
			_erase_floor(coord)
		Mode.PLACING_OBJECT:
			_place_object(coord, _placing_object_id)
		Mode.PLACING_SPAWNER:
			_place_spawner(coord, _placing_spawner_kind, _placing_spawner_ref)


func _place_floor(coord: Vector2i, source_id: int, atlas: Vector2i) -> void:
	# Floor placement always allowed — overwrites whatever was there. Object
	# and spawner stay (per plan.md table). Empty hex → painted.
	grid.tile_map_layer.set_cell(coord, source_id, atlas)
	# Update level model — replace existing floor entry or append.
	var found: bool = false
	for entry in _level.floor_cells:
		if entry.coord == coord:
			entry.source_id = source_id
			entry.atlas_coord = atlas
			found = true
			break
	if not found:
		_level.floor_cells.append({
			"coord": coord, "source_id": source_id, "atlas_coord": atlas})
	_mark_dirty()


func _erase_floor(coord: Vector2i) -> void:
	grid.tile_map_layer.erase_cell(coord)
	# Remove floor entry + any object/spawner on it. Build a typed Array in
	# place rather than .filter() (which returns untyped Array and would
	# trip the Array[Dictionary] type assignment at runtime in Godot 4).
	var kept_floor: Array[Dictionary] = []
	for f in _level.floor_cells:
		if f.coord != coord:
			kept_floor.append(f)
	_level.floor_cells = kept_floor
	_remove_object_at(coord)
	_remove_spawner_at(coord)
	_mark_dirty()


func _place_object(coord: Vector2i, object_id: StringName) -> void:
	if not _is_floor_painted(coord):
		_emit_occupied_toast("Сначала нарисуй пол")
		return
	if _has_object_at(coord) or _has_spawner_at(coord):
		_emit_occupied_toast("Занято")
		return
	_level.objects.append({"coord": coord, "object_id": object_id})
	if _objects_overlay != null and _objects_overlay.has_method("set_object"):
		_objects_overlay.set_object(coord, object_id)
	_mark_dirty()


func _place_spawner(coord: Vector2i, kind: StringName, ref: StringName) -> void:
	if not _is_floor_painted(coord):
		_emit_occupied_toast("Сначала нарисуй пол")
		return
	# Player spawner is a singleton — placing while one exists fades the old
	# out. Other collisions (object, enemy) → silent reject (toast).
	if kind == &"player":
		var existing_player_coord: Vector2i = _find_player_spawner()
		if existing_player_coord != Vector2i(-1, -1):
			# Same coord? No-op.
			if existing_player_coord == coord:
				return
			_remove_spawner_at(existing_player_coord)
		# Even player spawner can't go on top of an object or enemy.
		if _has_object_at(coord) or _has_spawner_at(coord):
			_emit_occupied_toast("Занято")
			return
	else:
		if _has_object_at(coord) or _has_spawner_at(coord):
			_emit_occupied_toast("Занято")
			return
	_level.spawners.append({"coord": coord, "kind": kind, "ref": ref})
	if _spawners_overlay != null and _spawners_overlay.has_method("set_spawner"):
		_spawners_overlay.set_spawner(coord, kind, ref)
	_mark_dirty()


# ── RMB — pending delete ────────────────────────────────────────────────────

func _handle_rmb(coord: Vector2i) -> void:
	if _delete == null:
		return
	if not _delete.has_coord():
		_delete.set_coord(coord)
		return
	if _delete.get_coord() == coord:
		_execute_delete(coord)
		_delete.clear()
		return
	# Different coord — re-mark
	_delete.set_coord(coord)


func _execute_delete(coord: Vector2i) -> void:
	# Priority: spawner > object > floor (matches plan.md RMB table)
	_history.push(_level)
	if _has_spawner_at(coord):
		_remove_spawner_at(coord)
	elif _has_object_at(coord):
		_remove_object_at(coord)
	else:
		_erase_floor(coord)
		return  # _erase_floor already called _mark_dirty
	_mark_dirty()


func _clear_pending_delete() -> void:
	if _delete != null:
		_delete.clear()


# ── Helpers ─────────────────────────────────────────────────────────────────

func _is_floor_painted(coord: Vector2i) -> bool:
	for f in _level.floor_cells:
		if f.coord == coord:
			return true
	return false


func _has_object_at(coord: Vector2i) -> bool:
	for o in _level.objects:
		if o.coord == coord:
			return true
	return false


func _has_spawner_at(coord: Vector2i) -> bool:
	for s in _level.spawners:
		if s.coord == coord:
			return true
	return false


func _find_player_spawner() -> Vector2i:
	for s in _level.spawners:
		if s.kind == &"player":
			return s.coord
	return Vector2i(-1, -1)


func _remove_object_at(coord: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for o in _level.objects:
		if o.coord != coord:
			kept.append(o)
	_level.objects = kept
	if _objects_overlay != null and _objects_overlay.has_method("clear_object"):
		_objects_overlay.clear_object(coord)


func _remove_spawner_at(coord: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for s in _level.spawners:
		if s.coord != coord:
			kept.append(s)
	_level.spawners = kept
	if _spawners_overlay != null and _spawners_overlay.has_method("clear_spawner"):
		_spawners_overlay.clear_spawner(coord)


## Silent-reject feedback. Single toast per ~800ms window — during drag-paint
## across occupied cells we don't want a stream of warnings, just the first one.
func _emit_occupied_toast(text: String) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms < _occupied_toast_until_msec:
		return
	_occupied_toast_until_msec = now_ms + 800
	EventBus.ui_toast_requested.emit(text, 1.0, &"info")


# ── Dirty / autosave ────────────────────────────────────────────────────────

func _mark_dirty() -> void:
	_dirty = true
	if _meta_panel != null and _meta_panel.has_method("set_dirty"):
		_meta_panel.set_dirty(true)
	if _autosave_timer != null:
		_autosave_timer.start()  # restart debounce countdown


## Counterpart to _mark_dirty — clear dirty state and update meta panel.
## Called after successful Save and just-loaded levels (both = on-disk = clean).
func _set_clean() -> void:
	_dirty = false
	if _meta_panel != null and _meta_panel.has_method("set_dirty"):
		_meta_panel.set_dirty(false)


func _do_autosave() -> void:
	# No validate, no toast — autosave is best-effort persistence.
	LevelSerializer.save(_level, AUTOSAVE_PATH)


func _check_autosave_recovery() -> void:
	if not FileAccess.file_exists(AUTOSAVE_PATH):
		return
	var modified: int = int(FileAccess.get_modified_time(AUTOSAVE_PATH))
	var age: int = int(Time.get_unix_time_from_system()) - modified
	if age > AUTOSAVE_MAX_AGE_SEC:
		DirAccess.remove_absolute(AUTOSAVE_PATH)
		return
	if _confirm_modal == null or not _confirm_modal.has_method("ask"):
		return
	var ok: bool = await _confirm_modal.ask(
		"Восстановить?",
		"Найдена несохранённая сессия редактора. Восстановить её?",
		"Восстановить", "Начать с нуля", false)
	if ok:
		var loaded: LevelData = LevelSerializer.load_from(AUTOSAVE_PATH)
		if loaded != null:
			_apply_level(loaded)
			_mark_dirty()  # restored — needs re-saving
			EventBus.ui_toast_requested.emit("Восстановлено", 1.5, &"success")
	else:
		DirAccess.remove_absolute(AUTOSAVE_PATH)


# ── Apply a loaded LevelData to the editor ──────────────────────────────────

func _apply_level(level: LevelData, recenter_camera: bool = true) -> void:
	_level = level
	# Re-paint floor to match new level
	if level.tileset_path != "":
		var ts: TileSet = load(level.tileset_path) as TileSet
		if ts != null:
			grid.tile_map_layer.tile_set = ts
			if grid.vfx_overlay != null:
				grid.vfx_overlay.tile_set = ts
	grid.tile_map_layer.clear()
	for cell in level.floor_cells:
		grid.tile_map_layer.set_cell(cell.coord, cell.source_id, cell.atlas_coord)
	# Re-init grid so HexTile data is fresh
	grid.initialize()
	if _objects_overlay != null and _objects_overlay.has_method("bind_registry"):
		_objects_overlay.bind_registry(grid.get_object_registry())
	# Repaint overlays
	if _objects_overlay != null:
		_objects_overlay.clear_all()
	if _spawners_overlay != null:
		_spawners_overlay.clear_all()
	for o in level.objects:
		_objects_overlay.set_object(o.coord, o.object_id)
	for s in level.spawners:
		_spawners_overlay.set_spawner(s.coord, s.kind, s.ref)
	# Update meta panel name field if present
	if _meta_panel != null and _meta_panel.has_method("set_level_name"):
		_meta_panel.set_level_name(level.name)
	# Camera recenter is opt-in — load/queued-resume want it (user expects
	# the new map in view), but undo/redo do NOT (we already see the map and
	# a jump on every Ctrl+Z is jarring).
	if recenter_camera:
		_center_camera()


# ── Wiring stubs (palettes/meta panel signal hookup) ────────────────────────

func _wire_floor_palette() -> void:
	if _floor_palette == null:
		return
	if _floor_palette.has_method("setup"):
		_floor_palette.setup(self)
	if _floor_palette.has_signal("tile_picked"):
		_floor_palette.tile_picked.connect(_on_floor_tile_picked)
	if _floor_palette.has_signal("erase_picked"):
		_floor_palette.erase_picked.connect(_on_erase_picked)
	if _floor_palette.has_signal("tileset_changed"):
		_floor_palette.tileset_changed.connect(_on_tileset_changed)
	if _floor_palette.has_signal("replace_all_requested"):
		_floor_palette.replace_all_requested.connect(_on_replace_all_requested)


func _wire_object_palette() -> void:
	if _object_palette == null:
		return
	if _object_palette.has_method("setup"):
		_object_palette.setup(self, grid.get_object_registry())
	if _object_palette.has_signal("object_picked"):
		_object_palette.object_picked.connect(_on_object_picked)
	if _object_palette.has_signal("spawner_picked"):
		_object_palette.spawner_picked.connect(_on_spawner_picked)


func _wire_meta_panel() -> void:
	if _meta_panel == null:
		return
	if _meta_panel.has_method("setup"):
		_meta_panel.setup(self)
	if _meta_panel.has_signal("save_requested"):
		_meta_panel.save_requested.connect(_on_save_requested)
	if _meta_panel.has_signal("load_requested"):
		_meta_panel.load_requested.connect(_on_load_requested)
	if _meta_panel.has_signal("playtest_requested"):
		_meta_panel.playtest_requested.connect(_on_playtest_requested)
	if _meta_panel.has_signal("exit_requested"):
		_meta_panel.exit_requested.connect(_on_exit_requested)
	if _meta_panel.has_signal("name_changed"):
		_meta_panel.name_changed.connect(_on_name_changed)


# ── Palette signal handlers ────────────────────────────────────────────────

func _on_floor_tile_picked(source_id: int, atlas: Vector2i) -> void:
	set_mode_place_floor(source_id, atlas)


func _on_erase_picked() -> void:
	set_mode_erase_floor()


func _on_tileset_changed(tileset_path: String) -> void:
	var ts: TileSet = load(tileset_path) as TileSet
	if ts == null:
		EventBus.ui_toast_requested.emit("Tileset не найден: %s" % tileset_path, 2.0, &"error")
		return
	_history.push(_level)
	grid.tile_map_layer.tile_set = ts
	if grid.vfx_overlay != null:
		grid.vfx_overlay.tile_set = ts
	_level.tileset_path = tileset_path
	_mark_dirty()


func _on_replace_all_requested(from_source: int, from_atlas: Vector2i,
		to_source: int, to_atlas: Vector2i) -> void:
	apply_replace_all(from_source, from_atlas, to_source, to_atlas)


## Public — used by FloorPalette's replace-all flow.
func apply_replace_all(from_source: int, from_atlas: Vector2i,
		to_source: int, to_atlas: Vector2i) -> void:
	# Pre-count so we don't push a no-op snapshot to the undo stack.
	var count: int = 0
	for entry in _level.floor_cells:
		if entry.source_id == from_source and entry.atlas_coord == from_atlas:
			count += 1
	if count == 0:
		EventBus.ui_toast_requested.emit("Нечего заменять", 1.5, &"info")
		return
	_history.push(_level)
	for entry in _level.floor_cells:
		if entry.source_id == from_source and entry.atlas_coord == from_atlas:
			entry.source_id = to_source
			entry.atlas_coord = to_atlas
			grid.tile_map_layer.set_cell(entry.coord, to_source, to_atlas)
	EventBus.ui_toast_requested.emit("Заменено %d тайлов" % count, 2.0, &"success")
	_mark_dirty()


func _on_object_picked(object_id: StringName) -> void:
	set_mode_place_object(object_id)


func _on_spawner_picked(kind: StringName, ref: StringName) -> void:
	set_mode_place_spawner(kind, ref)


func _on_name_changed(new_name: String) -> void:
	_level.name = new_name
	_mark_dirty()


# ── Save / Load / Playtest / Exit ───────────────────────────────────────────

func _on_save_requested() -> void:
	var errors: Array[String] = _level.validate()
	if not errors.is_empty():
		var msg: String = errors[0] if errors.size() == 1 else "%d ошибок: %s" % [errors.size(), errors[0]]
		EventBus.ui_toast_requested.emit(msg, 2.5, &"warn")
		return
	var sanitized: String = _sanitize_filename(_level.name)
	if sanitized == "__autosave__" or sanitized == "__playtest__":
		EventBus.ui_toast_requested.emit("Имя зарезервировано", 2.0, &"warn")
		return
	var path: String = MAPS_DIR + sanitized + ".json"
	if FileAccess.file_exists(path) and _confirm_modal != null:
		var ok: bool = await _confirm_modal.ask(
			"Перезаписать?", "Файл %s уже существует." % (sanitized + ".json"),
			"Перезаписать", "Отмена", true)
		if not ok:
			return
	if LevelSerializer.save(_level, path):
		_set_clean()
		EventBus.ui_toast_requested.emit("Сохранено: %s" % (sanitized + ".json"), 2.0, &"success")
	else:
		EventBus.ui_toast_requested.emit("Ошибка сохранения", 2.0, &"error")


func _on_load_requested(path: String) -> void:
	if path == "":
		return
	if _dirty and _confirm_modal != null:
		var save_first: bool = await _confirm_modal.ask(
			"Сохранить текущую карту?",
			"У вас есть несохранённые изменения.",
			"Сохранить", "Не сохранять", false)
		if save_first:
			_on_save_requested()
	var loaded: LevelData = LevelSerializer.load_from(path)
	if loaded == null:
		EventBus.ui_toast_requested.emit("Ошибка загрузки", 2.0, &"error")
		return
	_history.push(_level)
	_apply_level(loaded)
	_set_clean()
	EventBus.ui_toast_requested.emit("Загружено: %s" % path.get_file(), 2.0, &"success")


func _on_playtest_requested() -> void:
	var errors: Array[String] = _level.validate()
	if not errors.is_empty():
		EventBus.ui_toast_requested.emit(errors[0], 2.5, &"warn")
		return
	if not LevelSerializer.save(_level, PLAYTEST_PATH):
		EventBus.ui_toast_requested.emit("Не удалось записать playtest", 2.0, &"error")
		return
	# Mark origin so the playtest scene can offer Back-to-Editor; queue the
	# same path so godmode loads it on _ready.
	ActiveLevel.mark_playtest(PLAYTEST_PATH)
	ActiveLevel.queue(PLAYTEST_PATH)
	get_tree().change_scene_to_file(GODMODE_SCENE)


func _on_exit_requested() -> void:
	if _dirty and _confirm_modal != null:
		var leave: bool = await _confirm_modal.ask(
			"Выйти?", "Есть несохранённые изменения.",
			"Выйти без сохранения", "Остаться", true)
		if not leave:
			return
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


static func _sanitize_filename(s: String) -> String:
	var lower := s.to_lower().strip_edges()
	var out := ""
	for i in lower.length():
		var c: String = lower[i]
		var ok := false
		if c >= "a" and c <= "z":
			ok = true
		elif c >= "0" and c <= "9":
			ok = true
		elif c == "_" or c == "-":
			ok = true
		out += c if ok else "_"
	# Trim leading underscores
	while out.begins_with("_"):
		out = out.substr(1)
	if out == "":
		out = "untitled"
	return out
