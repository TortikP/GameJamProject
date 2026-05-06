## PanelResizeHandler — resize behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Approach: real Control handle nodes positioned ENTIRELY OUTSIDE the
## panel rect via anchors+negative-offsets in base_panel.tscn. Each
## handle is a regular Control with:
##   - mouse_default_cursor_shape set to its direction's resize cursor
##     (FDIAGSIZE / BDIAGSIZE / VSIZE / HSIZE) — Godot's native cursor
##     hover handling, no DisplayServer tricks.
##   - mouse_filter = STOP so it captures hovers and clicks reliably.
##   - modulate.a = 0 (invisible, but interactive).
##
## On click: gui_input fires with our connected callback, we capture
## initial state, then listen to global _input for motion/release until
## button-up. The set_anchors_preset(TOP_LEFT, true) call switches the
## panel to absolute positioning so size/global_position writes during
## resize don't fight with parent container layout.
##
## On release: state cleared. Handles auto-track via anchors when the
## panel resizes — no per-frame layout code.

class_name PanelResizeHandler
extends Node

## Handle name → resize direction sign vector.
##   dx, dy ∈ {-1, 0, 1}: -1 → that edge follows cursor (origin shifts);
##   1 → that edge follows cursor outward (size grows); 0 → unaffected.
const HANDLE_DIRS := {
	&"ResizeHandle_TopLeft":     Vector2i(-1, -1),
	&"ResizeHandle_Top":         Vector2i( 0, -1),
	&"ResizeHandle_TopRight":    Vector2i( 1, -1),
	&"ResizeHandle_Right":       Vector2i( 1,  0),
	&"ResizeHandle_BottomRight": Vector2i( 1,  1),
	&"ResizeHandle_Bottom":      Vector2i( 0,  1),
	&"ResizeHandle_BottomLeft":  Vector2i(-1,  1),
	&"ResizeHandle_Left":        Vector2i(-1,  0),
}

var _base_panel: BasePanel

var _is_resizing: bool = false
var _active_dir: Vector2i = Vector2i.ZERO
var _initial_mouse: Vector2
var _initial_size: Vector2
var _initial_pos: Vector2


func setup(base_panel: BasePanel) -> void:
	_base_panel = base_panel
	# is_resizable() returns the EFFECTIVE flag — folds in lock state
	# and header_visible cascade (Phases 4-5). When false, hide handles
	# entirely so they don't trigger cursor changes on hover.
	var enabled := base_panel.is_resizable()
	for handle_name in HANDLE_DIRS.keys():
		var handle := base_panel.get_node_or_null(String(handle_name)) as Control
		if handle == null:
			push_warning("[PanelResizeHandler] missing handle node: %s" % handle_name)
			continue
		if not enabled:
			handle.visible = false
			continue
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		var dir: Vector2i = HANDLE_DIRS[handle_name]
		handle.gui_input.connect(_on_handle_gui_input.bind(dir))


func _on_handle_gui_input(event: InputEvent, dir: Vector2i) -> void:
	if not _base_panel.is_resizable():
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
	# Switch to absolute positioning so size/global_position writes
	# during resize are not perturbed by parent container layout or
	# anchor recalc. keep_offsets=true preserves the visual rect.
	_base_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)


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
	# header content actually requires to render.
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
