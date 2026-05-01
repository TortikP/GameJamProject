class_name HealEffect
extends AbilityEffect
## Restores HP. target must be an Actor.
## HoT (duration > 0): # TODO 007 HoT scaffold — works as instant for now.

@export var heal: int = 0


func _init() -> void:
	type = &"heal"
	requires_alive_target = true


func apply(_caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	actor.heal(heal)
