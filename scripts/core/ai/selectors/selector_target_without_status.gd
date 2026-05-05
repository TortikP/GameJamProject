class_name SelectorTargetWithoutStatus
extends TargetSelector
## AC-T10 (030): pick the first opposing-team actor that does NOT have status_id active.
## Used by debuffer archetype to avoid stacking the same debuff on an already-affected target.
## Returns null if all candidates already have the status (rule falls through to next).
## Requires actor.has_status(id) from 027-status-effects — confirmed at actor.gd:201.

@export var status_id: StringName = &""


func resolve(_actor: Actor, candidates: Array, _ctx: Dictionary) -> Variant:
	if status_id == &"":
		return null   # misconfigured rule — bail silently
	for cand_v in candidates:
		if not (cand_v is Actor):
			continue
		var cand: Actor = cand_v
		if not cand.is_alive():
			continue
		if not cand.has_status(status_id):
			return cand
	return null
