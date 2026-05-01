class_name TargetSelector
extends Resource
## TargetSelector — picks ONE target from a candidate list during AI rule evaluation.
##
## Returns: Actor (entity-target) | Vector2i (hex-target, e.g. densest_enemy_hex) | null.
##
## EnemyAIPlanner builds the candidate list before calling resolve(). Candidates are
## filtered by team (enemy/ally/self) and reachable range across the rule's tag-priority
## skills. Selector only does the FINAL choice (sort + pick first).
##
## ctx schema: same as TacticCondition (registry, grid, all_actors, turn).


func resolve(_actor: Actor, _candidates: Array, _ctx: Dictionary) -> Variant:
	return null
