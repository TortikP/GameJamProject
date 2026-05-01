class_name MovementPolicy
extends Resource
## MovementPolicy — picks the next walkable hex for an enemy when no rule fires.
##
## Returns Vector2i: a NEIGHBOR coord of actor's current position to step into,
## or Vector2i(-1, -1) meaning "no anchor / hold position" (logged by planner as
## per Q-AI-6).
##
## Policies don't pathfind beyond one step — planner re-runs them every turn.
##
## ctx schema: same as TacticCondition (registry, grid, all_actors, turn).


func pick_step(_actor: Actor, _ctx: Dictionary) -> Vector2i:
	return Vector2i(-1, -1)
