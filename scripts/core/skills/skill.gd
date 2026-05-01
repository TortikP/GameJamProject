class_name Skill
extends Resource
## Skill — ordered composition of 1..N Abilities with a shared cooldown.
##
## cast() executes abilities in array order. Each ability resolves its own targets
## at execution time (not at skill-start) — enabling multi-ability combos like vampirism.
##
## tick_cooldown(n) is called by TurnManager each turn. Cooldown ticks at
## "end of caster's turn" by convention — clarified once TurnManager integrates.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var cooldown: int = 0
@export var abilities: Array[Ability] = []

var _cd_remaining: int = 0


func is_ready() -> bool:
	return _cd_remaining <= 0


## Pre-check for UI slot greying. Delegates to first ability.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if abilities.is_empty():
		return false
	return (abilities[0] as Ability).can_apply(caster, ctx)


## Damage preview for hover UI. Sums predicted_damage_to across all abilities.
func predicted_damage_to(caster: Actor, target: Actor, ctx: Dictionary) -> int:
	var total: int = 0
	for ab in abilities:
		total += (ab as Ability).predicted_damage_to(caster, target, ctx)
	return total


## Returns all contained ability IDs. Used by MoveRangeOverlay for attack-range painting.
func get_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for ab in abilities:
		ids.append((ab as Ability).id)
	return ids


func cast(caster: Actor, ctx: Dictionary) -> bool:
	if not is_ready():
		GameLogger.info("Skill", "%s on cooldown (%d remaining)" % [id, _cd_remaining])
		return false

	var any_resolved: bool = false
	var all_target_ids: Array = []

	for ab in abilities:
		var resolved: bool = ab.cast(caster, ctx)
		if resolved:
			any_resolved = true

	if any_resolved:
		_cd_remaining = cooldown
		EventBus.skill_cast.emit(caster.actor_id, id, all_target_ids)
		GameLogger.info("Skill", "%s cast by %s → cd=%d" % [id, caster.actor_id, _cd_remaining])

	return any_resolved


## Reduce remaining cooldown by `by` turns. Called from TurnManager.
func tick_cooldown(by: int = 1) -> void:
	_cd_remaining = maxi(0, _cd_remaining - by)
