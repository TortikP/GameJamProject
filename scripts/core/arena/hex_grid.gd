class_name HexGrid
extends Node2D

## Hex arena grid — single source of truth for cell data and actor positions.
## Depends on:
##   - A child TileMapLayer node exported as tile_map_layer (terrain)
##   - A child TileMapLayer node exported as vfx_overlay
##   - Autoloads: EventBus, GameSpeed, GameLogger
##
## Emits EventBus signals: actor_moved, tile_entered, tile_effect_triggered.
## Does NOT know about HP, mana, AI, spells — those are consumers of signals.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# ── Public signals (grid-local, for scene-level wiring) ─────────────────────
signal grid_built
signal actor_step_started(actor_id: StringName, from: Vector2i, to: Vector2i)
signal actor_step_finished(actor_id: StringName, coord: Vector2i)

# ── Scene refs (auto-resolved children) ──────────────────────────────────────
# 060 / Φ-9.a: switched from @export NodePath to @onready $Path. The
# @export form didn't auto-resolve when hex_grid.tscn was instanced into
# level_editor.tscn (F-059-IMPL-4) — Godot 4 ignored the NodePath value
# inside the .tscn, leaving the typed fields null. @onready resolves
# the child by literal scene-tree path on _ready, which works in every
# instancing context.
@onready var tile_map_layer: TileMapLayer = $Terrain
@onready var vfx_overlay: TileMapLayer = $VFXOverlay  # visual only, logic never reads this

# ── Runtime state ────────────────────────────────────────────────────────────
var _tiles: Dictionary = {}           # Vector2i -> HexTile
var _actor_positions: Dictionary = {} # StringName -> Vector2i   (id -> coord)
var _occupants: Dictionary = {}       # Vector2i -> StringName   (coord -> id)
var _overlay_effects: Dictionary = {} # Vector2i -> StringName   (coord -> effect_id)

var _pathfinder: HexPathfinder = HexPathfinder.new()
var _effect_registry: TileEffectRegistry
var _object_registry: TileObjectRegistry  # 018 — tile objects (rocks, lava, fountains, ...)

var _grid_width: int = 0
var _grid_height: int = 0
var _moving: bool = false  # lock during async move_actor traversal


# ── Lifecycle ────────────────────────────────────────────────────────────────

## Call this after the TileMapLayer has a TileSet assigned and cells painted.
## In editor-built scenes: connect grid_built signal and call initialize() from
## your controller's _ready(). Demo / godmode scenes paint cells procedurally
## from the controller before calling initialize() (see arena_demo_controller
## and godmode_controller for the pattern).
func initialize() -> void:
	if tile_map_layer == null:
		GameLogger.error("HexGrid", "tile_map_layer is null — call from controller after resolving nodes")
		return

	_effect_registry = TileEffectRegistry.new()
	_effect_registry.load_from_dir("res://data/tile_effects/")
	_object_registry = TileObjectRegistry.new()
	_object_registry.load_from_dir("res://data/tile_objects/")
	_pathfinder.set_object_registry(_object_registry)
	_build_tile_map()
	_build_pathfinder()
	emit_signal("grid_built")
	GameLogger.info("HexGrid", "Initialized: %dx%d, %d walkable cells" % [
		_grid_width, _grid_height,
		_tiles.values().filter(func(t: HexTile) -> bool: return t.walkable).size()
	])
	GameLogger.info("HexGrid", "Initialized: %dx%d, %d walkable cells" % [
		_grid_width, _grid_height,
		_tiles.values().filter(func(t: HexTile) -> bool: return t.walkable).size()
	])


# ── Tile map initialisation ──────────────────────────────────────────────────

