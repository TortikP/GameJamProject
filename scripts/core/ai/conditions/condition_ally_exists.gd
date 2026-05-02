class_name ConditionAllyExists
extends TacticCondition
## 030+: true if at least one living same-team ally (other than self) exists.
## Used by support archetypes to switch between "heal allies" and "attack player"
## modes when isolated.


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var actors: Array = ctx.get("all_actors", [])
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		return true
	return false
