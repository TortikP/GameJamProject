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
## Anchors normalization is BasePanel's responsibility (see
## BasePanel._normalize_anchors_to_top_left() — runs once in _ready).
## The handler assumes TOP_LEFT anchors with END/END grow_direction so
## global_position is absolute and writes go where expected.
##
## C2 (cant-lose-UI): the panel's HEADER must remain entirely inside
## the viewport. Body may spill past edges — only the drag handle
## (which is the only way to move the panel) is gated.

class_name PanelDragHandler
extends Node

## Emitted when the user releases LMB ending an in-progress drag. Carries
## the global position of the release. Consumers (e.g. PanelTabBar for
## tab-tear-off reattach) listen to this to detect drop targets without
## polling drag state every frame.
signal drag_ended(release_pos: Vector2)

var _base_panel: BasePanel
var _drag_handle: Control

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO


## Whether this handler is currently mid-drag. Public read-only state
## used by PanelTabBar to coordinate handoff timing.
func is_dragging() -> bool:
	return _is_dragging


## Public drag handoff: caller (e.g. PanelTabBar during tab tear-off)
## initiates a drag on this handler's panel without an LMB-press event
## having been delivered to the handle. Idempotent within a single
## gesture: if already dragging, returns no-op.
##
## After setting _is_dragging=true via _begin_drag, we synchronously call
## _do_drag(global_pos) to snap the panel to the cursor. This guards
## against the edge case where the first MouseMotion event after handoff
## doesn't reach this handler (R1 in spec 058 plan.md §Risks).
func begin_drag_at(global_pos: Vector2) -> void:
	if _is_dragging:
		return
	if not _base_panel.is_draggable() or _base_panel.is_locked():
		return
	_begin_drag(global_pos)
	_do_drag(global_pos)


func setup(base_panel: BasePanel, drag_handle: Control) -> void:
	_base_panel = base_panel
	_drag_handle = drag_handle
	if not _drag_handle.gui_input.is_connected(_on_handle_gui_input):
		_drag_handle.gui_input.connect(_on_handle_gui_input)


func _on_handle_gui_input(event: InputEvent) -> void:
	# is_draggable() returns the EFFECTIVE flag — Phase 5 folds in
	# header_visible cascade. is_locked() is checked separately because
	# lock is runtime-dynamic (see base_panel._compute_effective_flags
	# comment for rationale). Handler stays passive automatically when
	# the panel is locked or drag is disabled.
	if not _base_panel.is_draggable() or _base_panel.is_locked():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_begin_drag(mb.global_position)
			_drag_handle.accept_event()


func _begin_drag(mouse_global: Vector2) -> void:
	_is_dragging = true
	# Anchors are already TOP_LEFT (normalized by BasePanel._ready()), so
	# global_position is absolute. Just capture the offset.
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
			drag_ended.emit(mb.global_position)


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
