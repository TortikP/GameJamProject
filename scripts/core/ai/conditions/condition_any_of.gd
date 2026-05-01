class_name ConditionAnyOf
extends TacticCondition
## AC-C9 composer: true iff any child is true. Empty children → false.

@export var children: Array[TacticCondition] = []


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	for child in children:
		if child.evaluate(actor, ctx):
			return true
	return false
