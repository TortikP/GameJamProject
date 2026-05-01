class_name ConditionNotOf
extends TacticCondition
## AC-C9 composer: negates child. Child must be a PRIMITIVE (parser-enforced).
## Null child → false (defensive).

@export var child: TacticCondition


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	if child == null:
		return false
	return not child.evaluate(actor, ctx)
