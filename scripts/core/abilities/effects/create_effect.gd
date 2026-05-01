class_name CreateEffect
extends AbilityEffect
## Spawns a game object at a hex coordinate.
## target MUST be a Vector2i; if it's an Actor/other, effect is silently skipped (AC-E5).
## Spawning delegates to a future ObjectSpawner autoload; logs stub for now.
##
## 021: field renamed game_object_id → entity_id (matches "actor" target rename).

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var entity_id: StringName = &""


func _init() -> void:
	type = &"create"
	requires_alive_target = false   # hexes don't "die"


func apply(_caster: Actor, _target: Variant, ctx: Dictionary) -> void:
	# Coord comes from ctx — victims are now always Actors, not hex coords.
	var coord_var: Variant = ctx.get("target_coord")
	if not coord_var is Vector2i:
		return
	var coord := coord_var as Vector2i

	var grid: HexGrid = ctx.get("grid")
	if grid == null:
		return

	# Occupied check (AC-E5)
	if grid.get_actor_at(coord) != &"":
		GameLogger.info("CreateEffect", "hex %s occupied — skip create '%s'" % [str(coord), entity_id])
		return

	# TODO: delegate to ObjectSpawner.spawn(entity_id, coord) when available
	GameLogger.info("CreateEffect", "STUB — would spawn '%s' at %s" % [entity_id, str(coord)])