func _build_tile_map() -> void:
	if tile_map_layer == null:
		GameLogger.error("HexGrid", "tile_map_layer not assigned")
		return

	var cells := tile_map_layer.get_used_cells()
	var min_coord := Vector2i(INF, INF)
	var max_coord := Vector2i(-INF, -INF)

	for coord: Vector2i in cells:
		if coord.x < min_coord.x: min_coord.x = coord.x
		if coord.y < min_coord.y: min_coord.y = coord.y
		if coord.x > max_coord.x: max_coord.x = coord.x
		if coord.y > max_coord.y: max_coord.y = coord.y

	_grid_width = max_coord.x - min_coord.x + 1
	_grid_height = max_coord.y - min_coord.y + 1

	for coord: Vector2i in cells:
		var td: TileData = tile_map_layer.get_cell_tile_data(coord)
		var walkable: bool = true
		var move_cost: int = 1
		var tile_kind: StringName = &""
		var effect_id: StringName = &""
		var object_id: StringName = &""
		if td != null:
			walkable = td.get_custom_data("walkable")
			move_cost = td.get_custom_data("move_cost")
			tile_kind = td.get_custom_data("tile_kind")
			effect_id = td.get_custom_data("effect_id")
			# 018 — object_id custom data layer is optional. Returns null if the
			# layer hasn't been added to the TileSet yet. Treat as empty.
			var obj_raw: Variant = td.get_custom_data("object_id")
			if obj_raw != null and String(obj_raw) != "":
				object_id = StringName(obj_raw)
		_tiles[coord] = HexTile.new(coord, walkable, move_cost, tile_kind, effect_id, object_id)


func _build_pathfinder() -> void:
	_pathfinder.build(_tiles, _grid_width, _grid_height)
	# Connect neighbours via TileMapLayer.get_neighbor_cell so Godot handles offset parity.
	for coord: Vector2i in _tiles:
		var tile: HexTile = _tiles[coord]
		if not _is_tile_passable(tile):
			continue
		var neighbours: Array[Vector2i] = _get_walkable_neighbours(coord)
		_pathfinder.connect_neighbours(coord, neighbours)


## True when an actor can stand on / step through the tile.
## Composes terrain walkability with TileObject.blocks_movement (018).
## Single source of truth — every "can the actor go here" check routes through this.
func _is_tile_passable(tile: HexTile) -> bool:
	if not tile.walkable:
		return false
	if _object_registry == null:
		return true
	return not _object_registry.get_object(tile.object_id).blocks_movement


func get_walkable_neighbours(coord: Vector2i) -> Array[Vector2i]:
	return _get_walkable_neighbours(coord)


## Returns every walkable coord in the grid. Used by infinite-range abilities.
func get_all_walkable_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _tiles:
		if _is_tile_passable(_tiles[coord]):
			result.append(coord)
	return result


