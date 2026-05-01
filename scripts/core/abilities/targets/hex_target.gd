class_name HexTarget
extends AbilityTarget
## HexTarget — resolves ctx["target_coord"] as a Vector2i hex coordinate.
## Used by ground-targeted abilities (AoE landing, Create, etc.).
##
## @export range:
##   -1 = unrestricted (any walkable hex)
##    N = within N path-steps from caster

@export var range: int = -1


func resolve(caster: Actor, ctx: Dictionary) -> Variant:
	var coord: Variant = ctx.get("target_coord")
	if coord == null or not coord is Vector2i:
		return null
	if range >= 0:
		var grid: HexGrid = ctx.get("grid")
		if grid == null:
			return null
		var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
		if caster_coord == Vector2i(-1, -1):
			return null
		var path: Array[Vector2i] = grid.find_path(caster_coord, coord as Vector2i)
		var steps: int = path.size() - 1 if path.size() > 0 else 999
		if steps > range:
			return null
	return coord


func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	return resolve(caster, ctx) != null


func get_range_hexes(caster_coord: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	if range < 0:
		return grid.get_all_walkable_coords()
	# BFS up to range steps (no occupancy filter — overlay shows potential targets)
	var visited: Dictionary = {caster_coord: true}
	var frontier: Array[Vector2i] = [caster_coord]
	var result: Array[Vector2i] = []
	for _step in range:
		var next: Array[Vector2i] = []
		for coord in frontier:
			for nb in grid.get_walkable_neighbours(coord):
				if not visited.has(nb):
					visited[nb] = true
					result.append(nb)
					next.append(nb)
		frontier = next
	return result
