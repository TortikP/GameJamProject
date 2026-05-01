class_name HexTarget
extends AbilityTarget
## HexTarget — resolves ctx["target_coord"] as a Vector2i hex coordinate.
## Used by ground-targeted abilities (AoE landing, Create, etc.).

func resolve(_caster: Actor, ctx: Dictionary) -> Variant:
	var coord: Variant = ctx.get("target_coord")
	if coord == null:
		return null
	if not coord is Vector2i:
		return null
	return coord


func can_apply(_caster: Actor, ctx: Dictionary) -> bool:
	return ctx.has("target_coord") and ctx["target_coord"] is Vector2i
