class_name SelectorNearestEnemy
extends TargetSelector
## AC-T1: pick the closest opposing-team actor. Tiebreak — first in candidates order.


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return null
	var best: Actor = null
	var best_d: int = 0x7fffffff
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		var c: Vector2i = grid.get_coord(cand.actor_id)
		if c == Vector2i(-1, -1):
			continue
		var d: int = grid.hex_distance(my_coord, c)
		if d < 0:
			continue
		if d < best_d:
			best_d = d
			best = cand
	return best
