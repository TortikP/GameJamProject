extends Node
## ManekinSpawner — F1/F2 sandbox helpers. Spawns dummy enemies on the hex
## under the cursor (F1) and clears all enemies + revives player (F2). Plans
## the new manekin immediately so its intent is visible without ending turn.

var _ctrl: Node = null


func _ready() -> void:
	_ctrl = get_parent()
