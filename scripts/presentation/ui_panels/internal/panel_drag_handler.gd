## PanelDragHandler — drag behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Listens to gui_input on the drag handle (HeaderPanel) for LMB-press,
## then to global _input for motion/release so the drag survives the
## cursor leaving the handle's rect (and even leaving the window briefly).
##
## Cursor is set on HeaderPanel itself via mouse_default_cursor_shape
## (CURSOR_MOVE) in base_panel.tscn. Native Godot handling — no
## DisplayServer.cursor_set_shape tricks.
##
## On begin: switches anchors to PRESET_TOP_LEFT (keep_offsets=true) so
## the panel's global_position becomes absolute. Subsequent motion writes
## to _base_panel.global_position then move it directly, with no
## container layout fights.
##
## C2 (cant-lose-UI): the panel's HEADER must remain entirely inside
## the viewport. Body may spill past edges — only the drag handle
## (which is the only way to move the panel) is gated.

class_name PanelDragHandler
extends Node

var _base_panel: BasePanel
var _drag_handle: Control

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


func setup(base_panel: BasePanel, drag_handle: Control) -> void:
	_base_panel = base_panel
	_drag_handle = drag_handle
	if not _drag_handle.gui_input.is_connected(_on_handle_gui_input):
		_drag_handle.gui_input.connect(_on_handle_gui_input)


func _on_handle_gui_input(event: InputEvent) -> void:
	# is_draggable() returns the EFFECTIVE flag — Phases 4-5 fold in
	# lock state and header_visible cascade. Handler stays passive
	# automatically when locked or when header hidden.
	if not _base_panel.is_draggable():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_drag(mb.global_position)
			_drag_handle.accept_event()


func _begin_drag(mouse_global: Vector2) -> void:
	_is_dragging = true
	_base_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	_drag_offset = _base_panel.global_position - mouse_global


func _input(event: InputEvent) -> void:
	if not _is_dragging:
		return
	if event is InputEventMouseMotion:
		_do_drag((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_is_dragging = false


func _do_drag(mouse_global: Vector2) -> void:
	var new_pos := mouse_global + _drag_offset
	new_pos = _clamp_header_to_viewport(new_pos)
	_base_panel.global_position = new_pos
	_base_panel.panel_moved.emit(new_pos)


func _clamp_header_to_viewport(pos: Vector2) -> Vector2:
	# C2: header must stay entirely inside the viewport. Header rect at
	# the top of the panel = (panel.x, panel.y) to (panel.x + panel_width,
	# panel.y + header_height). header_height equals BasePanel.CORNER_SIZE
	# (header strip and corner zones share the same height by design).
	var viewport_size := _base_panel.get_viewport_rect().size
	var panel_width := _base_panel.size.x
	var header_height := float(BasePanel.CORNER_SIZE)
	pos.x = clamp(pos.x, 0.0, max(0.0, viewport_size.x - panel_width))
	pos.y = clamp(pos.y, 0.0, max(0.0, viewport_size.y - header_height))
	return pos
