class_name ZoneLineArea
extends AbilityArea
## ZoneLineArea — straight line from caster through primary.
## P2 stub — hex line geometry needs hex_grid.line() helper, not yet implemented.

@export var length: int = 3


func resolve(_caster: Actor, _primary_target: Variant, _ctx: Dictionary) -> Array:
	push_warning("ZoneLineArea: P2 stub — not implemented in 007 scope")
	return []
