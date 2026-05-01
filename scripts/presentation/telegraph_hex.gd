extends Node2D
## TelegraphHex — paints a translucent hex marker and a damage number
## on a single grid coord, indicating an incoming threat. One per
## threatened hex (NOT per attacker). Aggregated damage from multiple
## attackers shows as one summed number (e.g. "-12").
##
## Color: defaults to UiTheme.SEM_DAMAGE (red, the default "danger" tint).
## After 007 + 008 land, controllers set `semantic_tag` from cast_intent so
## heal-intent shows green tint, control purple, etc. (Pillar 1: player sees
## WHAT will happen, not just THAT something will). See spec AC-R7, T072.

const RADIUS: float = 60.0
const FONT_SIZE: int = 18

## Semantic tag drives hex color. &"" → SEM_DAMAGE (red, the default).
var semantic_tag: StringName = &"":
	set(value):
		semantic_tag = value
		queue_redraw()

var damage: int = 0:
	set(value):
		damage = value
		queue_redraw()


func _ready() -> void:
	EventBus.ui_theme_reloaded.connect(queue_redraw)


func _get_fill_color() -> Color:
	var base: Color = UiTheme.SEM_DAMAGE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	return Color(base.r, base.g, base.b, 0.42)


func _get_frame_color() -> Color:
	var base: Color = UiTheme.SEM_DAMAGE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	# Frame is darker, more saturated — multiply by 0.7 then bump alpha.
	return Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, 0.85)


func _draw() -> void:
	# Hex polygon (matches grid hex orientation: corners at angles 0°,60°,…)
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	draw_colored_polygon(pts, _get_fill_color())
	# Outline
	var frame_col: Color = _get_frame_color()
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		draw_line(a, b, frame_col, 2.0, true)
	# Damage label — pushed above the hex so it isn't hidden by an actor sprite
	# standing on the threatened tile.
	if damage <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var text: String = "-%d" % damage
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE)
	var pos: Vector2 = Vector2(-size.x * 0.5, -RADIUS - 6.0)
	# Drop shadow for readability over light/dark hexes
	draw_string(font, pos + Vector2(1, 1), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, Color(0, 0, 0, 0.85))
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, UiTheme.TEXT)
