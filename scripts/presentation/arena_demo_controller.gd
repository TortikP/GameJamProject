extends Node

## Demo controller for hex_grid_demo.tscn.
## Handles click-to-move and QWEADS keyboard movement.
## Listens to EventBus.tile_effect_triggered for logging.
## Not a reusable class — presentation glue for the demo scene only.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const PLAYER_ID: StringName = &"player"

@export var grid: HexGrid
@export var actor_node: Node2D   # the visual circle that moves

# Keyboard direction -> TileSet.CellNeighbor mapping for flat-top hex
const KEY_TO_NEIGHBOR: Dictionary = {
	"hex_move_top":          TileSet.CELL_NEIGHBOR_TOP_SIDE,
	"hex_move_top_left":     TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
	"hex_move_top_right":    TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	"hex_move_bottom":       TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	"hex_move_bottom_left":  TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	"hex_move_bottom_right": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
}


func _ready() -> void:
	EventBus.tile_effect_triggered.connect(_on_tile_effect_triggered)
	grid.actor_step_started.connect(_on_step_started)
	grid.actor_step_finished.connect(_on_step_finished)
	# Paint demo grid then initialize (TileSet already assigned via .tres in scene)
	_paint_demo_grid()
	grid.initialize()
	_place_player()


# Atlas column -> tile_kind mapping matches hex_terrain.tres
# 0=grass, 1=wall, 2=swamp, 3=acid(damage_zone), 4=fountain(heal_fountain)
const _GRID_MAP := [
	[0,0,0,1,0,0,0,0,0,0],
	[0,2,0,1,0,0,3,0,0,0],
	[0,2,0,0,0,0,3,0,0,0],
	[0,2,0,0,0,0,0,0,4,0],
	[0,0,0,1,1,0,0,0,0,0],
	[0,0,0,0,0,0,0,2,0,0],
	[0,0,3,0,0,0,0,2,0,0],
	[0,0,0,0,1,0,0,0,0,0],
	[0,0,0,0,0,0,4,0,2,0],
	[0,0,0,0,0,0,0,0,0,0],
]


func _paint_demo_grid() -> void:
	for row in _GRID_MAP.size():
		for col in _GRID_MAP[row].size():
			var atlas_col: int = _GRID_MAP[row][col]
			grid.tile_map_layer.set_cell(Vector2i(col, row), 0, Vector2i(atlas_col, 0))


func _place_player() -> void:
	# Find a central walkable cell to start on
	var center := Vector2i(4, 4)
	if not grid.is_walkable(center):
		# Fallback: first walkable cell
		for coord: Vector2i in grid._tiles:
			if grid.is_walkable(coord):
				center = coord
				break
	grid.place_actor(PLAYER_ID, center)
	_snap_actor_to_coord(center)
	GameLogger.info("Demo", "Player placed at %s" % str(center))


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard: 6-direction movement
	for action: String in KEY_TO_NEIGHBOR:
		if event.is_action_pressed(action):
			grid.step_actor(PLAYER_ID, KEY_TO_NEIGHBOR[action])
			get_viewport().set_input_as_handled()
			return

	# Mouse click: pathfind to target
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var coord := grid.coord_under_mouse()
			if coord != Vector2i(-1, -1):
				grid.move_actor(PLAYER_ID, coord)
			get_viewport().set_input_as_handled()


func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void:
	if actor_id != PLAYER_ID or actor_node == null:
		return
	var target_pos: Vector2 = grid.tile_map_layer.map_to_local(to)
	# Tween actor visual to new position
	var cost: int = grid.get_move_cost(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * cost
	create_tween().tween_property(actor_node, "position", target_pos, duration)


func _on_step_finished(actor_id: StringName, coord: Vector2i) -> void:
	if actor_id == PLAYER_ID:
		GameLogger.info("Demo", "Player at %s (kind=%s)" % [str(coord), grid.get_tile_kind(coord)])


func _on_tile_effect_triggered(actor_id: StringName, coord: Vector2i, effect_id: StringName) -> void:
	GameLogger.info("HexGrid", "tile_effect_triggered: %s @ %s for %s" % [effect_id, str(coord), actor_id])


func _snap_actor_to_coord(coord: Vector2i) -> void:
	if actor_node != null and grid.tile_map_layer != null:
		actor_node.position = grid.tile_map_layer.map_to_local(coord)
