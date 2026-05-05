class_name DraggablePanel
extends Node
## DraggablePanel — tiny mixin Node. Add as child of a Control panel and call
## setup(panel, handle). The handle becomes a drag area; LMB-press on it grabs
## the panel, and subsequent motion (anywhere on screen) repositions the panel
## until LMB is released.
##
## On first drag the panel is detached from its layout anchors
## (PRESET_TOP_LEFT, current rect preserved) so subsequent layout
## invalidations don't snap it back to its original side. Position is clamped
## to the viewport so panels can't be dragged off-screen.
##
## Usage (inside the panel's _build_ui):
##     const DraggablePanel = preload("res://scripts/presentation/dev/draggable_panel.gd")
##     ...
##     var dragger := DraggablePanel.new()
##     add_child(dragger)
##     dragger.setup(self, header_label)

var _panel: Control
var _handle: Control
var _drag_offset: Vector2 = Vector2.ZERO
var _dragging: bool = false


func setup(panel: Control, handle: Control) -> void:
	_panel = panel
	_handle = handle
	# Labels default to MOUSE_FILTER_IGNORE, which kills gui_input. Force STOP
	# so the handle actually receives press events.
	handle.mouse_filter = Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	handle.gui_input.connect(_on_handle_input)


func _on_handle_input(event: InputEvent) -> void:
	# Only listen for press here. Release/motion are handled in _input below
	# so the drag survives the cursor leaving the handle area mid-drag.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_drag()
			_handle.accept_event()


func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_do_drag()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_dragging = false


func _begin_drag() -> void:
	if _panel == null:
		return
	var current := _panel.global_position
	# Detach from any layout anchor; preserve current screen position.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.global_position = current
	_drag_offset = _panel.get_global_mouse_position() - current
	_dragging = true


func _do_drag() -> void:
	if _panel == null:
		return
	var target := _panel.get_global_mouse_position() - _drag_offset
	var vp := _panel.get_viewport_rect()
	target.x = clamp(target.x, 0.0, max(0.0, vp.size.x - _panel.size.x))
	target.y = clamp(target.y, 0.0, max(0.0, vp.size.y - _panel.size.y))
	_panel.global_position = target
