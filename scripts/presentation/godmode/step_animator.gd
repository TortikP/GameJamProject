extends Node
## StepAnimator — handles grid.actor_step_started: position tween + ActorMotion
## sway. Setup chain wires the signal to _on_step_started.

const ActorMotion = preload("res://scripts/infrastructure/actor_motion.gd")

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()


func _on_step_started(actor_id: StringName, _from: Vector2i, to: Vector2i) -> void:
	var actor: Actor = _ctrl.registry.get_actor(actor_id)
	if actor == null:
		return
	var pos: Vector2 = _ctrl.grid.tile_map_layer.map_to_local(to)
	var duration: float = GameSpeed.get_value("arena", "step_duration", 0.18) * _ctrl.grid.get_move_cost(to)
	create_tween().tween_property(actor, "position", pos, duration)
	# 029 / req-7: barely-visible side-to-side sway on the actor's sprite
	# during the step. Helper finds the conventional "Body" child sprite —
	# leaves the actor's own position tween (above) and overhead UI alone.
	ActorMotion.apply_step_sway(actor, duration)
