class_name ZoneConeArea
extends AbilityArea
## ZoneConeArea — cone from caster through primary.
## P2 stub — 007 scope.

@export var range: int = 3
@export var width: int = 2


func resolve(_caster: Actor, _primary_target: Variant, _ctx: Dictionary) -> Array:
	push_warning("ZoneConeArea: P2 stub — not implemented in 007 scope")
	return []
