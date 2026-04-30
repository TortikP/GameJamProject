class_name Ability
extends Resource
## Ability — composed cast unit. Target × Effect × Modifier[].
##
## Lifecycle (THEME_PLAN.md §4, fixed contract):
##   1. targets = target.resolve(caster, ctx)
##   2. for m in modifiers: m.before_apply(caster, targets, ctx)
##   3. for t in targets:
##        effect.apply(caster, t, ctx)
##        for m in modifiers: m.after_apply(caster, t, ctx)
##   4. for m in modifiers: m.after_cast(caster, targets, ctx)
##
## No priorities. Modifier order in array = execution order.
## Empty target list short-circuits at step 2.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var target: AbilityTarget
@export var effect: AbilityEffect
@export var modifiers: Array[AbilityModifier] = []


## Cheap pre-check used by UI to grey out un-castable slots. Doesn't run modifiers.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if target == null or effect == null:
		return false
	return target.can_apply(caster, ctx)


## Best-effort damage forecast for hover-preview UI. Currently just reads
## DamageEffect.amount; returns 0 for non-damage effects. Modifiers can
## later expose a multiplier hook if needed (jam scope: skip).
func predicted_damage_to(_caster: Actor, _target: Actor, _ctx: Dictionary) -> int:
	if effect is DamageEffect:
		return (effect as DamageEffect).amount
	return 0


## Returns true if the ability actually resolved (had at least one valid target).
## A no-target cast (e.g. clicked empty hex) returns false and consumers should
## NOT advance turns on it.
func cast(caster: Actor, ctx: Dictionary) -> bool:
	if target == null or effect == null:
		GameLogger.error("Ability", "%s: target or effect is null" % id)
		return false

	var targets: Array = target.resolve(caster, ctx)
	if targets.is_empty():
		GameLogger.info("Ability", "%s: no targets" % id)
		return false

	for m in modifiers:
		m.before_apply(caster, targets, ctx)

	for t in targets:
		if t == null:
			continue
		effect.apply(caster, t, ctx)
		for m in modifiers:
			m.after_apply(caster, t, ctx)

	for m in modifiers:
		m.after_cast(caster, targets, ctx)

	var target_ids: Array = []
	for t in targets:
		if t != null:
			target_ids.append(t.actor_id)
	EventBus.ability_cast.emit(caster.actor_id, id, target_ids)
	return true
