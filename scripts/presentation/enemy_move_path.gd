extends Node2D
## EnemyMovePath — polyline through hex centers from an enemy's current coord
## to its planned `move_intent_coord`. Drawn red (SEM_DAMAGE) to distinguish
## from the player's green hover-path preview, but uses the same path-style
## visualization for visual symmetry (Pillar 2: player & monsters speak the
## same UI language).
##
## Replaces 029's IntentArrow (straight-line shaft + arrowhead). Straight
## arrows lie about reality — the AI's actual route bends around obstacles
## via grid.find_path_around. Path-line tells the truth.
##
## Spawned & freed by TelegraphRenderer.refresh(). Position the node at
## (0,0) of HexGrid so all draw coords are in the grid's local space.

const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const _LINE_WIDTH:    float = 4.0
const _SHADOW_OFFSET: Vector2 = Vector2(1.0, 1.0)
const _ARROW_LEN:     float = 18.0
const _ARROW_HALF_W:  float = 10.0

var _grid: HexGrid = null
var _path: Array[Vector2i] = []


## Set the path before adding to scene (or any time — triggers redraw).
## `path` should be a non-trivial sequence (size >= 2) from current coord
## to intent coord, inclusive — same shape grid.find_path returns.
func setup(grid: HexGrid, path: Array[Vector2i]) -> void:
	_grid = grid
	_path = path
	queue_redraw()


func _ready() -> void:
	EventBus.ui_theme_reloaded.connect(queue_redraw)


func _draw() -> void:
	if _grid == null or _path.size() < 2:
		return
	var layer: TileMapLayer = _grid.tile_map_layer
	if layer == null:
		return
	# Resolve hex-centre points once.
	var pts: PackedVector2Array = PackedVector2Array()
	for c in _path:
		pts.append(layer.map_to_local(c))
	var color: Color = Color(UiTheme.SEM_DAMAGE.r, UiTheme.SEM_DAMAGE.g,
			UiTheme.SEM_DAMAGE.b, 0.85)
	# Drop shadow under each segment first, so the red line sits on top.
	for i in range(1, pts.size()):
		draw_line(pts[i - 1] + _SHADOW_OFFSET, pts[i] + _SHADOW_OFFSET,
				UiTheme.SHADOW_SOFT_COLOR, _LINE_WIDTH + 2.0, true)
	# Main red segments.
	for i in range(1, pts.size()):
		draw_line(pts[i - 1], pts[i], color, _LINE_WIDTH, true)
	# Arrowhead at the last segment, pointing toward path[-1] from path[-2].
	# Math mirrors the legacy IntentArrow: filled triangle, perpendicular
	# half-width offset from the tip.
	var tip: Vector2 = pts[pts.size() - 1]
	var prev: Vector2 = pts[pts.size() - 2]
	var dir: Vector2 = (tip - prev)
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var base: Vector2 = tip - dir * _ARROW_LEN
	var head_pts: PackedVector2Array = PackedVector2Array([
		tip,
		base + perp * _ARROW_HALF_W,
		base - perp * _ARROW_HALF_W,
	])
	# Shadow under the head.
	var shadow_pts: PackedVector2Array = PackedVector2Array()
	for p in head_pts:
		shadow_pts.append(p + _SHADOW_OFFSET)
	draw_colored_polygon(shadow_pts, UiTheme.SHADOW_SOFT_COLOR)
	draw_colored_polygon(head_pts, color)
