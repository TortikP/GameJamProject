extends Node
## GodmodeSetup — orchestrates GodmodeController._ready setup chain.
##
## Owns: level loading, player placement, slot seeding, post-init signal
## hookups, WaveController spin-up. Public entry: run() — called by the
## controller after node + module resolution.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
