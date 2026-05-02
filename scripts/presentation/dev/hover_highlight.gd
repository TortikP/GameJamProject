extends Node2D
## HoverHighlight — paints a hex outline at the current mouse coord. Cheap,
## one redraw per coord change. Pattern follows hex_cursor.gd.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

@export var grid: HexGrid

var _last_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	z_index = 6


func _process(_delta: float) -> void:
	if grid == null or grid.tile_map_layer == null:
		return
	var coord := grid.coord_under_mouse()
	if coord == _last_coord:
		return
	_last_coord = coord
	if coord == Vector2i(-1, -1):
		visible = false
		return
	visible = true
	position = grid.tile_map_layer.map_to_local(coord)


func _draw() -> void:
	if grid == null or grid.tile_map_layer == null or grid.tile_map_layer.tile_set == null:
		return
	var color: Color = Color(UiTheme.FOCUS.r, UiTheme.FOCUS.g, UiTheme.FOCUS.b, 0.75)
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(
		Vector2(grid.tile_map_layer.tile_set.tile_size))
	for i in 6:
		var p1: Vector2 = corners[i]
		var p2: Vector2 = corners[(i + 1) % 6]
		draw_line(p1, p2, color, 2.0, true)
