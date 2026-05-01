class_name ConditionAllOf
extends TacticCondition
## AC-C9 composer: true iff all children are true. Empty children → true (vacuous).
##
## Children must be PRIMITIVES (C1-C8). Nested composers are rejected at parse
## time by BehaviorDatabase._build_condition. If somehow a composer slips
## through, it's still a TacticCondition and evaluates by its rules — but the
## parser is the gate.

@export var children: Array[TacticCondition] = []


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	for child in children:
		if not child.evaluate(actor, ctx):
			return false
	return true
