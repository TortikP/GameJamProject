class_name MoveEffect
extends AbilityEffect
## Moves a target Actor. Absorbs the old KnockbackModifier.
##
## move_type:
##   "push"      — away from caster by move_distance hexes
##   "pull"      — toward caster by move_distance hexes
##   "teleport"  — to ctx["target_coord"] (if set) or skips
##
## Skips silently if grid context missing, target not on grid, or no valid hex.
## Move is instant (no tween) — prototype behaviour, same as old KnockbackModifier.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var move_type: StringName = &"push"
@export var move_distance: int = 1


## 021 scaling: only `duration` scales (per spec table).
## `move_distance` intentionally unscaled — knockback radius is a designed value,
## not a power axis.
func apply_level(level: int) -> void:
	if level <= 0 or duration <= 1:
		return
	duration += level


func apply(caster: Actor, target: Variant, ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return

	var grid: HexGrid = ctx.get("grid")
	if grid == null or grid.tile_map_layer == null:
		return

	match move_type:
		&"push":
			_do_shove(caster, actor, grid, false)
		&"pull":
			_do_shove(caster, actor, grid, true)
		&"teleport":
			_do_teleport(actor, grid, ctx)
		_:
			GameLogger.warn("MoveEffect", "unknown move_type: %s" % move_type)


# ── Internals ────────────────────────────────────────────────────────────────

func _do_shove(caster: Actor, target: Actor, grid: HexGrid, pull: bool) -> void:
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	var target_coord: Vector2i = grid.get_coord(target.actor_id)
	if caster_coord == Vector2i(-1, -1) or target_coord == Vector2i(-1, -1):
		return

	var dest: Vector2i = _find_shove_dest(grid, caster_coord, target_coord, target.actor_id, pull)
	if dest == target_coord:
		return   # blocked / nowhere to go

	grid.clear_actor(target.actor_id)
	grid.place_actor(target.actor_id, dest)
	target.position = grid.tile_map_layer.map_to_local(dest)
	GameLogger.info("MoveEffect", "%s %s %s: %s → %s" % [move_type, target.actor_id, str(move_distance), str(target_coord), str(dest)])


func _find_shove_dest(grid: HexGrid, caster_coord: Vector2i, start: Vector2i, target_id: StringName, pull: bool) -> Vector2i:
	var caster_pos: Vector2 = grid.tile_map_layer.map_to_local(caster_coord)
	var current: Vector2i = start
	for _i in move_distance:
		var best: Vector2i = current
		var best_score: float = -1.0
		var neighbors: Array[Vector2i] = grid.tile_map_layer.get_surrounding_cells(current)
		for n in neighbors:
			if not grid.is_walkable(n):
				continue
			var occupant: StringName = grid.get_actor_at(n)
			if occupant != &"" and occupant != target_id:
				continue
			var n_pos: Vector2 = grid.tile_map_layer.map_to_local(n)
			var dist_sq: float = caster_pos.distance_squared_to(n_pos)
			# pull = closer to caster (smaller dist), push = farther (larger dist)
			var score: float = dist_sq if not pull else -dist_sq
			if score > best_score:
				best_score = score
				best = n
		if best == current:
			break
		current = best
	return current


func _do_teleport(target: Actor, grid: HexGrid, ctx: Dictionary) -> void:
	var dest: Variant = ctx.get("target_coord")
	if not dest is Vector2i:
		GameLogger.info("MoveEffect", "teleport: no target_coord in ctx — skip")
		return
	var coord := dest as Vector2i
	if not grid.is_walkable(coord):
		return
	if grid.get_actor_at(coord) != &"":
		return   # occupied
	grid.clear_actor(target.actor_id)
	grid.place_actor(target.actor_id, coord)
	target.position = grid.tile_map_layer.map_to_local(coord)
