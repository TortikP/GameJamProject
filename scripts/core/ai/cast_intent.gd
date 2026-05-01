class_name CastIntent
extends Resource
## CastIntent — what an actor plans to cast on the next resolve step.
##
## Written by EnemyAIPlanner.plan() (or by player input on player turns).
## Consumed by GodmodeController._resolve_cast_intent() in the next tick.
##
## target_id == &"" means hex-target — read target_coord.
## target_id != &"" means entity-target — read target_id (target_coord may still be
## set as a hint, but the resolver should look up the entity by id).

@export var skill_id: StringName = &""
@export var target_id: StringName = &""
@export var target_coord: Vector2i = Vector2i(-1, -1)


func is_valid() -> bool:
	return skill_id != &""
