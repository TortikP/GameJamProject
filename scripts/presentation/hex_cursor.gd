class_name HexCursor
extends Polygon2D

## Подсвечивает гекс под курсором.
## Дочерняя нода HexGrid. grid резолвится через get_parent() если не задан.

@export var grid: HexGrid
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.25)

# Должен совпадать с outer radius атласа (BG_R=33)
const HEX_RADIUS := 33.0

var _last_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	color = highlight_color
	var pts: PackedVector2Array = []
	for i in 6:
		var a := deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * HEX_RADIUS, sin(a) * HEX_RADIUS))
	polygon = pts
	z_index = 10


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
