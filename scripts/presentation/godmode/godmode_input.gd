extends Node
## GodmodeInput — owns _unhandled_input switchboard + small player action helpers
## (_request_move, _wait_turn, _request_cast_active). Dispatches LMB to CastFsm
## or to controller's selection facade.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
