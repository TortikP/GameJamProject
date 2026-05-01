class_name ChainArea
extends AbilityArea
## ChainArea — BFS chain of up to max_chain_length targets.
##
## Starting from primary_target, each next step picks the nearest unvisited
## actor within `radius` BFS hops. Chain stops when no valid actor is
## reachable inside that radius or length is exhausted.
##
## "Single target" = ChainArea(max_chain_length=1) — radius is irrelevant
## with length 1 (no second link is ever sought).
##
## 021: `radius` field added explicitly. radius=1 reproduces pre-021 behaviour
## (direct-neighbours only).

@export var max_chain_length: int = 1
@export var radius: int = 1


func resolve(caster: Actor, primary_target: Variant, ctx: Dictionary) -> Array:
	var grid: HexGrid = ctx.get("grid")
	var registry: ActorRegistry = ctx.get("registry")
	if grid == null or registry == null:
		return []

	var start_coord: Vector2i = _coord_of(primary_target, caster, grid)
	if start_coord == Vector2i(-1, -1):
		return []

	var results: Array = []
	var visited_coords: Dictionary = {}   # Vector2i → true (all visited hexes)
	visited_coords[start_coord] = true

	# Caster's coord is visited so the chain can't bounce back to self.
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	if caster_coord != Vector2i(-1, -1):
		visited_coords[caster_coord] = true

	var current_coord: Vector2i = start_coord
	var jump: int = maxi(1, radius)

	for _step in max_chain_length:
		# Resolve an actor at current_coord (start of step or last jump dest).
		var occupant_id: StringName = grid.get_actor_at(current_coord)
		if occupant_id != &"":
			var actor: Actor = registry.get_actor(occupant_id)
			if actor != null and actor.is_alive() and actor != caster:
				results.append(actor)

		# Find next link: nearest unvisited actor within `jump` BFS hops.
		var best_next: Vector2i = _bfs_nearest_actor(grid, registry, caster, current_coord, jump, visited_coords)
		if best_next == Vector2i(-1, -1):
			break   # chain broken — no actor reachable inside radius

		visited_coords[best_next] = true
		current_coord = best_next

	return results


func get_affected_hexes(_caster_coord: Vector2i, primary: Variant, _grid: HexGrid) -> Array[Vector2i]:
	if primary is Vector2i:
		return [primary as Vector2i]
	return []


## 021 scaling: max_chain_length += level / 2 (integer div) if length > 1.
## Single-target chains (length=1) don't scale into multi-hops at any level.
func apply_level(level: int) -> void:
	if level <= 0 or max_chain_length <= 1:
		return
	max_chain_length += level / 2


# ── Helpers ──────────────────────────────────────────────────────────────────

func _coord_of(primary: Variant, caster: Actor, grid: HexGrid) -> Vector2i:
	if primary is Actor:
		return grid.get_coord((primary as Actor).actor_id)
	if primary is Vector2i:
		return primary as Vector2i
	# Fallback: caster position (for self-chain edge case)
	return grid.get_coord(caster.actor_id)


## BFS up to `max_hops` from `from_coord`, return coord of the first visited
## hex containing an alive non-caster actor not yet in `visited_coords`.
## Hexes traversed (including dead-ends) are marked visited to skip on later steps.
## Returns Vector2i(-1, -1) if no actor is reachable.
func _bfs_nearest_actor(
	grid: HexGrid,
	registry: ActorRegistry,
	caster: Actor,
	from_coord: Vector2i,
	max_hops: int,
	visited_coords: Dictionary,
) -> Vector2i:
	var local_visited: Dictionary = {from_coord: true}
	var frontier: Array[Vector2i] = [from_coord]
	for _hop in max_hops:
		var next_frontier: Array[Vector2i] = []
		for coord in frontier:
			for nb in grid.get_walkable_neighbours(coord):
				if local_visited.has(nb):
					continue
				local_visited[nb] = true
				if visited_coords.has(nb):
					continue   # already consumed by this chain
				var nb_id: StringName = grid.get_actor_at(nb)
				if nb_id != &"" and nb_id != caster.actor_id:
					var nb_actor: Actor = registry.get_actor(nb_id)
					if nb_actor != null and nb_actor.is_alive():
						return nb   # nearest BFS-actor wins
				# Empty hex (or caster's hex) — keep expanding through it.
				next_frontier.append(nb)
		frontier = next_frontier
		if frontier.is_empty():
			break
	return Vector2i(-1, -1)
