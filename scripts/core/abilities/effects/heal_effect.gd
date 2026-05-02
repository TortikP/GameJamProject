class_name HealEffect
extends AbilityEffect
## Restores HP. target must be an Actor.
##
## 027: was a HoT scaffold via base.duration; unused. Removed with base field.

@export var heal: int = 0


func apply(_caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	actor.heal(heal)


## 021 scaling: heal * (1 + 0.1 * level) → floor.
func apply_level(level: int) -> void:
	if level <= 0:
		return
	heal = int(floor(heal * (1.0 + 0.1 * level)))
