class_name ConditionUnclaimedHexExistsNearEnemy
extends TacticCondition
## AC-C10 (030): true if at least one hex within `distance` of the nearest opposing-team
## actor is NOT already claimed by a same-team ally's cast_intent.target_coord.
## Allows ranged enemies to detect available "pressure" hexes before firing Rule 2.

@export var distance: int = 1


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return false
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return false

	# Find nearest living opponent.
	var actors: Array = ctx.get("all_actors", [])
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team == actor.team:
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c == Vector2i(-1, -1):
			continue
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			target_coord = c
	if target_coord == Vector2i(-1, -1):
		return false

	# Collect hexes claimed by same-team allies that already have a cast_intent.
	var claimed: Array = []   # plain Array — typed Array[Vector2i] causes Variant-boundary crash
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.cast_intent != null and other.cast_intent.is_valid():
			claimed.append(other.cast_intent.target_coord)

	# Check neighbours of the target (within distance) + the target hex itself.
	var hexes: Array = grid.get_walkable_neighbours(target_coord)
	hexes.append(target_coord)
	for hex in hexes:
		var d: int = grid.hex_distance(target_coord, hex)
		if d > distance:
			continue
		if not (hex in claimed):
			return true
	return false
