class_name ConditionAoeNetPositive
extends TacticCondition
## True if firing at the nearest enemy would hit strictly more enemies than allies.
##
## Works for both chain and zone_circle skills:
##   chain: checks actors adjacent to the nearest enemy within check_radius hexes.
##          Simulates the chain's second hop — does it land on an ally or another enemy?
##   zone_circle: calls get_affected_hexes and counts occupants.
##   single-target (area == null): always returns true (no collateral).
##
## Formula: (primary_enemy + additional_enemies) > ally_hits
##   → strictly more enemies damaged than allies → cast is net positive.
##
## @export check_radius: how far from the nearest enemy to look for chain victims.
##   Mirrors ChainArea.radius (default 1).

@export var check_radius: int = 1


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return true   # can't check → don't block
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return true

	var actors: Array = ctx.get("all_actors", [])

	# Find nearest living enemy and collect all actor positions.
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_d: int = 0x7fffffff
	var ally_coords: Array = []    # same team, alive, excl. self
	var enemy_coords: Array = []   # opposite team, alive

	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c == Vector2i(-1, -1):
			continue
		if other.team == actor.team:
			if other != actor:
				ally_coords.append(c)
		else:
			enemy_coords.append(c)
			var d: int = grid.hex_distance(my_coord, c)
			if d >= 0 and d < best_d:
				best_d = d
				target_coord = c

	if target_coord == Vector2i(-1, -1):
		return true   # no enemy → condition not relevant

	# If no allies anywhere → always safe.
	if ally_coords.is_empty():
		return true

	# Check each skill — if ANY skill is net positive, return true.
	for skill_v in actor.get_skills():
		if not (skill_v is Skill):
			continue
		var skill: Skill = skill_v
		if skill.abilities.is_empty():
			continue
		var ab: Ability = skill.abilities[0]
		if ab == null:
			continue

		# No area → single target (primary enemy only) → always safe.
		if ab.area == null:
			return true

		# Zone_circle: use get_affected_hexes.
		if ab.area is ZoneCircleArea:
			var affected: Array = ab.area.get_affected_hexes(my_coord, target_coord, grid)
			var e_hits: int = 0
			var a_hits: int = 0
			for h in affected:
				if h in enemy_coords:
					e_hits += 1
				elif h in ally_coords:
					a_hits += 1
			if e_hits > a_hits:
				return true
			continue   # this skill not safe, check next

		# Chain: primary target = 1 enemy. Check actors adjacent to target.
		# Chain's second hop lands on the nearest actor within chain_radius of target.
		var ally_hits: int = 0
		var extra_enemy_hits: int = 0
		var checked: Dictionary = {target_coord: true}
		var frontier: Array = [target_coord]
		for _hop in check_radius:
			var next_f: Array = []
			for fc in frontier:
				for nb in grid.get_walkable_neighbours(fc):
					if checked.has(nb):
						continue
					checked[nb] = true
					if nb in ally_coords:
						ally_hits += 1
					elif nb in enemy_coords:
						extra_enemy_hits += 1
					next_f.append(nb)
			frontier = next_f
		# primary target + any extra enemies > ally hits?
		if (1 + extra_enemy_hits) > ally_hits:
			return true

	return false   # no skill is net positive → block cast
