class_name PolicyFollowLowestHpAlly
extends MovementPolicy
## AC-S2: pathfind one step toward the same-team ally with the lowest hp/max_hp ratio.
## Excludes self. Full-HP allies are eligible (so a healer doesn't sit alone if no one
## is hurt — they trail their lowest-hp teammate).
## No allies on the map → (-1,-1) (Q-AI-6 hold + log).


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var actors: Array = ctx.get("all_actors", [])
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_ratio: float = 2.0
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
		if other.team != actor.team:
			# Opposing team — block (don't path through them).
			blocked.append(c)
			continue
		# Same team — candidate to follow. Also a block if not the chosen one.
		if other.max_hp <= 0:
			blocked.append(c)
			continue
		var ratio: float = float(other.hp) / float(other.max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			# Previous candidate (if any) is now an obstacle, but we don't track that here —
			# planner-level optimization, ok to over-block (worst case: longer path).
			target_coord = c
		else:
			blocked.append(c)

	if target_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var path: Array = grid.find_path_around(my_coord, target_coord, blocked)
	# 029 / req-5: full-speed walk, never step onto ally's own hex.
	var max_steps: int = mini(actor.effective_speed(), path.size() - 2)
	if max_steps <= 0:
		return Vector2i(-1, -1)
	return path[max_steps]
