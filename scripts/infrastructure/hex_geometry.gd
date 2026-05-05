extends Object
## HexGeometry — flat-top hex polygon math, decoupled from any specific
## tile size or tileset. Single source of truth for "how to build a hex
## polygon" used by every overlay (cursor, range, telegraph, highlights).
##
## Usage (preload pattern, like GameLogger — no class_name, no autoload):
##
##   const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
##   var pts := HexGeometry.flat_top_polygon(layer.tile_set.tile_size)
##
## See specs/022-hex-shape-update/plan.md for why we read tile_size at draw
## time instead of caching a constant: lets tile shape change in .tres
## without code edits, and stays correct when godmode swaps tilesets at
## runtime.

## Flat-top hex inscribed in the bounding box `tile_size` (px).
## Returns 6 vertices, counter-clockwise in screen-space (Godot Y is down).
##
## Vertex layout: two on the horizontal axis (left/right edges of bbox),
## four at the top/bottom edges shifted inward by W/4. This is NOT a
## regular hexagon when H != W * sqrt(3)/2 — the polygon stretches to
## fit any aspect ratio. That's intentional: Katya's "squashed" tiles
## have H/W ≈ 0.62, far from the regular 0.866.
static func flat_top_polygon(tile_size: Vector2) -> PackedVector2Array:
	var hw: float = tile_size.x * 0.5
	var hh: float = tile_size.y * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2( hw,        0.0))
	pts.append(Vector2( hw * 0.5,  hh))
	pts.append(Vector2(-hw * 0.5,  hh))
	pts.append(Vector2(-hw,        0.0))
	pts.append(Vector2(-hw * 0.5, -hh))
	pts.append(Vector2( hw * 0.5, -hh))
	return pts


## Convenience: pull tile_size off a TileMapLayer. Returns empty polygon
## (callers should `if pts.is_empty(): return`) if the layer or its
## tile_set is null — happens during early init / scene load.
static func flat_top_polygon_for_layer(layer: TileMapLayer) -> PackedVector2Array:
	if layer == null or layer.tile_set == null:
		return PackedVector2Array()
	return flat_top_polygon(Vector2(layer.tile_set.tile_size))
