class_name SelfTarget
extends AbilityTarget
## SelfTarget — always resolves to the caster.
## Use with area=self for self-buffs/heals that should never fail due to
## external target state (e.g. vamp heal after the enemy is already dead).

func resolve(caster: Actor, _ctx: Dictionary) -> Variant:
	return caster

func can_apply(_caster: Actor, _ctx: Dictionary) -> bool:
	return true

func get_range_hexes(_caster_coord: Vector2i, _grid: HexGrid) -> Array[Vector2i]:
	return []
