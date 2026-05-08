class_name DeleteFlash
extends Node2D

## Short red pulse drawn over a hex on successful erase. Fades out in
## 150ms via a Tween on modulate.a, then queue_frees itself. One
## instance per flash; the InputDispatcher creates a new one per erase
## (or one per cascade — single flash on the affected coord).
##
## Pattern: `DeleteFlash.spawn_at(parent, coord, grid)` from any caller.
## Static spawn keeps the call-site clean and the lifecycle self-contained
## inside the spawned node.

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const FLASH_DURATION_SEC: float = 0.15
const FLASH_COLOR := Color(1.0, 0.2, 0.2, 0.7)

var _polygon: PackedVector2Array = PackedVector2Array()


## Construct + parent + tween in one call. `parent` is typically the
## HexGrid (Node2D) so the flash inherits its world transform; `grid`
## supplies the TileMapLayer used for coord → local conversion and the
## tile_size for polygon shape.
static func spawn_at(parent: Node, coord: Vector2i, grid: HexGrid) -> void:
	if grid == null or grid.tile_map_layer == null or grid.tile_map_layer.tile_set == null:
		return
	var flash := DeleteFlash.new()
	flash.position = grid.tile_map_layer.map_to_local(coord)
	flash._polygon = HexGeometry.flat_top_polygon(
		Vector2(grid.tile_map_layer.tile_set.tile_size))
	parent.add_child(flash)
	flash.queue_redraw()
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, FLASH_DURATION_SEC)
	tween.tween_callback(flash.queue_free)


func _draw() -> void:
	if _polygon.size() > 0:
		draw_colored_polygon(_polygon, FLASH_COLOR)
