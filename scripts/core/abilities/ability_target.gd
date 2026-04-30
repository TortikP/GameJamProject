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
