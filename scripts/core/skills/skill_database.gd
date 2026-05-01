extends Node
## SkillDatabase — loads data/skills/*.json into Skill resources at startup.
##
## Uses AbilityDatabase's internal ability parser (reused via shared helper).
## JSON format mirrors the skill schema in 007-skill-system/plan.md.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SKILLS_DIR := "res://data/skills/"
const SKILL_SCRIPT := preload("res://scripts/core/skills/skill.gd")

var _by_id: Dictionary = {}   # StringName -> Skill


func _ready() -> void:
	_load_dir(SKILLS_DIR)
	GameLogger.info("SkillDatabase", "loaded %d skills" % _by_id.size())


func get_skill(id: StringName) -> Skill:
	return _by_id.get(id, null) as Skill


func has_skill(id: StringName) -> bool:
	return _by_id.has(id)


func all_ids() -> Array:
	return _by_id.keys()


# ── Internals ────────────────────────────────────────────────────────────────

func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		GameLogger.info("SkillDatabase", "dir not found or empty: %s" % path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			_load_file(path + fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _load_file(file_path: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		GameLogger.warn("SkillDatabase", "cannot open %s" % file_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("SkillDatabase", "bad JSON: %s" % file_path)
		return
	var skill := _build_skill(parsed)
	if skill != null:
		_by_id[skill.id] = skill


func _build_skill(data: Dictionary) -> Skill:
	var sid: String = data.get("id", "")
	if sid == "":
		GameLogger.warn("SkillDatabase", "skill missing 'id'")
		return null

	var skill: Skill = SKILL_SCRIPT.new()
	skill.id = StringName(sid)
	skill.cooldown = int(data.get("cooldown", 0))

	for ab_data in data.get("abilities", []):
		var ab: Ability = AbilityDatabase._build_ability_from_dict(ab_data)
		if ab != null:
			skill.abilities.append(ab)

	if skill.abilities.is_empty():
		GameLogger.warn("SkillDatabase", "%s: no valid abilities — skipping skill" % sid)
		return null

	return skill
