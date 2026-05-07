## PanelClamps — pure stateless geometry clamps for BasePanel.
##
## Implements the math for the can't-lose-UI rules (spec 055 §6):
##   - C3 (viewport resize): called from BasePanel._on_viewport_size_changed.
##   - C4 (load-time clamp): called from PanelPersistence.load_layout.
##
## C1 (min size) and C2 (drag bounds) live in their respective handlers
## (panel_resize_handler enforces min on resize; panel_drag_handler keeps
## the header inside the viewport during drag). C5 (mouse_filter rule)
## is a one-shot init in BasePanel._ready.
##
## All methods are pure: take inputs, return new values, no side effects.
## The caller decides whether to write the result back.

class_name PanelClamps
extends RefCounted


## Clamp a rect (position + size) to fit inside `viewport_size`.
##
## Size is clamped to `[min_size, viewport_size]` per axis. Position
## is then clamped so that:
##   - the right edge of the panel does not leave the viewport
##     (panel.x + panel.width <= viewport.width)
##   - the top header_height strip stays inside the viewport
##     (panel.y in [0, viewport.height - header_height])
##
## The bottom of the body may spill past the bottom edge — only the
## header (the only drag handle) is gated. Mirrors panel_drag_handler's
## C2 contract so static-clamp and drag-clamp behave identically.
##
## Returns a Dictionary with keys "position" (Vector2) and "size" (Vector2).
static func clamp_rect_to_viewport(
		pos: Vector2,
		size: Vector2,
		header_height: float,
		min_size: Vector2,
		viewport_size: Vector2) -> Dictionary:
	var max_w: float = max(min_size.x, viewport_size.x)
	var max_h: float = max(min_size.y, viewport_size.y)
	var clamped_size := Vector2(
		clamp(size.x, min_size.x, max_w),
		clamp(size.y, min_size.y, max_h)
	)
	var clamped_pos := Vector2(
		clamp(pos.x, 0.0, max(0.0, viewport_size.x - clamped_size.x)),
		clamp(pos.y, 0.0, max(0.0, viewport_size.y - header_height))
	)
	return {"position": clamped_pos, "size": clamped_size}


## Clamp position only (size left untouched).
##
## For collapsed panels: their visible size is the header strip,
## determined by collapse state — not user-driven. Only the position
## needs to track the viewport. Same horizontal/vertical rules as
## clamp_rect_to_viewport.
static func clamp_position_to_viewport(
		pos: Vector2,
		size: Vector2,
		header_height: float,
		viewport_size: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, 0.0, max(0.0, viewport_size.x - size.x)),
		clamp(pos.y, 0.0, max(0.0, viewport_size.y - header_height))
	)
