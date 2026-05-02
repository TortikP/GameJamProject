class_name SelectorHexWithMostWoundedAllies
extends TargetSelector
## 030+: pick the hex within skill range that would cover the most wounded allies
## when the skill's area is applied. Used by support healers with AoE heal skills.
##
## "Wounded" = hp/max_hp < wounded_threshold (configurable, default 0.7).
## Candidates parameter is ignored — ally data comes directly from ctx.all_actors.
## Validates HexTarget; returns null for actor-targeting skills.

@export var wounded_threshold: float = 0.7


func resolve(actor: Actor, _candidates: Array, ctx: Dictionary) -> Variant:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return null

	# Validate HexTarget.
	var skill: Skill = ctx.get("candidate_skill")
	if skill == null or skill.abilities.is_empty():
		return null
	var ab: Ability = skill.abilities[0]
	if ab == null or ab.target == null or not (ab.target is HexTarget):
		return null
	var skill_range: int = (ab.target as HexTarget).range

	var my_coord: Vector2i = grid.get_coord(actor.actor_id)

	# Collect wounded ally coords.
	var all_actors: Array = ctx.get("all_actors", [])
	var wounded_coords: Array = []   # plain Array
	for other_v in all_actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		if other.max_hp <= 0:
			continue
		var ratio: float = float(other.hp) / float(other.max_hp)
		if ratio < wounded_threshold:
			var c: Vector2i = grid.get_coord(other.actor_id)
			if c != Vector2i(-1, -1):
				wounded_coords.append(c)

	if wounded_coords.is_empty():
		return null

	# Score every hex in skill range from actor.
	# Candidate hexes: iterate all wounded ally coords + their neighbours (likely targets).
	var checked: Dictionary = {}
	var best_hex: Vector2i = Vector2i(-1, -1)
	var best_score: int = 0

	for wc in wounded_coords:
		var hexes_to_try: Array = grid.get_walkable_neighbours(wc)
		hexes_to_try.append(wc)
		for hex in hexes_to_try:
			if checked.has(hex):
				continue
			checked[hex] = true
			if skill_range >= 0 and grid.hex_distance(my_coord, hex) > skill_range:
				continue
			var score: int = _count_wounded_covered(hex, ab, my_coord, wounded_coords, grid)
			if score > best_score:
				best_score = score
				best_hex = hex

	return best_hex if best_score > 0 else null


func _count_wounded_covered(hex: Vector2i, ab: Ability, caster_coord: Vector2i,
			wounded_coords: Array, grid: HexGrid) -> int:
	if ab.area != null:
		var affected: Array = ab.area.get_affected_hexes(caster_coord, hex, grid)
		var n: int = 0
		for h in affected:
			if h in wounded_coords:
				n += 1
		return n
	return 1 if (hex in wounded_coords) else 0
