class_name DamageEffect
extends AbilityEffect
## Flat damage. `damage` field set from JSON via AbilityDatabase.
## target is Variant — cast to Actor; silent no-op if cast fails.
##
## DoT (duration > 0): # TODO 007 DoT scaffold — not implemented, works as instant.

@export var damage: int = 1


func apply(caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	# KEEP IN SYNC with Ability.predicted_damage_to
	var bonus: int = 0 if caster == null else caster.damage_bonus
	actor.take_damage(maxi(0, damage + bonus))
