class_name PolicyMaintainRange
extends MovementPolicy
## 030 (post-playtest fix): keep actor inside [desired_min, desired_max] hex
## distance from the nearest opposing-team actor.
##
## Why: kite_from_nearest_enemy ALWAYS maximises distance — ranged enemies
## using it just run forever even when already in attack range. This policy
## holds at attack range and only moves when out of position.
##
## Algorithm:
##   d = distance to nearest enemy
##   d > desired_max  → approach one step (path[1] toward enemy)
##   d < desired_min  → kite one step (walkable neighbour with max distance)
##   else             → hold (-1,-1)

@export var desired_min: int = 2
@export var desired_max: int = 3


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var actors: Array = ctx.get("all_actors", [])
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	var blocked: Array = []
	var occupied: Dictionary = {}
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
		if other.team == actor.team:
			blocked.append(c)
			continue
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			target_coord = c

	if target_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)   # no enemy → hold

	# In sweet spot — hold position.
	if best_d >= desired_min and best_d <= desired_max:
		return Vector2i(-1, -1)

	# Too far — approach.
	if best_d > desired_max:
		var path: Array = grid.find_path_around(my_coord, target_coord, blocked)
		if path.size() < 2:
			return Vector2i(-1, -1)
		return path[1]

	# Too close — kite one step (neighbour that maximises distance to target).
	var best_step: Vector2i = Vector2i(-1, -1)
	var best_score: int = best_d
	for nb in grid.get_walkable_neighbours(my_coord):
		if occupied.has(nb):
			continue
		var s: int = grid.hex_distance(nb, target_coord)
		if s > best_score:
			best_score = s
			best_step = nb
	return best_step
