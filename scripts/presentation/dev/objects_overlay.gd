extends Node2D
## ObjectsOverlay — renders tile objects in the map editor.
##
## In the live game, tile objects exist as data on HexTile (object_id) plus
## the floor's custom_data. Visuals come from spritesheet baked into TileSet
## or from runtime decals. The editor doesn't have that pipeline, so this
## overlay paints a Sprite2D-per-coord using each TileObject's sprite_path.
##
## API:
##   set_object(coord, object_id) — place/replace; pass &"" to clear
##   clear_object(coord)
##   clear_all()
##
## Children are named by coord ("o_<x>_<y>") so set_object is idempotent and
## doesn't leak duplicate sprites.

const ObjectSilhouette = preload("res://scripts/presentation/dev/object_silhouette.gd")
const UiTheme = preload("res://scripts/presentation/ui_theme.gd")

const PLACEHOLDER_TEXTURE: Texture2D = null  # null = no texture, just modulated rect via icon node

@export var grid: HexGrid
@export var sprite_scale: float = 0.6  # most TileObject sprites are larger than a hex

var _registry: TileObjectRegistry  # resolved from grid in _ready


func _ready() -> void:
	if grid == null:
		grid = get_parent() as HexGrid


## Late-binding registry hook — controller calls this AFTER grid.initialize()
## so the registry exists. Without it, set_object can only place placeholders.
func bind_registry(registry: TileObjectRegistry) -> void:
	_registry = registry


func set_object(coord: Vector2i, object_id: StringName) -> void:
	var existing: Node = get_node_or_null(_node_name(coord))
	if existing != null:
		existing.queue_free()
	if object_id == &"":
		return
	if grid == null or grid.tile_map_layer == null:
		return

	var center := grid.tile_map_layer.map_to_local(coord)
	var tex: Texture2D = _resolve_texture(object_id)
	if tex != null:
		# Real sprite path — draw it.
		var sprite := Sprite2D.new()
		sprite.name = _node_name(coord)
		sprite.position = center
		sprite.scale = Vector2(sprite_scale, sprite_scale)
		sprite.texture = tex
		add_child(sprite)
		return

	# No sprite — fall back to a recognizable monochrome silhouette.
	# Shape comes from the object's id; color from its tags. Silhouettes
	# read as form (tree, table, fountain) rather than as hash-coloured rects.
	var silhouette: Node2D = ObjectSilhouette.new()
	silhouette.name = _node_name(coord)
	silhouette.position = center
	var info: Dictionary = _silhouette_for(object_id)
	silhouette.call("setup", info.get("shape", &"circle"), info.get("color", _placeholder_color(object_id)))
	add_child(silhouette)


func clear_object(coord: Vector2i) -> void:
	set_object(coord, &"")


func clear_all() -> void:
	for child in get_children():
		child.queue_free()


# ── Internal ────────────────────────────────────────────────────────────────

static func _node_name(coord: Vector2i) -> String:
	return "o_%d_%d" % [coord.x, coord.y]


func _resolve_texture(object_id: StringName) -> Texture2D:
	if _registry == null:
		return null
	var obj: TileObject = _registry.get_object(object_id)
	if obj == null or obj.sprite_path == "":
		return null
	# Tolerate missing files — return null so caller falls back to silhouette.
	if not ResourceLoader.exists(obj.sprite_path):
		return null
	var res: Resource = load(obj.sprite_path)
	return res as Texture2D


## Returns { "shape": StringName, "color": Color } for a TileObject.
## Shape is a per-id mapping; color is derived from tags so designers can
## tune visuals just by editing JSON tags. Unknown ids fall back to a
## hash-coloured circle (existing behaviour, just round instead of square).
func _silhouette_for(object_id: StringName) -> Dictionary:
	var shape: StringName = _shape_for_id(object_id)
	var color: Color = _color_for_object(object_id)
	return { "shape": shape, "color": color }


static func _shape_for_id(object_id: StringName) -> StringName:
	# Direct id-to-shape mapping. Add new objects here when introducing
	# them in data/tile_objects/.
	match String(object_id):
		"mountain":       return &"triangle_peak"
		"boulder":        return &"circle"
		"tree":           return &"triangle_tall"
		"crystal":        return &"diamond"
		"column":         return &"rect_tall"
		"wooden_table":   return &"rect_wide"
		"wooden_barrel":  return &"rect_tall"
		"heal_fountain":  return &"diamond_outline"
		"lava_pool":      return &"blob"
		_:                return &"circle"


func _color_for_object(object_id: StringName) -> Color:
	if _registry == null:
		return _placeholder_color(object_id)
	var obj: TileObject = _registry.get_object(object_id)
	if obj == null:
		return _placeholder_color(object_id)
	# Tag-driven palette. Order matters: hazard wins over liquid, liquid
	# beats stone, etc. Tweak per balance feedback.
	var tags := obj.tags as Array
	if "hazard" in tags:
		return UiTheme.SEM_DAMAGE.lightened(0.1)       # red-orange
	if "liquid" in tags:
		return UiTheme.SEM_BUFF                         # cool blue
	if "wood" in tags or "plant" in tags:
		return Color("4a7d4a")                          # forest green
	if "stone" in tags or "construct" in tags:
		return UiTheme.TEXT_DIM                         # cool grey
	if "metal" in tags:
		return Color("9aa3b2").lightened(0.2)           # silvery
	if "furniture" in tags:
		return Color("8a6d3b")                          # warm brown
	return _placeholder_color(object_id)


static func _placeholder_color(object_id: StringName) -> Color:
	# Deterministic per-id; saturated so it reads as "this is an object slot"
	# rather than terrain. Hash the StringName via String() — StringName.hash()
	# isn't exposed in 4.6 but String hash is.
	var h: int = String(object_id).hash()
	var hue: float = float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85, 0.85)
