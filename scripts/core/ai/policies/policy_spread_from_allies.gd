class_name PolicySpreadFromAllies
extends MovementPolicy
## When allies are within crowd_radius hexes, step away from the densest ally
## cluster so the actor can attack safely next turn (no chain collateral).
## When no allies are nearby → falls back to approach_nearest_enemy_unclaimed.
##
## Used as movement_policy when condition_aoe_net_positive blocks the cast:
## the actor retreats, creating space, then attacks cleanly next turn.

@export var crowd_radius: int = 1   ## distance threshold; ally within this = crowded


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var actors: Array = ctx.get("all_actors", [])
	var occupied: Dictionary = {}
	var ally_coords: Array = []
	var target_coord: Vector2i = Vector2i(-1, -1)
	var best_enemy_d: int = 0x7fffffff
	var blocked: Array = []

	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if not other.is_alive():
			continue
		var c: Vector2i = grid.get_coord(other.actor_id)
		if c == Vector2i(-1, -1):
			continue
		if other != actor:
			occupied[c] = true
		if other.team == actor.team:
			if other != actor:
				blocked.append(c)
				ally_coords.append(c)
		else:
			var d: int = grid.hex_distance(my_coord, c)
			if d >= 0 and d < best_enemy_d:
				best_enemy_d = d
				target_coord = c

	# Check if any ally is within crowd_radius.
	var crowded: bool = false
	for ac in ally_coords:
		if grid.hex_distance(my_coord, ac) <= crowd_radius:
			crowded = true
			break

	# Not crowded → standard approach (unclaimed).
	if not crowded:
		if target_coord == Vector2i(-1, -1):
			return Vector2i(-1, -1)
		var path: Array = grid.find_path_around(my_coord, target_coord, blocked)
		if path.size() < 2:
			return Vector2i(-1, -1)
		# Unclaimed check.
		var taken: Array = []
		for other_v2 in actors:
			if not (other_v2 is Actor):
				continue
			var other2: Actor = other_v2
			if other2 == actor or not other2.is_alive() or other2.team != actor.team:
				continue
			if other2.move_intent_coord != Vector2i(-1, -1):
				taken.append(other2.move_intent_coord)
		for i in [1, 2]:
			if i >= path.size():
				break
			if not (path[i] in taken):
				return path[i]
		return path[1]

	# Crowded → step away from nearest ally, biased toward enemy.
	var best_step: Vector2i = Vector2i(-1, -1)
	var best_score: float = -1e9
	for nb in grid.get_walkable_neighbours(my_coord):
		if occupied.has(nb):
			continue
		# Distance from nearest ally (higher = more spread).
		var min_ally_d: int = 0x7fffffff
		for ac in ally_coords:
			var d: int = grid.hex_distance(nb, ac)
			if d < min_ally_d:
				min_ally_d = d
		# Distance to nearest enemy (lower = closer to attack range).
		var enemy_d: int = 0x7fffffff
		if target_coord != Vector2i(-1, -1):
			enemy_d = grid.hex_distance(nb, target_coord)
		# Score: ally distance dominates, tiebreak by staying close to enemy.
		var score: float = float(min_ally_d) * 2.0 - float(enemy_d) * 0.5
		if score > best_score:
			best_score = score
			best_step = nb
	return best_step
