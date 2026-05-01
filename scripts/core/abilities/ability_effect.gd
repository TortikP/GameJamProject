class_name AbilityEffect
extends Resource
## AbilityEffect — abstract base. "What does the spell do to one target?"
##
## Subclasses override apply(). Called once per resolved victim.
## target is Variant (Actor | Vector2i | Object) — subclasses cast and validate.
## Clean no-op if the cast fails.
##
## 007-skill-system: added id, type, duration, requires_alive_target; target→Variant.

@export var id: StringName = &""
@export var type: StringName = &""
@export var duration: int = 0
@export var requires_alive_target: bool = true


func apply(_caster: Actor, _target: Variant, _ctx: Dictionary) -> void:
	push_warning("AbilityEffect.apply() not overridden on %s" % id)
