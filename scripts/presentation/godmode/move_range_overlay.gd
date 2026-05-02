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
## an attack, not movement"). Zone preview uses UiTheme.SEM_CONTROL (purple — the
## affected-area semantic). All colors derived once on each show_for call.

## Hex polygon dimensions come from the live tileset's tile_size — see
## scripts/infrastructure/hex_geometry.gd. tile_size in the .tres is the
## single source of truth.
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

var _grid: Node = null  # HexGrid
var _polys: Array[Node2D] = []
var _zone_polys: Array[Node2D] = []  # hover AoE preview — cleared every frame


func setup(grid: Node) -> void:
	_grid = grid


## Dynamic zone AoE preview — call every frame from _update_castability.
## Pass [] to erase the preview. Color: SEM_CONTROL (purple — "this is the
## affected area").
func show_zone_preview(hexes: Array[Vector2i]) -> void:
	clear_zone_preview()
	var base: Color = UiTheme.SEM_CONTROL
	var fill: Color = Color(base.r, base.g, base.b, 0.32)
	var outline: Color = Color(base.r, base.g, base.b, 0.80)
	for coord in hexes:
		_add_hex(coord, fill, outline, 4, _zone_polys)


func clear_zone_preview() -> void:
	for p in _zone_polys:
		if is_instance_valid(p):
			p.free()   # immediate — queue_free() lags one frame, leaves ghost hexes
	_zone_polys.clear()


func clear() -> void:
	for p in _polys:
		if is_instance_valid(p):
			p.queue_free()
	_polys.clear()
	clear_zone_preview()


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
	# ability_ids items can be Ability objects (player slot path, post-007)
	# or StringName IDs (legacy enemy path via actor.get_abilities()). Objects
	# are preferred — ID lookup via AbilityDatabase is unsafe when multiple
	# skills share an ability ID.
	var attack_base: Color = UiTheme.SEM_DEBUFF
	var attack_fill: Color = Color(attack_base.r, attack_base.g, attack_base.b, 0.28)
	var attack_outline: Color = Color(attack_base.r, attack_base.g, attack_base.b, 0.72)

	var attack_coords: Dictionary = {}  # Vector2i → true (dedup)
	for item in ability_ids:
		var ability: Ability
		if item is Ability:
			ability = item as Ability
		else:
			ability = AbilityDatabase.get_ability(StringName(str(item)))
		if ability == null or ability.target == null:
			continue
		var range_hexes: Array[Vector2i] = ability.target.get_range_hexes(actor_coord, _grid)
		for c in range_hexes:
			attack_coords[c] = true

	for coord in attack_coords.keys():
		_add_hex(coord, attack_fill, attack_outline, 3)


func _add_hex(coord: Vector2i, fill: Color, outline: Color, z: int = 2, target_array = null) -> void:
	# Polygon shape first — bail before allocating nodes if tile_set isn't ready.
	# Polygon dims come from the live tile_set — adapts when tile_size changes.
	var pts: PackedVector2Array = HexGeometry.flat_top_polygon_for_layer(_grid.tile_map_layer)
	if pts.is_empty():
		return  # controller will retry on next show_for
	var poly: Node2D = Node2D.new()
	poly.position = _grid.tile_map_layer.map_to_local(coord)
	poly.z_index = z
	poly.set_meta("fill", fill)
	poly.set_meta("outline", outline)
	_grid.add_child(poly)
	if target_array == null:
		_polys.append(poly)
	else:
		target_array.append(poly)
	# Draw immediately via a child Polygon2D (no custom _draw needed).
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
