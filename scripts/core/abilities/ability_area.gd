class_name AbilityArea
extends Resource
## AbilityArea — abstract base. "How does the primary target expand into a list of victims?"
##
## Subclasses implement resolve() and optionally get_affected_hexes().
## resolve() returns an Array of victims (Actor or Vector2i) ordered nearest→farthest.
##
## The type of elements returned depends on primary_target:
##   - primary is Actor   → victims are Actors found along the area
##   - primary is Vector2i → victims are Vector2i hex coords (for hex-target abilities)
## Effects cast+validate their own victim type; mismatches are silent no-ops.


## Returns ordered list of victims. primary_target is the resolved AbilityTarget value.
func resolve(_caster: Actor, _primary_target: Variant, _ctx: Dictionary) -> Array:
	push_warning("AbilityArea.resolve() not overridden")
	return []


## Returns hex coords covered by this area. Used by range-overlay UI.
func get_affected_hexes(_caster_coord: Vector2i, _primary: Variant, _grid: HexGrid) -> Array[Vector2i]:
	return []
