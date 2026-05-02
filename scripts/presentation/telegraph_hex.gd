extends Node2D
## TelegraphHex — paints a translucent hex marker and a damage number
## on a single grid coord, indicating an incoming threat. One per
## threatened hex (NOT per attacker). Aggregated damage from multiple
## attackers shows as one summed number (e.g. "-12").
##
## Color: defaults to UiTheme.SEM_DAMAGE (red, the default "danger" tint).
## After 007 + 008 land, controllers set `semantic_tag` from cast_intent so
## heal-intent shows green tint, control purple, etc. (Pillar 1: player sees
## WHAT will happen, not just THAT something will). See spec AC-R7, T072.

## Hex polygon dimensions come from the live tileset's tile_size — see
## scripts/infrastructure/hex_geometry.gd. Telegraph spawns are added as
## children of HexGrid by godmode_controller (`grid.add_child(hex)`),
## so we read tile_size off `get_parent()`.
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

## Fallback if parent isn't a HexGrid (contract violation — logged once).
## Matches old RADIUS=60 bbox: a regular hex with R=60 has bbox (120, ~104).
const _FALLBACK_TILE_SIZE := Vector2(120.0, 104.0)
var _warned_no_grid: bool = false

## Semantic tag drives hex color. &"" → SEM_DAMAGE (red, the default).
var semantic_tag: StringName = &"":
	set(value):
		semantic_tag = value
		queue_redraw()

var damage: int = 0:
	set(value):
		damage = value
		queue_redraw()

## 029 / req-6: secondary-hex mode. When true, draws only the outline (no
## fill, no damage label) so the AoE shape of an incoming spell reads as
## "this whole zone will be hit" without competing visually with the primary
## telegraph hex (which carries the damage number). Set by godmode_controller
## when an intent's area extends beyond its target_coord.
var outline_only: bool = false:
	set(value):
		outline_only = value
		queue_redraw()


func _ready() -> void:
	EventBus.ui_theme_reloaded.connect(queue_redraw)


func _get_fill_color() -> Color:
	var base: Color = UiTheme.SEM_DAMAGE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	return Color(base.r, base.g, base.b, 0.42)


func _get_frame_color() -> Color:
	var base: Color = UiTheme.SEM_DAMAGE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	# Frame is darker, more saturated — multiply by 0.7 then bump alpha.
	return Color(base.r * 0.7, base.g * 0.7, base.b * 0.7, 0.85)


func _draw() -> void:
	var tile_size: Vector2 = _resolve_tile_size()
	var pts: PackedVector2Array = HexGeometry.flat_top_polygon(tile_size)
	# Hex polygon (matches grid hex orientation: flat-top, vertex on right)
	if not outline_only:
		draw_colored_polygon(pts, _get_fill_color())
	# Outline — secondary hexes use a thinner, dimmer line so the AoE shape
	# reads without overwhelming the primary telegraph hex sitting on top of
	# the damage source.
	var frame_col: Color = _get_frame_color()
	var line_w: float = 2.0
	if outline_only:
		frame_col = Color(frame_col.r, frame_col.g, frame_col.b, 0.55)
		line_w = 1.5
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		draw_line(a, b, frame_col, line_w, true)
	# Damage label — pushed above the hex so it isn't hidden by an actor sprite
	# standing on the threatened tile. Crisp dark outline (visibility doctrine
	# in CLAUDE.md — incoming-damage telegraphs are Pillar 1 critical UI).
	if outline_only or damage <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = UiTheme.BAR_FONT_SIZE_OVERHEAD
	var text: String = "-%d" % damage
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos: Vector2 = Vector2(-size.x * 0.5, -tile_size.y * 0.5 - 6.0)
	draw_string_outline(font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
		UiTheme.WORLD_TEXT_OUTLINE_SIZE, UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, UiTheme.TEXT)


## Read tile_size from parent HexGrid's TileMapLayer. Telegraph is spawned as
## a child of HexGrid by godmode_controller; if that contract changes, fall
## back to the historical 60-radius bbox and warn once.
func _resolve_tile_size() -> Vector2:
	var parent := get_parent()
	if parent != null and parent is HexGrid:
		var grid: HexGrid = parent as HexGrid
		if grid.tile_map_layer != null and grid.tile_map_layer.tile_set != null:
			return Vector2(grid.tile_map_layer.tile_set.tile_size)
	if not _warned_no_grid:
		_warned_no_grid = true
		GameLogger.warn("TelegraphHex",
			"parent is not HexGrid or tile_set missing — using fallback tile_size %s" % _FALLBACK_TILE_SIZE)
	return _FALLBACK_TILE_SIZE
