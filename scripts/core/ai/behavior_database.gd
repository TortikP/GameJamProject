extends Node
## BehaviorDatabase — loads data/ai_behaviors/*.json into BehaviorScenario resources at startup.
## Mirrors SkillDatabase's pattern (autoload, _by_id dict).
##
## Validation per spec/008 AC-C9: nested composers (all_of inside all_of) are rejected
## at parse time and replaced with ConditionAlways + warn — runtime never sees invalid
## structure. See test #11.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const BEHAVIORS_DIR := "res://data/ai_behaviors/"

var _by_id: Dictionary = {}   # StringName -> BehaviorScenario


func _ready() -> void:
	_load_dir(BEHAVIORS_DIR)
	GameLogger.info("BehaviorDatabase", "loaded %d scenarios" % _by_id.size())


func get_scenario(id: StringName) -> BehaviorScenario:
	return _by_id.get(id, null) as BehaviorScenario


func has_scenario(id: StringName) -> bool:
	return _by_id.has(id)


func all_ids() -> Array:
	return _by_id.keys()


func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		GameLogger.warn("BehaviorDatabase", "dir not found: %s" % dir_path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			_load_file(dir_path + fname)
		fname = dir.get_next()
	dir.list_dir_end()


func _load_file(file_path: String) -> void:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		GameLogger.warn("BehaviorDatabase", "can't open: %s" % file_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("BehaviorDatabase", "bad JSON: %s" % file_path)
		return
	var scenario := _build_scenario(parsed)
	if scenario != null:
		_by_id[scenario.id] = scenario


func _build_scenario(data: Dictionary) -> BehaviorScenario:
	var sid: String = data.get("id", "")
	if sid == "":
		GameLogger.warn("BehaviorDatabase", "scenario missing 'id'")
		return null

	var scenario: BehaviorScenario = BehaviorScenario.new()
	scenario.id = StringName(sid)
	scenario.fallback_skill_id = StringName(data.get("fallback_skill_id", ""))

	var rules_raw: Variant = data.get("rules", [])
	if typeof(rules_raw) != TYPE_ARRAY or (rules_raw as Array).is_empty():
		GameLogger.warn("BehaviorDatabase", "%s: 'rules' must be non-empty array" % sid)
		return null
	for r_data in rules_raw:
		var rule := _build_rule(r_data, sid)
		if rule != null:
			scenario.rules.append(rule)

	if scenario.rules.is_empty():
		GameLogger.warn("BehaviorDatabase", "%s: no valid rules — skipping scenario" % sid)
		return null

	scenario.movement_policy = _build_policy(data.get("movement_policy", {}), sid)
	return scenario


func _build_rule(data: Variant, scenario_id: String) -> TacticRule:
	if typeof(data) != TYPE_DICTIONARY:
		GameLogger.warn("BehaviorDatabase", "%s: rule must be dictionary" % scenario_id)
		return null
	var rule: TacticRule = TacticRule.new()

	# Condition (top-level — composers allowed here ONLY).
	rule.condition = _build_condition(data.get("condition", {}), scenario_id, true)
	if rule.condition == null:
		rule.condition = ConditionAlways.new()

	# Target selector.
	rule.target_selector = _build_selector(data.get("target_selector", {}), scenario_id)
	if rule.target_selector == null:
		GameLogger.warn("BehaviorDatabase", "%s: rule has invalid target_selector — skipping" % scenario_id)
		return null

	# Tag priority.
	var tags_raw: Variant = data.get("tag_priority", [])
	if typeof(tags_raw) == TYPE_ARRAY:
		for t in tags_raw:
			rule.tag_priority.append(StringName(t))

	rule.min_skill_count = int(data.get("min_skill_count", 1))
	return rule


# composers_allowed=true at top level of rule.condition; false inside composer children
# (AC-C9: 1 level only).
func _build_condition(data: Variant, scenario_id: String, composers_allowed: bool) -> TacticCondition:
	if typeof(data) != TYPE_DICTIONARY:
		GameLogger.warn("BehaviorDatabase", "%s: condition must be dictionary — using always" % scenario_id)
		return ConditionAlways.new()
	var kind: String = data.get("kind", "")
	match kind:
		"always":
			return ConditionAlways.new()
		"self_hp_below":
			var c1 := ConditionSelfHpBelow.new()
			c1.pct = int(data.get("pct", 50))
			return c1
		"self_hp_above":
			var c2 := ConditionSelfHpAbove.new()
			c2.pct = int(data.get("pct", 50))
			return c2
		"enemy_in_range":
			var c3 := ConditionEnemyInRange.new()
			c3.distance = int(data.get("distance", 1))
			return c3
		"no_enemy_in_range":
			var c4 := ConditionNoEnemyInRange.new()
			c4.distance = int(data.get("distance", 1))
			return c4
		"enemy_count_in_range":
			var c5 := ConditionEnemyCountInRange.new()
			c5.distance = int(data.get("distance", 3))
			c5.min_count = int(data.get("min_count", 2))
			return c5
		"ally_hp_below":
			var c6 := ConditionAllyHpBelow.new()
			c6.pct = int(data.get("pct", 50))
			c6.distance = int(data.get("distance", 3))
			return c6
		"skill_ready":
			var c7 := ConditionSkillReady.new()
			c7.skill_id = StringName(data.get("skill_id", ""))
			return c7
		"all_of", "any_of":
			if not composers_allowed:
				GameLogger.warn("BehaviorDatabase", "%s: nested composer '%s' rejected (AC-C9) — using always" % [scenario_id, kind])
				return ConditionAlways.new()
			var children_raw: Variant = data.get("children", [])
			if typeof(children_raw) != TYPE_ARRAY:
				GameLogger.warn("BehaviorDatabase", "%s: %s.children must be array — using always" % [scenario_id, kind])
				return ConditionAlways.new()
			var built_children: Array[TacticCondition] = []
			for child_data in children_raw:
				# Inner level: composers_allowed=false. Nested composers replaced with always + warn.
				var child := _build_condition(child_data, scenario_id, false)
				if child != null:
					built_children.append(child)
			if kind == "all_of":
				var c_all := ConditionAllOf.new()
				c_all.children = built_children
				return c_all
			else:
				var c_any := ConditionAnyOf.new()
				c_any.children = built_children
				return c_any
		"not_of":
			if not composers_allowed:
				GameLogger.warn("BehaviorDatabase", "%s: nested 'not_of' rejected — using always" % scenario_id)
				return ConditionAlways.new()
			var n := ConditionNotOf.new()
			n.child = _build_condition(data.get("child", {}), scenario_id, false)
			return n
		_:
			GameLogger.warn("BehaviorDatabase", "%s: unknown condition kind '%s' — using always" % [scenario_id, kind])
			return ConditionAlways.new()


func _build_selector(data: Variant, scenario_id: String) -> TargetSelector:
	if typeof(data) != TYPE_DICTIONARY:
		GameLogger.warn("BehaviorDatabase", "%s: target_selector must be dictionary" % scenario_id)
		return null
	var kind: String = data.get("kind", "")
	match kind:
		"nearest_enemy":      return SelectorNearestEnemy.new()
		"lowest_hp_enemy":    return SelectorLowestHpEnemy.new()
		"highest_hp_enemy":   return SelectorHighestHpEnemy.new()
		"self":               return SelectorSelf.new()
		"lowest_hp_ally":     return SelectorLowestHpAlly.new()
		"densest_enemy_hex":  return SelectorDensestEnemyHex.new()
		"random_enemy":       return SelectorRandomEnemy.new()
		"specific_actor":     return SelectorSpecificActor.new()   # 027: feared/enraged
		_:
			GameLogger.warn("BehaviorDatabase", "%s: unknown target_selector kind '%s'" % [scenario_id, kind])
			return null


func _build_policy(data: Variant, scenario_id: String) -> MovementPolicy:
	if typeof(data) != TYPE_DICTIONARY:
		GameLogger.warn("BehaviorDatabase", "%s: movement_policy invalid — using hold_position" % scenario_id)
		return PolicyHoldPosition.new()
	var kind: String = data.get("kind", "")
	match kind:
		"approach_nearest_enemy":   return PolicyApproachNearestEnemy.new()
		"kite_from_nearest_enemy":  return PolicyKiteFromNearestEnemy.new()
		"hold_position":            return PolicyHoldPosition.new()
		"follow_lowest_hp_ally":    return PolicyFollowLowestHpAlly.new()
		"approach_specific_actor":  return PolicyApproachSpecificActor.new()   # 027: enraged
		"kite_specific_actor":      return PolicyKiteSpecificActor.new()       # 027: feared
		_:
			GameLogger.warn("BehaviorDatabase", "%s: unknown movement_policy kind '%s' — using hold_position" % [scenario_id, kind])
			return PolicyHoldPosition.new()
