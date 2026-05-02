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

	var sprite := Sprite2D.new()
	sprite.name = _node_name(coord)
	sprite.position = grid.tile_map_layer.map_to_local(coord)
	sprite.scale = Vector2(sprite_scale, sprite_scale)

	var tex: Texture2D = _resolve_texture(object_id)
	if tex != null:
		sprite.texture = tex
	else:
		# Placeholder: a small ColorRect parented to the sprite, sized roughly
		# to a hex inscribed circle, modulated by hashed object_id.
		var rect := ColorRect.new()
		rect.size = Vector2(48, 42)
		rect.position = -rect.size * 0.5
		rect.color = _placeholder_color(object_id)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.add_child(rect)
	add_child(sprite)


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
	# Tolerate missing files — return null so caller falls back to placeholder.
	if not ResourceLoader.exists(obj.sprite_path):
		return null
	var res: Resource = load(obj.sprite_path)
	return res as Texture2D


static func _placeholder_color(object_id: StringName) -> Color:
	# Deterministic per-id; saturated so it reads as "this is an object slot"
	# rather than terrain. Hash the StringName via String() — StringName.hash()
	# isn't exposed in 4.6 but String hash is.
	var h: int = String(object_id).hash()
	var hue: float = float(h % 360) / 360.0
	return Color.from_hsv(hue, 0.55, 0.85, 0.85)
