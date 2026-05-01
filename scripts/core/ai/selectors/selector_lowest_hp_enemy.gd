class_name SelectorLowestHpEnemy
extends TargetSelector
## AC-T2: pick opposing-team actor with the lowest hp. Tiebreak — first in candidates order.


func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	var best: Actor = null
	var best_hp: int = 0x7fffffff
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if cand.hp < best_hp:
			best_hp = cand.hp
			best = cand
	return best
