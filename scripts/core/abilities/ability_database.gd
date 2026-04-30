extends Node
## AbilityDatabase — loads data/abilities/*.json into Ability resources at startup.
##
## Kind registries map JSON `"kind": "..."` to a Resource subclass. Adding a new
## target/effect/modifier kind = new GDScript file + one line in the registry.
##
## JSON format:
##   {
##     "id": "debug_punch",
##     "target": {"kind": "single_enemy"},
##     "effect": {"kind": "damage", "amount": 5},
##     "modifiers": []
##   }

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ABILITIES_DIR := "res://data/abilities/"

const TARGET_KINDS: Dictionary = {
	"single_enemy": preload("res://scripts/core/abilities/targets/single_enemy_target.gd"),
}

const EFFECT_KINDS: Dictionary = {
	"damage": preload("res://scripts/core/abilities/effects/damage_effect.gd"),
}

const MODIFIER_KINDS: Dictionary = {
	# empty on this PR; populated by 005-modifiers feature
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


# ── Internals ────────────────────────────────────────────────────────────────

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
	var ability := _build_ability(parsed)
	if ability != null:
		_by_id[ability.id] = ability


func _build_ability(data: Dictionary) -> Ability:
	var id: String = data.get("id", "")
	if id == "":
		GameLogger.warn("AbilityDatabase", "ability missing 'id'")
		return null

	var target := _make_target(data.get("target", {}))
	if target == null:
		GameLogger.warn("AbilityDatabase", "%s: bad target" % id)
		return null

	var effect := _make_effect(data.get("effect", {}))
	if effect == null:
		GameLogger.warn("AbilityDatabase", "%s: bad effect" % id)
		return null

	var modifiers: Array[AbilityModifier] = []
	for mod_data in data.get("modifiers", []):
		var m := _make_modifier(mod_data)
		if m != null:
			modifiers.append(m)

	var ability: Ability = ABILITY_SCRIPT.new()
	ability.id = StringName(id)
	ability.target = target
	ability.effect = effect
	ability.modifiers = modifiers
	return ability


func _make_target(data: Dictionary) -> AbilityTarget:
	var kind: String = data.get("kind", "")
	var script: Variant = TARGET_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown target kind: %s" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityTarget


func _make_effect(data: Dictionary) -> AbilityEffect:
	var kind: String = data.get("kind", "")
	var script: Variant = EFFECT_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown effect kind: %s" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityEffect


func _make_modifier(data: Dictionary) -> AbilityModifier:
	var kind: String = data.get("kind", "")
	var script: Variant = MODIFIER_KINDS.get(kind)
	if script == null:
		GameLogger.warn("AbilityDatabase", "unknown modifier kind: %s" % kind)
		return null
	var inst: Object = script.new()
	_apply_params(inst, data)
	return inst as AbilityModifier


## Apply JSON keys (other than "kind") to instance @export properties via set().
func _apply_params(inst: Object, data: Dictionary) -> void:
	for key in data.keys():
		if key == "kind":
			continue
		inst.set(key, data[key])
