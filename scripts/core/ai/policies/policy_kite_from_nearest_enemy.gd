class_name PolicyKiteFromNearestEnemy
extends MovementPolicy
## AC-S2: step into the walkable neighbor that maximizes distance to the nearest
## opposing-team actor. If no neighbor is better than current spot OR no enemies
## exist on the map → return (-1,-1) (planner falls back to hold + log per Q-AI-6).


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	# Collect enemy coords + occupied tiles.
	var actors: Array = ctx.get("all_actors", [])
	var enemy_coords: Array[Vector2i] = []
	var occupied: Dictionary = {}   # Vector2i -> true
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c == Vector2i(-1, -1):
			continue
		occupied[c] = true
		if other.team != actor.team:
			enemy_coords.append(c)

	if enemy_coords.is_empty():
		return Vector2i(-1, -1)   # no anchor

	# Score: minimum distance to ANY enemy. Higher = safer.
	var current_score: int = _min_dist_to_enemies(my_coord, enemy_coords, grid)
	var best_step: Vector2i = Vector2i(-1, -1)
	var best_score: int = current_score

	for nb in grid.get_walkable_neighbours(my_coord):
		if occupied.has(nb):
			continue
		var s: int = _min_dist_to_enemies(nb, enemy_coords, grid)
		if s > best_score:
			best_score = s
			best_step = nb

	return best_step


func _min_dist_to_enemies(from: Vector2i, enemies: Array[Vector2i], grid: HexGrid) -> int:
	var best: int = 0x7fffffff
	for e in enemies:
		var d: int = grid.hex_distance(from, e)
		if d >= 0 and d < best:
			best = d
	return best
