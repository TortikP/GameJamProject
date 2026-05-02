class_name PolicyKiteSpecificActor
extends MovementPolicy
## Step one hex AWAY from the actor identified by ctx["behavior_target_id"]
## (used by the `feared` AI scenario). Picks the neighbor that maximises
## hex_distance to source. If no neighbor improves distance → return (-1,-1)
## (hold — no escape route).
##
## Source null/dead/missing-coord → (-1,-1) (defer; status will expire next
## tick via FearedRuntime.on_turn_start and behavior_id restores).
## 027: spec §"AI scenario building blocks" / AC-AI5.


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	var registry: ActorRegistry = ctx.get("registry") as ActorRegistry
	var bid: StringName = ctx.get("behavior_target_id", &"")
	if grid == null or registry == null or bid == &"":
		return Vector2i(-1, -1)
	var src: Actor = registry.get_actor(bid)
	if src == null or not src.is_alive():
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	var src_coord: Vector2i = grid.get_coord(src.actor_id)
	if my_coord == Vector2i(-1, -1) or src_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var current_d: int = grid.hex_distance(my_coord, src_coord)
	var best_step: Vector2i = my_coord
	var best_d: int = current_d
	for n in grid.tile_map_layer.get_surrounding_cells(my_coord):
		if not grid.is_walkable(n):
			continue
		if grid.get_actor_at(n) != &"":
			continue
		var d: int = grid.hex_distance(n, src_coord)
		if d > best_d:
			best_d = d
			best_step = n
	if best_step == my_coord:
		return Vector2i(-1, -1)
	return best_step
