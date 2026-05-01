class_name DamageEffect
extends AbilityEffect
## Flat damage. amount is set from JSON via AbilityDatabase.

@export var amount: int = 1


func apply(caster: Actor, target: Actor, _ctx: Dictionary) -> void:
	# KEEP IN SYNC with Ability.predicted_damage_to
	var bonus: int = 0 if caster == null else caster.damage_bonus
	target.take_damage(maxi(0, amount + bonus))
