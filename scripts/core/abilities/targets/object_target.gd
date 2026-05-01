class_name ObjectTarget
extends AbilityTarget
## ObjectTarget — passive game objects (crates, columns, etc.).
## P3 stub — object entity layer not in 007/021 scope.
##
## 021: kept range field + apply_level so when the layer lands the scaling
## already follows the standard pattern (range += level if > 1).

@export var range: int = -1


func resolve(_caster: Actor, _ctx: Dictionary) -> Variant:
	return null

func can_apply(_caster: Actor, _ctx: Dictionary) -> bool:
	return false


## 021 scaling: range += level if range > 1.
func apply_level(level: int) -> void:
	if level <= 0 or range <= 1:
		return
	range += level
