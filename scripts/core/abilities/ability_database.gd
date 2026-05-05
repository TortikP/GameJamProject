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
##       {"damage": 15, "status_id": "burning(3)"}
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
	"status_id": preload("res://scripts/core/abilities/effects/status_effect.gd"),
	"move_type": preload("res://scripts/core/abilities/effects/move_effect.gd"),
	"entity_id": preload("res://scripts/core/abilities/effects/create_effect.gd"),
}

# 026: deterministic fan-out order when an effect dict carries multiple keys.
# Decision is provisional — see 026 spec §"Open after playtest" (1).
# Keys are plain String to match JSON.parse_string output (Dictionary won't
# auto-convert String↔StringName for lookups).
# 031 phase 9: status → status_id rename to align with shipping skill JSON
# (data/skills/honey_cold.json etc. use "status_id"). Old "status" key now
# silently ignored — see _parse_effect_dict warning below.
const EFFECT_KEY_ORDER: Array[String] = ["damage", "heal", "status_id", "move_type", "entity_id"]

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
	# 027: `status` value is a string `"id(d, a1, a2, ...)"` parsed inline;
	# `duration` at effect-object level is legacy (was on AbilityEffect base) —
	# soft-shim with info log.
	if data.has("kind"):
		GameLogger.warn("AbilityDatabase", "%s: legacy 'kind' key in effect dict — ignoring (026 schema)" % ability_id)
	if data.has("duration"):
		GameLogger.info("AbilityDatabase", "%s: legacy 'duration' key in effect dict — ignoring (027 schema; duration lives in status string)" % ability_id)
	if data.has("status"):
		# 031 phase 9: key renamed to "status_id" to match shipping skill JSON.
		# Old key silently dropped status effects without warning — surface it.
		GameLogger.warn("AbilityDatabase", "%s: legacy 'status' key in effect dict — rename to 'status_id' (031 phase 9)" % ability_id)
	var out: Array[AbilityEffect] = []
	for key in EFFECT_KEY_ORDER:
		if not data.has(key):
			continue
		if key == "status_id":
			# 027/031: special parser for "id(args)" inline encoding.
			# 034: value may be a semicolon-separated list —
			# "rooted(2); slowed(3)" applies both statuses from one effect.
			# Single-status legacy "burning(2, 3, 1)" is unaffected (no
			# semicolon → split returns 1 element).
			out.append_array(_make_status_effects(data[key], ability_id))
			continue
		if key == "entity_id":
			# 041: status-style "id(duration)" encoding. arity=1, args=[duration].
			# duration > 0 — N turns; duration = -1 — infinite. duration = 0 — invalid.
			# Bare "id" without parens — invalid (legacy 026 format dropped).
			var ce: CreateEffect = _make_create_effect(data[key], ability_id)
			if ce != null:
				out.append(ce)
			continue
		# Defensive type pattern (CLAUDE.md trap #6): Variant→Object→cast.
		var script_v: Variant = EFFECT_KIND_BY_KEY[key]
		var inst: Object = (script_v as GDScript).new()
		# Broadcast all keys via Object.set(): non-matching properties no-op,
		# so DamageEffect picks up `damage`, MoveEffect picks up
		# `move_type`+`move_distance`, etc. `duration` and `status_id` are
		# skipped explicitly (status_id is handled above; duration is gone).
		# 041: `entity_id` skipped too — handled by dedicated branch above.
		for k in data.keys():
			if k == "kind" or k == "status" or k == "status_id" or k == "duration" or k == "entity_id":
				continue
			inst.set(k, data[k])
		var eff := inst as AbilityEffect
		if eff != null:
			out.append(eff)
	if out.is_empty():
		GameLogger.info("AbilityDatabase", "%s: effect dict has no recognised keys — skipping" % ability_id)
	return out


