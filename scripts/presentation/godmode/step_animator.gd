extends Node
## StepAnimator — handles grid.actor_step_started: position tween + ActorMotion
## sway. Setup chain wires the signal to _on_step_started.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
