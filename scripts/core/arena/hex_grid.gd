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

# ── Exported scene refs ──────────────────────────────────────────────────────
@export var tile_map_layer: TileMapLayer
@export var vfx_overlay: TileMapLayer          # visual only, logic never reads this

# ── Runtime state ────────────────────────────────────────────────────────────
var _tiles: Dictionary = {}           # Vector2i -> HexTile
var _actor_positions: Dictionary = {} # StringName -> Vector2i   (id -> coord)
var _occupants: Dictionary = {}       # Vector2i -> StringName   (coord -> id)
var _overlay_effects: Dictionary = {} # Vector2i -> StringName   (coord -> effect_id)

var _pathfinder: HexPathfinder = HexPathfinder.new()
var _effect_registry: TileEffectRegistry

var _grid_width: int = 0
var _grid_height: int = 0
var _moving: bool = false  # lock during async move_actor traversal


# ── Lifecycle ────────────────────────────────────────────────────────────────

## Call this after the TileMapLayer has a TileSet assigned and cells painted.
## In editor-built scenes: connect grid_built signal and call initialize() from
## your controller's _ready(). In demo scene: HexPlaceholderBuilder.setup() → initialize().
func initialize() -> void:
	if tile_map_layer == null:
		GameLogger.error("HexGrid", "tile_map_layer is null — call from controller after resolving nodes")
		return

	_effect_registry = TileEffectRegistry.new()
	_effect_registry.load_from_dir("res://data/tile_effects/")
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
		if td != null:
			walkable = td.get_custom_data("walkable")
			move_cost = td.get_custom_data("move_cost")
			tile_kind = td.get_custom_data("tile_kind")
			effect_id = td.get_custom_data("effect_id")
		_tiles[coord] = HexTile.new(coord, walkable, move_cost, tile_kind, effect_id)


func _build_pathfinder() -> void:
	_pathfinder.build(_tiles, _grid_width, _grid_height)
	# Connect neighbours via TileMapLayer.get_neighbor_cell so Godot handles offset parity.
	for coord: Vector2i in _tiles:
		var tile: HexTile = _tiles[coord]
		if not tile.walkable:
			continue
		var neighbours: Array[Vector2i] = _get_walkable_neighbours(coord)
		_pathfinder.connect_neighbours(coord, neighbours)


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
		if _tiles.has(nb) and _tiles[nb].walkable:
			result.append(nb)
	return result


# ── Actor positioning API ────────────────────────────────────────────────────

func place_actor(id: StringName, coord: Vector2i) -> bool:
	if not _tiles.has(coord):
		GameLogger.warn("HexGrid", "place_actor: coord %s not in grid" % str(coord))
		return false
	if not _tiles[coord].walkable:
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
	if not _tiles.has(to) or not _tiles[to].walkable:
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
	if not _tiles.has(nb) or not _tiles[nb].walkable:
		GameLogger.info("HexGrid", "step blocked at %s" % str(nb))
		return false
	if _occupants.has(nb):
		GameLogger.info("HexGrid", "step blocked: %s occupied" % str(nb))
		return false

	_moving = true
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


func get_coord(id: StringName) -> Vector2i:
	return _actor_positions.get(id, Vector2i(-1, -1))


func get_actor_at(coord: Vector2i) -> StringName:
	return _occupants.get(coord, &"")


# ── Tile query API ───────────────────────────────────────────────────────────

func is_walkable(coord: Vector2i) -> bool:
	return _tiles.has(coord) and _tiles[coord].walkable


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


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return _pathfinder.find_path(from, to)


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


# ── Overlay effects API ──────────────────────────────────────────────────────

func add_overlay_effect(coord: Vector2i, effect_id: StringName) -> void:
	_overlay_effects[coord] = effect_id


func remove_overlay_effect(coord: Vector2i) -> void:
	_overlay_effects.erase(coord)


# ── Internal ─────────────────────────────────────────────────────────────────

func _check_tile_effect(actor_id: StringName, coord: Vector2i) -> void:
	var eid := get_effect_id(coord)
	if eid != &"":
		EventBus.tile_effect_triggered.emit(actor_id, coord, eid)
