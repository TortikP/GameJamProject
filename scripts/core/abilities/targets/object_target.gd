class_name ObjectTarget
extends AbilityTarget
## ObjectTarget — passive game objects (crates, columns, etc.).
## P3 stub — object entity layer not in 007 scope.

func resolve(_caster: Actor, _ctx: Dictionary) -> Variant:
	return null

func can_apply(_caster: Actor, _ctx: Dictionary) -> bool:
	return false
