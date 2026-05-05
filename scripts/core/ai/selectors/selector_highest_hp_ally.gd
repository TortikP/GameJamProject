class_name SelectorHighestHpAlly
extends TargetSelector
## AC-T9 (030): pick the same-team ally with the highest hp/max_hp ratio.
## Mirror of SelectorLowestHpAlly. Used by buffer to prioritise the front-liner.
## Candidates arrive pre-filtered (allies, alive, != self) via _build_target_candidates
## after the AC-PL1 patch that adds SelectorHighestHpAlly to the want_allies branch.


func resolve(actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	var best: Actor = null
	var best_ratio: float = -1.0
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if cand == actor:
			continue
		if cand.max_hp <= 0:
			continue
		var ratio: float = float(cand.hp) / float(cand.max_hp)
		if ratio > best_ratio:
			best_ratio = ratio
			best = cand
	return best
