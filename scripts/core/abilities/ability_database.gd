extends Node
## AbilityDatabase — loads data/abilities/*.json into Ability resources at startup.
##
## 021-skill-system-v2: target kind "entity" → "actor"; ability gets sound/animation
## fields (stored, not dispatched yet).
##
## 026-skill-system-v3:
##   - Ability: `sound` → `sound_start`; new `sound_end`, `collision_effect`.
##   - Effects: `kind` discriminator removed. Effect class is inferred from
##     key presence (`damage` → DamageEffect, `heal` → HealEffect, `status` →
##     StatusEffect, `move_type` → MoveEffect, `entity_id` → CreateEffect).
##     One JSON dict can carry multiple effect-keys → parser fans out into
##     N typed AbilityEffect instances in registry-order:
##       damage → heal → status → move → create.
##     Common fields (`duration`, `requires_alive_target`) are broadcast to all
##     instances via Object.set() (silent no-op on non-matching properties).
##   - Areas: JSON keys `radius` / `max_chain_length` on `chain` & `zone_circle`
##     are renamed to `area_radius` / `area_max_chain_length`. Script field
##     names stay the same — remap lives in `_make_area`.
##
## JSON format (026):
##   {
##     "id": "fireball",
##     "sound_start": "snd_fire_start",
##     "sound_end":   "snd_fire_hit",
##     "collision_effect": "vfx_fire_burst",
##     "animation": "anim_blast",
##     "target": {"kind": "hex", "range": 4},
##     "area":   {"kind": "zone_circle", "area_radius": 2},
##     "effects": [
##       {"duration": 0, "damage": 15, "status": "burning"}
##     ],
##     "modifiers": [
##       {"kind": "parameter", "id": "fb_extra", "target_param": "damage", "op": "add", "value": 5}
##     ]
##   }

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const ABILITIES_DIR := "res://data/abilities/"

const TARGET_KINDS: Dictionary = {
	"self":      preload("res://scripts/core/abilities/targets/self_target.gd"),
	"actor":     preload("res://scripts/core/abilities/targets/actor_target.gd"),
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

# 026: JSON-key remap for area-blocks. Script field names stay the same
# (no touch to chain_area.gd / zone_circle_area.gd) — only the JSON key
# is renamed at parse time. Reason: the `area_` prefix in JSON is grep-
# friendly when scanning content, but inside the gd files the prefix
# would be redundant (they already live in *_area.gd).
const AREA_KEY_REMAP: Dictionary = {
	"chain": {
		"area_max_chain_length": "max_chain_length",
		"area_radius":            "radius",
	},
	"zone_circle": {
		"area_radius": "radius",
	},
}

const EFFECT_KIND_BY_KEY: Dictionary = {
	"damage":    preload("res://scripts/core/abilities/effects/damage_effect.gd"),
	"heal":      preload("res://scripts/core/abilities/effects/heal_effect.gd"),
	"status":    preload("res://scripts/core/abilities/effects/status_effect.gd"),
	"move_type": preload("res://scripts/core/abilities/effects/move_effect.gd"),
	"entity_id": preload("res://scripts/core/abilities/effects/create_effect.gd"),
}

# 026: deterministic fan-out order when an effect dict carries multiple keys.
# Decision is provisional — see 026 spec §"Open after playtest" (1).
# Keys are plain String to match JSON.parse_string output (Dictionary won't
# auto-convert String↔StringName for lookups).
const EFFECT_KEY_ORDER: Array[String] = ["damage", "heal", "status", "move_type", "entity_id"]

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


## Called by SkillDatabase to register abilities embedded in skills,
## so move_range_overlay / actor_inspector can look them up by ID.
func register_ability(ability: Ability) -> void:
	if ability == null or ability.id == &"":
		return
	_by_id[ability.id] = ability


func has_ability(id: StringName) -> bool:
	return _by_id.has(id)


func all_ids() -> Array:
	return _by_id.keys()


# ── Internals ─────────────────────────────────────────────────────────────────

func _load_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		GameLogger.info("AbilityDatabase", "no standalone files in %s (abilities live in skills)" % path)
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
	var ability := build_ability_from_dict(parsed)
	if ability != null:
		_by_id[ability.id] = ability


## Public — also used by SkillDatabase to parse abilities embedded in skill JSON.
func build_ability_from_dict(data: Dictionary) -> Ability:
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
		# 026: one JSON dict → N typed effects in registry-order.
		for e in _make_effects_from_dict(eff_data, id):
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
	# 021/026: presentation hooks. Stored on resource, dispatch in future
	# audio/anim/VFX systems. 026 split sound → sound_start + sound_end and
	# added collision_effect (impact VFX, distinct from animation = caster pose).
	ability.sound_start      = StringName(data.get("sound_start", ""))
	ability.sound_end        = StringName(data.get("sound_end", ""))
	ability.collision_effect = StringName(data.get("collision_effect", ""))
	ability.animation        = StringName(data.get("animation", ""))
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
	# 026: per-kind JSON→script key remap (e.g. `area_radius` → `radius`).
	# Unknown JSON keys pass through unchanged.
	var remap: Dictionary = AREA_KEY_REMAP.get(kind, {})
	for key in data.keys():
		if key == "kind":
			continue
		var script_key: String = remap.get(key, key)
		inst.set(script_key, data[key])
	return inst as AbilityArea


func _make_effects_from_dict(data: Dictionary, ability_id: String) -> Array[AbilityEffect]:
	# 026: discriminator is key-presence, not a `kind` field. Fan out into
	# one typed AbilityEffect per recognised key, in EFFECT_KEY_ORDER.
	if data.has("kind"):
		GameLogger.warn("AbilityDatabase", "%s: legacy 'kind' key in effect dict — ignoring (026 schema)" % ability_id)
	var out: Array[AbilityEffect] = []
	for key in EFFECT_KEY_ORDER:
		if not data.has(key):
			continue
		# Defensive type pattern (CLAUDE.md trap #6): Variant→Object→cast.
		var script_v: Variant = EFFECT_KIND_BY_KEY[key]
		var inst: Object = (script_v as GDScript).new()
		# Broadcast all keys via Object.set(): non-matching properties no-op,
		# so DamageEffect picks up `damage`+`duration`, MoveEffect picks up
		# `move_type`+`move_distance`+`duration`, etc.
		for k in data.keys():
			if k == "kind":
				continue
			inst.set(k, data[k])
		var eff := inst as AbilityEffect
		if eff != null:
			out.append(eff)
	if out.is_empty():
		GameLogger.info("AbilityDatabase", "%s: effect dict has no recognised keys — skipping" % ability_id)
	return out


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
