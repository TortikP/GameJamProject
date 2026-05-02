extends Node
## CastFsm — multi-step player cast collection state machine.
##
## See specs/026-skill-system-v3/plan.md §"Player cast state-machine".
##
## State: IDLE → AWAIT_TARGET / AWAIT_SELF_CONFIRM → ... → _commit_cast
## Cancel paths reset to IDLE without firing Skill.cast.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
