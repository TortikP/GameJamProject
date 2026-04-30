class_name AbilityEffect
extends Resource
## AbilityEffect — abstract base. "What does the spell do to one target?"
##
## Subclasses override apply(). Called once per resolved target.


func apply(_caster: Actor, _target: Actor, _ctx: Dictionary) -> void:
	push_warning("AbilityEffect.apply() not overridden")
