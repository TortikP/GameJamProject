class_name ConditionSkillReady
extends TacticCondition
## AC-C8: actor's named skill is off cooldown.
##
## 034: reads from actor.get_skill_by_id (per-owner Skill copy), not from
## SkillDatabase (DB instance never receives cd state under per-owner
## cooldown isolation). Was the case the original docstring foresaw:
## "If/when actors get their own cooldown state, this condition needs
## to look up via actor.get_skills() instead." — that day arrived.
## Returns false if the actor doesn't own a skill with this id.

@export var skill_id: StringName = &""


func evaluate(actor: Actor, _ctx: Dictionary) -> bool:
	if skill_id == &"":
		return false
	var skill: Skill = actor.get_skill_by_id(skill_id)
	if skill == null:
		return false
	return skill.is_ready()
