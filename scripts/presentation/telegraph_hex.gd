extends Node2D
## TelegraphHex — paints a translucent red hex marker and a damage number
## on a single grid coord, indicating an incoming threat. One per
## threatened hex (NOT per attacker). Aggregated damage from multiple
## attackers shows as one summed number (e.g. "-12").

const RADIUS: float = 60.0
const COLOR: Color = Color(0.92, 0.18, 0.18, 0.42)
const COLOR_FRAME: Color = Color(0.6, 0.0, 0.0, 0.85)
const TEXT_COLOR: Color = Color(1, 0.95, 0.85, 1)
const TEXT_SHADOW: Color = Color(0, 0, 0, 0.85)
const FONT_SIZE: int = 18

var damage: int = 0:
	set(value):
		damage = value
		queue_redraw()


func _draw() -> void:
	# Hex polygon (matches grid hex orientation: corners at angles 0°,60°,…)
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	draw_colored_polygon(pts, COLOR)
	# Outline
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		draw_line(a, b, COLOR_FRAME, 2.0, true)
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
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, TEXT_SHADOW)
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, FONT_SIZE, TEXT_COLOR)
