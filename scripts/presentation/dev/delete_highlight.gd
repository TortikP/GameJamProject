extends Node2D
## DeleteHighlight — red filled hex polygon at the editor's pending-delete
## coord. Two-step deletion: first RMB marks (this node moves to coord),
## second RMB on same coord executes (controller calls clear()).
##
## Set coord via `set_coord(c)`; pass Vector2i(-1, -1) to hide.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const HEX_RADIUS: float = 60.0

@export var grid: HexGrid

var _coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	z_index = 5
	visible = false


func set_coord(coord: Vector2i) -> void:
	_coord = coord
	if grid == null or grid.tile_map_layer == null:
		visible = false
		return
	if coord == Vector2i(-1, -1):
		visible = false
		return
	visible = true
	position = grid.tile_map_layer.map_to_local(coord)
	queue_redraw()


func clear() -> void:
	set_coord(Vector2i(-1, -1))


func get_coord() -> Vector2i:
	return _coord


func has_coord() -> bool:
	return _coord != Vector2i(-1, -1)


func _draw() -> void:
	if _coord == Vector2i(-1, -1):
		return
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = deg_to_rad(60.0 * i)
		pts.append(Vector2(cos(a) * HEX_RADIUS, sin(a) * HEX_RADIUS))
	var fill: Color = Color(UiTheme.SEM_DAMAGE.r, UiTheme.SEM_DAMAGE.g, UiTheme.SEM_DAMAGE.b, 0.45)
	var border: Color = Color(UiTheme.SEM_DAMAGE.r, UiTheme.SEM_DAMAGE.g, UiTheme.SEM_DAMAGE.b, 0.95)
	draw_colored_polygon(pts, fill)
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		draw_line(a, b, border, 2.5, true)
