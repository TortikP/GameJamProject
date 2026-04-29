class_name HexCursor
extends Polygon2D

## Follows coord_under_mouse() on the owning HexGrid.
## Attach as child of hex_grid.tscn root. Assign grid via inspector or _ready auto-find.

@export var grid: HexGrid
@export var highlight_color: Color = Color(1.0, 1.0, 1.0, 0.3)

var _last_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	color = highlight_color
	# Build a flat-top hex polygon (64px tile, radius = 32px horizontal, ~37px vertical)
	_build_hex_shape(32.0)
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


func _build_hex_shape(r: float) -> void:
	# Flat-top hexagon: 6 vertices starting from right
	var pts: PackedVector2Array = []
	for i in 6:
		var angle_deg := 60.0 * i
		var angle_rad := deg_to_rad(angle_deg)
		pts.append(Vector2(r * cos(angle_rad), r * sin(angle_rad)))
	polygon = pts
