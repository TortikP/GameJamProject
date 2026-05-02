class_name PolicyApproachSpecificActor
extends MovementPolicy
## Step one hex toward the actor identified by ctx["behavior_target_id"]
## (used by the `enraged` AI scenario). All other actors are obstacles for
## pathing — same convention as PolicyApproachNearestEnemy.
##
## If source is null/dead/missing-coord — return (-1,-1) (defer to fallback,
## which in our enraged scenario is empty → planner logs "no anchor" and holds).
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

	# Block all other live actors (excluding self and source — we path TO source).
	var blocked: Array = []
	for other_v in ctx.get("all_actors", []):
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or other == src or not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c != Vector2i(-1, -1):
			blocked.append(c)
	var path: Array = grid.find_path_around(my_coord, src_coord, blocked)
	# 029 / req-5: full-speed walk, never step onto source's own hex.
	var max_steps: int = mini(actor.effective_speed(), path.size() - 2)
	if max_steps <= 0:
		return Vector2i(-1, -1)
	return path[max_steps]
