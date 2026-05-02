class_name HexPathfinder

## Wraps AStar2D for hex grid pathfinding.
## build() must be called after HexGrid fills _tiles.
## Uses flat index: coord.y * grid_width + coord.x as point ID.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

var _astar: AStar2D = AStar2D.new()
var _object_registry: TileObjectRegistry = null   # 018 — optional; null = legacy behaviour


## Inject the tile-object registry so blocks_movement objects skip pathfinder
## point creation. Must be called BEFORE build(). Safe to skip — when null,
## passability falls back to tile.walkable only (pre-018 behaviour).
func set_object_registry(reg: TileObjectRegistry) -> void:
	_object_registry = reg


## grid_width / grid_height kept in the signature for backward compat with
## HexGrid._build_pathfinder; ignored now that point IDs use a fixed
## origin-centred encoding (see _coord_to_idx).
func build(tiles: Dictionary, _grid_width: int, _grid_height: int) -> void:
	_astar.clear()

	# Add points
	for coord: Vector2i in tiles:
		var tile: HexTile = tiles[coord]
		if _is_passable(tile):
			var idx := _coord_to_idx(coord)
			_astar.add_point(idx, Vector2(coord.x, coord.y))
			_astar.set_point_weight_scale(idx, float(tile.move_cost))

	# Connect walkable neighbours (we'll let HexGrid supply neighbours via a callback).
	# We rely on grid topology: for each walkable point, connect to all adjacent walkable points.
	# Adjacency is determined by comparing flat distance (we store it in the point coords).
	# Actual neighbour lookup is done externally — HexGrid calls connect_neighbours().
	GameLogger.info("HexPathfinder", "Built AStar2D with %d walkable points" % _astar.get_point_count())


func _is_passable(tile: HexTile) -> bool:
	if not tile.walkable:
		return false
	if _object_registry == null:
		return true
	return not _object_registry.get_object(tile.object_id).blocks_movement


func connect_neighbours(coord: Vector2i, neighbour_coords: Array[Vector2i]) -> void:
	var idx := _coord_to_idx(coord)
	if not _astar.has_point(idx):
		return
	for nb: Vector2i in neighbour_coords:
		var nb_idx := _coord_to_idx(nb)
		if _astar.has_point(nb_idx) and not _astar.are_points_connected(idx, nb_idx):
			_astar.connect_points(idx, nb_idx)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var from_idx := _coord_to_idx(from)
	var to_idx := _coord_to_idx(to)
	if not _astar.has_point(from_idx) or not _astar.has_point(to_idx):
		return []
	var id_path := _astar.get_id_path(from_idx, to_idx)
	var result: Array[Vector2i] = []
	for id: int in id_path:
		result.append(_idx_to_coord(id))
	return result


func set_point_walkable(coord: Vector2i, walkable: bool) -> void:
	var idx := _coord_to_idx(coord)
	if _astar.has_point(idx):
		_astar.set_point_disabled(idx, not walkable)


## AStar2D requires non-negative point IDs. Editor + future maps use signed
## coords (canvas centered at origin in 023), so we offset by HALF_LIMIT and
## use a fixed span. Constants mirror HexGrid.MAP_HALF_LIMIT (kept in sync;
## not imported to avoid cyclic class dependency).
const COORD_HALF_LIMIT: int = 250
const COORD_SPAN: int = 2 * COORD_HALF_LIMIT + 1  # 501


func _coord_to_idx(coord: Vector2i) -> int:
	return (coord.y + COORD_HALF_LIMIT) * COORD_SPAN + (coord.x + COORD_HALF_LIMIT)


func _idx_to_coord(idx: int) -> Vector2i:
	return Vector2i(
		(idx % COORD_SPAN) - COORD_HALF_LIMIT,
		(idx / COORD_SPAN) - COORD_HALF_LIMIT,
	)
