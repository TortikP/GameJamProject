extends Node
## HoverDispatcher — owns per-frame _process. Dispatches: slot castability tints,
## hp-bar damage preview on hovered enemy, AoE zone preview on cursor, hover-path
## preview, and cast-intent tooltip on hovered enemy.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
