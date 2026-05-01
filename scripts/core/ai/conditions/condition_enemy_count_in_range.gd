class_name ConditionEnemyCountInRange
extends TacticCondition
## AC-C6: at least `min_count` opposing-team actors within `distance` hexes.
## Triggers AOE rules ("3+ enemies clustered → cast fireball").

@export var distance: int = 3
@export var min_count: int = 2


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return false
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return false
	var actors: Array = ctx.get("all_actors", [])
	var hits: int = 0
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team == actor.team:
			continue
		var their_coord: Vector2i = grid.get_coord(other.actor_id)
		if their_coord == Vector2i(-1, -1):
			continue
		var d: int = grid.hex_distance(my_coord, their_coord)
		if d >= 0 and d <= distance:
			hits += 1
			if hits >= min_count:
				return true
	return false
