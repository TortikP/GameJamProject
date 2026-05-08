class_name InputDispatcher
extends RefCounted

## Centralized input pipeline for the level editor. Receives InputEvents
## from EditorController._unhandled_input, decides if the event triggers
## a paint/erase action, and dispatches via the controller's narrow API
## (paint_floor / erase_floor).
##
## ## Drag semantics
##
## LMB-down → start PAINTING, paint at coord_under_mouse.
## LMB-drag → paint at every NEW coord the cursor enters (anti-dup).
## LMB-up   → end drag.
## RMB → mirror, but ERASING.
##
## When active selection is the erase sentinel, LMB-paint becomes erase
## too — selecting Erase + clicking is the convenient erase shortcut.
##
## ## Anti-dup
##
## Held cursor over a single hex during a drag must not re-trigger the
## action every motion event. We track _last_painted_coord; if the
## resolved coord equals it, the motion is dropped. NO_COORD is the
## sentinel for "no coord painted yet in this drag".
##
## ## DI
##
## RefCounted with constructor injection — no Node lifecycle, no signals,
## no _input wiring at all (controller calls handle() explicitly). The
## controller field is intentionally untyped to avoid a circular
## class_name reference (controller has no class_name on purpose).

const NO_COORD := Vector2i(-99999, -99999)

enum DragState { NONE, PAINTING, ERASING }

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
		var ke: InputEventKey = event as InputEventKey
		if ke.keycode == KEY_ESCAPE:
			_drag_state = DragState.NONE
			_last_painted_coord = NO_COORD
			return true
	return false


func _handle_mouse_button(mb: InputEventMouseButton) -> bool:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_state = DragState.PAINTING
			_act_at(_grid.coord_under_mouse(), false)
		else:
			_drag_state = DragState.NONE
			_last_painted_coord = NO_COORD
		return true
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			_drag_state = DragState.ERASING
			_act_at(_grid.coord_under_mouse(), true)
		else:
			_drag_state = DragState.NONE
			_last_painted_coord = NO_COORD
		return true
	return false


func _handle_mouse_drag(_mm: InputEventMouseMotion) -> bool:
	var coord := _grid.coord_under_mouse()
	if coord == _last_painted_coord:
		return false
	_act_at(coord, _drag_state == DragState.ERASING)
	return true


## Single dispatch point: erase if explicitly requested (RMB) or if
## the active selection is the erase sentinel (LMB+Erase shortcut);
## otherwise paint with the current Dictionary selection.
##
## Always updates _last_painted_coord — even on no-op exits, so that
## holding RMB over a coord that has nothing to erase doesn't re-trigger
## the controller call every motion event in the same hex.
func _act_at(coord: Vector2i, erase: bool) -> void:
	if erase or _layers.is_erase():
		_controller.erase_floor(coord)
		_last_painted_coord = coord
		return
	var sel: Variant = _layers.get_active_selection()
	if typeof(sel) != TYPE_DICTIONARY:
		# No tile selected (initial state). Don't paint, but still
		# record the coord so we don't spam this branch every motion.
		_last_painted_coord = coord
		return
	var d: Dictionary = sel as Dictionary
	var atlas: Vector2i = d["atlas_coord"]
	_controller.paint_floor(coord, int(d["source_id"]), atlas)
	_last_painted_coord = coord
