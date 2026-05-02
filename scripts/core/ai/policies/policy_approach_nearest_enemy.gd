class_name PolicyApproachNearestEnemy
extends MovementPolicy
## AC-S2: step one hex closer to the nearest opposing-team actor.
## Uses HexGrid.find_path_around with other actors' positions blocked
## (matches current manekin AI behavior bit-for-bit, AC-S1 backward-compat).


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	# Find nearest enemy (by hex distance, ignoring blocks for the "find target" step).
	var actors: Array = ctx.get("all_actors", [])
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	var blocked: Array = []
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c == Vector2i(-1, -1):
			continue
		# Same-team and dead actors are obstacles when pathing.
		if other.team == actor.team:
			blocked.append(c)
			continue
		# Opposing team — candidate target. Don't add to `blocked` (path TO them).
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			target_coord = c

	if target_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)   # no anchor → hold

	var path: Array = grid.find_path_around(my_coord, target_coord, blocked)
	# 029 / req-5: walk up to effective_speed steps along the path, but never
	# step ONTO the target's own hex (path[-1]). path.size()-2 is the index of
	# the cell adjacent to target; capping to that keeps melee range intact.
	# Returns (-1,-1) if we're already adjacent (max_steps == 0).
	var max_steps: int = mini(actor.effective_speed(), path.size() - 2)
	if max_steps <= 0:
		return Vector2i(-1, -1)
	return path[max_steps]
