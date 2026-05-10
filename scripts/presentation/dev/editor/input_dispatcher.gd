class_name InputDispatcher
extends RefCounted

## Centralized input pipeline for the level editor. Receives InputEvents
## from EditorController._unhandled_input and dispatches via the
## controller's narrow API.
##
## ## Layered dispatch (060)
##
## LMB / RMB on a hex routes through _act_at, which branches on
## _layers.active_layer into paint_X / erase_X controller method.
## RMB erases the entity on the active layer (no priority chain).
## Shift+LMB / Shift+RMB → drag-cascade: wipes ALL layers on every
## hex visited (AC11 / spec.md §3.B). Erase-sentinel selection on
## hexes also makes LMB erase (059 convenience).
##
## Drag + anti-dup. LMB/RMB down → PAINTING/ERASING; Shift down →
## CASCADING. Drag → action per NEW coord (_last_painted_coord).
##
## ## Keyboard
##
## Q / W / E         direct layer pick (hexes / spawners / objects).
## Tab               cycle forward through LayersModel.LAYER_ORDER.
## 1..9              quick-select N-th button in active palette.
## Esc               cancel any active drag.
## F1 / ?            open HELP modal.
##
## All keyboard handlers no-op when focus is on a text input — checked
## via _controller.is_text_focused() so dispatcher needs no scene-tree
## access.
##
## ## DI
##
## RefCounted with constructor injection. Controller is intentionally
## untyped to avoid a circular class_name reference.

const NO_COORD := Vector2i(-99999, -99999)
const NO_HEX := Vector2i(-1, -1)  # HexGrid.coord_under_mouse_raw sentinel

enum DragState { NONE, PAINTING, ERASING, CASCADING }

var _controller: Variant  # EditorController (untyped — no class_name)
var _grid: HexGrid
var _layers: LayersModel

var _drag_state: int = DragState.NONE
var _last_painted_coord: Vector2i = NO_COORD


func _init(controller: Variant, grid: HexGrid, layers: LayersModel) -> void:
	_controller = controller
	_grid = grid
	_layers = layers


## Returns true when the event was consumed (controller should
## set_input_as_handled on viewport).
func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return _handle_mouse_button(event)
	if event is InputEventMouseMotion and _drag_state != DragState.NONE:
		return _handle_mouse_drag(event)
	if event is InputEventKey and event.pressed:
		return _handle_key(event as InputEventKey)
	return false


# ── Mouse ─────────────────────────────────────────────────────────

func _handle_mouse_button(mb: InputEventMouseButton) -> bool:
	var btn := mb.button_index
	if btn != MOUSE_BUTTON_LEFT and btn != MOUSE_BUTTON_RIGHT:
		return false
	if not mb.pressed:
		_drag_state = DragState.NONE
		_last_painted_coord = NO_COORD
		return true
	# Shift+LMB/RMB → drag-cascade (AC11 / Q-060-6).
	var coord := _grid.coord_under_mouse_raw()
	if mb.shift_pressed:
		_drag_state = DragState.CASCADING
		_cascade_at(coord)
	elif btn == MOUSE_BUTTON_LEFT:
		_drag_state = DragState.PAINTING
		_act_at(coord, false)
	else:
		_drag_state = DragState.ERASING
		_act_at(coord, true)
	return true


func _handle_mouse_drag(_mm: InputEventMouseMotion) -> bool:
	var coord := _grid.coord_under_mouse_raw()
	if coord == _last_painted_coord:
		return false
	if _drag_state == DragState.CASCADING:
		_cascade_at(coord)
	else:
		_act_at(coord, _drag_state == DragState.ERASING)
	return true


## Cascade helper — Shift+LMB/RMB down + CASCADING drag.
func _cascade_at(coord: Vector2i) -> void:
	if coord == NO_HEX:
		return
	if _controller.cascade_at(coord):
		_spawn_flash(coord)
	_last_painted_coord = coord


# ── Keyboard ──────────────────────────────────────────────────────

