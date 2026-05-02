class_name SelectorPlayerEscapeHex
extends TargetSelector
## 030+: predict where the player can move within one turn and return the best
## unclaimed hex among those reachable positions.
##
## Algorithm:
##   1. Validate HexTarget skill (actor-only skills return null).
##   2. Locate the nearest opposing-team actor (the player).
##   3. BFS from player's coord up to player.effective_speed steps → escape_hexes.
##   4. Remove hexes already claimed by same-team allies' cast_intent (they are
##      covered) and hexes outside this actor's skill range.
##   5. Among uncovered escape hexes, pick the one that hits the most enemies
##      through the skill's area (tiebreak: lowest hex_distance to actor).
##
## Falls through to null → planner tries next rule (direct attack fallback).


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null

	# 1. Validate HexTarget.
	var skill: Skill = ctx.get("candidate_skill")
	if skill == null or skill.abilities.is_empty():
		return null
	var ab: Ability = skill.abilities[0]
	if ab == null or ab.target == null or not (ab.target is HexTarget):
		return null
	var skill_range: int = (ab.target as HexTarget).range

	# 2. Find player (nearest living opponent from candidates).
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	var player: Actor = null
	var player_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	var all_actors: Array = ctx.get("all_actors", [])
	# collect all enemy coords for hit-count scoring
	var enemy_coords: Array = []
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if not cand.is_alive():
			continue
		var c: Vector2i = grid.get_coord(cand.actor_id)
		if c == Vector2i(-1, -1):
			continue
		enemy_coords.append(c)
		var d: int = grid.hex_distance(my_coord, c)
		if d >= 0 and d < best_d:
			best_d = d
			player = cand
			player_coord = c
	if player == null:
		return null

	# 3. BFS from player_coord up to player.effective_speed steps.
	var move_budget: int = player.effective_speed()
	if move_budget <= 0:
		move_budget = 1   # minimum 1 so at least neighbours are considered
	var visited: Dictionary = {}   # coord -> true
	var escape_hexes: Array = []   # plain Array[Vector2i]
	visited[player_coord] = true
	var frontier: Array = [player_coord]
	for _depth in range(move_budget):
		var next_frontier: Array = []
		for fc in frontier:
			for nb in grid.get_walkable_neighbours(fc):
				if visited.has(nb):
					continue
				visited[nb] = true
				escape_hexes.append(nb)
				next_frontier.append(nb)
		frontier = next_frontier
		if frontier.is_empty():
			break

	# Always include player's own hex (they might stay put).
	if not (player_coord in escape_hexes):
		escape_hexes.append(player_coord)

	# 4. Filter: remove claimed and out-of-range hexes.
	var claimed: Array = []   # plain Array
	for other_v in all_actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.cast_intent != null and other.cast_intent.is_valid():
			claimed.append(other.cast_intent.target_coord)

	# Collect ally positions for friendly-fire check.
	var ally_coords: Array = []
	for other_v2 in all_actors:
		if not (other_v2 is Actor):
			continue
		var other2: Actor = other_v2
		if other2 == actor or not other2.is_alive() or other2.team != actor.team:
			continue
		var ally_c: Vector2i = grid.get_coord(other2.actor_id)
		if ally_c != Vector2i(-1, -1):
			ally_coords.append(ally_c)

	var uncovered: Array = []
	for hex in escape_hexes:
		if hex in claimed:
			continue
		if skill_range >= 0 and grid.hex_distance(my_coord, hex) > skill_range:
			continue
		if _hits_ally(hex, ab, my_coord, ally_coords, grid):
			continue   # would damage a same-team unit
		uncovered.append(hex)

	if uncovered.is_empty():
		return null

	# 5. Best hex by hit-count, then closest to actor (tiebreak).
	var best_hex: Vector2i = Vector2i(-1, -1)
	var best_hits: int = -1
	var best_dist: int = 0x7fffffff
	for hex in uncovered:
		var hits: int = _count_hits(hex, ab, my_coord, enemy_coords, grid)
		var dist: int = grid.hex_distance(my_coord, hex)
		if hits > best_hits or (hits == best_hits and dist < best_dist):
			best_hits = hits
			best_dist = dist
			best_hex = hex

	return best_hex if best_hex != Vector2i(-1, -1) else null


func _count_hits(hex: Vector2i, ab: Ability, caster_coord: Vector2i,
			enemy_coords: Array, grid: HexGrid) -> int:
	if ab.area != null:
		var affected: Array = ab.area.get_affected_hexes(caster_coord, hex, grid)
		var n: int = 0
		for h in affected:
			if h in enemy_coords:
				n += 1
		return n
	return 1


func _hits_ally(hex: Vector2i, ab: Ability, caster_coord: Vector2i,
			ally_coords: Array, grid: HexGrid) -> bool:
	if ab.area == null:
		return hex in ally_coords
	var affected: Array = ab.area.get_affected_hexes(caster_coord, hex, grid)
	for h in affected:
		if h in ally_coords:
			return true
	return false
