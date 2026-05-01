extends Node2D
## MoveRangeOverlay — draws translucent hex highlights for all coords
## reachable by the selected actor in one turn.
##
## Lives as a child of HexGrid in godmode.tscn. Rendered below actors (z_index 2).
## Call show_for() whenever the selected actor or its speed changes.
## Call clear() to hide all highlights.
##
## Palette: team colors via UiTheme.team_color, attack range via UiTheme.SEM_DEBUFF
## (orange — visually distinct from team blue/red, signals "this is reachable for
## an attack, not movement"). All colors derived once on each show_for call.

const RADIUS: float = 60.0  # must match godmode_terrain.tres hex size

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
## `ability_ids` — which abilities to draw attack range for. Pass [] to skip
## attack range entirely (e.g. when no spell is selected).
func show_for(actor: Actor, registry: Node, ability_ids: Array) -> void:
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

	# Resolve colors via UiTheme. Team color drives both fill (low alpha) and
	# outline (higher alpha). Self-hex uses heal-green for "you are here".
	var team_base: Color = UiTheme.team_color(actor.team)
	var fill_col: Color = Color(team_base.r, team_base.g, team_base.b, 0.22)
	var outline_col: Color = Color(team_base.r, team_base.g, team_base.b, 0.55)
	var self_fill: Color = Color(UiTheme.SEM_HEAL.r, UiTheme.SEM_HEAL.g, UiTheme.SEM_HEAL.b, 0.35)

	# Draw self-hex (accent — marker for current position)
	_add_hex(actor_coord, self_fill, outline_col)

	# Draw reachable hexes
	for coord in reachable:
		_add_hex(coord, fill_col, outline_col)

	# ── Attack range ──────────────────────────────────────────────────────────
	# Collect all coords reachable by any of this actor's abilities.
	# Shown in debuff-orange, drawn ON TOP of move range (higher z).
	var attack_base: Color = UiTheme.SEM_DEBUFF
	var attack_fill: Color = Color(attack_base.r, attack_base.g, attack_base.b, 0.28)
	var attack_outline: Color = Color(attack_base.r, attack_base.g, attack_base.b, 0.72)

	var attack_coords: Dictionary = {}  # Vector2i → true (dedup)
	for ability_id in ability_ids:
		var ability: Ability = AbilityDatabase.get_ability(ability_id)
		if ability == null or ability.target == null:
			continue
		var range_hexes: Array[Vector2i] = ability.target.get_range_hexes(actor_coord, _grid)
		for c in range_hexes:
			attack_coords[c] = true

	for coord in attack_coords.keys():
		_add_hex(coord, attack_fill, attack_outline, 3)


func _add_hex(coord: Vector2i, fill: Color, outline: Color, z: int = 2) -> void:
	var poly: Node2D = Node2D.new()
	poly.position = _grid.tile_map_layer.map_to_local(coord)
	poly.z_index = z
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
