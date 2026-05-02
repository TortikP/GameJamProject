extends Node
## StatusRegistry — autoload. Pure dispatch table from status_id to runtime
## class. No JSON metadata loader anymore: arity, family, and all behaviour
## live entirely on the runtime class itself (static methods + static funcs).
##
## Runtime lookup: StatusRegistry.runtime_for(&"poisoned") → PoisonedRuntime
## (the GDScript class object — methods are static, no instances created).
##
## 027 (revised): metadata folder data/status_effects/ removed; runtime
## classes own their own arity/family via static funcs. Skill JSON is the
## sole source of per-status parameters via the inline encoding
## "id(d, a1, a2, ...)".
##
## Autoload order: MUST be before AbilityDatabase / SkillDatabase, since
## the parser calls arity_of() at skill-load time. See project.godot.

const GameLogger = preload("res://scripts/infrastructure/game_logger.gd")

# Preload table — id → runtime GDScript class. Only entry point for new
# statuses: add row here + create runtime class.
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
}


func _ready() -> void:
	GameLogger.info("StatusRegistry", "registered %d statuses: %s" % [_RT_BY_ID.size(), str(_RT_BY_ID.keys())])


## Returns the runtime GDScript class object, or null if unknown.
## Callers invoke static methods on it: rt.on_turn_start(actor, inst, ctx).
## Typed as GDScript (not Variant) so static dispatch works deterministically.
func runtime_for(id: StringName) -> GDScript:
	return _RT_BY_ID.get(id, null) as GDScript


func has_status(id: StringName) -> bool:
	return _RT_BY_ID.has(id)


## Number of expected args in the inline encoding `id(d, a1, ...)`. Returns 0
## for unknown ids — parser uses 0 as the "reject" signal.
## Delegates to runtime.arity().
func arity_of(id: StringName) -> int:
	var rt: GDScript = _RT_BY_ID.get(id, null) as GDScript
	if rt == null:
		return 0
	return rt.arity()


## UI pill colour family. Default fallback is "debuff" if id is unknown.
func family_of(id: StringName) -> StringName:
	var rt: GDScript = _RT_BY_ID.get(id, null) as GDScript
	if rt == null:
		return &"debuff"
	return rt.family()


func all_ids() -> Array:
	return _RT_BY_ID.keys()
