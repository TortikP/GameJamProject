class_name ConditionSkillReady
extends TacticCondition
## AC-C8: SkillDatabase.get_skill(skill_id).is_ready() — actor's named skill is off cooldown.
##
## Note: this checks the SHARED SkillDatabase instance, not the actor's per-instance
## cooldown state. In the current 007 design skills live in the database as singletons;
## per-actor cooldown lives on the singleton too. If/when actors get their own cooldown
## state, this condition needs to look up via actor.get_skills() instead.

@export var skill_id: StringName = &""


func evaluate(_actor: Actor, _ctx: Dictionary) -> bool:
	if skill_id == &"":
		return false
	var skill: Skill = SkillDatabase.get_skill(skill_id)
	if skill == null:
		return false
	return skill.is_ready()