func _get_walkable_neighbours(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var neighbour_dirs: Array = [
		TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_SIDE,
		TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
		TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	]
	for dir in neighbour_dirs:
		var nb: Vector2i = tile_map_layer.get_neighbor_cell(coord, dir)
		if _tiles.has(nb) and _is_tile_passable(_tiles[nb]):
			result.append(nb)
	return result


# ── Actor positioning API ────────────────────────────────────────────────────

func place_actor(id: StringName, coord: Vector2i) -> bool:
	if not _tiles.has(coord):
		GameLogger.warn("HexGrid", "place_actor: coord %s not in grid" % str(coord))
		return false
	if not _is_tile_passable(_tiles[coord]):
		GameLogger.warn("HexGrid", "place_actor: coord %s not walkable" % str(coord))
		return false
	if _occupants.has(coord):
		GameLogger.warn("HexGrid", "place_actor: coord %s already occupied by %s" % [str(coord), _occupants[coord]])
		return false
	if _actor_positions.has(id):
		_clear_position(id)
	_actor_positions[id] = coord
	_occupants[coord] = id
	return true


func clear_actor(id: StringName) -> void:
	if _actor_positions.has(id):
		_clear_position(id)


func _clear_position(id: StringName) -> void:
	var old_coord: Vector2i = _actor_positions[id]
	_actor_positions.erase(id)
	_occupants.erase(old_coord)


## Async: walks actor along found path, emitting signals each step.
func move_actor(id: StringName, to: Vector2i) -> void:
	if not _actor_positions.has(id):
		GameLogger.warn("HexGrid", "move_actor: unknown actor %s" % id)
		return
	if _moving:
		return  # simple guard; battle controller should queue moves
	var from: Vector2i = _actor_positions[id]
	if from == to:
		return
	if not _tiles.has(to) or not _is_tile_passable(_tiles[to]):
		GameLogger.info("HexGrid", "unreachable: %s" % str(to))
		return
	if _occupants.has(to):
		GameLogger.info("HexGrid", "move_actor: %s is occupied" % str(to))
		return

	var path: Array[Vector2i] = _pathfinder.find_path(from, to)
	if path.is_empty():
		GameLogger.info("HexGrid", "unreachable: %s" % str(to))
		return

	_moving = true
	var prev := from
	for step_coord: Vector2i in path.slice(1):  # skip 'from'
		# 018 — emit before clearing/moving so 'prev' is still the actor's tile.
		_emit_actor_exited_if_object(prev, id)
		_clear_position(id)
		_actor_positions[id] = step_coord
		_occupants[step_coord] = id

		emit_signal("actor_step_started", id, prev, step_coord)
		EventBus.actor_moved.emit(id, prev, step_coord)
		EventBus.tile_entered.emit(id, step_coord)

		var cost: int = _tiles[step_coord].move_cost if _tiles.has(step_coord) else 1
		await GameSpeed.wait("arena", "step_duration") # wait base duration
		if cost > 1:
			# additional wait proportional to extra cost
			for _i in range(cost - 1):
				await GameSpeed.wait("arena", "path_step_pause")

		_check_tile_effect(id, step_coord)
		emit_signal("actor_step_finished", id, step_coord)
		prev = step_coord

	_moving = false


## Single keyboard step in a neighbour direction. Returns false if blocked.
func step_actor(id: StringName, neighbor: int) -> bool:
	if not _actor_positions.has(id):
		return false
	if _moving:
		return false
	var coord: Vector2i = _actor_positions[id]
	var nb: Vector2i = tile_map_layer.get_neighbor_cell(coord, neighbor)
	if not _tiles.has(nb) or not _is_tile_passable(_tiles[nb]):
		GameLogger.info("HexGrid", "step blocked at %s" % str(nb))
		return false
	if _occupants.has(nb):
		GameLogger.info("HexGrid", "step blocked: %s occupied" % str(nb))
		return false

	_moving = true
	# 018 — emit before clearing/moving so 'coord' is still the actor's tile.
	_emit_actor_exited_if_object(coord, id)
	_clear_position(id)
	_actor_positions[id] = nb
	_occupants[nb] = id

	emit_signal("actor_step_started", id, coord, nb)
	EventBus.actor_moved.emit(id, coord, nb)
	EventBus.tile_entered.emit(id, nb)

	await GameSpeed.wait("arena", "step_duration")
	_check_tile_effect(id, nb)
	emit_signal("actor_step_finished", id, nb)
	_moving = false
	return true


## 029 / req-5: walk the actor along a PRE-COMPUTED path. First element must be
## the actor's current coord; subsequent elements are the steps to take. Each
## step revalidates passability + occupancy at execute-time and breaks early on
## conflict (another actor moved during this resolve phase). Same per-step
## signal/EventBus contract as `move_actor`, so the controller's tween hook
## fires identically per hex.
##
## Why not reuse `move_actor`: it re-pathfinds via `find_path` which doesn't
## consider actor occupancy — for multi-step AI moves it could path through
## another enemy. This entrypoint trusts the caller's path (built with
## `find_path_around` + live blocks).
func move_actor_along(id: StringName, path: Array) -> void:
	if not _actor_positions.has(id):
		GameLogger.warn("HexGrid", "move_actor_along: unknown actor %s" % id)
		return
	if _moving:
		return
	if path.size() < 2:
		return
	_moving = true
	var prev: Vector2i = _actor_positions[id]
	for i in range(1, path.size()):
		var step_coord: Vector2i = path[i]
		# Revalidate at execute-time. Plan was made earlier this turn; another
		# enemy may have stepped into our path.
		if not _tiles.has(step_coord) or not _is_tile_passable(_tiles[step_coord]):
			break
		if _occupants.has(step_coord):
			break
		_emit_actor_exited_if_object(prev, id)
		_clear_position(id)
		_actor_positions[id] = step_coord
		_occupants[step_coord] = id

		emit_signal("actor_step_started", id, prev, step_coord)
		EventBus.actor_moved.emit(id, prev, step_coord)
		EventBus.tile_entered.emit(id, step_coord)

		var cost: int = _tiles[step_coord].move_cost if _tiles.has(step_coord) else 1
		await GameSpeed.wait("arena", "step_duration")
		if cost > 1:
			for _i in range(cost - 1):
				await GameSpeed.wait("arena", "path_step_pause")

		_check_tile_effect(id, step_coord)
		emit_signal("actor_step_finished", id, step_coord)
		prev = step_coord
	_moving = false


func get_coord(id: StringName) -> Vector2i:
	return _actor_positions.get(id, Vector2i(-1, -1))


func get_actor_at(coord: Vector2i) -> StringName:
	return _occupants.get(coord, &"")


# ── Tile query API ───────────────────────────────────────────────────────────

## True iff an actor can stand on this coord. Combines terrain `walkable` flag
## with TileObject.blocks_movement (018). External API — callers expect "can the
## actor go here", not raw terrain.
func is_walkable(coord: Vector2i) -> bool:
	return _tiles.has(coord) and _is_tile_passable(_tiles[coord])


func get_move_cost(coord: Vector2i) -> int:
	return _tiles[coord].move_cost if _tiles.has(coord) else 1


func get_tile_kind(coord: Vector2i) -> StringName:
	return _tiles[coord].tile_kind if _tiles.has(coord) else &""


func get_effect_id(coord: Vector2i) -> StringName:
	# Overlay takes priority over static
	if _overlay_effects.has(coord):
		return _overlay_effects[coord]
	return _tiles[coord].static_effect_id if _tiles.has(coord) else &""


func coord_under_mouse() -> Vector2i:
	if tile_map_layer == null:
		return Vector2i(-1, -1)
	var local_pos: Vector2 = tile_map_layer.get_local_mouse_position()
	var coord: Vector2i = tile_map_layer.local_to_map(local_pos)
	if _tiles.has(coord):
		return coord
	return Vector2i(-1, -1)


## Editor-only: returns the hex coord under cursor without checking against
## the painted tile registry. Used by the map editor where the user can
## paint anywhere — `_tiles` only knows about cells already initialized.
## Hard-capped to ±MAP_HALF_LIMIT so a runaway scroll can't generate
## absurd coords (Vector2i has 32-bit space; we don't want to test it).
const MAP_HALF_LIMIT: int = 250  # ⇒ 500×500 effective canvas

func coord_under_mouse_raw() -> Vector2i:
	if tile_map_layer == null:
		return Vector2i(-1, -1)
	var local_pos: Vector2 = tile_map_layer.get_local_mouse_position()
	var coord: Vector2i = tile_map_layer.local_to_map(local_pos)
	if absi(coord.x) > MAP_HALF_LIMIT or absi(coord.y) > MAP_HALF_LIMIT:
		return Vector2i(-1, -1)
	return coord


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return _pathfinder.find_path(from, to)


## Hex step-distance between two coords, ignoring actor occupancy.
## Returns -1 if unreachable through walkable terrain.
## Used by AI conditions (range checks) — for shooting/AOE range, not movement
## planning (movement uses find_path_around with blocks).
func hex_distance(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return 0
	var path := _pathfinder.find_path(from, to)
	if path.is_empty():
		return -1
	return path.size() - 1


## Like find_path, but treats `blocked` coords as non-walkable for this query
## (typically other actors). `from` and `to` themselves are never blocked even
## if listed. Used by AI to route around teammates.
func find_path_around(from: Vector2i, to: Vector2i, blocked: Array) -> Array[Vector2i]:
	var disabled: Array[Vector2i] = []
	for c in blocked:
		if c == from or c == to:
			continue
		if not (c is Vector2i):
			continue
		_pathfinder.set_point_walkable(c, false)
		disabled.append(c)
	var result := _pathfinder.find_path(from, to)
	for c in disabled:
		_pathfinder.set_point_walkable(c, true)
	return result


func size() -> Vector2i:
	return Vector2i(_grid_width, _grid_height)


## BFS: returns all coords reachable from `from` in at most `max_steps` walkable steps,
## excluding `from` itself. `occupied` is an optional Array[Vector2i] of coords to treat
## as blocked (other actors' positions). Pass [] to ignore occupancy.
func reachable_within(from: Vector2i, max_steps: int, occupied: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if max_steps <= 0:
		return result
	var visited: Dictionary = { from: true }
	var frontier: Array[Vector2i] = [from]
	for _step in max_steps:
		var next: Array[Vector2i] = []
		for coord in frontier:
			for nb in _get_walkable_neighbours(coord):
				if visited.has(nb):
					continue
				if occupied.has(nb):
					visited[nb] = true  # mark visited so we don't path through, but don't add to result
					continue
				visited[nb] = true
				result.append(nb)
				next.append(nb)
		frontier = next
		if frontier.is_empty():
			break
	return result


# ── Overlay effects API ──────────────────────────────────────────────────────

func add_overlay_effect(coord: Vector2i, effect_id: StringName) -> void:
	_overlay_effects[coord] = effect_id


func remove_overlay_effect(coord: Vector2i) -> void:
	_overlay_effects.erase(coord)


# ── Tile object accessors (019-tile-object-resolver) ─────────────────────────

## Returns the object_id on the given tile; &"" if tile is absent or has no object.
## Used by TileObjectResolver to check trigger conditions without reading _tiles directly.
func get_tile_object_id(coord: Vector2i) -> StringName:
	if not _tiles.has(coord):
		return &""
	return _tiles[coord].object_id


## Overwrites the object_id on a tile. Used by TileObjectResolver for on_destroy
## (clearing destroyed objects and spawning replacement objects).
func set_tile_object_id(coord: Vector2i, id: StringName) -> void:
	if _tiles.has(coord):
		_tiles[coord].object_id = id


## Exposes the TileObjectRegistry so controllers can pass it to TileObjectResolver
## without accessing _object_registry directly. Returns null before initialize().
func get_object_registry() -> TileObjectRegistry:
	return _object_registry


## Exposes the TileEffectRegistry for the same reason.
func get_effect_registry() -> TileEffectRegistry:
	return _effect_registry


## Returns {Vector2i: StringName} for every tile that has a non-empty object_id.
## Called once per turn by TileObjectResolver to find aura-emitting objects.
## Cost: O(tile count) — fine for jam-scale arenas.
func get_all_tile_object_ids() -> Dictionary:
	var result: Dictionary = {}
	for coord: Variant in _tiles:
		var tile: HexTile = _tiles[coord]
		if tile.object_id != &"":
			result[coord] = tile.object_id
	return result


## 020 — public hook to rebuild the A* graph after batch tile_object mutations.
## Used by LevelLoader when applying a LevelData with N objects: call
## set_tile_object_id() N times then rebuild_pathfinder() once. Cheaper than
## rebuilding per-call. Resolver (019) does NOT currently call this; objects
## destroyed mid-battle don't update pathfinder routing — known follow-up.
func rebuild_pathfinder() -> void:
	_build_pathfinder()


## 024-wave-editor: rebuild HexTile dict + pathfinder after a wave-snapshot
## floor mutation, WITHOUT recreating the TileObject / TileEffect registries.
## Full initialize() instantiates fresh registries, which breaks any cached
## refs in TileObjectResolver (019). Wave transitions only mutate cell
## existence + atlas — registries are stable across waves, so we keep them.
func reinitialize_tiles_only() -> void:
	if tile_map_layer == null:
		GameLogger.warn("HexGrid", "reinitialize_tiles_only: tile_map_layer is null")
		return
	# Drop tile dict, rebuild from current TileMapLayer state. Registries
	# stay attached.
	_tiles.clear()
	_build_tile_map()
	_build_pathfinder()


# ── Displacement / push-out (024-wave-editor) ───────────────────────────────
##
## When a wave snapshot makes a hex impassable while an actor is standing on
## it, the actor must be pushed to the nearest passable cell. find_passable
## does the BFS spiral lookup; displace_actor applies the move and recurses
## if the target is itself occupied (chain-push). Same algorithm for player
## and enemies — symmetry pillar (CLAUDE.md §design pillars).

const MAX_DISPLACEMENT_RADIUS: int = 30


## BFS hex-spiral from `from` outward, returning the first passable + free
## coord. `exclude` is a list of coords to treat as blocked (used by
## chain-push to avoid bouncing into already-resolved cells).
##
## Returns Vector2i.MAX as a sentinel when no target is reachable within
## MAX_DISPLACEMENT_RADIUS layers. `from` itself is never considered as a
## destination — by definition it's the cell we're trying to leave.
##
## Determinism: neighbour iteration uses _get_walkable_neighbours which goes
## through TileMapLayer.get_neighbor_cell with a fixed dir order (TL→T→TR→
## BR→B→BL). BFS expand-order is therefore stable across runs.
func find_passable_for_displacement(from: Vector2i,
		exclude: Array = []) -> Vector2i:
	var blocked: Dictionary = { from: true }
	for c in exclude:
		blocked[c] = true
	var frontier: Array[Vector2i] = [from]
	for _depth in MAX_DISPLACEMENT_RADIUS:
		var next: Array[Vector2i] = []
		for coord in frontier:
			# Iterate ALL neighbours (incl. impassable terrain) so the BFS
			# can keep expanding through walls, but only return passable +
			# unoccupied + non-excluded cells.
			var dirs: Array = [
				TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
				TileSet.CELL_NEIGHBOR_TOP_SIDE,
				TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
				TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
				TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
				TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
			]
			for dir in dirs:
				var nb: Vector2i = tile_map_layer.get_neighbor_cell(coord, dir)
				if blocked.has(nb):
					continue
				blocked[nb] = true  # mark so we don't reprocess
				# Pass through impassable for spiral expansion, but only
				# return passable+free cells.
				if not _tiles.has(nb):
					continue
				if not _is_tile_passable(_tiles[nb]):
					next.append(nb)
					continue
				if _occupants.has(nb):
					next.append(nb)
					continue
				return nb
			# Bound on visited size as belt-and-suspenders against pathological
			# tilemaps (huge but disconnected regions).
			if blocked.size() > 4000:
				return Vector2i.MAX
		frontier = next
		if frontier.is_empty():
			break
	return Vector2i.MAX


## Move `actor` off its current coord onto the nearest passable + free cell.
## If that target is occupied by another actor B (chain case), recurses to
## displace B first. `exclude` accumulates source coords + intermediate
## targets across the chain so a → b → ... never bounces back to a.
##
## Returns true if the actor is now on a different coord (or was killed —
## either way we're done with it). Returns false only on hard failure
## (actor isn't on the grid, no neighbour passable in the chain — last
## actor in the chain dies in that case via kill_with_reason).
##
## Note: this uses _direct_set_position — NOT move_actor — because the cell
## we're leaving is in the middle of being mutated (a snapshot apply just
## erased it). move_actor would try to A* through a hole. We bypass the
## pathfinder and tween/animate via the same actor_step_started signal so
## listeners (camera, sprite tween) still get the visual.
func displace_actor(actor: Actor, exclude: Array = []) -> bool:
	if actor == null:
		return false
	var a: Actor = actor
	var from: Vector2i = _actor_positions.get(a.actor_id, Vector2i(-1, -1))
	if from == Vector2i(-1, -1):
		return false
	var target: Vector2i = find_passable_for_displacement(from, exclude)
	if target == Vector2i.MAX:
		# No room anywhere — actor is crushed. Frees the cell.
		a.kill_with_reason("crushed")
		_clear_position(a.actor_id)
		return true
	# If target is occupied, chain-push the resident first. Append the
	# original from + chosen target to exclude so recursion doesn't
	# double-back.
	var resident: StringName = _occupants.get(target, &"")
	if resident != &"" and resident != a.actor_id:
		var occupant: Actor = null
		if registry_lookup.has(resident):
			occupant = registry_lookup[resident]
		# Without a registry hook we fall back to scene-tree search.
		if occupant == null:
			occupant = _find_actor_node_by_id(resident)
		var next_exclude: Array = exclude.duplicate()
		next_exclude.append(from)
		next_exclude.append(target)
		if occupant != null:
			var chained: bool = displace_actor(occupant, next_exclude)
			if not chained:
				# Couldn't move the occupant — abort this displacement, kill
				# the original actor (worst case) so we don't leave stale
				# state.
				a.kill_with_reason("crushed")
				_clear_position(a.actor_id)
				return true
	# Land the actor on target.
	_clear_position(a.actor_id)
	_actor_positions[a.actor_id] = target
	_occupants[target] = a.actor_id
	# Visual: snap position + emit step_started so listeners can tween.
	emit_signal("actor_step_started", a.actor_id, from, target)
	a.position = tile_map_layer.map_to_local(target)
	EventBus.actor_moved.emit(a.actor_id, from, target)
	EventBus.tile_entered.emit(a.actor_id, target)
	# Trigger tile-effect resolution at the landing tile (lava, fountain,
	# etc.) — push-out damage-on-land per spec AC-W11.
	_check_tile_effect(a.actor_id, target)
	emit_signal("actor_step_finished", a.actor_id, target)
	return true


# Optional registry-by-id lookup. Owners (godmode/arena controllers) can
# poke their ActorRegistry into this dict so displace_actor's chain-push can
# resolve occupant ids without a tree walk. Unset → falls back to scene-tree
# scan (slow but works).
var registry_lookup: Dictionary = {}


func _find_actor_node_by_id(id: StringName) -> Actor:
	# Slow path — scan all known actor nodes under HexGrid/Actors. Cheap
	# enough for jam scope (a handful of enemies).
	var actors_node: Node = get_node_or_null("Actors")
	if actors_node == null:
		actors_node = self
	for child in actors_node.get_children():
		if child is Actor and (child as Actor).actor_id == id:
			return child
	return null


# ── Internal ─────────────────────────────────────────────────────────────────

func _check_tile_effect(actor_id: StringName, coord: Vector2i) -> void:
	var eid := get_effect_id(coord)
	if eid != &"":
		EventBus.tile_effect_triggered.emit(actor_id, coord, eid)


## 018 — emit tile_object_actor_exited when an actor leaves a tile that has an
## object on it. The runtime resolver (019, follow-up) listens to this and
## applies linger_effect_id where present. Until then: graceful no-op.
func _emit_actor_exited_if_object(coord: Vector2i, actor_id: StringName) -> void:
	if not _tiles.has(coord):
		return
	var obj_id: StringName = _tiles[coord].object_id
	if obj_id == &"":
		return
	EventBus.tile_object_actor_exited.emit(coord, actor_id, obj_id)
