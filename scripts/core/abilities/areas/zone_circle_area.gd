class_name ZoneCircleArea
extends AbilityArea
## ZoneCircleArea — all hexes within `radius` BFS steps of primary_target.
##
## Result ordering: nearest → farthest (BFS layer order).
## If primary is Actor → victims are Actors found at those hexes.
## If primary is Vector2i → victims are the Vector2i coords (for hex-targeted abilities).
##
## Includes the primary hex itself (step 0). Occupied hexes that have actors
## on them are included (actors might block further BFS expansion though).

@export var radius: int = 1


func resolve(caster: Actor, primary_target: Variant, ctx: Dictionary) -> Array:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return []

	var center: Vector2i = _coord_of(primary_target, caster, grid)
	if center == Vector2i(-1, -1):
		return []

	var registry: ActorRegistry = ctx.get("registry")

	# BFS — collect hexes layer by layer (nearest→farthest)
	var visited: Dictionary = {center: true}
	var frontier: Array[Vector2i] = [center]
	var ordered_hexes: Array[Vector2i] = [center]

	for _step in radius:
		var next: Array[Vector2i] = []
		for coord in frontier:
			for nb in grid.get_walkable_neighbours(coord):
				if not visited.has(nb):
					visited[nb] = true
					ordered_hexes.append(nb)
					next.append(nb)
		frontier = next
		if frontier.is_empty():
			break

	# Always return actors standing on those hexes.
	# Effects that need a coord (CreateEffect) read ctx.target_coord directly.
	var result: Array = []
	for coord in ordered_hexes:
		var occ_id: StringName = grid.get_actor_at(coord)
		if occ_id == &"":
			continue
		var actor: Actor = registry.get_actor(occ_id) if registry != null else null
		if actor != null and actor.is_alive():
			result.append(actor)
	return result


func get_affected_hexes(caster_coord: Vector2i, primary: Variant, grid: HexGrid) -> Array[Vector2i]:
	var center: Vector2i = _coord_of(primary, null, grid)
	if center == Vector2i(-1, -1):
		return []
	var result: Array[Vector2i] = []
	# Reuse grid's reachable_within for the overlay (ignore occupancy)
	result.append(center)
	var reached: Array[Vector2i] = grid.reachable_within(center, radius, [])
	result.append_array(reached)
	return result


func _coord_of(primary: Variant, _caster: Variant, grid: HexGrid) -> Vector2i:
	if primary is Actor:
		return grid.get_coord((primary as Actor).actor_id)
	if primary is Vector2i:
		return primary as Vector2i
	return Vector2i(-1, -1)


## 021 scaling: radius += level / 2 (integer div) if radius > 1.
## Single-hex zones (radius=1, e.g. tile-targeted Create) stay pinpoint at any level.
func apply_level(level: int) -> void:
	if level <= 0 or radius <= 1:
		return
	radius += level / 2
