extends Node2D
## CastRangeOverlay — distinct from MoveRangeOverlay. Highlights ONLY the
## valid target hexes for the active ability of the active caster — no
## reachable-walk hexes, no self-position marker.
##
## Use case: while a slot is active (player has Q/W/E/R selected), this
## overlay paints all hexes that ability could land on. Color uses the
## ability's primary tag if available (post-007), else SEM_DEBUFF.
##
## Wiring: parent it to the same HexGrid node as MoveRangeOverlay. The host
## controller calls show_range(caster, ability_id) when cast_mode enters
## "selecting target", and hide_range() when leaving (cancel / commit).
##
## Z-index 4 — below cursor (z=7), above terrain, above move overlay (z=2).

const RADIUS: float = 60.0   # match MoveRangeOverlay / godmode_terrain.tres

var _grid: Node = null  # HexGrid
var _polys: Array[Node2D] = []


func setup(grid: Node) -> void:
	_grid = grid


func _ready() -> void:
	EventBus.ui_theme_reloaded.connect(_on_theme_reloaded)


## Show valid target hexes for a skill or ability cast by caster. Accepts
## either a Skill object (post-007 — iterates its abilities[]) or a single
## ability_id StringName (legacy lookup via AbilityDatabase). Pass null to
## clear via hide_range().
func show_range(caster: Actor, skill_or_id) -> void:
	hide_range()
	if _grid == null or caster == null or skill_or_id == null:
		return
	var caster_coord: Vector2i = _grid.get_coord(caster.actor_id)
	if caster_coord == Vector2i(-1, -1):
		return
	# Collect target hexes from one or many abilities.
	var hexes: Dictionary = {}  # Vector2i → true (dedup across abilities)
	if "abilities" in skill_or_id:
		# Skill — iterate contained abilities.
		for ab in skill_or_id.abilities:
			if ab == null or ab.target == null:
				continue
			for c in ab.target.get_range_hexes(caster_coord, _grid):
				hexes[c] = true
	else:
		# Treated as ability id (StringName / String).
		var ability: Ability = AbilityDatabase.get_ability(StringName(str(skill_or_id)))
		if ability == null or ability.target == null:
			return
		for c in ability.target.get_range_hexes(caster_coord, _grid):
			hexes[c] = true

	# Color: tag-driven once 007/008 ship ability.primary_tag; for now SEM_DEBUFF
	# (visually distinct from move-range team color).
	var base: Color = UiTheme.SEM_DEBUFF
	var fill := Color(base.r, base.g, base.b, 0.32)
	var outline := Color(base.r, base.g, base.b, 0.78)
	for c in hexes.keys():
		_add_hex(c, fill, outline)


func hide_range() -> void:
	for p in _polys:
		if is_instance_valid(p):
			p.queue_free()
	_polys.clear()


func _on_theme_reloaded() -> void:
	# Overlay holds no current state across reloads (controller re-pushes on
	# cast_mode events). No-op.
	pass


func _add_hex(coord: Vector2i, fill: Color, outline: Color) -> void:
	if _grid == null:
		return
	var poly: Node2D = Node2D.new()
	poly.position = _grid.tile_map_layer.map_to_local(coord)
	poly.z_index = 4
	_grid.add_child(poly)
	_polys.append(poly)

	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	var pgon := Polygon2D.new()
	pgon.polygon = pts
	pgon.color = fill
	poly.add_child(pgon)
	var line := Line2D.new()
	var line_pts := PackedVector2Array()
	for p in pts:
		line_pts.append(p)
	line_pts.append(pts[0])
	line.points = line_pts
	line.default_color = outline
	line.width = 1.5
	poly.add_child(line)
