class_name KnockbackModifier
extends AbilityModifier
## Pushes the target away from the caster by `distance` hexes after the
## effect resolves. Hooks into after_apply (per-target).
##
## Direction algorithm (jam-pragmatic, not axial-perfect):
##   For each push step, look at the target's 6 hex neighbors (via
##   TileMapLayer.get_surrounding_cells). Pick the walkable+unoccupied
##   one whose world-space position is FURTHEST from the caster. Repeat
##   `distance` times, stopping early if no valid hex is found.
##
## Skipped if target is dead (no shoving corpses) or grid context missing.
## Move is instant (no tween) — fast feedback for the prototype. We can
## animate later by routing through a generic "smoothly_place" helper.

@export var distance: int = 1


func after_apply(caster: Actor, target: Actor, ctx: Dictionary) -> void:
	if not target.is_alive():
		return
	var grid: HexGrid = ctx.get("grid")
	if grid == null or grid.tile_map_layer == null:
		return
	var caster_coord: Vector2i = grid.get_coord(caster.actor_id)
	var target_coord: Vector2i = grid.get_coord(target.actor_id)
	if caster_coord == Vector2i(-1, -1) or target_coord == Vector2i(-1, -1):
		return
	var dest: Vector2i = _find_push_destination(grid, caster_coord, target_coord, target.actor_id)
	if dest == target_coord:
		return  # blocked / nowhere to go
	grid.clear_actor(target.actor_id)
	grid.place_actor(target.actor_id, dest)
	target.position = grid.tile_map_layer.map_to_local(dest)


func _find_push_destination(grid: HexGrid, caster_coord: Vector2i, start: Vector2i, target_id: StringName) -> Vector2i:
	var caster_pos: Vector2 = grid.tile_map_layer.map_to_local(caster_coord)
	var current: Vector2i = start
	for _i in distance:
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
			var score: float = caster_pos.distance_squared_to(n_pos)
			if score > best_score:
				best_score = score
				best = n
		if best == current:
			break
		current = best
	return current
