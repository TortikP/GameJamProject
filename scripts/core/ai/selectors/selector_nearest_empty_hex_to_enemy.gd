class_name SelectorNearestEmptyHexToEnemy
extends TargetSelector
## 044: returns a Vector2i hex for summon-tagged skills — empty (no actor / no
## tile-object), walkable, within the candidate skill's range, BFS-closest to
## the nearest opposing-team actor. Skips hexes already claimed by same-team
## allies' cast_intent (030 intent-awareness).
##
## Symmetric input contract with `unclaimed_hex_near_enemy` (030 AC-T8) but
## different semantics: that one finds a hex maximising AOE enemy-hits, this
## one finds a hex suitable for SPAWNING (empty + close to enemy). They share
## the HexTarget gate and the claimed-by-allies filter; everything else differs.
##
## See specs/044-summoned-entity-ai/.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const MAX_RING: int = 32   # AC-S5 safety cap; jam-arena ~10×10 needs <= ring 5


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null

	# AC-S2: HexTarget validation. Summon skills are hex-targeted; if planner
	# is probing this selector for an actor-target skill, fail fast — planner
	# will then skip this skill entry.
	var skill: Skill = ctx.get("candidate_skill")
	if skill == null or skill.abilities.is_empty():
		return null
	var ab: Ability = skill.abilities[0]
	if ab == null or ab.target == null or not (ab.target is HexTarget):
		return null
	var max_range: int = int(ab.target.range)   # -1 → unbounded

	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return null

	# AC-S3: nearest opposing-team actor by hex distance. Candidates are
	# already filtered to opposing team by EnemyAIPlanner._build_target_candidates
	# (want_allies=false branch). We just pick the closest live one.
	var enemy_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if not cand.is_alive():
			continue
		var c: Vector2i = grid.get_coord(cand.actor_id)
		if c == Vector2i(-1, -1):
			continue
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			enemy_coord = c
	if enemy_coord == Vector2i(-1, -1):
		return null

	# AC-S4: hexes already claimed by same-team allies' cast_intent (030).
	# Don't summon onto a hex an ally is about to AOE.
	var claimed: Dictionary = {}   # Vector2i -> bool
	var all_actors: Array = ctx.get("all_actors", [])
	for other_v in all_actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.cast_intent != null and other.cast_intent.is_valid():
			claimed[other.cast_intent.target_coord] = true

	# AC-S5/S6: BFS rings outward from enemy_coord. Visit each cell once.
	# Within a ring, prefer the hex closest to the caster (we're summoning at
	# range, so pulling spawn closer to caster minimises wasted distance for
	# the spawned actor's first move toward target). Tie-break is iteration
	# order from grid.get_walkable_neighbours, which is deterministic.
	var visited: Dictionary = {}   # Vector2i -> bool
	var frontier: Array = [enemy_coord]
	visited[enemy_coord] = true
	var ring: int = 0
	while ring <= MAX_RING and not frontier.is_empty():
		var best_hex: Vector2i = Vector2i(-1, -1)
		var best_caster_d: int = 0x7fffffff
		for hex_v in frontier:
			var hex: Vector2i = hex_v
			if not _is_summon_target_ok(hex, grid, max_range, my_coord, claimed):
				continue
			var cd: int = grid.hex_distance(my_coord, hex)
			if cd >= 0 and cd < best_caster_d:
				best_caster_d = cd
				best_hex = hex
		if best_hex != Vector2i(-1, -1):
			return best_hex

		# Expand to next ring via walkable-neighbour traversal. Unwalkable
		# cells naturally drop out (get_walkable_neighbours already filters).
		# Cells that are walkable but unsuitable for spawn (occupied by actor
		# / tile-object / out-of-range / claimed) still propagate the BFS
		# frontier — we don't want a single occupied actor to break the ring
		# expansion past it.
		var next_frontier: Array = []
		for hex_v in frontier:
			var hex: Vector2i = hex_v
			for nb in grid.get_walkable_neighbours(hex):
				if visited.has(nb):
					continue
				visited[nb] = true
				next_frontier.append(nb)
		frontier = next_frontier
		ring += 1
	return null


# AC-S4: hex is a valid summon target iff walkable, no actor on it, no
# tile-object on it, within caster's skill range, not claimed by ally.
func _is_summon_target_ok(hex: Vector2i, grid: HexGrid, max_range: int,
		caster_coord: Vector2i, claimed: Dictionary) -> bool:
	if not grid.is_walkable(hex):
		return false
	if grid.get_actor_at(hex) != &"":
		return false
	if grid.get_tile_object_id(hex) != &"":
		return false
	if max_range >= 0:
		var d: int = grid.hex_distance(caster_coord, hex)
		if d < 0 or d > max_range:
			return false
	if claimed.has(hex):
		return false
	return true
