extends Node2D
## IntentArrow — draws a line from `origin` to `target` (both in the same
## coord space as this node) with a small arrowhead at the target end.
## Used to telegraph an enemy's planned next move during the player's turn.
##
## Position the node anywhere; the line is drawn in this node's local coords
## from `origin` to `target`. Simplest usage: keep node at (0,0) of the grid
## and pass world positions for both endpoints.

const COLOR: Color = Color(0.95, 0.85, 0.20, 0.85)
const COLOR_SHADOW: Color = Color(0, 0, 0, 0.55)
const WIDTH: float = 4.0
const HEAD_LEN: float = 18.0
const HEAD_HALF_W: float = 10.0
const SHRINK_FROM_ENDS: float = 28.0  # so line doesn't bury under sprites

var origin: Vector2 = Vector2.ZERO:
	set(value):
		origin = value
		queue_redraw()
var target: Vector2 = Vector2.ZERO:
	set(value):
		target = value
		queue_redraw()


func _draw() -> void:
	var delta: Vector2 = target - origin
	var dist: float = delta.length()
	if dist <= SHRINK_FROM_ENDS * 2.0 + HEAD_LEN:
		return  # too short to render meaningfully
	var dir: Vector2 = delta / dist
	var start: Vector2 = origin + dir * SHRINK_FROM_ENDS
	var end: Vector2 = target - dir * SHRINK_FROM_ENDS
	var shaft_end: Vector2 = end - dir * HEAD_LEN
	# Drop shadow first (1px offset)
	draw_line(start + Vector2(1, 1), shaft_end + Vector2(1, 1), COLOR_SHADOW, WIDTH + 2.0, true)
	draw_line(start, shaft_end, COLOR, WIDTH, true)
	# Arrowhead (filled triangle)
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var head_pts: PackedVector2Array = [
		end,
		shaft_end + perp * HEAD_HALF_W,
		shaft_end - perp * HEAD_HALF_W,
	]
	# Shadow
	var shadow_pts: PackedVector2Array = []
	for p in head_pts:
		shadow_pts.append(p + Vector2(1, 1))
	draw_colored_polygon(shadow_pts, COLOR_SHADOW)
	draw_colored_polygon(head_pts, COLOR)
