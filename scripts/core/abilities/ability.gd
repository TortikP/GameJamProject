class_name Ability
extends Resource
## Ability — single cast unit. target × area × effect[] × modifier[].
##
## Lifecycle (007-skill-system, THEME_PLAN §4):
##   1. primary = target.resolve(caster, ctx)   → Variant
##   2. eff_area = area.duplicate(); apply param-mods to area
##   3. victims = eff_area.resolve(caster, primary, ctx)   → Array
##   4. for victim in victims:
##        for base_eff in effects:
##          eff_dup = base_eff.duplicate()
##          apply param-mods to eff_dup
##          if requires_alive_target and victim is dead: continue
##          eff_dup.apply(caster, victim, ctx)
##   5. EventBus.ability_cast.emit(...)
##
## Modifier formula (AC-M5): final = (base + Σ adds) × Π muls
## Applied per-param, commutative, int → floor, float → as-is.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var target: AbilityTarget
@export var area: AbilityArea
@export var effects: Array[AbilityEffect] = []
@export var modifiers: Array[ParameterModifier] = []


## Cheap pre-check for UI (grey-out un-castable slots). Doesn't run area/effects.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if target == null or area == null or effects.is_empty():
		return false
	return target.can_apply(caster, ctx)


## Damage preview for hover UI. Sums all DamageEffect.damage values + caster bonus,
## after applying add/mul modifiers. Returns 0 for non-damage-only abilities.
## KEEP IN SYNC with DamageEffect.apply.
func predicted_damage_to(caster: Actor, _target: Actor, _ctx: Dictionary) -> int:
	var total: int = 0
	var bonus: int = 0 if caster == null else caster.damage_bonus
	for base_eff in effects:
		if not base_eff is DamageEffect:
			continue
		var eff_dup: AbilityEffect = base_eff.duplicate()
		_apply_param_modifiers(eff_dup, modifiers)
		total += maxi(0, (eff_dup as DamageEffect).damage + bonus)
	return total


## Returns true if at least one victim was processed.
## False means "no valid targets" — callers should NOT advance the turn.
func cast(caster: Actor, ctx: Dictionary) -> bool:
	if target == null or area == null or effects.is_empty():
		GameLogger.error("Ability", "%s: target / area / effects misconfigured" % id)
		return false

	var primary: Variant = target.resolve(caster, ctx)
	if primary == null:
		GameLogger.info("Ability", "%s: no primary target" % id)
		return false

	# Duplicate area and mutate with param-mods (shared resource protection)
	var eff_area: AbilityArea = area.duplicate()
	_apply_param_modifiers(eff_area, modifiers)

	var victims: Array = eff_area.resolve(caster, primary, ctx)
	if victims.is_empty():
		GameLogger.info("Ability", "%s: no victims in area" % id)
		return false

	var target_ids: Array = []

	for victim in victims:
		for base_eff in effects:
			var eff_dup: AbilityEffect = base_eff.duplicate()
			_apply_param_modifiers(eff_dup, modifiers)
			if eff_dup.requires_alive_target and _is_dead(victim):
				continue
			eff_dup.apply(caster, victim, ctx)
		if victim is Actor:
			target_ids.append((victim as Actor).actor_id)

	EventBus.ability_cast.emit(caster.actor_id, id, target_ids)
	return true


# ── Internals ────────────────────────────────────────────────────────────────

## Mutates obj's numeric properties in-place per modifier list.
## Formula per param p: final = (base + Σ adds_p) × Π muls_p
## int → floor, float → as-is.
func _apply_param_modifiers(obj: Object, mods: Array[ParameterModifier]) -> void:
	var params: Dictionary = {}
	for m in mods:
		if m.applies_to(obj):
			params[m.target_param] = true

	for param in params.keys():
		var base: Variant = obj.get(param)
		var add_sum: float = 0.0
		var mul_prod: float = 1.0
		for m in mods:
			if m.target_param != param:
				continue
			if m.op == &"add":
				add_sum += m.value
			elif m.op == &"mul":
				mul_prod *= m.value
		var final_val: float = (float(base) + add_sum) * mul_prod
		if typeof(base) == TYPE_INT:
			obj.set(param, int(floor(final_val)))
		else:
			obj.set(param, final_val)


func _is_dead(victim: Variant) -> bool:
	if victim is Actor:
		return not (victim as Actor).is_alive()
	return false
