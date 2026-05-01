class_name ZoneArcArea
extends AbilityArea
## ZoneArcArea — ring sector. P3 stub.

@export var radius: int = 3
@export var inner_radius: int = 1
@export var angle: float = 90.0


func resolve(_caster: Actor, _primary_target: Variant, _ctx: Dictionary) -> Array:
	push_warning("ZoneArcArea: P3 stub — not implemented in 007 scope")
	return []
