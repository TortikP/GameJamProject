extends Node
## SkillDatabase — loads data/skills/*.json into Skill resources at startup.
##
## Uses AbilityDatabase's internal ability parser (reused via shared helper).
## JSON format mirrors the skill schema in 007-skill-system/plan.md.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const SKILLS_DIR := "res://data/skills/"
const SKILL_SCRIPT := preload("res://scripts/core/skills/skill.gd")

# 038: canonical mood vocabulary. Chimera intentionally excluded — meta-only,
# returned by MoodTracker.get_dominant on a tie, never attached to a Skill.
# Local copy (not MoodTracker.MOODS_SKILL ref) to avoid cross-autoload load
# order dependency at SkillDatabase._ready time.
const _VALID_MOODS: Array[StringName] = [&"neutral", &"tranquility", &"burnout", &"ascended"]

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
	skill.type = StringName(str(data.get("type", "active")))
	skill.cooldown = int(data.get("cooldown", 0))

	# 021: localization keys (raw strings; resolution out of scope).
	skill.name = String(data.get("name", ""))
	skill.tooltip = String(data.get("tooltip", ""))
	skill.desc = String(data.get("desc", ""))

	# 026: icon — id for future IconDB (storage only, no dispatch).
	skill.icon = StringName(data.get("icon", ""))

	# 021: skill level. Default 0 → no scaling (identity).
	skill.level = int(data.get("level", 0))

	# 021: behaviour_tags (renamed from `tags`). AI strategy reads these.
	var btags_raw: Variant = data.get("behaviour_tags", [])
	if typeof(btags_raw) != TYPE_ARRAY:
		GameLogger.warn("SkillDatabase", "%s: 'behaviour_tags' must be array, got %s — using []" % [sid, type_string(typeof(btags_raw))])
		btags_raw = []
	for t in btags_raw:
		skill.behaviour_tags.append(StringName(t))

	# 021: mood — narrative archetype tags. Reserved.
	# 038: validated against _VALID_MOODS canon; unknowns warn but still parse.
	var mood_raw: Variant = data.get("mood", [])
	if typeof(mood_raw) != TYPE_ARRAY:
		GameLogger.warn("SkillDatabase", "%s: 'mood' must be array, got %s — using []" % [sid, type_string(typeof(mood_raw))])
		mood_raw = []
	for m in mood_raw:
		var m_sn: StringName = StringName(m)
		if not _VALID_MOODS.has(m_sn):
			GameLogger.warn("SkillDatabase", "%s: unknown mood '%s' (canon: %s)" % [sid, m_sn, _VALID_MOODS])
		skill.mood.append(m_sn)

	for ab_data in data.get("abilities", []):
		var ab: Ability = AbilityDatabase.build_ability_from_dict(ab_data)
		if ab != null:
			skill.abilities.append(ab)
			AbilityDatabase.register_ability(ab)  # visible to overlay / inspector

	if skill.type != &"passive" and skill.abilities.is_empty():
		GameLogger.warn("SkillDatabase", "%s: no valid abilities — skipping skill" % sid)
		return null

	var passive_raw: Variant = data.get("passive_effects", [])
	if typeof(passive_raw) != TYPE_ARRAY:
		GameLogger.warn("SkillDatabase", "%s: 'passive_effects' must be array, got %s — using []" % [sid, type_string(typeof(passive_raw))])
		passive_raw = []
	for eff_v in passive_raw:
		if eff_v is Dictionary:
			skill.passive_effects.append((eff_v as Dictionary).duplicate(true))
		else:
			GameLogger.warn("SkillDatabase", "%s: passive effect must be dict, got %s — skipped" % [sid, type_string(typeof(eff_v))])

	if skill.type == &"passive" and skill.passive_effects.is_empty():
		GameLogger.warn("SkillDatabase", "%s: passive skill has no valid passive_effects — skipping skill" % sid)
		return null

	return skill
