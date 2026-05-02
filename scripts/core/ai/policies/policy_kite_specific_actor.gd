class_name PolicyKiteSpecificActor
extends MovementPolicy
## Walk up to actor.effective_speed() hexes AWAY from the actor identified by
## ctx["behavior_target_id"] (used by the `feared` AI scenario). Returns the
## destination hex that maximises hex_distance to source among all coords
## reachable within the speed budget. If no reachable coord improves
## distance → return (-1,-1) (hold — no escape route).
##
## Source null/dead/missing-coord → (-1,-1) (defer; status will expire next
## tick via FearedRuntime.on_turn_start and behavior_id restores).
##
## 027: spec §"AI scenario building blocks" / AC-AI5.
## 034: was 1-hex/turn regardless of speed — feared enemy with speed=5
## kited only 1 tile/turn. Fix: use HexGrid.reachable_within to enumerate
## every hex within effective_speed and pick the one furthest from source.
## Mirrors PolicyApproachSpecificActor's full-speed walk (029/req-5).


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

	var speed: int = actor.effective_speed()
	if speed <= 0:
		return Vector2i(-1, -1)

	# Other live actors block the path. Source included — we never want to
	# step onto src (would close to melee, opposite of kite).
	var occupied: Array = []
	for other_v in ctx.get("all_actors", []):
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c != Vector2i(-1, -1):
			occupied.append(c)

	# BFS yields candidates ring-by-ring (1 step, 2 steps, …). Strict >
	# comparison keeps the first match at any given distance, which is
	# the closest one in path-length. So if multiple hexes share the
	# maximum kite distance, we pick the cheapest to reach.
	var current_d: int = grid.hex_distance(my_coord, src_coord)
	var best_step: Vector2i = Vector2i(-1, -1)
	var best_d: int = current_d
	for cand in grid.reachable_within(my_coord, speed, occupied):
		var d: int = grid.hex_distance(cand, src_coord)
		if d > best_d:
			best_d = d
			best_step = cand
	return best_step
