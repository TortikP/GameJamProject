class_name ConditionSelfHpAbove
extends TacticCondition
## AC-C3: symmetric to ConditionSelfHpBelow.

@export var pct: int = 50


func evaluate(actor: Actor, _ctx: Dictionary) -> bool:
	if actor.max_hp <= 0:
		return false
	return actor.hp * 100 > actor.max_hp * pct
