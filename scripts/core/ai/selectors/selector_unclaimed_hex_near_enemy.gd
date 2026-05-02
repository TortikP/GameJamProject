class_name SelectorUnclaimedHexNearEnemy
extends TargetSelector
## AC-T8 (030): return a Vector2i hex adjacent to the nearest enemy that is NOT
## already claimed by a same-team ally's cast_intent. Returns null if all adjacent
## hexes are claimed or if the candidate_skill is not a HexTarget skill.
##
## Candidates = opposing-team actors (from _build_target_candidates want_allies=false).
## Claimed  = same-team cast_intent.target_coord of allies who already planned this turn.
## Tiebreak: hex that would hit the most enemies through the skill's area (AC-T8 §5).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null

	# 1. Target.kind validation — only fire for HexTarget skills (AC, plan §hex-targeting).
	var skill: Skill = ctx.get("candidate_skill")
	if skill == null or skill.abilities.is_empty():
		return null
	var ab: Ability = skill.abilities[0]
	if ab == null or ab.target == null:
		return null
	if not (ab.target is HexTarget):
		return null   # actor-only skill — planner will skip this entry

	# 2. Nearest enemy from candidates.
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	var enemy_coords: Array = []   # plain Array for Variant-safety
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
			target_coord = c
	if target_coord == Vector2i(-1, -1):
		return null

	# 3. Claimed coords + ally positions (friendly-fire filter).
	var all_actors: Array = ctx.get("all_actors", [])
	var claimed: Array = []
	var ally_coords: Array = []
	for other_v in all_actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		var ac: Vector2i = grid.get_coord(other.actor_id)
		if ac != Vector2i(-1, -1):
			ally_coords.append(ac)
		if other.cast_intent != null and other.cast_intent.is_valid():
			claimed.append(other.cast_intent.target_coord)

	# 4. Candidate hexes: neighbours of target + target itself.
	var hexes: Array = grid.get_walkable_neighbours(target_coord)
	hexes.append(target_coord)

	# 5. Skip claimed and friendly-fire hexes; best enemy hit-count tiebreak.
	var best_hex: Vector2i = Vector2i(-1, -1)
	var best_hits: int = -1
	for hex in hexes:
		if hex in claimed:
			continue
		if _hits_ally(hex, ab, my_coord, ally_coords, grid):
			continue
		var hits: int = _count_hits(hex, ab, my_coord, enemy_coords, grid)
		if hits > best_hits:
			best_hits = hits
			best_hex = hex

	if best_hex == Vector2i(-1, -1):
		return null
	return best_hex


func _count_hits(hex: Vector2i, ab: Ability, caster_coord: Vector2i,
			enemy_coords: Array, grid: HexGrid) -> int:
	if ab.area != null:
		var affected: Array = ab.area.get_affected_hexes(caster_coord, hex, grid)
		var n: int = 0
		for h in affected:
			if h in enemy_coords:
				n += 1
		return n
	return 1   # no area — counts as 1 (the hex itself)


func _hits_ally(hex: Vector2i, ab: Ability, caster_coord: Vector2i,
			ally_coords: Array, grid: HexGrid) -> bool:
	## Returns true if the skill's area fired at hex would cover any ally position.
	if ab.area == null:
		return hex in ally_coords
	var affected: Array = ab.area.get_affected_hexes(caster_coord, hex, grid)
	for h in affected:
		if h in ally_coords:
			return true
	return false
