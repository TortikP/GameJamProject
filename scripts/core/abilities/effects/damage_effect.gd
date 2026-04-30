class_name DamageEffect
extends AbilityEffect
## Flat damage. amount is set from JSON via AbilityDatabase.

@export var amount: int = 1


func apply(_caster: Actor, target: Actor, _ctx: Dictionary) -> void:
	target.take_damage(amount)
