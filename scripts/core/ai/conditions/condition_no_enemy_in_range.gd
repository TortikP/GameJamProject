class_name ConditionNoEnemyInRange
extends TacticCondition
## AC-C5: inversion of ConditionEnemyInRange. Used by ranged casters to gate
## "don't engage in melee" rules.

@export var distance: int = 1


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	# Reuse the positive condition's logic via a transient instance — cheaper than
	# duplicating the loop and keeps behavior in lockstep.
	var inner := ConditionEnemyInRange.new()
	inner.distance = distance
	return not inner.evaluate(actor, ctx)
