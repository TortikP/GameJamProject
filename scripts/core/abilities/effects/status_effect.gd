class_name StatusEffect
extends AbilityEffect
## Applies a named status to an Actor for `duration` turns.
## Actor.add_status(id, duration) is called if the method exists;
## otherwise logs and skips — real status system is a separate feature.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var status: StringName = &""


func _init() -> void:
	type = &"status"
	requires_alive_target = true


func apply(_caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	if status == &"":
		GameLogger.warn("StatusEffect", "status id is empty — skipping")
		return
	if actor.has_method("add_status"):
		actor.add_status(status, duration)
	else:
		GameLogger.info("StatusEffect", "Actor.add_status not yet implemented; would apply '%s' for %d turns to %s" % [status, duration, actor.actor_id])
