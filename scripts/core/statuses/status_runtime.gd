class_name StatusRuntime
extends RefCounted
## StatusRuntime — abstract base. All methods are static; runtime instances
## are never created. Lookup yields the GDScript class itself via
## StatusRegistry.runtime_for(id).
##
## 027: spec/027-status-effects/spec.md §"StatusRuntime (abstract base)".


## Compute snapshot_value at apply-time. Args come straight from JSON parse;
## skill_level is the Skill.level effective at cast-time.
## Default 0 (statuses with no numeric scaling).
static func compute_snapshot(_args: Array[int], _skill_level: int) -> int:
	return 0


## Called by Actor.add_status AFTER the instance is stored. Side effects on
## the actor are allowed (e.g. behavior_id swap for feared/enraged).
static func on_apply(_actor: Actor, _instance: StatusInstance) -> void:
	pass


## Symmetric to on_apply. Called by Actor.remove_status BEFORE the instance
## is erased (so on_remove sees its own instance still in _statuses if it
## needs to inspect siblings).
static func on_remove(_actor: Actor, _instance: StatusInstance) -> void:
	pass


## Called at the start of the actor's turn (world_turn_ended), before AI
## planning / player input. May call actor.take_damage, may set
## instance.duration = 0 to expire early, may toggle instance.rt_flag.
static func on_turn_start(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> void:
	pass


## Called from Actor.effective_speed. Each runtime sees the previous result.
## Order: rooted → slowed → others (rooted wins via 0-clamp).
static func modify_speed(current: int, _instance: StatusInstance) -> int:
	return current


## Summed by Actor.damage_reduction over all active instances. Default 0;
## only shielded overrides.
static func damage_reduction(_instance: StatusInstance) -> int:
	return 0


## Movement override hook for SLOWED (flip-flop) and ROOTED (always hold).
## Sentinel return values:
##   Vector2i(-1, -1) → defer to default policy
##   Vector2i(-2, -2) → hold this turn (suppress movement_policy.pick_step)
##   Any other Vector2i → use as actor.move_intent_coord (currently unused)
##
## Feared/enraged DO NOT use this hook — they swap behavior_id via on_apply
## and let the dedicated scenario's movement_policy steer.
static func override_movement(_actor: Actor, _instance: StatusInstance, _ctx: Dictionary) -> Vector2i:
	return Vector2i(-1, -1)
