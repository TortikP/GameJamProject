class_name ConditionSelfHpBelow
extends TacticCondition
## AC-C2: actor.hp / actor.max_hp * 100 < pct.

@export var pct: int = 50


func evaluate(actor: Actor, _ctx: Dictionary) -> bool:
	if actor.max_hp <= 0:
		return false
	return actor.hp * 100 < actor.max_hp * pct
