extends Object
## ActorMotion — static presentation helpers for per-step actor animation.
## No state, no autoload, no class_name. Use via explicit preload from
## controllers that own the step-tween:
##
##   const ActorMotion = preload("res://scripts/infrastructure/actor_motion.gd")
##   ActorMotion.apply_step_sway(actor, duration)
##
## Lives in infrastructure/ (not presentation/) because it's reusable pure-
## utility shared across multiple controllers (godmode + arena_demo). Same
## pattern as game_logger.gd / hex_geometry.gd.

const _SWAY_PIXELS: float = 2.0   # peak amplitude — "barely visible" per 029 req-7
const _SWAY_CYCLES: float = 1.0   # one full L→R→L per step (any more = jitter)
const _BODY_NODE_NAME: StringName = &"Body"


## 029 / req-7: subtle x-oscillation on the actor's visual sprite during a
## step. Targets the child node named "Body" (convention shared by player.tscn
## and manekin.tscn — both have a Sprite2D child at that name). Fails silent
## if the convention isn't met — sway is purely cosmetic.
##
## Why on Body, not the actor itself: the actor Node2D also carries HealthBar
## and StatusIconStrip children that should stay rock-steady. Applying the
## sway only to the sprite child keeps overhead UI anchored.
##
## Animation: SINE through one full cycle, peak ±_SWAY_PIXELS, returning to
## the original x at the end of the step. Synthesized as 4 quarter-cycles via
## chained SINE tweens so a tween chain can be created cheaply without
## tween_method overhead.
static func apply_step_sway(actor: Node, duration: float) -> void:
	if actor == null or duration <= 0.0:
		return
	var body: Node2D = actor.get_node_or_null(NodePath(String(_BODY_NODE_NAME))) as Node2D
	if body == null:
		return
	var base_x: float = body.position.x
	var quarter: float = duration * 0.25
	# Sequence the four phases with a single chain. Each tween_property uses
	# TRANS_SINE so the motion eases through the inflection points without a
	# noticeable beat. Body's y is left untouched to avoid coupling with the
	# actor's vertical position tween.
	var tw := actor.create_tween()
	tw.tween_property(body, "position:x", base_x + _SWAY_PIXELS, quarter).set_trans(Tween.TRANS_SINE)
	tw.tween_property(body, "position:x", base_x, quarter).set_trans(Tween.TRANS_SINE)
	tw.tween_property(body, "position:x", base_x - _SWAY_PIXELS, quarter).set_trans(Tween.TRANS_SINE)
	tw.tween_property(body, "position:x", base_x, quarter).set_trans(Tween.TRANS_SINE)
