class_name SingleEnemyTarget
extends AbilityTarget
## Resolve one actor by id from ctx.
##
## ctx requires: "registry" (ActorRegistry), "target_id" (StringName).
## Returns [actor] or [] if no actor / actor is the caster / actor is dead.


func resolve(caster: Actor, ctx: Dictionary) -> Array:
	var registry: ActorRegistry = ctx.get("registry")
	if registry == null:
		return []
	var id: StringName = ctx.get("target_id", &"")
	if id == &"":
		return []
	var actor: Actor = registry.get_actor(id)
	if actor == null:
		return []
	if actor == caster:
		return []
	if not actor.is_alive():
		return []
	return [actor]
