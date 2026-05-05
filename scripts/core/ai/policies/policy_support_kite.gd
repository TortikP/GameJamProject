class_name PolicySupportKite
extends MovementPolicy
## 030+: hybrid movement for support archetypes (Q4).
##
## Priority:
##   1. If a same-team ally is heavily wounded (hp/max_hp < ally_hp_threshold) AND
##      we are farther than heal_range hex → move toward that ally.
##   2. Otherwise: kite from player. Score each walkable neighbour by:
##        distance_to_player * 2  +  (safe_ally_range bonus if near any ally)
##      This keeps the support close to its melee screen while retreating from the
##      player. Prefer holding (return -1,-1) over moving toward the player.

@export var ally_hp_threshold: float = 0.4   ## wounded threshold; move toward ally below this
@export var heal_range: int = 2               ## approach wounded ally if farther than this
@export var safe_ally_range: int = 3          ## range considered "near ally" for kite scoring


func pick_step(actor: Actor, ctx: Dictionary) -> Vector2i:
	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return Vector2i(-1, -1)
	var my_coord: Vector2i = grid.get_coord(actor.actor_id)
	if my_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	var actors: Array = ctx.get("all_actors", [])

	# Build occupied dict and ally/enemy lists.
	var occupied: Dictionary = {}
	var player_coord: Vector2i = Vector2i(-1, -1)
	var best_enemy_d: int = 0x7fffffff
	var wounded_ally: Actor = null
	var worst_ratio: float = 1.1
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
			if other == actor:
				continue
			blocked.append(c)
			# Track most wounded ally.
			if other.max_hp > 0:
				var ratio: float = float(other.hp) / float(other.max_hp)
				if ratio < worst_ratio:
					worst_ratio = ratio
					wounded_ally = other
		else:
			# Opponent — track nearest for kite.
			var d: int = grid.hex_distance(my_coord, c)
			if d >= 0 and d < best_enemy_d:
				best_enemy_d = d
				player_coord = c

	# 1. Approach heavily wounded ally if out of heal range.
	if wounded_ally != null and worst_ratio < ally_hp_threshold:
		var wc: Vector2i = grid.get_coord(wounded_ally.actor_id)
		var dist_to_wounded: int = grid.hex_distance(my_coord, wc)
		if dist_to_wounded > heal_range:
			var path: Array = grid.find_path_around(my_coord, wc, blocked)
			if path.size() >= 2:
				return path[1]

	# 2. Kite from player, biased toward allies.
	if player_coord == Vector2i(-1, -1):
		return Vector2i(-1, -1)   # no enemy → hold

	var best_step: Vector2i = Vector2i(-1, -1)
	var best_score: int = -0x7fffffff

	for nb in grid.get_walkable_neighbours(my_coord):
		if occupied.has(nb):
			continue
		var d_player: int = grid.hex_distance(nb, player_coord)
		# Bonus: within safe_ally_range of at least one ally.
		var near_ally: bool = false
		for other_v2 in actors:
			if not (other_v2 is Actor):
				continue
			var other2: Actor = other_v2
			if other2 == actor or not other2.is_alive() or other2.team != actor.team:
				continue
			if grid.hex_distance(nb, grid.get_coord(other2.actor_id)) <= safe_ally_range:
				near_ally = true
				break
		var score: int = d_player * 2 + (safe_ally_range if near_ally else 0)
		if score > best_score:
			best_score = score
			best_step = nb

	# Only move if it actually improves our position (don't walk toward player).
	var current_score: int = grid.hex_distance(my_coord, player_coord) * 2
	for other_v3 in actors:
		if not (other_v3 is Actor):
			continue
		var other3: Actor = other_v3
		if other3 == actor or not other3.is_alive() or other3.team != actor.team:
			continue
		if grid.hex_distance(my_coord, grid.get_coord(other3.actor_id)) <= safe_ally_range:
			current_score += safe_ally_range
			break
	if best_score <= current_score:
		return Vector2i(-1, -1)   # hold — already in a good spot

	return best_step
