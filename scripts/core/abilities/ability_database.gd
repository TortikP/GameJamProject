extends Node
## AbilityDatabase — loads data/abilities/*.json into Ability resources at startup.
##
## 007-skill-system: new registries for target/area/effect/modifier kinds.
## JSON format (new — see 007-skill-system/plan.md):
##   {
##     "id": "fireball",
##     "target": {"kind": "hex"},
##     "area":   {"kind": "zone_circle", "radius": 2},
##     "effects": [
##       {"kind": "damage", "id": "fb_dmg", "duration": 0, "damage": 15},
##       {"kind": "status", "id": "fb_burn", "duration": 3, "status": "burning"}
##     ],
##     "modifiers": [
##       {"kind": "parameter", "id": "fb_extra", "target_param": "damage", "op": "add", "value": 5}
##     ]
##   }

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ABILITIES_DIR := "res://data/abilities/"

const TARGET_KINDS: Dictionary = {
	"self":      preload("res://scripts/core/abilities/targets/self_target.gd"),
	"entity":    preload("res://scripts/core/abilities/targets/entity_target.gd"),
	"hex":       preload("res://scripts/core/abilities/targets/hex_target.gd"),
	"direction": preload("res://scripts/core/abilities/targets/direction_target.gd"),
	"object":    preload("res://scripts/core/abilities/targets/object_target.gd"),
}

const AREA_KINDS: Dictionary = {
	"self":        preload("res://scripts/core/abilities/areas/self_area.gd"),
	"chain":       preload("res://scripts/core/abilities/areas/chain_area.gd"),
	"zone_circle": preload("res://scripts/core/abilities/areas/zone_circle_area.gd"),
	"zone_line":   preload("res://scripts/core/abilities/areas/zone_line_area.gd"),
	"zone_cone":   preload("res://scripts/core/abilities/areas/zone_cone_area.gd"),
	"zone_arc":    preload("res://scripts/core/abilities/areas/zone_arc_area.gd"),
}

const EFFECT_KINDS: Dictionary = {
	"damage": preload("res://scripts/core/abilities/effects/damage_effect.gd"),
	"heal":   preload("res://scripts/core/abilities/effects/heal_effect.gd"),
	"status": preload("res://scripts/core/abilities/effects/status_effect.gd"),
	"move":   preload("res://scripts/core/abilities/effects/move_effect.gd"),
	"create": preload("res://scripts/core/abilities/effects/create_effect.gd"),
}

const MODIFIER_KINDS: Dictionary = {
	"parameter": preload("res://scripts/core/abilities/parameter_modifier.gd"),
}

const ABILITY_SCRIPT := preload("res://scripts/core/abilities/ability.gd")

var _by_id: Dictionary = {}  # StringName -> Ability


func _ready() -> void:
	_load_dir(ABILITIES_DIR)
	GameLogger.info("AbilityDatabase", "loaded %d abilities" % _by_id.size())


func get_ability(id: StringName) -> Ability:
	return _by_id.get(id, null) as Ability


func has_ability(id: StringName) -> bool:
	return _by_id.has(id)


func all_ids() -> Array:
	return _by_id.keys()


# ── Internals ─────────────────────────────────────────────────────────────────

func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		GameLogger.warn("AbilityDatabase", "dir not found: %s" % path)
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
		GameLogger.warn("AbilityDatabase", "cannot open %s" % file_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("AbilityDatabase", "bad JSON: %s" % file_path)
		return
	var ability := _build_ability_from_dict(parsed)
	if ability != null:
		_by_id[ability.id] = ability


## Public — also used by SkillDatabase to parse abilities embedded in skill JSON.
func _build_ability_from_dict(data: Dictionary) -> Ability:
	var id: String = data.get("id", "")
	if id == "":
		GameLogger.warn("AbilityDatabase", "ability missing 'id'")
		return null

	var tgt := _make_target(data.get("target", {}))
	if tgt == null:
		GameLogger.warn("AbilityDatabase", "%s: bad target" % id)
		return null

	var area := _make_area(data.get("area", {}))
	if area == null:
		GameLogger.warn("AbilityDatabase", "%s: bad area" % id)
		return null

	var effects: Array[AbilityEffect] = []
	for eff_data in data.get("effects", []):
		var e := _make_effect(eff_data)
		if e != null:
			effects.append(e)
	if effects.is_empty():
		GameLogger.warn("AbilityDatabase", "%s: no valid effects" % id)
		return null

	var mods: Array[ParameterModifier] = []
	for mod_data in data.get("modifiers", []):
		var m := _make_modifier(mod_data)
		if m != null:
			mods.append(m)

	var ability: Ability = ABILITY_SCRIPT.new()
	ability.id = StringName(id)
	ability.target = tgt
	ability.area = area
	ability.effects = effects
	ability.modifiers = mods
	return ability


func _make_target(data: Dictionary) -> AbilityTarget:
	var kind: String = data.get("kind", "")
	var script: Variant = TARGET_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown target kind: '%s'" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityTarget


func _make_area(data: Dictionary) -> AbilityArea:
	var kind: String = data.get("kind", "")
	var script: Variant = AREA_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown area kind: '%s'" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityArea


func _make_effect(data: Dictionary) -> AbilityEffect:
	var kind: String = data.get("kind", "")
	var script: Variant = EFFECT_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown effect kind: '%s'" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityEffect


func _make_modifier(data: Dictionary) -> ParameterModifier:
	var kind: String = data.get("kind", "")
	var script: Variant = MODIFIER_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown modifier kind: '%s'" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as ParameterModifier


## Apply JSON keys (except "kind") to instance @export properties via set().
func _apply_params(inst: Object, data: Dictionary) -> void:
	for key in data.keys():
		if key == "kind":
			continue
		inst.set(key, data[key])
