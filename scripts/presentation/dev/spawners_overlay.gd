extends Node2D
## SpawnersOverlay — renders player/enemy spawners in the map editor.
##
## Player spawner: distinct icon (★ glyph + accent color).
## Enemy spawner: ◆ glyph tinted by hashed enemy_id so different enemies are
## visually distinguishable even before art lands.
##
## API mirrors ObjectsOverlay:
##   set_spawner(coord, kind, ref) — kind ∈ &"player" | &"enemy", ref = enemy_id or &""
##   clear_spawner(coord)
##   clear_all()
##
## Children are named "s_<x>_<y>" so set_spawner is idempotent.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

@export var grid: HexGrid


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid


func set_spawner(coord: Vector2i, kind: StringName, ref: StringName) -> void:
	var existing: Node = get_node_or_null(_node_name(coord))
	if existing != null:
		existing.queue_free()
	if kind == &"":
		return
	if grid == null or grid.tile_map_layer == null:
		return

	var glyph: String = "★" if kind == &"player" else "◆"
	var color: Color = UiTheme.FOCUS if kind == &"player" else _enemy_color(ref)
	var label_text: String = "P" if kind == &"player" else String(ref).substr(0, 3).to_upper()

	var holder := Node2D.new()
	holder.name = _node_name(coord)
	holder.position = grid.tile_map_layer.map_to_local(coord)

	var glyph_label := Label.new()
	glyph_label.text = glyph
	glyph_label.add_theme_font_size_override("font_size", 48)
	glyph_label.add_theme_color_override("font_color", color)
	glyph_label.add_theme_constant_override("outline_size", 4)
	glyph_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	glyph_label.position = Vector2(-22, -34)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph_label)

	var tag_label := Label.new()
	tag_label.text = label_text
	tag_label.add_theme_font_size_override("font_size", 14)
	tag_label.add_theme_color_override("font_color", UiTheme.TEXT if "TEXT" in UiTheme else Color.WHITE)
	tag_label.add_theme_constant_override("outline_size", 3)
	tag_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	tag_label.position = Vector2(-12, 6)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag_label)

	add_child(holder)


func clear_spawner(coord: Vector2i) -> void:
	set_spawner(coord, &"", &"")


func clear_all() -> void:
	for child in get_children():
		child.queue_free()


# ── Internal ────────────────────────────────────────────────────────────────

static func _node_name(coord: Vector2i) -> String:
	return "s_%d_%d" % [coord.x, coord.y]


static func _enemy_color(enemy_id: StringName) -> Color:
	var h: int = String(enemy_id).hash()
	var hue: float = float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.95, 1.0)
