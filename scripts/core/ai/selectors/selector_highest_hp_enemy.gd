class_name SelectorHighestHpEnemy
extends TargetSelector
## AC-T3: pick opposing-team actor with the highest hp. Tiebreak — first in candidates order.


func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	var best: Actor = null
	var best_hp: int = -1
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if cand.hp > best_hp:
			best_hp = cand.hp
			best = cand
	return best
