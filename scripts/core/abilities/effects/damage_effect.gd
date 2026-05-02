class_name DamageEffect
extends AbilityEffect
## Flat damage. `damage` field set from JSON via AbilityDatabase.
## target is Variant — cast to Actor; silent no-op if cast fails.
##
## 027: was a DoT scaffold via base.duration; unused. Removed with base field.

@export var damage: int = 1


func apply(caster: Actor, target: Variant, _ctx: Dictionary) -> void:
	var actor := target as Actor
	if actor == null:
		return
	# KEEP IN SYNC with Ability.predicted_damage_to
	# 027: damage_amplifier sums strong/weak status modifiers (signed).
	var bonus: int = 0
	if caster != null:
		bonus = caster.damage_bonus + caster.damage_amplifier()
	actor.take_damage(maxi(0, damage + bonus))


## 021 scaling: damage * (1 + 0.2 * level) → floor.
func apply_level(level: int) -> void:
	if level <= 0:
		return
	damage = int(floor(damage * (1.0 + 0.2 * level)))
