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

## Self-cast AoE previews are anchored on the caster, regardless of where the
## mouse hovers — `resolve(...)` always returns the caster, so the preview
## must reflect that. Without this, a Self+ZoneCircle ability would draw its
## blast radius around the cursor and then snap to the caster on commit.
func preview_anchor_coord(caster_coord: Vector2i, _hover_coord: Vector2i) -> Vector2i:
	return caster_coord
