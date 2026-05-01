class_name TacticCondition
extends Resource
## TacticCondition — predicate evaluated against world state during AI planning.
##
## Subclasses override evaluate(). Composers (all_of / any_of / not_of) hold
## children but per AC-C9 only ONE level of nesting is allowed — children must
## be primitives, not composers themselves. BehaviorDatabase enforces this at
## parse time and replaces invalid structures with condition_always + warn.
##
## ctx schema (filled by EnemyAIPlanner.plan):
##   {
##     "registry": ActorRegistry,   # all actors lookup
##     "grid":     HexGrid,         # positions, distances, paths
##     "all_actors": Array,         # registry.all() snapshot for the turn
##     "turn":     int,             # TurnManager.current_turn
##   }


func evaluate(_actor: Actor, _ctx: Dictionary) -> bool:
	return false
