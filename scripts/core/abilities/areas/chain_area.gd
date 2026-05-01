class_name ChainArea
extends AbilityArea
## ChainArea — BFS chain of up to max_chain_length targets.
##
## Starting from primary_target, each next step picks the nearest unvisited
## walkable neighbour that has an Actor on it. Chain stops when no valid
## neighbour exists or length is reached.
##
## "Single target" = ChainArea(max_chain_length=1).

@export var max_chain_length: int = 1


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

	# Add caster's coord to visited so we don't bounce back
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	if caster_coord != Vector2i(-1, -1):
		visited_coords[caster_coord] = true

	var current_coord: Vector2i = start_coord

	for _step in max_chain_length:
		# Try to resolve an Actor at current_coord
		var occupant_id: StringName = grid.get_actor_at(current_coord)
		if occupant_id != &"":
			var actor: Actor = registry.get_actor(occupant_id)
			if actor != null and actor.is_alive() and actor != caster:
				results.append(actor)

		# Find next link: walkable neighbour with an alive non-caster actor, not yet visited
		var best_next: Vector2i = Vector2i(-1, -1)
		for nb in grid.get_walkable_neighbours(current_coord):
			if visited_coords.has(nb):
				continue
			var nb_id: StringName = grid.get_actor_at(nb)
			if nb_id == &"" or nb_id == caster.actor_id:
				visited_coords[nb] = true   # mark so we skip empty hexes efficiently
				continue
			var nb_actor: Actor = registry.get_actor(nb_id)
			if nb_actor == null or not nb_actor.is_alive():
				visited_coords[nb] = true
				continue
			# First valid unvisited neighbour wins (consistent ordering)
			best_next = nb
			break

		if best_next == Vector2i(-1, -1):
			break   # chain broken
		visited_coords[best_next] = true
		current_coord = best_next

	return results


func get_affected_hexes(_caster_coord: Vector2i, primary: Variant, _grid: HexGrid) -> Array[Vector2i]:
	if primary is Vector2i:
		return [primary as Vector2i]
	return []


# ── Helpers ──────────────────────────────────────────────────────────────────

func _coord_of(primary: Variant, caster: Actor, grid: HexGrid) -> Vector2i:
	if primary is Actor:
		return grid.get_coord((primary as Actor).actor_id)
	if primary is Vector2i:
		return primary as Vector2i
	# Fallback: caster position (for self-chain edge case)
	return grid.get_coord(caster.actor_id)
