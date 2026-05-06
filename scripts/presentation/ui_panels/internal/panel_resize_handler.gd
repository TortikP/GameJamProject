## PanelResizeHandler — resize behavior for BasePanel.
##
## Composition handler. Owned by BasePanel; not a public API.
##
## Approach inspired by the Eranot/godot-resizable plugin (MIT, Godot 4):
## instead of placing 8 invisible Control nodes for corners/edges, this
## handler listens to global `_input(event)` and computes which "virtual
## handle" the mouse is over by proximity to the parent's edges. The
## cursor is set via DisplayServer.cursor_set_shape() and the event is
## marked handled so it doesn't fall through to gui_input dispatch
## (otherwise downstream Controls' mouse_default_cursor_shape would
## fight us).
##
## Why this approach:
##   - 8-handle approach (earlier attempt) suffered from input dispatch
##     ambiguities, anchor drift on resize, and z-order conflicts with
##     the panel content underneath. The proximity-check approach is a
##     single state machine, no scene-tree machinery.
##   - Cursor changes are global and per-frame, so they correctly track
##     mouse motion without depending on which exact rect was entered.
##
## Behaviors:
##   - On hover near an edge (within BORDER_WIDTH px): cursor changes
##     to the appropriate resize shape (FDIAGSIZE / BDIAGSIZE / VSIZE /
##     HSIZE).
##   - On LMB-press near an edge: resize starts. State persists during
##     mouse motion until LMB release.
##   - C1 min size enforced via _effective_min_size().
##   - Top/Left edges shift the panel's origin so the OPPOSITE edge
##     stays anchored (drag top-left grows from bottom-right).

class_name PanelResizeHandler
extends Node

## Width in pixels of the proximity zone around each edge where resize
## handles "live". 6px matches Eranot plugin default and is comfortable
## for mouse precision without overlapping much with body content.
const BORDER_WIDTH := 6

enum HANDLE {
	NONE         = 0,
	TOP          = 1,
	BOTTOM       = 2,
	LEFT         = 4,
	RIGHT        = 8,
	TOP_LEFT     = 16,
	TOP_RIGHT    = 32,
	BOTTOM_LEFT  = 64,
	BOTTOM_RIGHT = 128,
}

var _base_panel: BasePanel

var _is_resizing: bool = false
var _active_handle: int = HANDLE.NONE
var _initial_mouse: Vector2
var _initial_size: Vector2
var _initial_pos: Vector2


func setup(base_panel: BasePanel) -> void:
	_base_panel = base_panel


func _input(event: InputEvent) -> void:
	# is_resizable() returns the EFFECTIVE flag — in Phase 4 (lock) and
	# Phase 5 (header_visible cascade) this will fold in additional gates.
	# Handler stays passive when locked; no separate lock check needed here.
	if not _base_panel.is_resizable():
		return
	if event is InputEventMouseMotion:
		_on_mouse_motion()
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)


func _on_mouse_motion() -> void:
	# Determine which handle the mouse is currently associated with —
	# either the active one (during drag) or whatever the mouse is over.
	var handle := _active_handle if _is_resizing else _hovered_handle()

	# Apply cursor shape via DisplayServer; mark event handled so the
	# regular Control.mouse_default_cursor_shape chain doesn't override.
	match handle:
		HANDLE.TOP_LEFT, HANDLE.BOTTOM_RIGHT:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_FDIAGSIZE)
			get_viewport().set_input_as_handled()
		HANDLE.TOP_RIGHT, HANDLE.BOTTOM_LEFT:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_BDIAGSIZE)
			get_viewport().set_input_as_handled()
		HANDLE.TOP, HANDLE.BOTTOM:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_VSIZE)
			get_viewport().set_input_as_handled()
		HANDLE.LEFT, HANDLE.RIGHT:
			DisplayServer.cursor_set_shape(DisplayServer.CURSOR_HSIZE)
			get_viewport().set_input_as_handled()

	if _is_resizing:
		_apply_resize()


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		var handle := _hovered_handle()
		if handle == HANDLE.NONE:
			return
		_is_resizing = true
		_active_handle = handle
		_initial_mouse = event.global_position
		_initial_size = _base_panel.size
		_initial_pos = _base_panel.global_position
		# Switch to absolute positioning (anchors at top-left, offsets
		# preserve current visual position). Subsequent size/position
		# writes are then absolute.
		_base_panel.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		get_viewport().set_input_as_handled()
	else:
		if _is_resizing:
			_is_resizing = false
			_active_handle = HANDLE.NONE


# ── Geometry helpers ───────────────────────────────────────────────

