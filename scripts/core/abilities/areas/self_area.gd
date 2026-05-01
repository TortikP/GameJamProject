class_name SelfArea
extends AbilityArea
## SelfArea — resolves to [caster], ignoring primary_target entirely.
## Use for self-heals, self-buffs, "channelled into own body" spells.


func resolve(caster: Actor, _primary_target: Variant, _ctx: Dictionary) -> Array:
	return [caster]


func get_affected_hexes(caster_coord: Vector2i, _primary: Variant, _grid: HexGrid) -> Array[Vector2i]:
	return [caster_coord]
