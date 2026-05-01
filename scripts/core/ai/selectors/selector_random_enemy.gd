class_name SelectorRandomEnemy
extends TargetSelector
## AC-T7: pick one of the candidate enemies uniformly at random.
## Uses global RNG (project-wide, not seeded per-actor — chaos is the point).


func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	var enemies: Array = []
	for cand_v in candidates:
		if cand_v is Actor:
			enemies.append(cand_v)
	if enemies.is_empty():
		return null
	return enemies[randi() % enemies.size()]
