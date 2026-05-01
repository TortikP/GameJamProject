class_name SelectorDensestEnemyHex
extends TargetSelector
## AC-T6: return the hex (Vector2i) that, when used as primary target of the rule's
## chosen Skill, would hit the most enemies. Uses Skill.abilities[0].area.get_affected_hexes
## from 007 architecture §6.
##
## NOTE: this selector requires the skill to be passed via ctx because area shape depends
## on it. EnemyAIPlanner sets ctx.candidate_skill before calling resolve() for selectors
## that need it. If absent, falls back to picking the hex of the densest enemy cluster
## using a simple radius-1 neighborhood (cheap heuristic).


func resolve(actor: Actor, candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null
	var enemy_coords: Array[Vector2i] = []
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var c: Vector2i = grid.get_coord((cand_v as Actor).actor_id)
		if c != Vector2i(-1, -1):
			enemy_coords.append(c)
	if enemy_coords.is_empty():
		return null

	var skill: Skill = ctx.get("candidate_skill")
	var caster_coord: Vector2i = grid.get_coord(actor.actor_id)

	# If we have the skill and its first ability area, use that for accurate counting.
	if skill != null and not skill.abilities.is_empty():
		var ab: Ability = skill.abilities[0]
		if ab != null and ab.area != null:
			var best_coord: Vector2i = enemy_coords[0]
			var best_hits: int = 0
			for primary in enemy_coords:
				var affected: Array[Vector2i] = ab.area.get_affected_hexes(caster_coord, primary, grid)
				var hits: int = 0
				for hex in affected:
					if enemy_coords.has(hex):
						hits += 1
				if hits > best_hits:
					best_hits = hits
					best_coord = primary
			return best_coord

	# Fallback: pick the enemy whose 1-hex neighborhood contains the most other enemies.
	var best_coord_fb: Vector2i = enemy_coords[0]
	var best_hits_fb: int = 0
	for primary in enemy_coords:
		var hits: int = 1   # primary itself
		for nb in grid.get_walkable_neighbours(primary):
			if enemy_coords.has(nb):
				hits += 1
		if hits > best_hits_fb:
			best_hits_fb = hits
			best_coord_fb = primary
	return best_coord_fb
