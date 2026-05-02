class_name SelectorSpecificActor
extends TargetSelector
## Returns the single actor identified by ctx["behavior_target_id"].
## Bypass team filter — the source of feared/enraged is typically on the
## opposite team, but the selector mustn't assume that.
##
## Candidate list is built specially in EnemyAIPlanner._build_target_candidates
## (singleton list with the lookup, no team filter). resolve() just returns
## the first / only candidate.
##
## 027: spec/027-status-effects/spec.md §"AI scenario building blocks" / AC-AI1.


func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	if candidates.is_empty():
		return null
	return candidates[0]