# 027: parse `"id(d, a1, a2, ...)"` into a StatusEffect.
# 034: extended to accept multiple statuses separated by semicolons:
#   "rooted(2); slowed(3)"  → [StatusEffect(rooted), StatusEffect(slowed)]
#   "burning(2, 3, 1)"      → [StatusEffect(burning)]   (legacy single)
# Semicolon (not comma) so the separator never collides with status args
# like "burning(2, 3, 1)". Whitespace around the semicolon is tolerated.
# Returns Array — empty on malformed input. Each bad part logs a warn
# and is dropped; the others survive.
func _make_status_effects(value: Variant, ability_id: String) -> Array[StatusEffect]:
	var out: Array[StatusEffect] = []
	if not (value is String):
		GameLogger.warn("AbilityDatabase", "%s: status value must be string, got %s" % [ability_id, type_string(typeof(value))])
		return out
	for part in (value as String).split(";"):
		var trimmed: String = part.strip_edges()
		if trimmed.is_empty():
			continue
		var eff: StatusEffect = _build_one_status_effect(trimmed, ability_id)
		if eff != null:
			out.append(eff)
	return out


func _build_one_status_effect(s: String, ability_id: String) -> StatusEffect:
	var parsed: Dictionary = _parse_status_string(s)
	if parsed.is_empty():
		GameLogger.warn("AbilityDatabase", "%s: malformed status string '%s' (expected 'id(n0, n1, ...)')" % [ability_id, s])
		return null
	var id: StringName = parsed["id"]
	var args: Array[int] = parsed["args"]
	# Arity check via StatusRegistry (returns 0 for unknown id, which we treat as reject).
	var expected: int = StatusRegistry.arity_of(id)
	if expected == 0:
		GameLogger.warn("AbilityDatabase", "%s: unknown status_id '%s'" % [ability_id, id])
		return null
	if args.size() != expected:
		GameLogger.warn("AbilityDatabase", "%s: status '%s' arity mismatch — expected %d args, got %d" % [ability_id, id, expected, args.size()])
		return null
	var eff := StatusEffect.new()
	eff.status_id = id
	eff.args = args
	return eff


# 041: parse `"id(duration)"` into a CreateEffect. Same grammar as status,
# but arity=1 strictly, args=[duration]. duration > 0 — N turns; duration = -1 —
# infinite (Actor.tick_statuses_with_ctx skips decrement when duration < 0).
# duration = 0 invalid. Bare "id" without parens — invalid (no shim from 026).
# Returns null on any malformed input; caller continues, skill loads without
# this create-effect.
func _make_create_effect(value: Variant, ability_id: String) -> CreateEffect:
	if not (value is String):
		GameLogger.warn("AbilityDatabase", "%s: entity_id must be string, got %s" % [ability_id, type_string(typeof(value))])
		return null
	var parsed: Dictionary = _parse_status_string(value as String)
	if parsed.is_empty():
		GameLogger.warn("AbilityDatabase", "%s: malformed entity_id '%s' (expected 'id(duration)')" % [ability_id, value])
		return null
	var args: Array[int] = parsed["args"]
	if args.size() != 1:
		GameLogger.warn("AbilityDatabase", "%s: entity_id arity mismatch — expected 1 (duration), got %d" % [ability_id, args.size()])
		return null
	var dur: int = args[0]
	if dur == 0:
		GameLogger.warn("AbilityDatabase", "%s: entity_id duration=0 invalid — skipping" % ability_id)
		return null
	var ce := CreateEffect.new()
	ce.entity_id = parsed["id"]
	ce.duration = dur
	return ce


# Strict parser for the inline encoding. Returns {} on any malformed input.
# Whitespace around commas and inside parens is tolerated.
#   "burning(2, 3, 1)" → {id: &"burning", args: [2, 3, 1]}
#   "stunned(2)"       → {id: &"stunned", args: [2]}
#   "feared()"         → {} (need at least duration)
func _parse_status_string(s: String) -> Dictionary:
	var open: int = s.find("(")
	var close: int = s.rfind(")")
	if open <= 0 or close < 0 or close <= open:
		return {}
	var id_str: String = s.substr(0, open).strip_edges()
	if id_str.is_empty():
		return {}
	var argstr: String = s.substr(open + 1, close - open - 1).strip_edges()
	var args: Array[int] = []
	if argstr != "":
		for piece in argstr.split(","):
			var trimmed: String = piece.strip_edges()
			if not trimmed.is_valid_int():
				return {}
			args.append(trimmed.to_int())
	if args.is_empty():
		return {}
	return {"id": StringName(id_str), "args": args}


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
