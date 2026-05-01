class_name TileObject

## Pure data holder for a static object placed on a hex tile.
## Constructed once by TileObjectRegistry from a validated/normalised dict.
## Read-only by convention — consumers (pathfinder, resolver, presentation)
## just read fields directly. No signals, no node ops, no EventBus calls here —
## the resolver (follow-up 019) emits EventBus signals on behalf of objects.

enum Level { LARGE = -1, SMALL = 0, ELEVATION = 1 }

# core
var id: StringName
var level: int
var blocks_movement: bool
var blocks_abilities_through: bool
var sprite_path: String

# destructible
var breakable: bool
var hp: int
var armor_tags: Array[StringName]

# behavior — independent boolean trigger flags (see spec OQ-2 resolution)
var behavior_effect_id: StringName
var applies_on_enter: bool
var applies_on_turn_end: bool
var aura_radius: int            # 0 = no aura, >=1 = active aura
var applies_on_attacked: bool

# linger (only SMALL walkable; &"" = off). References a tile_effect with duration > 0.
var linger_effect_id: StringName

# synergy tags (used by modifier engine, downstream)
var tags: Array[StringName]

# on-destroy (only meaningful when breakable=true and hp reached 0)
var on_destroy_effect_id: StringName
var on_destroy_spawn_object_id: StringName

# audio/visual hints (presentation layer reads these — core never resolves them)
var vfx_destroy: String
var sfx_destroy: String


## Construct from a validated dict. The registry already enforced level rules,
## blocks_movement / blocks_abilities_through forcing for LARGE/ELEVATION,
## trigger zeroing for forbidden combinations, and linger gating. Treat input
## as trusted — no further validation here.
func _init(p_data: Dictionary = {}) -> void:
	id = StringName(p_data.get("id", ""))
	level = int(p_data.get("level", 0))
	blocks_movement = bool(p_data.get("blocks_movement", false))
	blocks_abilities_through = bool(p_data.get("blocks_abilities_through", false))
	sprite_path = String(p_data.get("sprite_path", ""))

	breakable = bool(p_data.get("breakable", false))
	hp = int(p_data.get("hp", 0))
	armor_tags = []
	for t in p_data.get("armor_tags", []):
		armor_tags.append(StringName(t))

	behavior_effect_id = StringName(p_data.get("behavior_effect_id", ""))
	applies_on_enter = bool(p_data.get("applies_on_enter", false))
	applies_on_turn_end = bool(p_data.get("applies_on_turn_end", false))
	aura_radius = int(p_data.get("aura_radius", 0))
	applies_on_attacked = bool(p_data.get("applies_on_attacked", false))

	linger_effect_id = StringName(p_data.get("linger_effect_id", ""))

	tags = []
	for t in p_data.get("tags", []):
		tags.append(StringName(t))

	on_destroy_effect_id = StringName(p_data.get("on_destroy_effect_id", ""))
	on_destroy_spawn_object_id = StringName(p_data.get("on_destroy_spawn_object_id", ""))

	vfx_destroy = String(p_data.get("vfx_destroy", ""))
	sfx_destroy = String(p_data.get("sfx_destroy", ""))


## Convenience: empty/null object (id=&"", all flags false). Returned by
## TileObjectRegistry.get() for unknown ids — consumers can read fields without
## null checks. Don't mutate the result; the registry hands out a shared instance.
static func empty() -> TileObject:
	return TileObject.new({})


func is_empty() -> bool:
	return id == &""


func has_aura() -> bool:
	return aura_radius >= 1
