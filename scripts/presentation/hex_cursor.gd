extends Node2D
## HexCursor — hover indicator under the mouse. One outline per frame at the
## hovered hex coord. Single source of truth for "where is the player pointing"
## (other previews like cast-range / move-range key off this).
##
## Four visual modes:
##   IDLE           — neutral white-dim outline (no action queued)
##   ACTION_VALID   — focus-yellow tint, thicker outline (cast/move possible here)
##   ACTION_INVALID — semantic-damage tint, dashed-feel via thicker stroke
##   INSPECT        — 6 corner brackets (no full outline); reads "I'm reading
##                    info, not committing"
##
## Controllers set `mode` based on cast_mode + target validity. Default is IDLE.

## Hex polygon is built from the live tileset's tile_size — see
## scripts/infrastructure/hex_geometry.gd. No hex-radius constant here:
## tile_size in the .tres is the single source of truth, this overlay
## just inscribes a flat-top hex into that bbox at draw time.
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")

enum Mode { IDLE, ACTION_VALID, ACTION_INVALID, INSPECT }

@export var grid: HexGrid

## Drives color/geometry. Set by host controller (godmode/arena) on cast_mode change.
var mode: int = Mode.IDLE:
	set(value):
		if mode == value:
			return
		mode = value
		queue_redraw()

var _last_coord: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid
	z_index = 7  # above C7/C8 overlays per design (cursor is single source of truth)
	EventBus.ui_theme_reloaded.connect(queue_redraw)


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


func _get_color_and_width() -> Array:
	# Returns [color, width] tuple for current mode.
	match mode:
		Mode.ACTION_VALID:
			return [UiTheme.FOCUS, 2.5]
		Mode.ACTION_INVALID:
			return [UiTheme.SEM_DAMAGE, 2.5]
		Mode.INSPECT:
			# Drawn as brackets; color same as IDLE but thicker per-stroke
			return [UiTheme.TEXT, 2.0]
		_:
			return [Color(UiTheme.TEXT_DIM.r, UiTheme.TEXT_DIM.g, UiTheme.TEXT_DIM.b, 0.6), 1.5]


func _draw() -> void:
	if grid == null or grid.tile_map_layer == null or grid.tile_map_layer.tile_set == null:
		return
	var ret := _get_color_and_width()
	var color: Color = ret[0]
	var width: float = ret[1]
	# Flat-top hex inscribed in the live tile bbox. Polygon adapts when
	# tile_size in the .tres changes — no const sync needed.
	var corners: PackedVector2Array = HexGeometry.flat_top_polygon(
		Vector2(grid.tile_map_layer.tile_set.tile_size))
	if mode == Mode.INSPECT:
		_draw_inspect_brackets(corners, color, width)
	else:
		# Full outline, closed loop.
		for i in 6:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 6]
			draw_line(a, b, color, width, true)


## Draws 6 short corner-bracket strokes. Each bracket is a pair of half-edges
## meeting at a corner, ~33% of the edge length. Visually says "I'm pointing at
## this hex but not selecting it" — read-only inspect intent.
func _draw_inspect_brackets(corners: PackedVector2Array, color: Color, width: float) -> void:
	const FRACTION := 0.35  # how far along each adjacent edge the bracket extends
	for i in 6:
		var corner: Vector2 = corners[i]
		var prev: Vector2 = corners[(i + 5) % 6]   # previous corner (counter-clockwise)
		var next: Vector2 = corners[(i + 1) % 6]   # next corner (clockwise)
		# Two segments meeting at `corner`:
		#   corner → toward prev (FRACTION of the way)
		#   corner → toward next (FRACTION of the way)
		var to_prev: Vector2 = corner.lerp(prev, FRACTION)
		var to_next: Vector2 = corner.lerp(next, FRACTION)
		draw_line(corner, to_prev, color, width, true)
		draw_line(corner, to_next, color, width, true)
