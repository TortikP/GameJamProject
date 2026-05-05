extends Node2D
## ObjectSilhouette — placeholder for tile objects in the map editor when no
## sprite is available. Draws a simple monochrome shape so the editor user
## recognizes objects by silhouette, not by hash-color square.
##
## Used by ObjectsOverlay as a fallback when TileObject.sprite_path is
## empty or unresolvable. Configure once via setup() and queue_redraw is
## called automatically.
##
## Shape vocabulary (extend by adding cases to _draw and the table in
## ObjectsOverlay._silhouette_for):
##   "circle"           — boulder, fountain (default round bulk)
##   "diamond"          — crystal, magic items
##   "diamond_outline"  — same shape, hollow stroke (heal_fountain)
##   "triangle_tall"    — tree (treetop)
##   "triangle_low"     — bush (low foliage)
##   "triangle_peak"    — mountain (terrain)
##   "rect_wide"        — table (low wide cover)
##   "rect_tall"        — barrel (upright cylinder approximation)
##   "blob"             — lava pool (irregular splat)

const RADIUS: float = 24.0   # roughly hex inscribed circle
const STROKE: float = 3.0


var shape: StringName = &"circle"
var color: Color = Color.WHITE


func setup(shape_name: StringName, fill: Color) -> void:
	shape = shape_name
	color = fill
	queue_redraw()


func _draw() -> void:
	match String(shape):
		"circle":
			draw_circle(Vector2.ZERO, RADIUS, color)
		"diamond":
			draw_colored_polygon(_diamond_points(RADIUS), color)
		"diamond_outline":
			var pts := _diamond_points(RADIUS)
			# Connect last->first manually since draw_polyline doesn't loop.
			var loop: PackedVector2Array = pts.duplicate()
			loop.append(pts[0])
			draw_polyline(loop, color, STROKE, true)
		"triangle_tall":
			# Tall triangle with crown peak (tree).
			var tt: PackedVector2Array = PackedVector2Array([
				Vector2(0, -RADIUS),
				Vector2(RADIUS * 0.85, RADIUS * 0.6),
				Vector2(-RADIUS * 0.85, RADIUS * 0.6),
			])
			draw_colored_polygon(tt, color)
		"triangle_low":
			# Squat triangle (bush) — wider, shorter.
			var tl: PackedVector2Array = PackedVector2Array([
				Vector2(0, -RADIUS * 0.5),
				Vector2(RADIUS, RADIUS * 0.5),
				Vector2(-RADIUS, RADIUS * 0.5),
			])
			draw_colored_polygon(tl, color)
		"triangle_peak":
			# Sharp peak with outline — mountain. Filled + thin dark outline
			# so it reads as terrain (not foliage).
			var tp: PackedVector2Array = PackedVector2Array([
				Vector2(0, -RADIUS),
				Vector2(RADIUS, RADIUS * 0.7),
				Vector2(-RADIUS, RADIUS * 0.7),
			])
			draw_colored_polygon(tp, color)
			var outline_loop: PackedVector2Array = tp.duplicate()
			outline_loop.append(tp[0])
			draw_polyline(outline_loop, color.darkened(0.4), STROKE * 0.6, true)
		"rect_wide":
			var rw := Rect2(-RADIUS, -RADIUS * 0.4, RADIUS * 2.0, RADIUS * 0.8)
			draw_rect(rw, color, true)
		"rect_tall":
			var rt := Rect2(-RADIUS * 0.5, -RADIUS, RADIUS, RADIUS * 2.0)
			draw_rect(rt, color, true)
		"blob":
			# Approximated as a slightly-flattened circle with a darker rim
			# so it reads as a pool, not a solid object.
			draw_circle(Vector2(0, RADIUS * 0.1), RADIUS * 0.95, color)
			draw_arc(Vector2(0, RADIUS * 0.1), RADIUS * 0.95, 0.0, TAU,
					32, color.darkened(0.3), STROKE * 0.8, true)
		_:
			# Unknown shape — fallback to circle so we at least see something.
			draw_circle(Vector2.ZERO, RADIUS, color)


static func _diamond_points(r: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -r),
		Vector2(r, 0),
		Vector2(0, r),
		Vector2(-r, 0),
	])
