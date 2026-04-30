class_name AbilityTarget
extends Resource
## AbilityTarget — abstract base. "What does the spell hit?"
##
## Subclasses override resolve(). Return Array[Actor].
##
## ctx Dictionary contract:
##   "registry"     → ActorRegistry  (always present in godmode/arena)
##   "grid"         → HexGrid        (always present)
##   "target_id"    → StringName     (for single-target kinds)
##   "target_coord" → Vector2i       (for zone/ray kinds)


func resolve(_caster: Actor, _ctx: Dictionary) -> Array:
	push_warning("AbilityTarget.resolve() not overridden")
	return []


## True iff at least one valid target exists for ctx. Default impl runs resolve
## and checks emptiness — fine for cheap targets like single_enemy. Override for
## targets where resolve is expensive (e.g. zone scans) and want a faster predicate.
func can_apply(caster: Actor, ctx: Dictionary) -> bool:
	return not resolve(caster, ctx).is_empty()