func _handle_key(ke: InputEventKey) -> bool:
	# Let LineEdit / TextEdit / SpinBox eat the event first — Q in the
	# level-name input must type 'q', not switch the active layer.
	if _controller.is_text_focused():
		return false
	match ke.keycode:
		KEY_ESCAPE:
			_drag_state = DragState.NONE
			_last_painted_coord = NO_COORD
			return true
		KEY_Q:
			_set_layer(LayersModel.LAYER_HEXES)
			return true
		KEY_W:
			_set_layer(LayersModel.LAYER_SPAWNERS)
			return true
		KEY_E:
			_set_layer(LayersModel.LAYER_OBJECTS)
			return true
		KEY_TAB:
			var next: StringName = _layers.cycle_active_forward()
			_controller.notify_active_layer_changed(next)
			return true
		KEY_F1, KEY_QUESTION:
			_controller.show_help()
			return true
	if ke.keycode >= KEY_1 and ke.keycode <= KEY_9:
		var n := ke.keycode - KEY_0
		_controller.quick_select_in_active_palette(n)
		return true
	return false


func _set_layer(layer_id: StringName) -> void:
	_layers.active_layer = layer_id
	_controller.notify_active_layer_changed(layer_id)


# ── Per-layer dispatch ────────────────────────────────────────────

## Single dispatch point. Branches on active layer; each branch decides
## paint vs erase from `erase` (RMB) ∪ LayersModel.is_erase() (hexes-only
## LMB+Erase shortcut). Always updates _last_painted_coord at the end —
## even on no-op exits — so holding LMB/RMB over a coord doesn't re-fire
## the action every motion event. Returns early on the (-1, -1) sentinel
## (cursor over HUD or beyond MAP_HALF_LIMIT).
func _act_at(coord: Vector2i, erase: bool) -> void:
	if coord == NO_HEX:
		return
	match _layers.active_layer:
		LayersModel.LAYER_HEXES:
			_act_hexes(coord, erase)
		LayersModel.LAYER_SPAWNERS:
			_act_spawners(coord, erase)
		LayersModel.LAYER_OBJECTS:
			_act_objects(coord, erase)
	_last_painted_coord = coord


func _act_hexes(coord: Vector2i, erase: bool) -> void:
	if erase or _layers.is_erase():
		if _controller.erase_floor(coord):
			_spawn_flash(coord)
		return
	var sel: Variant = _layers.get_active_selection()
	if typeof(sel) != TYPE_DICTIONARY:
		return  # No tile selected; silently no-op.
	var d: Dictionary = sel as Dictionary
	_controller.paint_floor(coord, int(d["source_id"]), d["atlas_coord"])


func _act_spawners(coord: Vector2i, erase: bool) -> void:
	if erase or _layers.is_erase():
		if _controller.erase_spawner(coord):
			_spawn_flash(coord)
		return
	var sel: Variant = _layers.get_active_selection()
	if typeof(sel) != TYPE_DICTIONARY:
		return
	var d: Dictionary = sel as Dictionary
	_controller.paint_spawner(coord, d["kind"], d["ref"],
		int(d.get("timer", LevelData.DEFAULT_SPAWNER_TIMER)))


func _act_objects(coord: Vector2i, erase: bool) -> void:
	if erase or _layers.is_erase():
		if _controller.erase_object(coord):
			_spawn_flash(coord)
		return
	var sel: Variant = _layers.get_active_selection()
	if typeof(sel) != TYPE_DICTIONARY:
		return
	var d: Dictionary = sel as Dictionary
	_controller.paint_object(coord, d["object_id"])


# ── Flash ─────────────────────────────────────────────────────────

## Spawn a delete-flash on a coord. Parent = HexGrid (Node2D) so the
## flash inherits world transform; grid supplies tile_map_layer for
## coord-to-local conversion and tile_size for polygon shape.
func _spawn_flash(coord: Vector2i) -> void:
	DeleteFlash.spawn_at(_grid, coord, _grid)
