class_name ActorTarget
extends AbilityTarget
## ActorTarget — resolves one Actor from ctx["target_id"].
##
## 021: renamed from EntityTarget (file: entity_target.gd → actor_target.gd).
## JSON kind: "actor" (was "entity").
##
## @export range:
##   -1  = unrestricted (any alive actor, including caster)
##    0  = self only
##    1+ = within N path-steps of caster (adjacency: range=1, includes caster)
##
## 035: caster IS now a valid pick — the previous `if actor == caster: return null`
## contradicted the documented `range=0 = self only` semantic and made
## target=actor heals/buffs unable to land on the caster. Designers control
## self-targetability via `range` and behaviour_tags.
##
## Returns the Actor or null. Never returns dead actors.

@export var range: int = -1


func resolve(caster: Actor, ctx: Dictionary) -> Variant:
	var registry: ActorRegistry = ctx.get("registry")
	if registry == null:
		return null
	var id: StringName = ctx.get("target_id", &"")
	if id == &"":
		return null
	var actor: Actor = registry.get_actor(id)
	if actor == null or not actor.is_alive():
		return null
	# 035: self-target shortcut. Skip the path/range walk — distance to
	# self is always 0, which satisfies any range >= 0. find_path(c, c)
	# is implementation-defined and we don't want to depend on it.
	if actor == caster:
		return actor
	if range >= 0:
		var grid: HexGrid = ctx.get("grid")
		if grid == null:
			return null
		var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
		var target_coord: Vector2i = grid.get_coord(id)
		if caster_coord == Vector2i(-1, -1) or target_coord == Vector2i(-1, -1):
			return null
		var path: Array[Vector2i] = grid.find_path(caster_coord, target_coord)
		# path includes start+end, so steps = path.size()-1; empty path = unreachable
		var steps: int = path.size() - 1 if path.size() > 0 else 999
		if steps > range:
			return null
	return actor


func get_range_hexes(caster_coord: Vector2i, grid: HexGrid) -> Array[Vector2i]:
	if range < 0:
		return grid.get_all_walkable_coords()
	if range == 0:
		return [caster_coord]
	# 035 cont.: include caster_coord. Without it, the FSM click validator
	# (godmode_controller._handle_cast_lmb) rejects clicks on self before
	# resolve() ever runs — so the resolve-side self fix in 035 was masked.
	# BFS still walks neighbours; we just seed the result with caster.
	var visited: Dictionary = {caster_coord: true}
	var frontier: Array[Vector2i] = [caster_coord]
	var result: Array[Vector2i] = [caster_coord]
	for _step in range:
		var next: Array[Vector2i] = []
		for coord in frontier:
			for nb in grid.get_walkable_neighbours(coord):
				if not visited.has(nb):
					visited[nb] = true
					result.append(nb)
					next.append(nb)
		frontier = next
	return result


## 021 scaling: range += level if range > 1.
## Adjacency (range=1), self-only (range=0), and unrestricted (range=-1)
## are designed values — not scaled.
func apply_level(level: int) -> void:
	if level <= 0 or range <= 1:
		return
	range += level
