extends Node2D
## TutorialHexHighlight -- lightweight in-world pulse for guided tutorial hexes.

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

var _grid: HexGrid = null
var _hexes: Array = []
var _phase: float = 0.0


func setup(grid: HexGrid) -> void:
	_grid = grid
	queue_redraw()


func set_hexes(hexes: Array) -> void:
	_hexes = hexes.duplicate()
	visible = not _hexes.is_empty()
	queue_redraw()


func clear() -> void:
	if _hexes.is_empty():
		return
	_hexes.clear()
	visible = false
	queue_redraw()


func _process(delta: float) -> void:
	if _hexes.is_empty():
		return
	_phase += delta
	queue_redraw()


func _draw() -> void:
	if _grid == null or _grid.tile_map_layer == null:
		return
	var layer: TileMapLayer = _grid.tile_map_layer
	if layer.tile_set == null:
		return
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(Vector2(layer.tile_set.tile_size))
	if corners.is_empty():
		return
	var pulse: float = 0.5 + 0.5 * sin(_phase * TAU / 1.1)
	var fill := Color(UiTheme.FOCUS.r, UiTheme.FOCUS.g, UiTheme.FOCUS.b, 0.16 + 0.10 * pulse)
	var line := Color(UiTheme.FOCUS.r, UiTheme.FOCUS.g, UiTheme.FOCUS.b, 0.78 + 0.18 * pulse)
	for coord in _hexes:
		var center: Vector2 = layer.map_to_local(coord)
		var points := PackedVector2Array()
		for i in 6:
			points.append(center + corners[i])
		draw_colored_polygon(points, fill)
		for i in 6:
			draw_line(points[i], points[(i + 1) % 6], line, 3.0 + pulse, true)
		draw_circle(center, 5.0 + 2.0 * pulse, line)
