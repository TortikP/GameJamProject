extends Node2D
## SpawnersOverlay — renders player/enemy spawners in the map editor.
##
## ## Visuals (spec 060 follow-up: F-060-IMPL-?)
##
## Enemy spawner: semi-transparent enemy sprite from
## `data/enemies/<ref>.json:sprite`, modulate.a = 0.65 so the
## underlying terrain stays readable through the placement preview.
## Timer label sits at the top-right corner, FS_NUM_HUGE, tinted by
## hashed enemy_id (so different enemies remain visually distinct).
## Sprite is centered on hex; falls back to the diamond glyph idiom
## (◆ + first three letters of ref) if the sprite asset is missing.
##
## Player spawner: ★ glyph (no player sprite asset exists yet) +
## timer label (timer ignored at runtime for kind=player but kept
## for visual symmetry with enemies — matches old behavior).
##
## API mirrors ObjectsOverlay:
##   set_spawner(coord, kind, ref) — kind ∈ &"player" | &"enemy"
##   clear_spawner(coord) / clear_all() / refresh(spawners)
##
## Children are named "s_<x>_<y>" so set_spawner is idempotent.

const UiTheme = preload("res://scripts/presentation/ui_theme.gd")
const ENEMIES_DIR := "res://data/enemies/"
const SPRITE_ALPHA := 0.65  # placement-preview transparency
const HEX_FIT_PX := 96.0    # sprite scaled-to-fit target on its longer side

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

	var color: Color = UiTheme.FOCUS if kind == &"player" else _enemy_color(ref)

	var holder := Node2D.new()
	holder.name = _node_name(coord)
	holder.position = grid.tile_map_layer.map_to_local(coord)

	# Try real sprite for enemies. Player has no asset yet — fall through
	# to glyph fallback. Missing/invalid sprite path also falls through.
	var sprite_node: Node2D = null
	if kind == &"enemy":
		sprite_node = _build_sprite_node(ref)
	if sprite_node != null:
		holder.add_child(sprite_node)
	else:
		# Fallback — original glyph + monogram pair.
		_add_glyph_fallback(holder, kind, ref, color)

	# Timer label, top-right of hex. Always shown (visibility doctrine)
	# — big number, outline, sits over the sprite at full opacity so it
	# stays legible even with the semi-transparent sprite below.
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


## Bulk-rebuild from a LevelData.spawners array. Each entry is
## `{"coord": Vector2i, "kind": StringName, "ref": StringName, "timer": int}`.
## Used by the new level editor (060). Per-coord set_spawner remains
## for incremental editing.
func refresh(spawners: Array) -> void:
	clear_all()
	for entry in spawners:
		var coord: Vector2i = entry["coord"]
		var kind: StringName = StringName(entry["kind"])
		var ref: StringName = StringName(entry.get("ref", &""))
		var timer: int = int(entry.get("timer", 1))
		set_spawner(coord, kind, ref, timer)


# ── Internal ────────────────────────────────────────────────────────────────

## Build a Sprite2D node for the given enemy ref, scaled to fit a hex,
## with placement-preview alpha. Returns null on missing/invalid asset.
static func _build_sprite_node(ref: StringName) -> Node2D:
	var sprite_path := _read_sprite_field(ENEMIES_DIR + String(ref) + ".json")
	if sprite_path == "":
		return null
	var p: String = sprite_path if sprite_path.begins_with("res://") else "res://" + sprite_path
	if not ResourceLoader.exists(p):
		return null
	var tex: Texture2D = load(p) as Texture2D
	if tex == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.centered = true
	sprite.modulate = Color(1.0, 1.0, 1.0, SPRITE_ALPHA)
	# Scale-to-fit so big art fits on a hex; small art doesn't get blown
	# up beyond its native size.
	var size: Vector2 = tex.get_size()
	var longer: float = max(size.x, size.y)
	if longer > 0.0 and longer > HEX_FIT_PX:
		var s: float = HEX_FIT_PX / longer
		sprite.scale = Vector2(s, s)
	return sprite


static func _read_sprite_field(json_path: String) -> String:
	if not FileAccess.file_exists(json_path):
		return ""
	var raw := FileAccess.get_file_as_string(json_path)
	if raw == "":
		return ""
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return ""
	return str((parsed as Dictionary).get("sprite", ""))


## Fallback rendering when no sprite asset is available — the prior
## glyph+monogram approach. Used for the Player spawner (no asset)
## and for enemies whose sprite path is missing or fails to load.
static func _add_glyph_fallback(holder: Node2D, kind: StringName,
		ref: StringName, color: Color) -> void:
	var glyph: String = "★" if kind == &"player" else "◆"
	var label_text: String = "P" if kind == &"player" else String(ref).substr(0, 3).to_upper()

	var glyph_label := Label.new()
	glyph_label.text = glyph
	glyph_label.add_theme_font_size_override("font_size", UiTheme.FS_DIALOGUE_NAME)
	glyph_label.add_theme_color_override("font_color", color)
	glyph_label.add_theme_constant_override("outline_size", 4)
	glyph_label.add_theme_color_override("font_outline_color", UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	glyph_label.position = Vector2(-22, -34)
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glyph_label)

	var tag_label := Label.new()
	tag_label.text = label_text
	tag_label.add_theme_font_size_override("font_size", UiTheme.FS_SMALL)
	tag_label.add_theme_color_override("font_color",
		UiTheme.TEXT if "TEXT" in UiTheme else Color.WHITE)
	tag_label.add_theme_constant_override("outline_size", 3)
	tag_label.add_theme_color_override("font_outline_color", UiTheme.WORLD_TEXT_OUTLINE_COLOR)
	tag_label.position = Vector2(-12, 6)
	tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tag_label)


static func _node_name(coord: Vector2i) -> String:
	return "s_%d_%d" % [coord.x, coord.y]


static func _enemy_color(enemy_id: StringName) -> Color:
	var h: int = String(enemy_id).hash()
	var hue: float = float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.6, 0.95, 1.0)
