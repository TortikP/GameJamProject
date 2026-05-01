class_name ConditionAlways
extends TacticCondition
## AC-C1: always true. Used as catch-all in the last rule of a scenario.


func evaluate(_actor: Actor, _ctx: Dictionary) -> bool:
	return true
