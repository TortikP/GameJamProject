class_name ConditionAllyCountBelow
extends TacticCondition
## AC-C11 (030): true if the number of living same-team allies (excluding self) < count.
## Hook for summoner archetype (summoner.json out of scope for 030).

@export var count: int = 2


func evaluate(actor: Actor, ctx: Dictionary) -> bool:
	var actors: Array = ctx.get("all_actors", [])
	var n: int = 0
	for other_v in actors:
		if not (other_v is Actor):
			continue
		var other: Actor = other_v
		if other == actor or not other.is_alive() or other.team != actor.team:
			continue
		n += 1
	return n < count
