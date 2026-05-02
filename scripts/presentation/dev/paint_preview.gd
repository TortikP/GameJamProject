extends Node2D
## PaintPreview — visualizes the cells LMB-paint would affect, given the current
## tool/size/anchor. Sister to HoverHighlight: HoverHighlight is the thick
## outline at cursor, this draws thin outlines on additional cells (brush disk
## past size 1, rect-fill region while LMB held in rect mode).
##
## Coords are pushed by MapEditorController via set_coords() — overlay is
## stateless about tool/mode.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

@export var grid: HexGrid

var _coords: Array[Vector2i] = []


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	# Below HoverHighlight (z=6) so the cursor outline always reads on top.
	z_index = 5


func set_coords(coords: Array[Vector2i]) -> void:
	if coords == _coords:
		return
	_coords = coords
	queue_redraw()


func clear() -> void:
	if _coords.is_empty():
		return
	_coords = []
	queue_redraw()


func _draw() -> void:
	if grid == null or grid.tile_map_layer == null or grid.tile_map_layer.tile_set == null:
		return
	if _coords.is_empty():
		return
	var color: Color = Color(UiTheme.FOCUS.r, UiTheme.FOCUS.g, UiTheme.FOCUS.b, 0.45)
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(
			Vector2(grid.tile_map_layer.tile_set.tile_size))
	for c in _coords:
		var center: Vector2 = grid.tile_map_layer.map_to_local(c)
		for i in 6:
			draw_line(center + corners[i], center + corners[(i + 1) % 6],
					color, 1.5, true)
