class_name AbilityTarget
extends Resource
## AbilityTarget — abstract base. "What category of thing does the spell hit?"
##
## 007-skill-system: resolve() now returns ONE Variant (Actor | Vector2i | Vector2 | Object).
## AbilityArea is responsible for expanding that into a list of victims.
##
## ctx Dictionary contract (unchanged):
##   "registry"     → ActorRegistry
##   "grid"         → HexGrid
##   "target_id"    → StringName   (for entity kinds)
##   "target_coord" → Vector2i     (for hex / direction kinds)


## Returns ONE primary target. Null if nothing valid in ctx.
func resolve(_caster: Actor, _ctx: Dictionary) -> Variant:
	push_warning("AbilityTarget.resolve() not overridden")
	return null


## True iff at least one valid primary target exists for ctx.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	return resolve(caster, ctx) != null


## All coords reachable from caster_coord for range-overlay painting.
## Default: empty. Override in spatial subclasses.
func get_range_hexes(_caster_coord: Vector2i, _grid: HexGrid) -> Array[Vector2i]:
	return []
