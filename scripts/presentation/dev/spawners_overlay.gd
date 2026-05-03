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


func set_spawner(coord: Vector2i, kind: StringName, ref: StringName, timer: int = 1) -> void:
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
	glyph_label.add_theme_color_override("font_outline_color", UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	glyph_label.position = Vector2(-22, -34)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph_label)

	var tag_label := Label.new()
	tag_label.text = label_text
	tag_label.add_theme_font_size_override("font_size", 14)
	tag_label.add_theme_color_override("font_color", UiTheme.TEXT if "TEXT" in UiTheme else Color.WHITE)
	tag_label.add_theme_constant_override("outline_size", 3)
	tag_label.add_theme_color_override("font_outline_color", UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	tag_label.position = Vector2(-12, 6)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag_label)

	# T88 — countdown label drawn always (visibility doctrine: big number,
	# outline, sits over the spawner sprite). Uses UiTheme.FS_NUM_HUGE so
	# it reads at default zoom. Player spawner shows timer too for symmetry,
	# even though runtime ignores it for kind=player.
	var timer_label := Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = str(timer)
	UiTheme.apply_label_kind(timer_label, "num_huge")
	UiTheme.apply_world_text_outline(timer_label)
	timer_label.add_theme_color_override("font_color", color)
	timer_label.position = Vector2(18, -52)
	timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(timer_label)

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
