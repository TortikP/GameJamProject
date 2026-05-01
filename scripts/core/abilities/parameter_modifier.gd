class_name ParameterModifier
extends Resource
## ParameterModifier — mutates a numeric field on an Ability or AbilityEffect.
##
## Formula (AC-M5):  final = (base + Σ adds) × Π muls
## Applied centrally in Ability._apply_param_modifiers(). Commutative by construction.
##
## Categorical fields (StringName) are not handled here — spec says last-writer-wins,
## formalised in a later feature if needed.

@export var id: StringName = &""
@export var target_param: StringName = &""   # e.g. "damage", "heal", "max_chain_length"
@export var op: StringName = &"add"          # "add" | "mul"
@export var value: float = 0.0


## True if obj has a property named target_param.
## GDScript `in` operator checks property existence on Object.
func applies_to(obj: Object) -> bool:
	if target_param == &"":
		return false
	return target_param in obj
