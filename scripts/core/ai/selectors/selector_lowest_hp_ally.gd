class_name SelectorLowestHpAlly
extends TargetSelector
## AC-T5: pick same-team ally with lowest hp/max_hp ratio. Excludes self and full-HP allies.
## (Caller already pre-filters by team and "hp < max_hp" but we double-check defensively.)


func resolve(actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	var best: Actor = null
	var best_ratio: float = 2.0
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if cand == actor:
			continue
		if cand.max_hp <= 0 or cand.hp >= cand.max_hp:
			continue
		var ratio: float = float(cand.hp) / float(cand.max_hp)
		if ratio < best_ratio:
			best_ratio = ratio
			best = cand
	return best
