extends Object
## EnemyDataLoader — reads data/enemies/<id>.json and applies fields to an Actor.
##
## Static-only helper, no instance state. Called from manekin_view._ready (and any
## future enemy view that wants data-driven config).
##
## JSON schema:
##   {
##     "id": "manekin",
##     "max_hp": 30,
##     "team": "enemy",
##     "speed": 1,
##     "skills": ["skill_manekin_attack"],
##     "behavior_id": "default_melee",
##     "fallback_skill_id": "skill_manekin_attack"
##   }
##
## Note: fallback_skill_id is NOT applied to the actor — it lives on the
## BehaviorScenario JSON. We tolerate it in the enemy file for forward-compat
## but ignore it here.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ENEMIES_DIR := "res://data/enemies/"


## Reads data/enemies/<id>.json and writes max_hp / team / speed / behavior_id
## / skills onto the actor. Missing file → warn + return false (caller keeps
## scene defaults).
static func apply_to_actor(actor: Actor, enemy_id: StringName) -> bool:
	if enemy_id == &"":
		return false
	var path: String = ENEMIES_DIR + str(enemy_id) + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.warn("EnemyDataLoader", "missing enemy data: %s" % path)
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("EnemyDataLoader", "bad JSON: %s" % path)
		return false
	var data: Dictionary = parsed

	if data.has("max_hp"):
		actor.max_hp = int(data["max_hp"])
	if data.has("team"):
		actor.team = StringName(data["team"])
	if data.has("speed"):
		actor.speed = int(data["speed"])
	if data.has("behavior_id"):
		actor.behavior_id = StringName(data["behavior_id"])

	# Skills: list of skill_ids → resolve via SkillDatabase, attach via set_skills.
	# 034: clone_for_owner — each enemy gets its own Skill copy so cooldowns
	# don't leak between two instances of the same enemy type.
	var skill_ids: Variant = data.get("skills", [])
	if typeof(skill_ids) == TYPE_ARRAY:
		var skills: Array = []
		for sid_v in skill_ids:
			var sid: StringName = StringName(sid_v)
			var src: Skill = SkillDatabase.get_skill(sid)
			if src != null:
				skills.append(src.clone_for_owner())
			else:
				GameLogger.warn("EnemyDataLoader", "%s: unknown skill_id '%s' — skipped" % [enemy_id, sid])
		actor.set_skills(skills)

	return true
