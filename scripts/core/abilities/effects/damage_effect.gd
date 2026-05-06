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
	var dealt_raw: int = maxi(0, damage + bonus)
	if dealt_raw <= 0:
		return
	var hp_before: int = actor.hp
	actor.take_damage(dealt_raw, caster)
	var dealt_actual: int = maxi(0, hp_before - actor.hp)
	if caster != null and dealt_actual > 0:
		var lifesteal_percent: int = caster.passive_lifesteal_percent()
		if lifesteal_percent > 0:
			var heal_amount: int = int(floor(float(dealt_actual) * float(lifesteal_percent) / 100.0))
			if heal_amount > 0:
				caster.heal(heal_amount)


## 021 scaling: damage * (1 + 0.2 * level) → floor.
func apply_level(level: int) -> void:
	if level <= 0:
		return
	damage = int(floor(damage * (1.0 + 0.2 * level)))
