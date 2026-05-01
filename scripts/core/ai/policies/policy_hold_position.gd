class_name PolicyHoldPosition
extends MovementPolicy
## AC-S2: never moves. Returned by parser as fallback for invalid policy strings.
## Also explicitly used by sentries / boss-arena phases.


func pick_step(_actor: Actor, _ctx: Dictionary) -> Vector2i:
	return Vector2i(-1, -1)
