class_name SingleEnemyAdjacentTarget
extends SingleEnemyTarget
## Single-enemy target that additionally requires the enemy to be on a
## hex adjacent to the caster. Adjacency is measured via grid.find_path —
## path of size 2 means [caster, target] = one step apart.


func resolve(caster: Actor, ctx: Dictionary) -> Array:
	var base: Array = super.resolve(caster, ctx)
	if base.is_empty():
		return []
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return []
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	var target_actor: Actor = base[0]
	var target_coord: Vector2i = grid.get_coord(target_actor.actor_id)
	var path: Array = grid.find_path(caster_coord, target_coord)
	if path.size() != 2:
		return []
	return base
