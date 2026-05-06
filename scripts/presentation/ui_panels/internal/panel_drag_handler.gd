## PanelDragHandler — drag behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API. Listens
## to gui_input on the drag handle (typically HeaderPanel) for press,
## then to _input (global) for motion/release so the drag survives the
## cursor leaving the handle's rect.
##
## On begin: switches the panel's anchors to PRESET_TOP_LEFT with
## keep_offsets=true. This preserves visual position but makes
## subsequent global_position writes absolute (avoids container layout
## or anchor-based recalc fighting the drag).
##
## C2 (cant-lose-UI): the panel's HEADER is clamped to remain entirely
## inside the viewport. The body may spill past the viewport edge
## (useful for prying space at corners) but the header — which carries
## the drag affordance — never leaves the screen.

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
	if not _base_panel.is_draggable():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_drag(mb.global_position)
			_drag_handle.accept_event()


func _begin_drag(mouse_global: Vector2) -> void:
	_is_dragging = true
	# Switch to absolute positioning so global_position writes are stable.
	# keep_offsets=true preserves visual position across the anchor change.
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
			_end_drag()


func _do_drag(mouse_global: Vector2) -> void:
	var new_pos := mouse_global + _drag_offset
	new_pos = _clamp_header_to_viewport(new_pos)
	_base_panel.global_position = new_pos
	_base_panel.panel_moved.emit(new_pos)


func _clamp_header_to_viewport(pos: Vector2) -> Vector2:
	# C2: header rect must stay entirely inside the viewport.
	# Header sits at the top of the panel and spans its width, so:
	#   header rect = (panel.x, panel.y) -> (panel.x + panel.size.x, panel.y + header.size.y)
	var viewport_size := _base_panel.get_viewport_rect().size
	var panel_width := _base_panel.size.x
	var header_height := _drag_handle.size.y
	pos.x = clamp(pos.x, 0.0, max(0.0, viewport_size.x - panel_width))
	pos.y = clamp(pos.y, 0.0, max(0.0, viewport_size.y - header_height))
	return pos


func _end_drag() -> void:
	_is_dragging = false
