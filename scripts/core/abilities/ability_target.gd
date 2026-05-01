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


## Coord that the area's hover-preview should anchor on (i.e. what `primary`
## the presentation passes into `AbilityArea.get_affected_hexes`). Default:
## the hex under the cursor — preview follows the mouse, matching how
## ActorTarget / HexTarget actually resolve at cast time. SelfTarget overrides
## this to caster_coord so self-cast AoE previews stay glued to the caster.
func preview_anchor_coord(_caster_coord: Vector2i, hover_coord: Vector2i) -> Vector2i:
	return hover_coord


## 021: skill-level scaling hook. Default no-op; subclasses with a `range`
## field override per the formula in 021-skill-system-v2/spec.md §"Уровень навыка".
## Called on a duplicate before resolve(), so the base resource stays untouched.
func apply_level(_level: int) -> void:
	pass
