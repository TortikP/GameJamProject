class_name Skill
extends Resource
## Skill — ordered composition of 1..N Abilities with a shared cooldown.
##
## cast() executes abilities in array order. Each ability resolves its own targets
## at execution time (not at skill-start) — enabling multi-ability combos like vampirism.
##
## tick_cooldown(n) is called once per round by
## godmode_controller._tick_all_skills (driven from _on_world_turn_ended)
## for every live Actor. See spec 031-skill-cooldown-fix.
##
## 021 additions (021-skill-system-v2):
##  - name / tooltip / desc — localization keys (raw strings; resolution out of scope).
##  - behaviour_tags — renamed from `tags`. AI strategy uses these to pick a skill.
##  - mood — narrative archetype tags. No consumer yet; reserved for character system.
##  - level — power axis. Propagated into Ability.cast and predicted_damage_to.
##    Components (target/area/effect) self-react via apply_level(level) on a duplicate
##    before resolve/apply — base resource stays untouched.
##
## 026 additions (026-skill-system-v3):
##  - icon — StringName id for future IconDB. Stored, not dispatched.
##  - cast(caster, ctxs: Array[Dictionary]) — per-ability ctx. ctxs.size() must
##    equal abilities.size(); abilities[i] gets ctxs[i]. Caller (godmode_controller
##    for player, _resolve_cast_intent for AI) is responsible for collecting
##    targets per ability before calling cast.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

@export var id: StringName = &""
@export var name: String = ""
@export var tooltip: String = ""
@export var desc: String = ""
@export var icon: StringName = &""                   # 026: future IconDB lookup
@export var cooldown: int = 0
@export var behaviour_tags: Array[StringName] = []   # was: tags (renamed in 021)
@export var mood: Array[StringName] = []
@export var level: int = 0
@export var abilities: Array[Ability] = []

var _cd_remaining: int = 0


func is_ready() -> bool:
	return _cd_remaining <= 0


## Pre-check for UI slot greying. Delegates to first ability.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	if abilities.is_empty():
		return false
	return (abilities[0] as Ability).can_apply(caster, ctx)


## Damage preview for hover UI. Sums predicted_damage_to across all abilities,
## passing this skill's level so previewed numbers match what the cast will deal.
func predicted_damage_to(caster: Actor, target: Actor, ctx: Dictionary) -> int:
	var total: int = 0
	for ab in abilities:
		total += (ab as Ability).predicted_damage_to(caster, target, ctx, level)
	return total


## Returns all contained ability IDs. Used by MoveRangeOverlay for attack-range painting.
func get_ability_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for ab in abilities:
		ids.append((ab as Ability).id)
	return ids


func cast(caster: Actor, ctxs: Array[Dictionary]) -> bool:
	if not is_ready():
		GameLogger.info("Skill", "%s on cooldown (%d remaining)" % [id, _cd_remaining])
		return false

	# 026: ctxs is one Dictionary per ability — caller collects targets in phase 1.
	if ctxs.size() != abilities.size():
		GameLogger.error("Skill", "%s: ctxs.size()=%d != abilities.size()=%d" % [id, ctxs.size(), abilities.size()])
		return false

	var any_resolved: bool = false
	var all_target_ids: Array = []

	for i in abilities.size():
		# 021: pass this skill's level into each ability so per-component
		# apply_level(level) hooks fire on duplicates inside Ability.cast.
		# 026: each ability gets its own ctx from ctxs[i].
		var resolved: bool = abilities[i].cast(caster, ctxs[i], level)
		if resolved:
			any_resolved = true
			# 015 / F-014: aggregate per-ability target_ids into skill-level emit.
			# Read last_target_ids immediately after cast() — see Ability docstring.
			for tid in abilities[i].last_target_ids:
				if not all_target_ids.has(tid):
					all_target_ids.append(tid)

	if any_resolved:
		_cd_remaining = cooldown
		EventBus.skill_cast.emit(caster.actor_id, id, all_target_ids)
		GameLogger.info("Skill", "%s cast by %s → cd=%d" % [id, caster.actor_id, _cd_remaining])

	return any_resolved


## Reduce remaining cooldown by `by` turns. Called from TurnManager.
func tick_cooldown(by: int = 1) -> void:
	_cd_remaining = maxi(0, _cd_remaining - by)
