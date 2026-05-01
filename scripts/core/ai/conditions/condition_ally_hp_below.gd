class_name ConditionAllyHpBelow
extends TacticCondition
## AC-C7: at least one same-team ally (excluding self) within `distance` whose
## hp/max_hp*100 < pct. Triggers heal rules.

@export var pct: int = 50
@export var distance: int = 3


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return false
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return false
	var actors: Array = ctx.get("all_actors", [])
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.max_hp <= 0:
			continue
		if other.hp * 100 >= other.max_hp * pct:
			continue
		var their_coord: Vector2i = grid.get_coord(other.actor_id)
		if their_coord == Vector2i(-1, -1):
			continue
		var d: int = grid.hex_distance(my_coord, their_coord)
		if d >= 0 and d <= distance:
			return true
	return false
