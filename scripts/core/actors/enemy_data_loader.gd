extends Object
## EnemyDataLoader — reads data/enemies/<id>.json and applies fields to an Actor.
##
## Static-only helper, no instance state. Called from enemy_view._ready (and any
## future enemy view that wants data-driven config).
##
## JSON schema:
##   {
##     "id": "manekin",
##     "sprite": "assets/sprites/enemies/manekin.png",
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
## / skills onto the actor. Returns a Dictionary of view hints for the caller
## (presentation layer) — keeps Actor itself free of presentation-only fields
## per CLAUDE.md hard rule #1.
##
## Returned dict (empty on failure):
##   "sprite": String  — res://-prefixed path to the body texture, if JSON
##                       declared one. View resolves Sprite2D and applies.
##
## Missing file / bad JSON → warn + return empty dict. Caller checks emptiness
## and keeps scene defaults (enemy_view does max_hp <= 0 fallback).
static func apply_to_actor(actor: Actor, enemy_id: StringName) -> Dictionary:
	var hints: Dictionary = {}
	if enemy_id == &"":
		return hints
	var path: String = ENEMIES_DIR + str(enemy_id) + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		GameLogger.warn("EnemyDataLoader", "missing enemy data: %s" % path)
		return hints
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("EnemyDataLoader", "bad JSON: %s" % path)
		return hints
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

	# View hints — sprite path. JSON stores repo-relative ("assets/sprites/..."),
	# we prefix res:// once here so callers can pass straight to load().
	if data.has("sprite"):
		var sprite_rel: String = String(data["sprite"])
		if sprite_rel != "":
			hints["sprite"] = "res://" + sprite_rel

	return hints


## Spec 050 rev3: lightweight reader for just the sprite path. Used by
## SpawnerPlaceholder which previews an enemy without instantiating it as
## an Actor — apply_to_actor would be overkill (parses skills, behaviors,
## etc just to get one string). Returns res://-prefixed path, or "" if the
## file/field is missing/malformed.
static func get_sprite_path(enemy_id: StringName) -> String:
	if enemy_id == &"":
		return ""
	var path: String = ENEMIES_DIR + str(enemy_id) + ".json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var data: Dictionary = parsed
	var sprite_rel: String = String(data.get("sprite", ""))
	if sprite_rel == "":
		return ""
	return "res://" + sprite_rel
