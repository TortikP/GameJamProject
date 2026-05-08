## PanelResizeHandler — resize behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Connects to the 10 Control handles inside ResizeFrame (8 logical
## edges/corners; top corners are split into _H + _V arms — see
## HANDLE_DIRS docstring below). Each handle is a Control with:
##   - mouse_default_cursor_shape set per direction in tscn
##     (FDIAGSIZE / BDIAGSIZE / VSIZE / HSIZE) — Godot's native cursor
##     handling on hover, no DisplayServer tricks.
##   - mouse_filter = STOP captures clicks reliably.
##   - No drawing — Control has no body, only a hit rect; nothing
##     visible to the user (cursor change on hover is the only feedback).
##   - anchors+offsets in tscn place each rect at the correct corner /
##     edge zone (see base_panel.gd geometry constants).
##
## On click: gui_input fires with our connected callback (bound with
## the handle's direction vector); we capture initial state and listen
## to global _input for motion/release until button-up.
##
## Anchors normalization is BasePanel's responsibility (see
## BasePanel._normalize_anchors_to_top_left() — runs once in _ready).
## The handler assumes TOP_LEFT anchors with END/END grow_direction so
## size/global_position writes are absolute.

class_name PanelResizeHandler
extends Node

## Handle name → resize direction sign vector.
##   dx, dy ∈ {-1, 0, 1}: -1 → that edge follows cursor (origin shifts);
##   1 → that edge follows cursor outward (size grows); 0 → unaffected.
##
## Top corners are split into horizontal (_H) and vertical (_V) arms so
## their hit zones form an L-shape outside the panel and don't overlap
## with LockButton / CollapseButton (which sit at the same corners).
## Bottom corners stay as single 44×44 Control rects — no header buttons
## there, no input contention. Both arms of a top corner emit the same
## diagonal direction vector, so dragging either resizes diagonally.
const HANDLE_DIRS := {
	&"TopLeft_H":   Vector2i(-1, -1),
	&"TopLeft_V":   Vector2i(-1, -1),
	&"Top":         Vector2i( 0, -1),
	&"TopRight_H":  Vector2i( 1, -1),
	&"TopRight_V":  Vector2i( 1, -1),
	&"Right":       Vector2i( 1,  0),
	&"BottomRight": Vector2i( 1,  1),
	&"Bottom":      Vector2i( 0,  1),
	&"BottomLeft":  Vector2i(-1,  1),
	&"Left":        Vector2i(-1,  0),
}

var _base_panel: BasePanel
var _resize_frame: Control

var _is_resizing: bool = false
var _active_dir: Vector2i = Vector2i.ZERO
var _initial_mouse: Vector2
var _initial_size: Vector2
var _initial_pos: Vector2


func setup(base_panel: BasePanel) -> void:
	_base_panel = base_panel
	_resize_frame = base_panel.get_node_or_null("ResizeFrame") as Control
	# This setup is only called when base_panel.is_resizable() is true
	# (gated by BasePanel._setup_handlers). When resize is disabled the
	# whole handler isn't created and BasePanel hides ResizeFrame itself.
	# Lock state is checked separately at input time AND via
	# locked_changed signal here — when locked, hide the whole
	# ResizeFrame so handles don't change cursor on hover.
	for handle_name in HANDLE_DIRS.keys():
		var path := "ResizeFrame/" + String(handle_name)
		var handle := base_panel.get_node_or_null(path) as Control
		if handle == null:
			push_warning("[PanelResizeHandler] missing handle node: %s" % path)
			continue
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		var dir: Vector2i = HANDLE_DIRS[handle_name]
		handle.gui_input.connect(_on_handle_gui_input.bind(dir))

	if not base_panel.locked_changed.is_connected(_on_locked_changed):
		base_panel.locked_changed.connect(_on_locked_changed)


func _on_locked_changed(locked: bool) -> void:
	# Hide entire ResizeFrame on lock so cursor doesn't change on hover.
	# Collapse handler also hides ResizeFrame independently — when both
	# trigger simultaneously, last write wins, but both want
	# ResizeFrame.visible = false, so no conflict.
	if _resize_frame == null:
		return
	if locked:
		_resize_frame.visible = false
	else:
		# Don't blindly re-show — collapsed panels keep ResizeFrame hidden.
		_resize_frame.visible = not _base_panel.is_collapsed()


func _on_handle_gui_input(event: InputEvent, dir: Vector2i) -> void:
	if not _base_panel.is_resizable() or _base_panel.is_locked():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_resize(dir, mb.global_position)


func _begin_resize(dir: Vector2i, mouse_global: Vector2) -> void:
	_is_resizing = true
	_active_dir = dir
	_initial_mouse = mouse_global
	_initial_size = _base_panel.size
	_initial_pos = _base_panel.global_position
	# Anchors are already TOP_LEFT (normalized by BasePanel._ready()), so
	# size/global_position writes below are absolute.


func _input(event: InputEvent) -> void:
	if not _is_resizing:
		return
	if event is InputEventMouseMotion:
		_do_resize((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_is_resizing = false
			_active_dir = Vector2i.ZERO


func _do_resize(mouse_global: Vector2) -> void:
	var delta := mouse_global - _initial_mouse
	var new_size := _initial_size + Vector2(delta.x * _active_dir.x, delta.y * _active_dir.y)

	# C1 minimum size — never below export, and never below what the
	# header content actually requires.
	var min_size := _effective_min_size()
	new_size.x = max(new_size.x, min_size.x)
	new_size.y = max(new_size.y, min_size.y)

	# Top/Left edges shift the panel's origin so the OPPOSITE edge stays
	# anchored. Without this, dragging the top-left handle would drag
	# the whole panel around instead of resizing.
	var new_pos := _initial_pos
	if _active_dir.x == -1:
		new_pos.x = _initial_pos.x + (_initial_size.x - new_size.x)
	if _active_dir.y == -1:
		new_pos.y = _initial_pos.y + (_initial_size.y - new_size.y)

	_base_panel.global_position = new_pos
	_base_panel.size = new_size
	_base_panel.panel_resized.emit(new_size)


func _effective_min_size() -> Vector2:
	var exp_min := _base_panel.min_panel_size
	var header_min := Vector2.ZERO
	if _base_panel._header_panel != null:
		header_min = _base_panel._header_panel.get_combined_minimum_size()
	return Vector2(max(exp_min.x, header_min.x), max(exp_min.y, header_min.y))
