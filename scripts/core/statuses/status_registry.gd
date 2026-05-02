extends Node
## StatusRegistry — autoload. Two responsibilities:
##
##   1. Dispatch table: status_id → runtime GDScript class (preload table).
##      Runtime classes hold the *behaviour* (compute_snapshot, on_turn_start,
##      modify_speed, …); methods are static, no instances created.
##
##   2. Designer-tunable metadata: family (UI pill colour), arity (parser
##      validation), param_names (warn message clarity), loc keys (future
##      localisation). Loaded from data/status_effects/<id>.json at boot.
##
## Why two layers: behaviour is code (lots of moving parts, requires
## programmer); metadata is data (Stasyan can tune pill colour or rename
## a status without touching .gd files).
##
## Autoload order: MUST be before AbilityDatabase / SkillDatabase, since
## the parser calls arity_of() at skill-load time. See project.godot.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")
const STATUSES_DIR := "res://data/status_effects/"

# Preload table — id → runtime GDScript class. Adding a status: row here +
# create runtime class + create JSON metadata file.
const _RT_BY_ID: Dictionary = {
	&"stunned":  preload("res://scripts/core/statuses/runtimes/stunned_runtime.gd"),
	&"slowed":   preload("res://scripts/core/statuses/runtimes/slowed_runtime.gd"),
	&"poisoned": preload("res://scripts/core/statuses/runtimes/poisoned_runtime.gd"),
	&"rooted":   preload("res://scripts/core/statuses/runtimes/rooted_runtime.gd"),
	&"feared":   preload("res://scripts/core/statuses/runtimes/feared_runtime.gd"),
	&"burning":  preload("res://scripts/core/statuses/runtimes/burning_runtime.gd"),
	&"glitched": preload("res://scripts/core/statuses/runtimes/glitched_runtime.gd"),
	&"shielded": preload("res://scripts/core/statuses/runtimes/shielded_runtime.gd"),
	&"enraged":  preload("res://scripts/core/statuses/runtimes/enraged_runtime.gd"),
	&"strong":   preload("res://scripts/core/statuses/runtimes/strong_runtime.gd"),
	&"weak":     preload("res://scripts/core/statuses/runtimes/weak_runtime.gd"),
}

# id → {family, arity, param_names, loc_name, loc_desc}
var _meta: Dictionary = {}


func _ready() -> void:
	_load_dir(STATUSES_DIR)
	# Cross-check: every runtime should have metadata, and every metadata
	# file should reference a runtime. Soft warn — game still boots if
	# only one side is present.
	for id in _RT_BY_ID.keys():
		if not _meta.has(id):
			GameLogger.warn("StatusRegistry", "no metadata for runtime '%s' — JSON missing in %s" % [id, STATUSES_DIR])
	for id in _meta.keys():
		if not _RT_BY_ID.has(id):
			GameLogger.warn("StatusRegistry", "no runtime class for metadata '%s'" % id)
	GameLogger.info("StatusRegistry", "loaded %d statuses (runtimes: %d, metadata: %d)" % [_RT_BY_ID.size(), _RT_BY_ID.size(), _meta.size()])


## Returns the runtime GDScript class object, or null if unknown.
## Callers invoke static methods on it: rt.on_turn_start(actor, inst, ctx).
## Typed as GDScript (not Variant) so static dispatch works deterministically.
func runtime_for(id: StringName) -> GDScript:
	return _RT_BY_ID.get(id, null) as GDScript


func has_status(id: StringName) -> bool:
	return _RT_BY_ID.has(id)


func meta_for(id: StringName) -> Dictionary:
	return _meta.get(id, {}) as Dictionary


func family_of(id: StringName) -> StringName:
	var m: Dictionary = _meta.get(id, {})
	return StringName(m.get("family", &"debuff"))


## Returns the icon resource path for the status (e.g. "res://assets/icons/status/poisoned.png"),
## or empty string if no icon is configured. UI falls back to family-glyph
## when icon is empty.
func icon_of(id: StringName) -> String:
	var m: Dictionary = _meta.get(id, {})
	return String(m.get("icon", ""))


## Path to the status icon texture (e.g. "res://assets/icons/burning.png").
## Empty if not configured — UI falls back to family-glyph.
func icon_of(id: StringName) -> String:
	var m: Dictionary = _meta.get(id, {})
	return String(m.get("icon", ""))


## Number of expected args in the inline encoding `id(d, a1, ...)`.
## Returns 0 for unknown ids — parser uses 0 as the "reject" signal.
func arity_of(id: StringName) -> int:
	if not _meta.has(id):
		return 0
	return int((_meta[id] as Dictionary).get("arity", 1))


func all_ids() -> Array:
	return _RT_BY_ID.keys()


# ── Internal ────────────────────────────────────────────────────────────────

func _load_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		GameLogger.warn("StatusRegistry", "dir not found: %s" % dir_path)
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
		GameLogger.warn("StatusRegistry", "can't open: %s" % file_path)
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		GameLogger.warn("StatusRegistry", "bad JSON: %s" % file_path)
		return
	var data := parsed as Dictionary
	var id_str: String = data.get("id", "")
	if id_str == "":
		GameLogger.warn("StatusRegistry", "missing id in %s" % file_path)
		return
	var id: StringName = StringName(id_str)
	var arity: int = int(data.get("arity", 1))
	if arity < 1:
		GameLogger.warn("StatusRegistry", "%s: arity must be >= 1, got %d" % [id, arity])
		return
	_meta[id] = {
		"family":      StringName(data.get("family", "debuff")),
		"icon":        String(data.get("icon", "")),
		"arity":       arity,
		"param_names": data.get("param_names", []),
		"loc_name":    String(data.get("loc_name", "")),
		"loc_desc":    String(data.get("loc_desc", "")),
	}