func _hovered_handle() -> int:
	var mouse_pos := _base_panel.get_global_mouse_position()

	# Defensive: header buttons (lock, collapse) are always interactive
	# in their own right. They must NEVER resolve to a resize handle,
	# even if a future layout change moves them onto the panel border.
	# Today the geometry already prevents this (buttons are inside, resize
	# zones are outside) but the cost of an explicit check is one rect
	# test and saves a class of regressions.
	if _is_over_header_button(mouse_pos):
		return HANDLE.NONE

	var pp := _base_panel.global_position
	var ps := _base_panel.size

	# Resize zones live ENTIRELY OUTSIDE the panel rect, in a BORDER_WIDTH-px
	# frame around it. The panel's edge pixel itself is included as the
	# inner boundary so the zone is grabbable right where the panel ends.
	# This way resize never overlaps with header buttons / body content
	# inside the panel — a click on a button is unambiguously a button
	# click; you have to move the cursor past the panel border to enter
	# the resize zone.
	var near_top: bool    = pp.y - BORDER_WIDTH <= mouse_pos.y and mouse_pos.y <= pp.y
	var near_bottom: bool = pp.y + ps.y <= mouse_pos.y and mouse_pos.y <= pp.y + ps.y + BORDER_WIDTH
	var near_left: bool   = pp.x - BORDER_WIDTH <= mouse_pos.x and mouse_pos.x <= pp.x
	var near_right: bool  = pp.x + ps.x <= mouse_pos.x and mouse_pos.x <= pp.x + ps.x + BORDER_WIDTH

	# Bail early if mouse is far from the panel's expanded rect — saves
	# the corner/edge fallthroughs.
	var within: bool = pp.x - BORDER_WIDTH <= mouse_pos.x \
			and mouse_pos.x <= pp.x + ps.x + BORDER_WIDTH \
			and pp.y - BORDER_WIDTH <= mouse_pos.y \
			and mouse_pos.y <= pp.y + ps.y + BORDER_WIDTH
	if not within:
		return HANDLE.NONE

	# Corners win over edges.
	if near_top and near_left:    return HANDLE.TOP_LEFT
	if near_top and near_right:   return HANDLE.TOP_RIGHT
	if near_bottom and near_left: return HANDLE.BOTTOM_LEFT
	if near_bottom and near_right:return HANDLE.BOTTOM_RIGHT

	if near_top:    return HANDLE.TOP
	if near_bottom: return HANDLE.BOTTOM
	if near_left:   return HANDLE.LEFT
	if near_right:  return HANDLE.RIGHT

	return HANDLE.NONE


func _is_over_header_button(mouse_pos: Vector2) -> bool:
	var lock_btn := _base_panel._lock_button
	if lock_btn != null and lock_btn.get_global_rect().has_point(mouse_pos):
		return true
	var collapse_btn := _base_panel._collapse_button
	if collapse_btn != null and collapse_btn.get_global_rect().has_point(mouse_pos):
		return true
	return false


func _apply_resize() -> void:
	var delta := _base_panel.get_global_mouse_position() - _initial_mouse
	var new_size := _initial_size
	var new_pos := _initial_pos

	# Width axis — right-side handles grow with cursor; left-side handles
	# shrink-with-cursor, so the panel's left edge follows the cursor and
	# the right edge stays anchored at its original x.
	match _active_handle:
		HANDLE.RIGHT, HANDLE.TOP_RIGHT, HANDLE.BOTTOM_RIGHT:
			new_size.x = _initial_size.x + delta.x
		HANDLE.LEFT, HANDLE.TOP_LEFT, HANDLE.BOTTOM_LEFT:
			new_size.x = _initial_size.x - delta.x

	# Height axis — symmetric: bottom handles grow downward, top handles
	# shrink-with-cursor.
	match _active_handle:
		HANDLE.BOTTOM, HANDLE.BOTTOM_LEFT, HANDLE.BOTTOM_RIGHT:
			new_size.y = _initial_size.y + delta.y
		HANDLE.TOP, HANDLE.TOP_LEFT, HANDLE.TOP_RIGHT:
			new_size.y = _initial_size.y - delta.y

	# C1: minimum size. Take the larger of the export and the header's
	# combined min size — the panel can never be shrunk below where its
	# own caption stops fitting.
	var min_size := _effective_min_size()
	new_size.x = max(new_size.x, min_size.x)
	new_size.y = max(new_size.y, min_size.y)

	# When dragging from a top/left handle, the OPPOSITE edge must stay
	# anchored: as size shrinks, position shifts to keep that edge fixed.
	if _active_handle in [HANDLE.LEFT, HANDLE.TOP_LEFT, HANDLE.BOTTOM_LEFT]:
		new_pos.x = _initial_pos.x + (_initial_size.x - new_size.x)
	if _active_handle in [HANDLE.TOP, HANDLE.TOP_LEFT, HANDLE.TOP_RIGHT]:
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
