class_name PolicyApproachNearestEnemyUnclaimed
extends MovementPolicy
## AC-MP5 (030): like PolicyApproachNearestEnemy but avoids stepping onto a hex
## already claimed as move_intent_coord by a same-team ally. Prevents melee pile-up
## when multiple enemies converge on the same player-adjacent cell.
##
## Falls back to path[1] if no unclaimed step exists within 2 hops (never blocks
## movement completely — let the engine handle collision).


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	# Find nearest enemy and build blocked list (same logic as PolicyApproachNearestEnemy).
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
		if other.team == actor.team:
			blocked.append(c)
			continue
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			target_coord = c

	if target_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var path: Array = grid.find_path_around(my_coord, target_coord, blocked)
	if path.size() < 2:
		return Vector2i(-1, -1)

	# Collect move steps already claimed by same-team allies.
	var taken: Array = []   # plain Array — Variant-safe
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.move_intent_coord != Vector2i(-1, -1):
			taken.append(other.move_intent_coord)

	# Try path[1] then path[2]; fall back to path[1] if both taken.
	for i in [1, 2]:
		if i >= path.size():
			break
		if not (path[i] in taken):
			return path[i]

	return path[1]
