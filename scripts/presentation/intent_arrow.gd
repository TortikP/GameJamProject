extends Node2D
## IntentArrow — draws a line from `origin` to `target` (both in the same
## coord space as this node) with a small arrowhead at the target end.
## Used to telegraph an enemy's planned next move during the player's turn.
##
## Position the node anywhere; the line is drawn in this node's local coords
## from `origin` to `target`. Simplest usage: keep node at (0,0) of the grid
## and pass world positions for both endpoints.
##
## Color: defaults to UiTheme.SEM_MOVE for plain movement intent. After 008
## (enemy AI) lands, controllers pass `semantic_tag` from cast_intent to color
## by tag (damage→red, heal→green, control→purple). See spec AC-R5, T070.

const WIDTH: float = 4.0
const HEAD_LEN: float = 18.0
const HEAD_HALF_W: float = 10.0
const SHRINK_FROM_ENDS: float = 28.0  # so line doesn't bury under sprites

## Semantic tag drives arrow color. &"" → fall back to SEM_MOVE.
## After 008 lands, controllers should set this from cast_intent.skill.primary_tag.
var semantic_tag: StringName = &"":
	set(value):
		semantic_tag = value
		queue_redraw()

var origin: Vector2 = Vector2.ZERO:
	set(value):
		origin = value
		queue_redraw()
var target: Vector2 = Vector2.ZERO:
	set(value):
		target = value
		queue_redraw()


func _ready() -> void:
	EventBus.ui_theme_reloaded.connect(queue_redraw)


func _get_color() -> Color:
	# &"" tag → SEM_MOVE. Otherwise resolve via UiTheme. Alpha kept at 0.85
	# for visual contrast against arena background.
	var base: Color = UiTheme.SEM_MOVE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	return Color(base.r, base.g, base.b, 0.85)


func _draw() -> void:
	var delta: Vector2 = target - origin
	var dist: float = delta.length()
	if dist <= SHRINK_FROM_ENDS * 2.0 + HEAD_LEN:
		return  # too short to render meaningfully
	var dir: Vector2 = delta / dist
	var start: Vector2 = origin + dir * SHRINK_FROM_ENDS
	var end: Vector2 = target - dir * SHRINK_FROM_ENDS
	var shaft_end: Vector2 = end - dir * HEAD_LEN
	var color: Color = _get_color()
	# Drop shadow first (1px offset)
	draw_line(start + Vector2(1, 1), shaft_end + Vector2(1, 1), UiTheme.SHADOW_SOFT_COLOR, WIDTH + 2.0, true)
	draw_line(start, shaft_end, color, WIDTH, true)
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
	draw_colored_polygon(shadow_pts, UiTheme.SHADOW_SOFT_COLOR)
	draw_colored_polygon(head_pts, color)
