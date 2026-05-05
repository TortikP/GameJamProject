extends Node2D
## TelegraphHex — paints a translucent hex marker, optionally a skill icon
## (or letter fallback), and a damage number on a single grid coord. One per
## threatened hex (NOT per attacker). Aggregated damage from multiple
## attackers shows as one summed number (e.g. "-12").
##
## Color: defaults to UiTheme.SEM_DAMAGE (red, the default "danger" tint).
## Controllers set `semantic_tag` from cast_intent so heal-intent shows
## green tint, control purple, etc. (Pillar 1: player sees WHAT will happen,
## not just THAT something will). See spec AC-R7, T072.
##
## 049 / AC-5: primary telegraphs draw the casting skill's icon at hex
## center. Texture from SkillIconResolver; fallback — first letter of
## localized skill name in big outlined font (visibility doctrine — this is
## in-world text overlapping sprites + tiles + VFX).
## Damage label was previously above the hex (`-tile.y/2 - 6`) which collided
## with HP bars on the actor standing on the threatened tile. Now drawn at
## bottom-center inside the hex, below the icon. Outline-only secondary
## hexes (AoE-shape outlines) still suppress both icon and damage label.

## Hex polygon dimensions come from the live tileset's tile_size — see
## scripts/infrastructure/hex_geometry.gd. Telegraph spawns are added as
## children of HexGrid by godmode_controller (`grid.add_child(hex)`),
## so we read tile_size off `get_parent()`.
const HexGeometry = preload("res://scripts/infrastructure/hex_geometry.gd")
const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SkillIconResolver = preload("res://scripts/presentation/skill_icon_resolver.gd")

## Fallback if parent isn't a HexGrid (contract violation — logged once).
## Matches old RADIUS=60 bbox: a regular hex with R=60 has bbox (120, ~104).
const _FALLBACK_TILE_SIZE := Vector2(120.0, 104.0)
## Icon rendering metrics — kept here so changes are visible without grepping
## CLAUDE.md's visibility doctrine.
const _ICON_SIZE: Vector2 = Vector2(32.0, 32.0)
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
## fill, no damage label, no icon) so the AoE shape of an incoming spell
## reads as "this whole zone will be hit" without competing visually with
## the primary telegraph hex (which carries the damage number + icon). Set
## by telegraph_renderer when an intent's area extends beyond its
## target_coord.
var outline_only: bool = false:
	set(value):
		outline_only = value
		queue_redraw()

## 049 / AC-5: primary skill icon. Set by TelegraphRenderer.refresh()
## alongside semantic_tag/damage. Null → no icon (legacy / non-skill
## telegraphs). When set, _draw paints either the resolved Texture2D or a
## big outlined letter at hex center.
var icon_skill: Skill = null:
	set(value):
		icon_skill = value
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
	# Hex polygon fill — primary mode (full-strength fill) plus, in 049b
	# T039, a faint version for outline_only secondaries so the affected
	# AoE region reads as a coloured zone, not just a wireframe.
	var base: Color = UiTheme.SEM_DAMAGE if semantic_tag == &"" else UiTheme.semantic_color(semantic_tag)
	if outline_only:
		# 049b / T039: faint fill on AoE-shape hexes. ~0.18 alpha keeps the
		# tile underneath readable but turns the "this whole zone will be
		# hit" boundary into a region. Was outline-only with no fill; in
		# practice the thin red border vanished against busy biome tiles.
		draw_colored_polygon(pts, Color(base.r, base.g, base.b, 0.18))
	else:
		draw_colored_polygon(pts, _get_fill_color())
	# Outline. 049b / T039: secondary outline bumped from 1.5px α0.55 to
	# 2.0px α0.85 — same vibe as the primary frame, so primary vs secondary
	# distinction now lives in fill density (0.42 vs 0.18) instead of in
	# outline weight where it disappeared.
	var frame_col: Color = _get_frame_color()
	var line_w: float = 2.0
	if outline_only:
		frame_col = Color(frame_col.r, frame_col.g, frame_col.b, 0.85)
		line_w = 2.0
	for i in 6:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % 6]
		draw_line(a, b, frame_col, line_w, true)
	# Outline-only mode: no icon, no damage label. AoE shape outlines must
	# stay visually quiet vs primary hex (icon + number live on the source).
	if outline_only:
		return
	_draw_icon()
	_draw_damage_label(tile_size)


# 049 / AC-5: icon at hex center — Texture2D when SkillIconResolver finds
# one, else first-letter fallback in big outlined font. Letter sized via
# UiTheme.FS_NUM_LARGE so it reads at default zoom (visibility doctrine —
# in-world text MUST use FS_NUM_*).
func _draw_icon() -> void:
	if icon_skill == null:
		return
	var tex: Texture2D = SkillIconResolver.resolve(icon_skill)
	if tex != null:
		# Center the texture rect on (0, 0) — Node2D's local origin = hex center.
		draw_texture_rect(tex,
				Rect2(-_ICON_SIZE * 0.5, _ICON_SIZE),
				false)
		return
	# Letter fallback. Localised name first, then skill id as last resort
	# so unlocalised dev skills still render something readable.
	var name_str: String = Localization.t(String(icon_skill.name), String(icon_skill.id))
	if name_str.is_empty():
		return
	var letter: String = name_str.substr(0, 1).to_upper()
	var font: Font = ThemeDB.fallback_font
	var fs: int = UiTheme.FS_NUM_LARGE
	var sz: Vector2 = font.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	# Baseline correction — get_string_size returns ascender height, not
	# vertical center. Pulling up by ~30% of size puts the visual letter
	# centroid near (0,0).
	var pos: Vector2 = Vector2(-sz.x * 0.5, sz.y * 0.30)
	draw_string_outline(font, pos, letter,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
			UiTheme.WORLD_TEXT_OUTLINE_SIZE, UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	draw_string(font, pos, letter,
			HORIZONTAL_ALIGNMENT_CENTER, -1, fs, UiTheme.TEXT)


# 049 / AC-5: damage moved from above-hex (was -tile.y/2 - 6, collided with
# HP bars) to bottom-center inside the hex, below the icon. Crisp dark
# outline retained — telegraph damage is Pillar 1 critical UI per CLAUDE.md.
func _draw_damage_label(tile_size: Vector2) -> void:
	if damage <= 0:
		return
	var font: Font = ThemeDB.fallback_font
	var font_size: int = UiTheme.BAR_FONT_SIZE_OVERHEAD
	var text: String = "-%d" % damage
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	# Bottom-center: tile_size.y * 0.32 sits just inside the lower flat edge
	# of a flat-top hex. Slight tweak vs 0.5 because get_string_size returns
	# ascender height; this places the visual baseline near the edge.
	var pos: Vector2 = Vector2(-size.x * 0.5, tile_size.y * 0.32)
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
