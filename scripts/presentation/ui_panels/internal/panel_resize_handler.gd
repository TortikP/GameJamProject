## PanelResizeHandler — resize behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API. Wires
## the eight ResizeHandles children (TopLeft .. Left) into a uniform
## resize state machine.
##
## Each handle:
##   - has a per-direction cursor shape applied via mouse_default_cursor_shape
##   - fades in on mouse_entered (modulate.a 0 → 0.5) and out on exit
##   - on LMB-press, starts resize state with that handle's (dx, dy) direction
##
## During resize, mouse motion is read via _input (global) so the drag
## survives leaving the handle rect. On release, returns to NONE state.
##
## Anchor preset is switched to PRESET_TOP_LEFT (keep_offsets=true) on
## resize start — same reason as PanelDragHandler: writes to size and
## global_position become absolute, no container fights.
##
## C1: min size enforced via _base_panel.min_panel_size. Effective min
## takes max with HeaderPanel's combined minimum size so the panel can
## never be shrunk below its header content.

class_name PanelResizeHandler
extends Node

# Per-handle config: cursor + direction sign for x/y.
# dx/dy ∈ {-1, 0, 1}: -1 means dragging this side moves the corresponding
# panel edge to follow the cursor (top/left edges); 1 means the side
# follows the cursor outward (bottom/right edges); 0 means that axis
# is unaffected by this handle.
const HANDLES := {
	&"TopLeft":     {"cursor": Control.CURSOR_FDIAGSIZE, "dx": -1, "dy": -1},
	&"Top":         {"cursor": Control.CURSOR_VSIZE,     "dx":  0, "dy": -1},
	&"TopRight":    {"cursor": Control.CURSOR_BDIAGSIZE, "dx":  1, "dy": -1},
	&"Right":       {"cursor": Control.CURSOR_HSIZE,     "dx":  1, "dy":  0},
	&"BottomRight": {"cursor": Control.CURSOR_FDIAGSIZE, "dx":  1, "dy":  1},
	&"Bottom":      {"cursor": Control.CURSOR_VSIZE,     "dx":  0, "dy":  1},
	&"BottomLeft":  {"cursor": Control.CURSOR_BDIAGSIZE, "dx": -1, "dy":  1},
	&"Left":        {"cursor": Control.CURSOR_HSIZE,     "dx": -1, "dy":  0},
}

var _base_panel: BasePanel
var _handles_root: Control

var _is_resizing: bool = false
var _active_dx: int = 0
var _active_dy: int = 0
var _start_size: Vector2
var _start_pos: Vector2
var _start_mouse: Vector2


func setup(base_panel: BasePanel, handles_root: Control) -> void:
	_base_panel = base_panel
	_handles_root = handles_root
	for handle_name in HANDLES.keys():
		var handle := _handles_root.get_node_or_null(String(handle_name)) as Control
		if handle == null:
			push_warning("[PanelResizeHandler] missing handle: %s" % handle_name)
			continue
		var cfg: Dictionary = HANDLES[handle_name]
		handle.mouse_default_cursor_shape = cfg["cursor"]
		# Hover visibility — only fade in if resize is currently allowed.
		if not handle.mouse_entered.is_connected(_on_handle_entered):
			handle.mouse_entered.connect(_on_handle_entered.bind(handle))
		if not handle.mouse_exited.is_connected(_on_handle_exited):
			handle.mouse_exited.connect(_on_handle_exited.bind(handle))
		# Drag start.
		handle.gui_input.connect(_on_handle_gui_input.bind(handle_name))


func _on_handle_entered(handle: Control) -> void:
	if not _base_panel.is_resizable():
		return
	handle.modulate.a = 0.5


func _on_handle_exited(handle: Control) -> void:
	if _is_resizing:
		# Don't fade out during active resize even if cursor leaves the rect.
		return
	handle.modulate.a = 0.0


func _on_handle_gui_input(event: InputEvent, handle_name: StringName) -> void:
	if not _base_panel.is_resizable():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_resize(handle_name, mb.global_position)


func _begin_resize(handle_name: StringName, mouse_global: Vector2) -> void:
	_is_resizing = true
	var cfg: Dictionary = HANDLES[handle_name]
	_active_dx = cfg["dx"]
	_active_dy = cfg["dy"]
	_start_size = _base_panel.size
	_start_pos = _base_panel.global_position
	_start_mouse = mouse_global
	# Switch to absolute positioning — same rationale as drag handler.
	_base_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)


func _input(event: InputEvent) -> void:
	if not _is_resizing:
		return
	if event is InputEventMouseMotion:
		_do_resize((event as InputEventMouseMotion).global_position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_resize()


func _do_resize(mouse_global: Vector2) -> void:
	var delta := mouse_global - _start_mouse
	var new_size := _start_size
	var new_pos := _start_pos

	# Apply size delta along the active axes only.
	new_size.x = _start_size.x + delta.x * _active_dx
	new_size.y = _start_size.y + delta.y * _active_dy

	# C1: enforce minimum panel size, taking header's required width
	# into account so we never shrink past where the caption stops fitting.
	var min_size := _effective_min_size()
	new_size.x = max(new_size.x, min_size.x)
	new_size.y = max(new_size.y, min_size.y)

	# Top/left handles shift the panel's origin so that the OPPOSITE edge
	# stays anchored. Without this, dragging the top-left handle would
	# drag the whole panel around.
	if _active_dx == -1:
		new_pos.x = _start_pos.x + (_start_size.x - new_size.x)
	if _active_dy == -1:
		new_pos.y = _start_pos.y + (_start_size.y - new_size.y)

	_base_panel.global_position = new_pos
	_base_panel.size = new_size
	_base_panel.panel_resized.emit(new_size)


func _end_resize() -> void:
	_is_resizing = false
	# Hide handles that are no longer hovered (mouse may have left the rect
	# during drag and we suppressed the exit fade).
	for handle_name in HANDLES.keys():
		var handle := _handles_root.get_node_or_null(String(handle_name)) as Control
		if handle == null:
			continue
		var local_mouse := handle.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, handle.size).has_point(local_mouse):
			handle.modulate.a = 0.0


func _effective_min_size() -> Vector2:
	var exp_min := _base_panel.min_panel_size
	var header_min := Vector2.ZERO
	if _base_panel._header_panel != null:
		header_min = _base_panel._header_panel.get_combined_minimum_size()
	return Vector2(max(exp_min.x, header_min.x), max(exp_min.y, header_min.y))
