extends Node2D
## MoveRangeOverlay — draws translucent hex highlights for all coords
## reachable by the selected actor in one turn.
##
## Lives as a child of HexGrid in godmode.tscn. Rendered below actors (z_index 2).
## Call show_for() whenever the selected actor or its speed changes.
## Call clear() to hide all highlights.

const RADIUS: float = 60.0       # must match godmode_terrain.tres hex size
const COLOR_ALLY: Color  = Color(0.40, 0.70, 1.00, 0.22)
const COLOR_ENEMY: Color = Color(1.00, 0.40, 0.40, 0.22)
const COLOR_SELF: Color  = Color(0.30, 1.00, 0.45, 0.35)  # current hex of selected actor
const COLOR_OUTLINE_ALLY:  Color = Color(0.40, 0.70, 1.00, 0.55)
const COLOR_OUTLINE_ENEMY: Color = Color(1.00, 0.40, 0.40, 0.55)

var _grid: Node = null  # HexGrid
var _polys: Array[Node2D] = []


func setup(grid: Node) -> void:
	_grid = grid


func clear() -> void:
	for p in _polys:
		if is_instance_valid(p):
			p.queue_free()
	_polys.clear()


## Show reachable hexes for `actor`. `registry` is ActorRegistry — used to
## build the occupied list so BFS doesn't route through other actors.
func show_for(actor: Actor, registry: Node) -> void:
	clear()
	if _grid == null or actor == null:
		return

	var actor_coord: Vector2i = _grid.get_coord(actor.actor_id)
	if actor_coord == Vector2i(-1, -1):
		return

	# Build occupied list: all actor positions except the selected one
	var occupied: Array = []
	if registry != null and registry.has_method("all"):
		for a in registry.all():
			if a is Actor and (a as Actor).actor_id != actor.actor_id:
				var c: Vector2i = _grid.get_coord((a as Actor).actor_id)
				if c != Vector2i(-1, -1):
					occupied.append(c)

	var reachable: Array[Vector2i] = _grid.reachable_within(actor_coord, actor.speed, occupied)

	# Colour scheme based on team
	var is_enemy: bool = actor.team == &"enemy"
	var fill_col: Color = COLOR_ENEMY if is_enemy else COLOR_ALLY
	var outline_col: Color = COLOR_OUTLINE_ENEMY if is_enemy else COLOR_OUTLINE_ALLY

	# Draw self-hex (accent)
	_add_hex(actor_coord, COLOR_SELF, outline_col)

	# Draw reachable hexes
	for coord in reachable:
		_add_hex(coord, fill_col, outline_col)


func _add_hex(coord: Vector2i, fill: Color, outline: Color) -> void:
	var poly: Node2D = Node2D.new()
	poly.position = _grid.tile_map_layer.map_to_local(coord)
	poly.z_index = 2
	# Store colors so _draw can access them via metadata
	poly.set_meta("fill", fill)
	poly.set_meta("outline", outline)
	_grid.add_child(poly)
	_polys.append(poly)
	# Draw immediately via a draw-script attached inline.
	# Simplest jam approach: use a child Polygon2D (no custom _draw needed).
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	var pgon := Polygon2D.new()
	pgon.polygon = pts
	pgon.color = fill
	pgon.z_index = 2
	poly.add_child(pgon)
	# Outline via Line2D
	var line := Line2D.new()
	var line_pts := PackedVector2Array()
	for p in pts:
		line_pts.append(p)
	line_pts.append(pts[0])  # close
	line.points = line_pts
	line.default_color = outline
	line.width = 1.5
	line.z_index = 2
	poly.add_child(line)
